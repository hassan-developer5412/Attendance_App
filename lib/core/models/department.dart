import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Department model representing an academic department or program at GILT.
class Department {
  Department({
    String? id,
    required this.name,
    required this.code,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String name;
  final String code;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  factory Department.fromMap(Map<String, dynamic> map) {
    return Department(
      id: map['id'].toString(),
      name: map['name'] as String,
      code: map['code'] as String,
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  Department copyWith({
    String? id,
    String? name,
    String? code,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Department(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
