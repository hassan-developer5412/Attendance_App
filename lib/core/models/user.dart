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

  /// Returns true when the string is a plain integer (legacy INTEGER PK).
  static bool _looksLikeInteger(String s) => RegExp(r'^\d+$').hasMatch(s);
}
