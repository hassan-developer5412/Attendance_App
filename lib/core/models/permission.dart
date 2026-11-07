import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

export 'package:attendance_app/core/constants/app_constants.dart'
    show PermissionCodes;

/// A securable action in the system (e.g. `student.create`, `attendance.mark`).
///
/// Permissions are registered in the `permissions` table and granted to roles
/// through `role_permissions`. [PermissionService] evaluates whether the active
/// user holds a given permission.
class Permission {
  Permission({
    String? id,
    required this.code,
    required this.module,
    required this.description,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isSynced = false,
    this.instituteId = AppConstants.defaultInstituteId,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  /// Machine-readable codename, e.g. `student.create`.
  final String code;
  /// Functional module the permission belongs to, e.g. `students`.
  final String module;
  /// Human-readable description shown in the grant editor.
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSynced;
  final String instituteId;

  factory Permission.fromMap(Map<String, dynamic> map) {
    return Permission(
      id: map['id']?.toString() ?? UuidUtils.generate(),
      code: (map['code'] as String?) ?? '',
      module: (map['module'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      createdAt: _parse(map['created_at']),
      updatedAt: _parse(map['updated_at']),
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int?) == 1,
      isSynced: (map['is_synced'] as int?) == 1,
      instituteId: (map['institute_id'] as String?) ?? AppConstants.defaultInstituteId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'module': module,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
      'is_synced': isSynced ? 1 : 0,
      'institute_id': instituteId,
    };
  }

  /// Supabase replication payload (no local-only bookkeeping).
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'code': code,
      'module': module,
      'description': description,
      'is_deleted': isDeleted,
    };
  }

  Permission copyWith({
    String? id,
    String? code,
    String? module,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSynced,
    String? instituteId,
  }) {
    return Permission(
      id: id ?? this.id,
      code: code ?? this.code,
      module: module ?? this.module,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
      instituteId: instituteId ?? this.instituteId,
    );
  }

  static DateTime _parse(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toUtc() ?? DateTime.now().toUtc();
  }

  @override
  String toString() => 'Permission(id: $id, code: $code, module: $module)';
}
