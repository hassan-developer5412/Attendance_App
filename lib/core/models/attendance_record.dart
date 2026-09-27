import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/date_utils.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A single daily attendance record for a student.
class AttendanceRecord {
  AttendanceRecord({
    String? id,
    this.sessionId,
    required this.studentId,
    required this.date,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.studentName,
    this.studentRollNumber,
    this.studentClassId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String? sessionId;
  final int studentId;
  final DateTime date;
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;

  /// Populated from JOIN queries for display purposes.
  final String? studentName;
  final String? studentRollNumber;
  final int? studentClassId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Creates an [AttendanceRecord] from a database row map.
  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    // Prefer the canonical UUID; fall back to the legacy integer primary key.
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty)
        ? rawUuid
        : (rawId ?? '');

    return AttendanceRecord(
      id: canonicalId,
      sessionId: map['session_id']?.toString(),
      studentId: map['student_id'] is int
          ? map['student_id'] as int
          : int.tryParse(map['student_id'].toString()) ?? 0,
      date: AppDateUtils.parseDateKey(map['date'] as String),
      status: AttendanceStatus.fromString(map['status'] as String),
      checkInTime: map['check_in_time'] != null
          ? DateTime.parse(map['check_in_time'] as String)
          : null,
      checkOutTime: map['check_out_time'] != null
          ? DateTime.parse(map['check_out_time'] as String)
          : null,
      studentName: map['student_name'] as String?,
      studentRollNumber: map['roll_number'] as String?,
      studentClassId: map['class_id'] is int
          ? map['class_id'] as int
          : (map['class_id'] != null
              ? int.tryParse(map['class_id'].toString())
              : null),
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

  /// Converts to a database row map for insert/update.
  ///
  /// `id` is intentionally omitted: on the legacy `attendance_records` table it
  /// is an `INTEGER PRIMARY KEY AUTOINCREMENT`, so the canonical UUID is written
  /// to the dedicated `uuid` column instead.
  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'session_id': sessionId,
      'student_id': studentId,
      'date': AppDateUtils.dateKey(date),
      'status': status.value,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Future REST API representation.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_id': studentId.toString(),
      'date': AppDateUtils.dateKey(date),
      'status': status.serverValue,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? sessionId,
    int? studentId,
    DateTime? date,
    AttendanceStatus? status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? studentName,
    String? studentRollNumber,
    int? studentClassId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentId: studentId ?? this.studentId,
      date: date ?? this.date,
      status: status ?? this.status,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      studentName: studentName ?? this.studentName,
      studentRollNumber: studentRollNumber ?? this.studentRollNumber,
      studentClassId: studentClassId ?? this.studentClassId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

