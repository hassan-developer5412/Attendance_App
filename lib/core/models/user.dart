import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A user of the attendance and institute management system.
///
/// The `id` field is a client-generated v4 UUID that is used as the primary
/// key in both local SQLite (`users.id TEXT PRIMARY KEY`) and Supabase.
class User {
  User({
    String? id,
    required this.username,
    this.rollNo,
    this.employeeId,
    required this.displayName,
    required this.email,
    required this.role,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isDefaultPassword = false,
    this.isSuspended = false,
    this.suspendedAt,
    this.suspendedReason,
    this.failedLoginAttempts = 0,
    this.lockedUntil,
    this.passwordChangedAt,
    this.lastLoginAt,
    this.sessionExpiresAt,
    this.authUserId,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String username;
  /// Roll number — alternate login identifier (students / staff).
  final String? rollNo;
  /// Employee ID — alternate login identifier (staff).
  final String? employeeId;
  final String displayName;
  final String email;
  final UserRole role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;
  /// Whether the account is still using its default password and must be
  /// changed before the dashboard becomes accessible.
  final bool isDefaultPassword;
  /// Whether the account is suspended and must not be allowed to log in.
  final bool isSuspended;
  final String? suspendedAt;
  final String? suspendedReason;
  /// Consecutive failed password attempts since the last successful login.
  final int failedLoginAttempts;
  /// Account is locked until this instant (`null` when not locked).
  final String? lockedUntil;
  /// When the password was last changed (ISO-8601 UTC).
  final String? passwordChangedAt;
  /// When the user last logged in (ISO-8601 UTC).
  final String? lastLoginAt;
  /// Absolute session expiry (ISO-8601 UTC).
  final String? sessionExpiresAt;
  /// Linked Supabase Auth user id (nullable).
  final String? authUserId;

  /// True when [lockedUntil] is set and the lockout window has not elapsed.
  bool get isLocked {
    if (lockedUntil == null) return false;
    final unlockAt = DateTime.tryParse(lockedUntil!)?.toUtc();
    return unlockAt != null && DateTime.now().toUtc().isBefore(unlockAt);
  }

  /// Creates a [User] from a database row map.
  ///
  /// Handles the v5→v6 migration window: if the row still has the old
  /// `uuid` column the canonical id is taken from there; the new schema
  /// stores it directly in `id`.
  factory User.fromMap(Map<String, dynamic> map) {
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    // Prefer uuid column when present (v5 rows), fall back to id column (v6).
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInteger(rawUuid))
        ? rawUuid
        : (rawId ?? UuidUtils.generate());

    return User(
      id: canonicalId,
      username: map['username'] as String,
      displayName: (map['display_name'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      role: UserRole.fromString(map['role'] as String),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      isDefaultPassword: (map['is_default_password'] as int? ?? 0) == 1,
      rollNo: map['roll_no'] as String?,
      employeeId: map['employee_id'] as String?,
      isSuspended: (map['is_suspended'] as int? ?? 0) == 1,
      suspendedAt: map['suspended_at'] as String?,
      suspendedReason: map['suspended_reason'] as String?,
      failedLoginAttempts: (map['failed_login_attempts'] as int? ?? 0),
      lockedUntil: map['locked_until'] as String?,
      passwordChangedAt: map['password_changed_at'] as String?,
      lastLoginAt: map['last_login_at'] as String?,
      sessionExpiresAt: map['session_expires_at'] as String?,
      authUserId: map['auth_user_id'] as String?,
    );
  }

  /// Converts this user to a database row map (excludes password).
  ///
  /// In the v6 schema `id` is the TEXT UUID primary key.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'role': role.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
      'roll_no': rollNo,
      'employee_id': employeeId,
      'is_suspended': isSuspended ? 1 : 0,
      'suspended_at': suspendedAt,
      'suspended_reason': suspendedReason,
      'failed_login_attempts': failedLoginAttempts,
      'locked_until': lockedUntil,
      'password_changed_at': passwordChangedAt,
      'last_login_at': lastLoginAt,
      'session_expires_at': sessionExpiresAt,
      'auth_user_id': authUserId,
    };
  }

  /// Backend-ready representation for REST API.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'role': role.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  /// Supabase replication payload: canonical UUID as `id`, JSON-native types,
  /// and no local-only bookkeeping (`sync_status`, `is_synced`).
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'role': role.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  User copyWith({
    String? id,
    String? username,
    String? displayName,
    String? email,
    UserRole? role,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isDefaultPassword,
    bool? isSuspended,
    String? suspendedAt,
    String? suspendedReason,
    int? failedLoginAttempts,
    String? lockedUntil,
    String? passwordChangedAt,
    String? lastLoginAt,
    String? sessionExpiresAt,
    String? authUserId,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      rollNo: rollNo ?? rollNo,
      employeeId: employeeId ?? employeeId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isDefaultPassword: isDefaultPassword ?? this.isDefaultPassword,
      isSuspended: isSuspended ?? this.isSuspended,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedReason: suspendedReason ?? this.suspendedReason,
      failedLoginAttempts:
          failedLoginAttempts ?? this.failedLoginAttempts,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      passwordChangedAt: passwordChangedAt ?? this.passwordChangedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      sessionExpiresAt: sessionExpiresAt ?? this.sessionExpiresAt,
      authUserId: authUserId ?? this.authUserId,
    );
  }

  /// Returns true when the string is a plain integer (legacy INTEGER PK).
  static bool _looksLikeInteger(String s) => RegExp(r'^\d+$').hasMatch(s);
}
