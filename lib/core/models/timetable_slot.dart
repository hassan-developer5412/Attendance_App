import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// A single weekly recurring class or lab timetable slot.
///
/// `dayOfWeek` follows `DateTime.weekday` convention: 1 = Monday … 6 = Saturday.
/// `startTime` and `endTime` are stored in `'HH:mm'` 24-hour format.
class TimetableSlot {
  TimetableSlot({
    String? id,
    required this.instituteId,
    this.academicSessionId,
    required this.classId,
    required this.subjectId,
    required this.teacherId,
    required this.roomName,
    required this.dayOfWeek,
    required this.periodSlot,
    required this.startTime,
    required this.endTime,
    this.isLab = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isSynced = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String instituteId;
  final String? academicSessionId;
  final String classId;
  final String subjectId;
  final String teacherId;
  final String roomName;
  /// 1 = Monday … 6 = Saturday, matching `DateTime.weekday`.
  final int dayOfWeek;
  final int periodSlot;
  /// `'HH:mm'` 24-hour format, e.g. `'10:30'`.
  final String startTime;
  /// `'HH:mm'` 24-hour format, e.g. `'11:15'`.
  final String endTime;
  final bool isLab;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSynced;

  /// Human-readable day name (`Monday` … `Saturday`).
  String get dayName {
    switch (dayOfWeek) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      default:
        return 'Unknown';
    }
  }

  /// `startTime` in 12-hour format with AM/PM, e.g. `'10:30 AM'`.
  String get formattedStartTime => _to12Hour(startTime);

  /// `endTime` in 12-hour format with AM/PM, e.g. `'11:15 AM'`.
  String get formattedEndTime => _to12Hour(endTime);

  /// Converts a `'HH:mm'` string to 12-hour format (`'h:mm AM/PM'`).
  static String _to12Hour(String time) {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final period = hour < 12 ? 'AM' : 'PM';
    final twelveHour = hour == 0
        ? 12
        : hour > 12
            ? hour - 12
            : hour;
    return '$twelveHour:${minute.toString().padLeft(2, '0')} $period';
  }

  factory TimetableSlot.fromMap(Map<String, dynamic> map) {
    return TimetableSlot(
      id: map['id'].toString(),
      instituteId: map['institute_id'] as String,
      academicSessionId: map['academic_session_id']?.toString(),
      classId: map['class_id'].toString(),
      subjectId: map['subject_id'].toString(),
      teacherId: map['teacher_id'].toString(),
      roomName: map['room_name'] as String,
      dayOfWeek: (map['day_of_week'] as num).toInt(),
      periodSlot: (map['period_slot'] as num).toInt(),
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      isLab: (map['is_lab'] as int? ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc() ??
              DateTime.now().toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
    );
  }

  /// Supabase replication payload: mirrors the local row with JSON-native
  /// types and excludes local-only bookkeeping (`sync_status`, `is_synced`).
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'institute_id': instituteId,
      'academic_session_id': academicSessionId,
      'class_id': classId,
      'subject_id': subjectId,
      'teacher_id': teacherId,
      'room_name': roomName,
      'day_of_week': dayOfWeek,
      'period_slot': periodSlot,
      'start_time': startTime,
      'end_time': endTime,
      'is_lab': isLab,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institute_id': instituteId,
      'academic_session_id': academicSessionId,
      'class_id': classId,
      'subject_id': subjectId,
      'teacher_id': teacherId,
      'room_name': roomName,
      'day_of_week': dayOfWeek,
      'period_slot': periodSlot,
      'start_time': startTime,
      'end_time': endTime,
      'is_lab': isLab ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'sync_status': syncStatus.value,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  TimetableSlot copyWith({
    String? id,
    String? instituteId,
    String? academicSessionId,
    String? classId,
    String? subjectId,
    String? teacherId,
    String? roomName,
    int? dayOfWeek,
    int? periodSlot,
    String? startTime,
    String? endTime,
    bool? isLab,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSynced,
  }) {
    return TimetableSlot(
      id: id ?? this.id,
      instituteId: instituteId ?? this.instituteId,
      academicSessionId: academicSessionId ?? this.academicSessionId,
      classId: classId ?? this.classId,
      subjectId: subjectId ?? this.subjectId,
      teacherId: teacherId ?? this.teacherId,
      roomName: roomName ?? this.roomName,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      periodSlot: periodSlot ?? this.periodSlot,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isLab: isLab ?? this.isLab,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}