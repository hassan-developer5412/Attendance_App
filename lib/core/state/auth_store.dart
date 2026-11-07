import 'dart:async';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A key-value store for sensitive session data (user id, role, expiry,
/// last activity). Implementations must encrypt at rest â€”
/// [FlutterSecureStorageAdapter] backs this with platform encrypted storage
/// (Keychain / Keystore / Credential Manager).
abstract class SecureStorage {
  /// Reads [key], or `null` when absent.
  Future<String?> read({required String key});

  /// Writes [value] under [key].
  Future<void> write({required String key, required String value});

  /// Removes [key].
  Future<void> delete({required String key});
}

/// Backs [SecureStorage] with `flutter_secure_storage`.
class FlutterSecureStorageAdapter implements SecureStorage {
  const FlutterSecureStorageAdapter([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// In-memory [SecureStorage] used by unit tests (no platform plugins).
class FakeSecureStorage implements SecureStorage {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<String?> read({required String key}) async => _store[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _store.remove(key);
  }
}

/// Manages user authentication state backed by UserRepository.
///
/// SQLite remains the authority for app access (offline-first): a user must
/// authenticate against the local database before a session is created.
/// When Supabase is configured, a best-effort cloud sign-in runs alongside
/// so RLS-protected pushes are authenticated â€” but its failure never blocks
/// local login, and it is skipped entirely when Supabase is unavailable.
///
/// Session tokens (user id, role, expiry, last activity) are persisted in
/// `flutter_secure_storage` rather than plaintext `SharedPreferences`. On the
/// first launch after this upgrade, any legacy plaintext session held in
/// `SharedPreferences` is migrated into secure storage and the plaintext
/// keys are removed.
///
/// The tenant id (`institute_id`) is centralized here: restored from
/// SharedPreferences on [init], refreshed from the signed-in cloud user's
/// metadata after a successful Supabase sign-in, and pushed into
/// [SupabaseConfig.instituteId] where `SyncService` stamps it on payloads.
class AuthStore extends ChangeNotifier {
  AuthStore({
    UserRepository? userRepository,
    SecureStorage? secureStorage,
    DatabaseHelper? databaseHelper,
  })  : _userRepository = userRepository ?? UserRepository(),
        _secureStorage = secureStorage ?? const FlutterSecureStorageAdapter(),
        _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  final UserRepository _userRepository;
  final SecureStorage _secureStorage;
  final DatabaseHelper _databaseHelper;

  /// Optional RBAC store that caches the current user's grants. Wired up by
  /// the composition root (`main.dart`) after construction.
  RBACStore? _rbacStore;

  /// Attaches an [RBACStore] so login/logout can load/clear permission grants.
  void attachRbacStore(RBACStore store) => _rbacStore = store;

  User? _currentUser;

  /// Reason for the most recent login failure. Safe to surface to the user:
  /// it distinguishes suspended / locked accounts from invalid credentials
  /// without revealing whether an identifier exists.
  String? _lastAuthError;

  /// Reason for the most recent login failure, or `null` after a successful
  /// login.
  String? get lastAuthError => _lastAuthError;

  /// The currently authenticated user, or `null` if no session is active.
  User? get currentUser => _currentUser;

  /// Whether a session is currently active.
  bool get isLoggedIn => _currentUser != null;

  /// The legacy flat role on the `users` row (backward compatibility).
  UserRole? get currentUserRole => _currentUser?.role;

  /// Cached permission grants for the current user (via [RBACStore]).
  Set<String> get currentUserPermissions =>
      _rbacStore?.currentUserPermissions ?? const {};

  /// Whether the current user holds [permission].
  bool hasPermission(String permission, {String? departmentId}) =>
      _rbacStore?.hasPermission(permission, departmentId: departmentId) ??
      false;

  /// The secure-storage backend (exposed for testing and session inspection).
  SecureStorage get sessionStorage => _secureStorage;

  /// Session TTL rules.
  ///
  /// Absolute session lifetime (30 days) and idle timeout (8 hours). Once
  /// either bound is exceeded the restored session is considered expired and
  /// the user must log in again.
  static const Duration _absoluteTtl = Duration(days: 30);
  static const Duration _idleTtl = Duration(hours: 8);

  /// Whether the current account is still on its default password and must
  /// change it before the dashboard becomes accessible.
  bool get requirePasswordChange =>
      _currentUser != null && _currentUser!.isDefaultPassword;

  /// The currently logged-in user, or `null` if unauthenticated.

  /// Whether a user is currently logged in.

  /// Restores the session from secure storage if a user was previously logged
  /// in and the session has not expired.
  ///
  /// On first run after this upgrade, migrates any legacy plaintext session
  /// from `SharedPreferences` into flutter_secure_storage and clears the
  /// plaintext keys.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Restore the centralized tenant id learned at a previous login.
    final savedInstituteId = prefs.getString(AppConstants.prefInstituteId);
    if (savedInstituteId != null && savedInstituteId.isNotEmpty) {
      SupabaseConfig.instituteId = savedInstituteId;
    }

    // One-time migration: move any legacy plaintext session out of
    // SharedPreferences and into flutter_secure_storage, then clear the
    // plaintext keys.
    await _migrateLegacySession(prefs);

    final userIdStr = await _secureStorage.read(key: _sessionKeyUserId);
    if (userIdStr == null || userIdStr.isEmpty) return;

    // Session TTL validation: reject restored sessions that have exceeded
    // either the absolute expiry or the idle timeout.
    final expiresAtStr = await _secureStorage.read(key: _sessionKeyExpiresAt);
    final lastActivityStr =
        await _secureStorage.read(key: _sessionKeyLastActivity);
    final now = DateTime.now().toUtc();

    final expiresAt = expiresAtStr != null
        ? DateTime.tryParse(expiresAtStr)?.toUtc()
        : null;
    final lastActivity = lastActivityStr != null
        ? DateTime.tryParse(lastActivityStr)?.toUtc()
        : null;

    final absoluteExpired =
        expiresAt != null && now.isAfter(expiresAt);
    final idleExpired =
        lastActivity != null && now.difference(lastActivity) > _idleTtl;

    if (absoluteExpired || idleExpired) {
      await logout(clearSecure: true);
      return;
    }

    final user = await _userRepository.getById(userIdStr);
    if (user == null) {
      // Session referred to an account that no longer exists locally.
      await logout(clearSecure: true);
      return;
    }

    // Guard: the account must still be active in the local database. This
    // catches suspensions (deletions / lockouts) that were applied while the
    // app was offline â€” sync writes them to SQLite, so checking here blocks
    // access immediately even without a network connection.
    if (user.isDeleted || user.isSuspended || user.isLocked) {
      await logout(clearSecure: true);
      _lastAuthError = user.isDeleted
          ? 'This account is no longer active.'
          : user.isSuspended
              ? 'This account is suspended. Contact your institute administrator.'
              : 'This account is temporarily locked.';
      notifyListeners();
      return;
    }

    _currentUser = user;
    // Refresh idle activity on restore.
    await _secureStorage.write(
      key: _sessionKeyLastActivity,
      value: now.toIso8601String(),
    );
    notifyListeners();
  }

  /// Attempts to authenticate with [identifier] and [password].
  ///
  /// [identifier] may be a username, roll number, or employee ID.
  ///
  /// Local authentication is the source of truth: a suspended account is
  /// rejected immediately without checking the password, and a locked
  /// account is rejected until its lockout window elapses. A cloud sign-in
  /// failure never blocks the local session. On success the session is
  /// persisted to `flutter_secure_storage` and SQLite session timestamps are
  /// refreshed. Returns the authenticated user, or `null` when the attempt
  /// failed â€” inspect [lastAuthError] for a user-safe reason.
  Future<User?> login(String identifier, String password) async {
    _lastAuthError = null;

    final result = await _userRepository.authenticate(identifier, password);
    if (result == null) {
      _lastAuthError = 'Invalid identifier or password.';
      return null;
    }

    final user = result.user;
    if (result.isSuspended || user.isSuspended) {
      _lastAuthError =
          'This account is suspended. Contact your institute administrator.';
      return null;
    }
    if (result.isLocked || user.isLocked) {
      final unlockedAt = user.lockedUntil != null
          ? DateTime.tryParse(user.lockedUntil!)?.toUtc()
          : null;
      _lastAuthError = unlockedAt != null
          ? 'Too many failed attempts. This account is locked until '
              '${unlockedAt.hour.toString().padLeft(2, '0')}:'
              '${unlockedAt.minute.toString().padLeft(2, '0')}. Try again later.'
          : 'Too many failed attempts. This account is temporarily locked.';
      return null;
    }

    // Best-effort cloud sign-in; never blocks or fails the local session.
    await _signInToSupabase(user, password);

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(_absoluteTtl);

    await _userRepository.updateSessionTimestamps(
      userId: user.id,
      lastLoginAt: now,
      sessionExpiresAt: expiresAt,
    );

    _currentUser = user;

    // Load the signed-in user's RBAC grants (roles, departments, permissions).
    await _rbacStore?.loadForUser(user.id);

    await _secureStorage.write(
      key: _sessionKeyUserId,
      value: user.id,
    );
    await _secureStorage.write(
      key: _sessionKeyUserRole,
      value: user.role.value,
    );
    await _secureStorage.write(
      key: _sessionKeyExpiresAt,
      value: expiresAt.toIso8601String(),
    );
    await _secureStorage.write(
      key: _sessionKeyLastActivity,
      value: now.toIso8601String(),
    );

    // Seed cloud sync under the newly verified session. Items stay queued
    // locally unless the Supabase session is valid and profile-linked.
    if (SupabaseConfig.isReady) {
      unawaited(SyncService.instance.flushSyncQueue());
    }

    notifyListeners();
    return _currentUser;
  }

  /// Development workaround: bypasses credentials to sign in immediately as
  /// an administrator, ensuring developers are never blocked during dev/testing.
  Future<User> devBypassLogin({
    String username = AppConstants.defaultAdminUsername,
    String displayName = AppConstants.defaultAdminDisplayName,
    String email = AppConstants.defaultAdminEmail,
  }) async {
    _lastAuthError = null;
    final db = await _databaseHelper.database;
    final adminId = UuidUtils.deterministic('users', username);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(_absoluteTtl);

    final rows = await db.query(
      'users',
      where: 'username = ? AND is_deleted = 0',
      whereArgs: [username],
      limit: 1,
    );

    User user;
    if (rows.isEmpty) {
      user = User(
        id: adminId,
        username: username,
        displayName: displayName,
        email: email,
        role: UserRole.admin,
        isDefaultPassword: false,
        createdAt: now,
        updatedAt: now,
      );
      await db.insert('users', {
        'id': user.id,
        'username': user.username,
        'password_hash': BCrypt.hashpw(AppConstants.defaultAdminPassword, BCrypt.gensalt()),
        'display_name': user.displayName,
        'email': user.email,
        'role': 'admin',
        'is_deleted': 0,
        'is_default_password': 0,
        'is_suspended': 0,
        'failed_login_attempts': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'sync_status': 'SYNCED',
        'is_synced': 1,
        'institute_id': AppConstants.defaultInstituteId,
      });
    } else {
      user = User.fromMap(rows.first);
    }

    try {
      final roleRows = await db.query('roles', where: 'code = ?', whereArgs: ['admin'], limit: 1);
      if (roleRows.isNotEmpty) {
        final roleId = roleRows.first['id'] as String;
        final urRows = await db.query('user_roles', where: 'user_id = ? AND role_id = ?', whereArgs: [user.id, roleId]);
        if (urRows.isEmpty) {
          await db.insert('user_roles', {
            'id': UuidUtils.generate(),
            'user_id': user.id,
            'role_id': roleId,
            'institute_id': AppConstants.defaultInstituteId,
            'assigned_at': now.toIso8601String(),
            'sync_status': 'SYNCED',
            'is_deleted': 0,
            'is_synced': 1,
          });
        }
      }
    } catch (_) {}

    _currentUser = user;

    await _rbacStore?.loadForUser(user.id);

    try {
      await _secureStorage.write(key: _sessionKeyUserId, value: user.id);
      await _secureStorage.write(key: _sessionKeyUserRole, value: user.role.value);
      await _secureStorage.write(key: _sessionKeyExpiresAt, value: expiresAt.toIso8601String());
      await _secureStorage.write(key: _sessionKeyLastActivity, value: now.toIso8601String());
    } catch (_) {}

    notifyListeners();
    return _currentUser!;
  }


  /// Re-validates the in-memory session against the local database: reloads
  /// the current user row and clears the session when the account has been
  /// suspended, soft-deleted, or locked since the session was created.
  ///
  /// Call this on app resume and after sync applies remote account updates
  /// so a suspended account loses access as soon as the local database
  /// reflects it, even while the device is offline.
  Future<bool> validateSession() async {
    final current = _currentUser;
    if (current == null) return false;

    final fresh = await _userRepository.getById(current.id);
    if (fresh == null || fresh.isDeleted || fresh.isSuspended || fresh.isLocked) {
      await logout(clearSecure: true);
      _lastAuthError = fresh == null || fresh.isDeleted
          ? 'This account is no longer active.'
          : fresh.isSuspended
              ? 'This account is suspended. Contact your institute administrator.'
              : 'This account is temporarily locked.';
      notifyListeners();
      return false;
    }

    _currentUser = fresh;
    await _refreshIdleActivity();
    return true;
  }

  Future<void> _refreshIdleActivity() async {
    await _secureStorage.write(
      key: _sessionKeyLastActivity,
      value: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Changes the current user's password to [newPassword], clears the
  /// default-password flag, records the change timestamp in SQLite, and
  /// refreshes the secure session.
  ///
  /// Returns `false` when there is no current user.
  Future<bool> changePassword(String newPassword) async {
    if (_currentUser == null) return false;

    await _userRepository.updatePassword(_currentUser!.id, newPassword);

    _currentUser = _currentUser!.copyWith(isDefaultPassword: false);
    notifyListeners();
    return true;
  }

  // -------------------------------------------------------------------------
  // Email-based OTP password recovery (offline-capable)
  // -------------------------------------------------------------------------

  /// Issues a 6-digit OTP to [email] when an account with that address
  /// exists. The code is valid for 10 minutes and single-use; it is stored
  /// (bcrypt-hashed) in the local `password_reset_codes` table, so the flow
  /// works fully offline without an email provider.
  ///
  /// To avoid account enumeration the caller should show the same message
  /// regardless of the return value. Returns `true` when a code was actually
  /// issued (email found). In debug builds the issued code is exposed through
  /// [lastSentOtp] for manual testing.
  Future<bool> requestPasswordReset(String email) async {
    final normalized = email.trim().toLowerCase();
    final user = await _userRepository.getByEmail(normalized);
    if (user == null) return false;

    final code = _generateOtp();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 10));

    final db = await _databaseHelper.database;
    await db.execute('''CREATE TABLE IF NOT EXISTS password_reset_codes (
      email TEXT PRIMARY KEY,
      code_hash TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      used_at TEXT,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');

    await db.insert(
      'password_reset_codes',
      {
        'email': normalized,
        'code_hash': BCrypt.hashpw(code, BCrypt.gensalt()),
        'expires_at': expiresAt.toIso8601String(),
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (kDebugMode) _lastSentOtp = code;
    return true;
  }

  /// The OTP most recently issued by [requestPasswordReset] â€” debug builds
  /// only. Use only when no email provider is configured.
  String? _lastSentOtp;
  String? get lastSentOtp {
    assert(kDebugMode, 'lastSentOtp is available in debug builds only');
    return _lastSentOtp;
  }

  String _generateOtp() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  /// Verifies [otp] for [email] and, on success, replaces the account's
  /// password with [newPassword] (bcrypt). The code is single-use.
  ///
  /// Returns `false` when no unused, unexpired code matches or the code is
  /// wrong (wrong attempts are counted; three wrong attempts consume the
  /// code).
  Future<bool> resetPasswordWithOtp(
      String email, String otp, String newPassword) async {
    final normalized = email.trim().toLowerCase();
    final db = await _databaseHelper.database;

    final rows = await db.query(
      'password_reset_codes',
      where:
          'email = ? AND used_at IS NULL AND expires_at > ?',
      whereArgs: [
        normalized,
        DateTime.now().toUtc().toIso8601String(),
      ],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final row = rows.first;
    if (!BCrypt.checkpw(otp, row['code_hash'] as String)) {
      final attempts = (row['attempts'] as int? ?? 0) + 1;
      await db.update(
        'password_reset_codes',
        {'attempts': attempts},
        where: 'email = ?',
        whereArgs: [normalized],
      );
      if (attempts >= 3) {
        await db.update(
          'password_reset_codes',
          {'used_at': DateTime.now().toUtc().toIso8601String()},
          where: 'email = ?',
          whereArgs: [normalized],
        );
      }
      return false;
    }

    final user = await _userRepository.getByEmail(normalized);
    if (user == null) return false;

    await _userRepository.updatePassword(user.id, newPassword);

    await db.update(
      'password_reset_codes',
      {'used_at': DateTime.now().toUtc().toIso8601String()},
      where: 'email = ?',
      whereArgs: [normalized],
    );
    return true;
  }

  /// Creates a Supabase Auth account (best-effort). Returns `true` only when
  /// Supabase is configured and account creation succeeds.
  Future<bool> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    if (!SupabaseConfig.isReady) return false;
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: data,
      );
      return res.user != null;
    } catch (e) {
      debugPrint('Supabase signUp failed: $e');
      return false;
    }
  }

  /// Logs the current user out and clears the saved session.
  ///
  /// When [clearSecure] is true the secure-storage session keys are removed;
  /// otherwise they are retained (used for TTL-driven expiry).
  Future<void> logout({bool clearSecure = false}) async {
    // Best-effort cloud sign-out; local logout always proceeds.
    if (SupabaseConfig.isReady) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint('Supabase signOut failed (continuing local logout): $e');
      }
    }

    _currentUser = null;
    _rbacStore?.clear();
    PermissionService.instance.reset();
    if (clearSecure) {
      await _secureStorage.delete(key: _sessionKeyUserId);
      await _secureStorage.delete(key: _sessionKeyUserRole);
      await _secureStorage.delete(key: _sessionKeyExpiresAt);
      await _secureStorage.delete(key: _sessionKeyLastActivity);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.prefUserId);
      await prefs.remove(AppConstants.prefUserRole);
    }
    notifyListeners();
  }

  /// Attempts a Supabase password sign-in for [user]'s email.
  ///
  /// On success the tenant id from the user's `institute_id` metadata is
  /// adopted centrally (persisted + re-tagged locally). Any failure â€” not
  /// configured, offline, wrong cloud account â€” is swallowed: the caller
  /// keeps working with the local session only.
  Future<void> _signInToSupabase(User user, String password) async {
    if (!SupabaseConfig.isReady || user.email.isEmpty) return;
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: user.email,
        password: password,
      );
      final cloudUser = res.user;
      if (cloudUser == null) return;

      final metadata = cloudUser.userMetadata;
      final instituteId = metadata?['institute_id']?.toString();
      if (instituteId != null && instituteId.isNotEmpty) {
        await _adoptInstituteId(instituteId);
      }
    } catch (e) {
      debugPrint('Supabase sign-in failed; continuing with local session: $e');
    }
  }

  /// Centralizes [instituteId]: persists it and updates [SupabaseConfig].
  ///
  /// Local rows are deliberately NOT re-tagged to the cloud tenant here:
  /// `institute_id` is a server-controlled field bound to the user's
  /// `public.profiles` row, and SyncService stamps payloads from that
  /// verified profile at drain time. Cross-tenant logins must never silently
  /// re-stamp local records (retagLocalRows removed).
  Future<void> _adoptInstituteId(String instituteId) async {
    if (instituteId == SupabaseConfig.instituteId) return;
    SupabaseConfig.instituteId = instituteId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefInstituteId, instituteId);
  }

  /// Updates the current user's display name and email.
  Future<void> updateProfile({
    required String displayName,
    required String email,
  }) async {
    if (_currentUser == null) return;

    await _userRepository.updateProfile(
      id: _currentUser!.id,
      displayName: displayName.trim(),
      email: email.trim(),
    );

    _currentUser = _currentUser!.copyWith(
      displayName: displayName.trim(),
      email: email.trim(),
    );
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Secure-storage session helpers
  // -------------------------------------------------------------------------

  static const String _sessionKeyUserId = 'session_user_id';
  static const String _sessionKeyUserRole = 'session_user_role';
  static const String _sessionKeyExpiresAt = 'session_expires_at';
  static const String _sessionKeyLastActivity = 'session_last_activity';

  /// Migrates a legacy plaintext session from SharedPreferences into
  /// flutter_secure_storage (one-time), then removes the plaintext keys.
  /// No-op when there is no legacy session or secure storage is already
  /// populated.
  Future<void> _migrateLegacySession(SharedPreferences prefs) async {
    final legacyUserId = prefs.getString(AppConstants.prefUserId);
    final legacyRole = prefs.getString(AppConstants.prefUserRole);
    final secureUserId = await _secureStorage.read(key: _sessionKeyUserId);

    // Already migrated or secure session exists: just clean up plaintext.
    if (secureUserId != null && secureUserId.isNotEmpty) {
      await prefs.remove(AppConstants.prefUserId);
      await prefs.remove(AppConstants.prefUserRole);
      return;
    }

    if (legacyUserId != null && legacyUserId.isNotEmpty) {
      await _secureStorage.write(key: _sessionKeyUserId, value: legacyUserId);
      if (legacyRole != null && legacyRole.isNotEmpty) {
        await _secureStorage.write(
          key: _sessionKeyUserRole,
          value: legacyRole,
        );
      }
      // Conservative expiry/activity values for migrated sessions: treat as
      // created now so the full TTL window applies going forward.
      final now = DateTime.now().toUtc();
      await _secureStorage.write(
        key: _sessionKeyExpiresAt,
        value: now.add(_absoluteTtl).toIso8601String(),
      );
      await _secureStorage.write(
        key: _sessionKeyLastActivity,
        value: now.toIso8601String(),
      );
    }

    await prefs.remove(AppConstants.prefUserId);
    await prefs.remove(AppConstants.prefUserRole);
  }
}