import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/date_utils.dart';

/// A single daily attendance record for a student.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.date,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.studentName,
    this.studentRollNumber,
    this.studentClassId,
  });

  final int id;
  final int studentId;
  final DateTime date;
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;

  /// Populated from JOIN queries for display purposes.
  final String? studentName;
  final String? studentRollNumber;
  final int? studentClassId;

  /// Creates an [AttendanceRecord] from a database row map.
  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    return AttendanceRecord(
      id: map['id'] as int,
      studentId: map['student_id'] as int,
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
      studentClassId: map['class_id'] as int?,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'student_id': studentId,
      'date': AppDateUtils.dateKey(date),
      'status': status.value,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
    };
  }
}
