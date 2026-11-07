import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Links a [User] to a [Role] (many-to-many).
///
/// A user may hold several roles (e.g. `teacher` + `hod`). The effective
/// permission set is the union of all granted permissions across the user's
/// roles, subject to the authority rules enforced by [PermissionService].
///
/// Note: this class is named `UserRoleAssignment` because the `UserRole` enum
/// (legacy `users.role` column) already occupies that identifier.
class UserRoleAssignment {
  UserRoleAssignment({
    String? id,
    required this.userId,
    required this.roleId,
    required this.instituteId,
    this.assignedAt,
    this.assignedBy,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isSynced = false,
  }) : id = id ?? UuidUtils.generate();

  final String id;
  final String userId;
  final String roleId;
  final String instituteId;
  final DateTime? assignedAt;
  final String? assignedBy;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSynced;

  factory UserRoleAssignment.fromMap(Map<String, dynamic> map) {
    return UserRoleAssignment(
      id: map['id']?.toString() ?? UuidUtils.generate(),
      userId: (map['user_id'] as String?) ?? '',
      roleId: (map['role_id'] as String?) ?? '',
      instituteId: (map['institute_id'] as String?) ?? AppConstants.defaultInstituteId,
      assignedAt: _parse(map['assigned_at']),
      assignedBy: map['assigned_by'] as String?,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int?) == 1,
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'role_id': roleId,
      'institute_id': instituteId,
      'assigned_at': assignedAt?.toIso8601String(),
      'assigned_by': assignedBy,
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'user_id': userId,
      'role_id': roleId,
      'is_deleted': isDeleted,
    };
  }

  UserRoleAssignment copyWith({
    String? id,
    String? userId,
    String? roleId,
    String? instituteId,
    DateTime? assignedAt,
    String? assignedBy,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSynced,
  }) {
    return UserRoleAssignment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      roleId: roleId ?? this.roleId,
      instituteId: instituteId ?? this.instituteId,
      assignedAt: assignedAt ?? this.assignedAt,
      assignedBy: assignedBy ?? this.assignedBy,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  static DateTime? _parse(dynamic value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toUtc();
  }

  @override
  String toString() => 'UserRoleAssignment(userId: $userId, roleId: $roleId)';
}
