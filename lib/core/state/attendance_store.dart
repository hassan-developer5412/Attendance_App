import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';

/// Manages attendance records and subject-based attendance sessions backed by [AttendanceRepository].
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
  String _sessionRemarks = '';
  final Map<int, AttendanceStatus> _draftStatuses = {};

  String? get currentSessionId => _currentSessionId;
  bool get isSessionLoaded => _isSessionLoaded;
  bool get isPreviouslySaved => _isPreviouslySaved;
  String get sessionRemarks => _sessionRemarks;
  Map<int, AttendanceStatus> get draftStatuses =>
      Map.unmodifiable(_draftStatuses);

  AttendanceStatus getStatus(int studentId) {
    return _draftStatuses[studentId] ?? AttendanceStatus.present;
  }

  void setStatus(int studentId, AttendanceStatus status) {
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
    required int classId,
    required String year,
    required int subjectId,
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
    required int classId,
    required String year,
    required int subjectId,
    required DateTime date,
    required List<Student> students,
    String subjectCode = '',
    String? teacherId,
    String remarks = '',
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
      );
    }

    _isPreviouslySaved = true;
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
    required int studentId,
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

  /// Number of students marked late today.
  Future<int> todayLateCount() => _repository.getTodayLateCount();

  /// Real-time today's institute-wide attendance summary.
  Future<Map<String, dynamic>> todayOverview() => _repository.getTodayOverview();

  /// Returns present/absent counts for each weekday of the current week.
  Future<List<Map<String, int>>> weeklyStats() => _repository.getWeeklyStats();

  /// Returns the count of each [AttendanceStatus] for the current month.
  Future<Map<AttendanceStatus, int>> monthlyDistribution() =>
      _repository.getMonthlyDistribution();

  /// Returns the most recent attendance records for the dashboard activity feed.
  Future<List<AttendanceRecord>> recentActivity({int limit = 5}) =>
      _repository.getRecentActivity(limit: limit);

  // ---------------------------------------------------------------------------
  // Reports queries
  // ---------------------------------------------------------------------------

  /// Monthly attendance rate for the last [months] months.
  Future<List<Map<String, dynamic>>> monthlyTrend({int months = 6}) async {
    final trend = await _repository.getMonthlyTrend();
    if (months >= trend.length) return trend;
    return trend.sublist(trend.length - months);
  }

  /// Average attendance rate per class for the current month.
  Future<List<Map<String, dynamic>>> classComparison() =>
      _repository.getClassComparison();

  /// Top students by attendance rate for the current month.
  Future<List<Map<String, dynamic>>> topAttenders({int limit = 5}) =>
      _repository.getTopAttenders(limit: limit);

  /// Sessions history for a subject.
  Future<List<Map<String, dynamic>>> getSubjectSessionHistory(int subjectId) =>
      _repository.getSubjectSessionHistory(subjectId);

  /// Per-student attendance for a subject.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceByStudent({
    required int subjectId,
    int? classId,
  }) =>
      _repository.getSubjectAttendanceByStudent(
        subjectId: subjectId,
        classId: classId,
      );

  /// Summary for all subjects in a session or class.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceSummary({
    String? academicSessionId,
    int? classId,
  }) =>
      _repository.getSubjectAttendanceSummary(
        academicSessionId: academicSessionId,
        classId: classId,
      );

  /// Attendance breakdown across subjects for a student.
  Future<List<Map<String, dynamic>>> getStudentAttendanceBySubject(
          int studentId) =>
      _repository.getStudentAttendanceBySubject(studentId);
}
