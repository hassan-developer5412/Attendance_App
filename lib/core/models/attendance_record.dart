import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/date_utils.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Returns true when the string looks like a plain integer (legacy INTEGER PK).
bool _looksLikeInt(String s) => RegExp(r'^\d+$').hasMatch(s);

/// A single daily attendance record for a student.
///
/// `id`, `studentId`, and `studentClassId` are all v4 UUID strings in the v6
/// schema. The [fromMap] factory transparently converts legacy integer values
/// to their deterministic UUID equivalents so old rows keep working.
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

  /// UUID of the student (TEXT FK → students.id).
  final String studentId;

  final DateTime date;
  final AttendanceStatus status;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;

  /// Populated from JOIN queries for display purposes.
  final String? studentName;
  final String? studentRollNumber;

  /// UUID of the class the student belongs to (from JOIN).
  final String? studentClassId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Creates an [AttendanceRecord] from a database row map.
  ///
  /// Handles both v5 (integer PKs + uuid column) and v6 (TEXT UUID PKs).
  factory AttendanceRecord.fromMap(Map<String, dynamic> map) {
    // Resolve record id
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInt(rawUuid))
        ? rawUuid
        : (rawId != null && !_looksLikeInt(rawId))
            ? rawId
            : UuidUtils.deterministic('attendance_records', rawId ?? '0');

    // Resolve student_id (may be integer in old rows)
    String studentId;
    final rawStudentId = map['student_id']?.toString() ?? '0';
    if (_looksLikeInt(rawStudentId)) {
      studentId = UuidUtils.deterministic('students', rawStudentId);
    } else {
      studentId = rawStudentId;
    }

    // Resolve class_id from JOIN (display only)
    String? studentClassId;
    final rawClassId = map['class_id']?.toString();
    if (rawClassId != null && rawClassId.isNotEmpty) {
      studentClassId = _looksLikeInt(rawClassId)
          ? UuidUtils.deterministic('classes', rawClassId)
          : rawClassId;
    }

    return AttendanceRecord(
      id: canonicalId,
      sessionId: map['session_id']?.toString(),
      studentId: studentId,
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
      studentClassId: studentClassId,
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
  /// In the v6 schema `id` is the TEXT UUID primary key.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      'student_id': studentId,
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

  /// Supabase replication payload.
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'student_id': studentId,
      'date': AppDateUtils.dateKey(date),
      'status': status.serverValue,
      'check_in_time': checkInTime?.toIso8601String(),
      'check_out_time': checkOutTime?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? sessionId,
    String? studentId,
    DateTime? date,
    AttendanceStatus? status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? studentName,
    String? studentRollNumber,
    String? studentClassId,
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
