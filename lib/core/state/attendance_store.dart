import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';

/// Manages attendance records and subject-based attendance sessions backed
/// by [AttendanceRepository].
///
/// All student/class/subject identifiers are now UUID strings (v6 schema).
class AttendanceStore extends ChangeNotifier {
  AttendanceStore({AttendanceRepository? repository})
      : _repository = repository ?? AttendanceRepository();

  final AttendanceRepository _repository;

  List<AttendanceRecord> _records = [];

  /// Records loaded for the currently selected date or session.
  List<AttendanceRecord> get records => List.unmodifiable(_records);

  // ---------------------------------------------------------------------------
  // Subject-Based Attendance State
  // ---------------------------------------------------------------------------

  String? _currentSessionId;
  bool _isSessionLoaded = false;
  bool _isPreviouslySaved = false;
  bool _isSessionLocked = false;
  String _sessionRemarks = '';

  /// Draft statuses keyed by student UUID string.
  final Map<String, AttendanceStatus> _draftStatuses = {};

  String? get currentSessionId => _currentSessionId;
  bool get isSessionLoaded => _isSessionLoaded;
  bool get isPreviouslySaved => _isPreviouslySaved;
  bool get isSessionLocked => _isSessionLocked;
  String get sessionRemarks => _sessionRemarks;
  Map<String, AttendanceStatus> get draftStatuses =>
      Map.unmodifiable(_draftStatuses);

  AttendanceStatus getStatus(String studentId) {
    return _draftStatuses[studentId] ?? AttendanceStatus.present;
  }

  void setStatus(String studentId, AttendanceStatus status) {
    _draftStatuses[studentId] = status;
    notifyListeners();
  }

  void markAll(AttendanceStatus status) {
    for (final key in _draftStatuses.keys.toList()) {
      _draftStatuses[key] = status;
    }
    notifyListeners();
  }

  void updateRemarks(String remarks) {
    _sessionRemarks = remarks;
  }

  /// Loads attendance for a specific subject gathering:
  /// Department → Academic Session → Class → Year → Subject → Date.
  Future<void> loadSubjectAttendance({
    required String departmentId,
    required String academicSessionId,
    required String classId,
    required String year,
    required String subjectId,
    required DateTime date,
    required List<Student> students,
    String subjectCode = '',
  }) async {
    _isSessionLoaded = false;
    notifyListeners();

    final sessionId = AttendanceRepository.sessionIdFor(
      academicSessionId: academicSessionId,
      classId: classId,
      subjectId: subjectId,
      date: date,
    );
    _currentSessionId = sessionId;

    final existingRecords = await _repository.getForSession(sessionId);
    _records = existingRecords;

    _draftStatuses.clear();
    _sessionRemarks = '';
    _isSessionLocked = await _repository.isSessionLocked(sessionId);

    if (existingRecords.isNotEmpty) {
      _isPreviouslySaved = true;
      final recordMap = {for (final r in existingRecords) r.studentId: r.status};
      for (final student in students) {
        _draftStatuses[student.id] =
            recordMap[student.id] ?? AttendanceStatus.present;
      }
    } else {
      _isPreviouslySaved = false;
      for (final student in students) {
        _draftStatuses[student.id] = AttendanceStatus.present;
      }
    }

    _isSessionLoaded = true;
    notifyListeners();
  }

  /// Saves or updates the subject-based attendance session and all student records.
  Future<void> saveSubjectAttendance({
    required String departmentId,
    required String academicSessionId,
    required String classId,
    required String year,
    required String subjectId,
    required DateTime date,
    required List<Student> students,
    String subjectCode = '',
    String? teacherId,
    String remarks = '',
    bool isOverride = false,
  }) async {
    final sessionId = await _repository.ensureSession(
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      classId: classId,
      year: year,
      subjectId: subjectId,
      subjectCode: subjectCode,
      teacherId: teacherId,
      remarks: remarks,
      date: date,
    );
    _currentSessionId = sessionId;
    _sessionRemarks = remarks;

    final now = DateTime.now();
    for (final student in students) {
      final status = _draftStatuses[student.id] ?? AttendanceStatus.present;
      final checkIn = (status == AttendanceStatus.present ||
              status == AttendanceStatus.late)
          ? now
          : null;
      await _repository.upsertAttendanceForSession(
        sessionId: sessionId,
        studentId: student.id,
        status: status,
        checkInTime: checkIn,
        isOverride: isOverride,
      );
    }

    _isPreviouslySaved = true;
    _isSessionLocked = await _repository.isSessionLocked(sessionId);
    _records = await _repository.getForSession(sessionId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Backward-compatible CRUD
  // ---------------------------------------------------------------------------

  /// Loads all attendance records for [date], joined with student data.
  Future<void> loadForDate(DateTime date) async {
    _records = await _repository.getForDate(date);
    notifyListeners();
  }

  /// Inserts or updates an attendance record (upsert on student_id + date).
  Future<void> markAttendance({
    required String studentId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
  }) async {
    await _repository.upsertAttendance(
      studentId: studentId,
      date: date,
      status: status,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
    );
    await loadForDate(date);
  }

  // ---------------------------------------------------------------------------
  // Dashboard queries
  // ---------------------------------------------------------------------------

  Future<int> todayLateCount() => _repository.getTodayLateCount();
  Future<Map<String, dynamic>> todayOverview() => _repository.getTodayOverview();
  Future<List<Map<String, int>>> weeklyStats() => _repository.getWeeklyStats();
  Future<Map<AttendanceStatus, int>> monthlyDistribution() =>
      _repository.getMonthlyDistribution();
  Future<List<AttendanceRecord>> recentActivity({int limit = 5}) =>
      _repository.getRecentActivity(limit: limit);

  // ---------------------------------------------------------------------------
  // Reports queries
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> monthlyTrend({int months = 6}) async {
    final trend = await _repository.getMonthlyTrend();
    if (months >= trend.length) return trend;
    return trend.sublist(trend.length - months);
  }

  Future<List<Map<String, dynamic>>> classComparison() =>
      _repository.getClassComparison();

  Future<List<Map<String, dynamic>>> topAttenders({int limit = 5}) =>
      _repository.getTopAttenders(limit: limit);

  /// Sessions history for a subject.
  Future<List<Map<String, dynamic>>> getSubjectSessionHistory(
          String subjectId) =>
      _repository.getSubjectSessionHistory(subjectId);

  /// Per-student attendance for a subject.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceByStudent({
    required String subjectId,
    String? classId,
  }) =>
      _repository.getSubjectAttendanceByStudent(
        subjectId: subjectId,
        classId: classId,
      );

  /// Summary for all subjects in a session or class.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceSummary({
    String? academicSessionId,
    String? classId,
  }) =>
      _repository.getSubjectAttendanceSummary(
        academicSessionId: academicSessionId,
        classId: classId,
      );

  /// Attendance breakdown across subjects for a student.
  Future<List<Map<String, dynamic>>> getStudentAttendanceBySubject(
          String studentId) =>
      _repository.getStudentAttendanceBySubject(studentId);

  /// Per-subject attendance analytics for a student including recent trend
  /// (last 5 sessions vs overall average).
  Future<List<Map<String, dynamic>>> getStudentSubjectAnalytics(String studentId) async {
    // Base per‑subject analytics from the repository
    final List<Map<String, dynamic>> base = await _repository.getStudentSubjectAnalytics(studentId);
    // Enrich each subject entry with recent‑trend information (last 5 sessions)
    for (final item in base) {
      final String subjectId = item['subject_id'] as String;
      final recent = await _repository.getSubjectRecentStats(studentId, subjectId, limit: 5);
      final int recentSessions = recent['recentSessions'] as int? ?? 0;
      final double? recentRate = recent['recentRate'] as double?;
      final double overallRate = (item['attendanceRate'] as num?)?.toDouble() ?? 0.0;
      final double? trend = recentRate != null ? recentRate - overallRate : null;
      item['recentSessions'] = recentSessions;
      item['recentRate'] = recentRate;
      item['trend'] = trend;
    }
    return base;
  }

  /// Detailed attendance log records for a student.
  Future<List<Map<String, dynamic>>> getDetailedAttendanceForStudent(
          String studentId) =>
      _repository.getDetailedAttendanceForStudent(studentId);
}
