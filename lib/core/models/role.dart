import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A role in the RBAC model.
///
/// Predefined roles (Principal, Vice Principal, Admin, HOD, Teacher, Student,
/// Parent, Accountant, Lab In-Charge, Assistant) ship with default permission
/// grants. Administrators can create [isCustom] roles and edit their grants via
/// the role management UI.
///
/// [isInstituteWide] marks roles whose grants apply institute-wide regardless of
/// department (Admin, Principal, Vice Principal). Department-scoped roles such
/// as HOD only apply their grants within the user's assigned departments.
class Role {
  Role({
    String? id,
    required this.name,
    required this.code,
    this.description = '',
    this.isCustom = false,
    this.isInstituteWide = false,
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
  /// Human-readable role name shown in the UI.
  final String name;
  /// Stable code used for logic branching, e.g. `principal`, `hod`.
  final String code;
  final String description;
  /// True when the role was created by an administrator (not predefined).
  final bool isCustom;
  /// True when grants apply institute-wide regardless of department.
  final bool isInstituteWide;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSynced;
  final String instituteId;

  /// Predefined role codes shipped with the app.
  static const _kPredefined = <String>{
    'admin',
    'principal',
    'vice_principal',
    'hod',
    'teacher',
    'student',
    'parent',
    'accountant',
    'lab_in_charge',
    'assistant',
  };

  /// Roles whose grants apply institute-wide regardless of department.
  static const _kInstituteWide = <String>{
    'admin',
    'principal',
    'vice_principal',
  };

  static Set<String> get predefinedCodes => _kPredefined;
  static Set<String> get instituteWideCodes => _kInstituteWide;
  static bool isCodeInstituteWide(String code) => _kInstituteWide.contains(code);

  factory Role.fromMap(Map<String, dynamic> map) {
    return Role(
      id: map['id']?.toString() ?? UuidUtils.generate(),
      name: (map['name'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      isCustom: (map['is_custom'] as int?) == 1,
      isInstituteWide: (map['is_institute_wide'] as int?) == 1,
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
      'name': name,
      'code': code,
      'description': description,
      'is_custom': isCustom ? 1 : 0,
      'is_institute_wide': isInstituteWide ? 1 : 0,
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
      'name': name,
      'code': code,
      'description': description,
      'is_custom': isCustom,
      'is_institute_wide': isInstituteWide,
      'is_deleted': isDeleted,
    };
  }

  Role copyWith({
    String? id,
    String? name,
    String? code,
    String? description,
    bool? isCustom,
    bool? isInstituteWide,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSynced,
    String? instituteId,
  }) {
    return Role(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      isCustom: isCustom ?? this.isCustom,
      isInstituteWide: isInstituteWide ?? this.isInstituteWide,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
      instituteId: instituteId ?? this.instituteId,
    );
  }

  /// True when this is one of the system-predefined roles.
  bool get isPredefined => _kPredefined.contains(code);

  static DateTime _parse(dynamic value) {
    if (value == null) return DateTime.now().toUtc();
    final parsed = DateTime.tryParse(value.toString());
    return parsed?.toUtc() ?? DateTime.now().toUtc();
  }

  @override
  String toString() => 'Role(id: $id, code: $code, name: $name)';
}
