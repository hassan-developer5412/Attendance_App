import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';

/// Manages attendance records backed by [AttendanceRepository].
class AttendanceStore extends ChangeNotifier {
  AttendanceStore({AttendanceRepository? repository})
      : _repository = repository ?? AttendanceRepository();

  final AttendanceRepository _repository;

  List<AttendanceRecord> _records = [];

  /// Records loaded for the currently selected date.
  List<AttendanceRecord> get records => List.unmodifiable(_records);

  // ---------------------------------------------------------------------------
  // Core CRUD
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

  /// Returns present/absent counts for each weekday of the current week.
  ///
  /// Result: list of 5 maps `{present: int, absent: int}` for Mon-Fri.
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
  ///
  /// Returns a list of `{month: String, rate: double}`.
  Future<List<Map<String, dynamic>>> monthlyTrend({int months = 6}) async {
    final trend = await _repository.getMonthlyTrend();
    if (months >= trend.length) return trend;
    return trend.sublist(trend.length - months);
  }

  /// Average attendance rate per class for the current month.
  ///
  /// Returns a list of `{className: String, rate: double}`.
  Future<List<Map<String, dynamic>>> classComparison() =>
      _repository.getClassComparison();

  /// Top students by attendance rate for the current month.
  ///
  /// Returns a list of `{name, className, rate, onTimeRate}`.
  Future<List<Map<String, dynamic>>> topAttenders({int limit = 5}) =>
      _repository.getTopAttenders(limit: limit);
}
