import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A user of the attendance and institute management system.
class User {
  User({
    String? id,
    required this.username,
    required this.displayName,
    required this.email,
    required this.role,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String username;
  final String displayName;
  final String email;
  final UserRole role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Creates a [User] from a database row map.
  factory User.fromMap(Map<String, dynamic> map) {
    // Prefer the canonical UUID; fall back to the legacy integer primary key.
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty)
        ? rawUuid
        : (rawId ?? '');

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
    );
  }

  /// Converts this user to a database row map (excludes password).
  ///
  /// `id` is intentionally omitted: on the legacy `users` table it is an
  /// `INTEGER PRIMARY KEY AUTOINCREMENT`, so the canonical UUID is written to the
  /// dedicated `uuid` column instead.
  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'username': username,
      'display_name': displayName,
      'email': email,
      'role': role.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Backend-ready representation for future REST API.
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

  /// Supabase replication payload: canonical uuid as `id`, JSON-native types,
  /// and no local-only bookkeeping (`sync_status`, `is_synced`).
  ///
  /// The local `password_hash` column is **never** included — credentials
  /// stay on-device and in Supabase Auth only. `institute_id` is stamped
  /// centrally by `SyncService` at send time.
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
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

