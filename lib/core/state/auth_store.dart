import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Manages user authentication state backed by UserRepository.
///
/// SQLite remains the authority for app access (offline-first): a user must
/// authenticate against the local database before a session is created.
/// When Supabase is configured, a best-effort cloud sign-in runs alongside
/// so RLS-protected pushes are authenticated — but its failure never blocks
/// local login, and it is skipped entirely when Supabase is unavailable.
///
/// The tenant id (`institute_id`) is centralized here: restored from
/// SharedPreferences on [init], refreshed from the signed-in cloud user's
/// metadata after a successful Supabase sign-in, and pushed into
/// [SupabaseConfig.instituteId] where `SyncService` stamps it on payloads.
class AuthStore extends ChangeNotifier {
  AuthStore({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final UserRepository _userRepository;
  User? _currentUser;

  /// The currently logged-in user, or `null` if unauthenticated.
  User? get currentUser => _currentUser;

  /// Whether a user is currently logged in.
  bool get isLoggedIn => _currentUser != null;

  /// Restores the session from [SharedPreferences] if a user was previously logged in.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Restore the centralized tenant id learned at a previous login.
    final savedInstituteId = prefs.getString(AppConstants.prefInstituteId);
    if (savedInstituteId != null && savedInstituteId.isNotEmpty) {
      SupabaseConfig.instituteId = savedInstituteId;
    }

    final userIdStr = prefs.getString(AppConstants.prefUserId);
    if (userIdStr == null || userIdStr.isEmpty) return;

    final user = await _userRepository.getById(userIdStr);
    if (user != null) {
      _currentUser = user;
      notifyListeners();
    }
  }

  /// Attempts to authenticate with [username] and [password].
  ///
  /// Local authentication always decides access (source of truth). When
  /// Supabase is ready, a cloud sign-in is attempted afterwards with the
  /// same credentials; a failure is logged and otherwise ignored so the
  /// offline session continues to work.
  Future<User?> login(String username, String password) async {
    final hash = sha256.convert(utf8.encode(password)).toString();
    final user = await _userRepository.authenticate(username, hash);

    if (user == null) return null;

    _currentUser = user;

    // Best-effort cloud sign-in; never blocks or fails the local session.
    await _signInToSupabase(user, password);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.prefUserId,
      _currentUser!.id.toString(),
    );
    await prefs.setString(
      AppConstants.prefUserRole,
      _currentUser!.role.value,
    );

    notifyListeners();
    return _currentUser;
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
  Future<void> logout() async {
    // Best-effort cloud sign-out; local logout always proceeds.
    if (SupabaseConfig.isReady) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint('Supabase signOut failed (continuing local logout): $e');
      }
    }

    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefUserId);
    await prefs.remove(AppConstants.prefUserRole);
    notifyListeners();
  }

  /// Attempts a Supabase password sign-in for [user]'s email.
  ///
  /// On success the tenant id from the user's `institute_id` metadata is
  /// adopted centrally (persisted + re-tagged locally). Any failure — not
  /// configured, offline, wrong cloud account — is swallowed: the caller
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

  /// Centralizes [instituteId]: persists it, updates [SupabaseConfig], and
  /// re-tags local rows so the next sync pushes under the new tenant.
  Future<void> _adoptInstituteId(String instituteId) async {
    if (instituteId == SupabaseConfig.instituteId) return;
    SupabaseConfig.instituteId = instituteId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefInstituteId, instituteId);
    SyncService.instance.retagLocalRows(instituteId);
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
}
