import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Attendance session representing a lecture, lab, or class gathering.
class AttendanceSession {
  AttendanceSession({
    String? id,
    required this.subjectCode,
    required this.departmentId,
    required this.facultyId,
    required this.sessionDate,
    this.academicSessionId = '',
    this.classId,
    this.year = '',
    this.subjectId,
    this.remarks = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String subjectCode;
  final String departmentId;
  final String facultyId;
  final String sessionDate; // YYYY-MM-DD
  final String academicSessionId;
  final int? classId;
  final String year;
  final int? subjectId;
  final String remarks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  factory AttendanceSession.fromMap(Map<String, dynamic> map) {
    return AttendanceSession(
      id: map['id'].toString(),
      subjectCode: (map['subject_code'] as String?) ?? '',
      departmentId: (map['department_id'] as String?) ?? '',
      facultyId: (map['faculty_id'] as String?) ?? '',
      sessionDate: (map['session_date'] as String?) ?? '',
      academicSessionId: (map['academic_session_id'] as String?) ?? '',
      classId: map['class_id'] is int
          ? map['class_id'] as int
          : (map['class_id'] != null
              ? int.tryParse(map['class_id'].toString())
              : null),
      year: (map['year'] as String?) ?? '',
      subjectId: map['subject_id'] is int
          ? map['subject_id'] as int
          : (map['subject_id'] != null
              ? int.tryParse(map['subject_id'].toString())
              : null),
      remarks: (map['remarks'] as String?) ?? '',
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
      'subject_code': subjectCode,
      'department_id': departmentId,
      'faculty_id': facultyId,
      'session_date': sessionDate,
      'academic_session_id': academicSessionId,
      'class_id': classId,
      'year': year,
      'subject_id': subjectId,
      'remarks': remarks,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'subject_code': subjectCode,
      'department_id': departmentId,
      'faculty_id': facultyId,
      'session_date': sessionDate,
      'academic_session_id': academicSessionId,
      'class_id': classId,
      'year': year,
      'subject_id': subjectId,
      'remarks': remarks,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  AttendanceSession copyWith({
    String? id,
    String? subjectCode,
    String? departmentId,
    String? facultyId,
    String? sessionDate,
    String? academicSessionId,
    int? classId,
    String? year,
    int? subjectId,
    String? remarks,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return AttendanceSession(
      id: id ?? this.id,
      subjectCode: subjectCode ?? this.subjectCode,
      departmentId: departmentId ?? this.departmentId,
      facultyId: facultyId ?? this.facultyId,
      sessionDate: sessionDate ?? this.sessionDate,
      academicSessionId: academicSessionId ?? this.academicSessionId,
      classId: classId ?? this.classId,
      year: year ?? this.year,
      subjectId: subjectId ?? this.subjectId,
      remarks: remarks ?? this.remarks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
