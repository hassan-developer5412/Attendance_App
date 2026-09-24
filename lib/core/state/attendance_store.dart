import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/utils/date_utils.dart';

/// Manages attendance records backed by the SQLite attendance_records table.
class AttendanceStore extends ChangeNotifier {
  List<AttendanceRecord> _records = [];

  /// Records loaded for the currently selected date.
  List<AttendanceRecord> get records => List.unmodifiable(_records);

  // ---------------------------------------------------------------------------
  // Core CRUD
  // ---------------------------------------------------------------------------

  /// Loads all attendance records for [date], joined with student data.
  Future<void> loadForDate(DateTime date) async {
    final db = await DatabaseHelper.instance.database;
    final dateStr = AppDateUtils.dateKey(date);

    final rows = await db.rawQuery('''
      SELECT
        a.id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.date = ?
      ORDER BY s.name ASC
    ''', [dateStr]);

    _records = rows.map(AttendanceRecord.fromMap).toList();
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
    final db = await DatabaseHelper.instance.database;
    final dateStr = AppDateUtils.dateKey(date);

    // Check for existing record.
    final existing = await db.query(
      'attendance_records',
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, dateStr],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      await db.update(
        'attendance_records',
        {
          'status': status.value,
          'check_in_time': checkInTime?.toIso8601String(),
          'check_out_time': checkOutTime?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('attendance_records', {
        'student_id': studentId,
        'date': dateStr,
        'status': status.value,
        'check_in_time': checkInTime?.toIso8601String(),
        'check_out_time': checkOutTime?.toIso8601String(),
      });
    }

    await loadForDate(date);
  }

  // ---------------------------------------------------------------------------
  // Dashboard queries
  // ---------------------------------------------------------------------------

  /// Number of students marked late today.
  Future<int> todayLateCount() async {
    final db = await DatabaseHelper.instance.database;
    final today = AppDateUtils.dateKey(DateTime.now());
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status = 'late'",
      [today],
    );
    return result.first['cnt'] as int;
  }

  /// Returns present/absent counts for each weekday of the current week.
  ///
  /// Result: list of 5 maps `{present: int, absent: int}` for Mon–Fri.
  Future<List<Map<String, int>>> weeklyStats() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    // Find the Monday of the current week.
    final monday = now.subtract(Duration(days: now.weekday - 1));

    final stats = <Map<String, int>>[];
    for (int i = 0; i < 5; i++) {
      final day = monday.add(Duration(days: i));
      final dateStr = AppDateUtils.dateKey(day);

      final present = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status IN ('present', 'late')",
        [dateStr],
      );
      final absent = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status = 'absent'",
        [dateStr],
      );

      stats.add({
        'present': present.first['cnt'] as int,
        'absent': absent.first['cnt'] as int,
      });
    }
    return stats;
  }

  /// Returns the count of each [AttendanceStatus] for the current month.
  Future<Map<AttendanceStatus, int>> monthlyDistribution() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final startOfMonth = AppDateUtils.dateKey(DateTime(now.year, now.month, 1));
    final endOfMonth = AppDateUtils.dateKey(
      DateTime(now.year, now.month, AppDateUtils.daysInMonth(now.year, now.month)),
    );

    final result = <AttendanceStatus, int>{};
    for (final status in AttendanceStatus.values) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM attendance_records WHERE date >= ? AND date <= ? AND status = ?',
        [startOfMonth, endOfMonth, status.value],
      );
      result[status] = rows.first['cnt'] as int;
    }
    return result;
  }

  /// Returns the most recent attendance records for the dashboard activity feed.
  Future<List<AttendanceRecord>> recentActivity({int limit = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery('''
      SELECT
        a.id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      ORDER BY a.date DESC, a.check_in_time DESC
      LIMIT ?
    ''', [limit]);

    return rows.map(AttendanceRecord.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Reports queries
  // ---------------------------------------------------------------------------

  /// Monthly attendance rate for the last [months] months.
  ///
  /// Returns a list of `{month: String, rate: double}`.
  Future<List<Map<String, dynamic>>> monthlyTrend({int months = 6}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final trends = <Map<String, dynamic>>[];

    for (int i = months - 1; i >= 0; i--) {
      final date = DateTime(now.year, now.month - i, 1);
      final year = date.year;
      final month = date.month;
      final startDate = AppDateUtils.dateKey(DateTime(year, month, 1));
      final endDate = AppDateUtils.dateKey(
        DateTime(year, month, AppDateUtils.daysInMonth(year, month)),
      );

      final total = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM attendance_records WHERE date >= ? AND date <= ?',
        [startDate, endDate],
      );
      final present = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date >= ? AND date <= ? AND status IN ('present', 'late')",
        [startDate, endDate],
      );

      final totalCount = total.first['cnt'] as int;
      final presentCount = present.first['cnt'] as int;
      final rate = totalCount > 0 ? (presentCount / totalCount * 100) : 0.0;

      trends.add({'month': _monthLabel(month), 'rate': rate});
    }
    return trends;
  }

  /// Average attendance rate per class for the current month.
  ///
  /// Returns a list of `{className: String, rate: double}`.
  Future<List<Map<String, dynamic>>> classComparison() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final startDate = AppDateUtils.dateKey(DateTime(now.year, now.month, 1));
    final endDate = AppDateUtils.dateKey(
      DateTime(now.year, now.month, AppDateUtils.daysInMonth(now.year, now.month)),
    );

    final rows = await db.rawQuery('''
      SELECT
        c.name || ' — ' || c.section AS class_name,
        COUNT(a.id) AS total,
        SUM(CASE WHEN a.status IN ('present', 'late') THEN 1 ELSE 0 END) AS present_count
      FROM classes c
      INNER JOIN students s ON s.class_id = c.id
      LEFT JOIN attendance_records a ON a.student_id = s.id
        AND a.date >= ? AND a.date <= ?
      GROUP BY c.id
      ORDER BY c.name ASC
    ''', [startDate, endDate]);

    return rows.map((row) {
      final total = row['total'] as int;
      final presentCount = row['present_count'] as int;
      final rate = total > 0 ? (presentCount / total * 100) : 0.0;
      return {'className': row['class_name'] as String, 'rate': rate};
    }).toList();
  }

  /// Top students by attendance rate for the current month.
  ///
  /// Returns a list of `{name, className, rate, onTimeRate}`.
  Future<List<Map<String, dynamic>>> topAttenders({int limit = 5}) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final startDate = AppDateUtils.dateKey(DateTime(now.year, now.month, 1));
    final endDate = AppDateUtils.dateKey(
      DateTime(now.year, now.month, AppDateUtils.daysInMonth(now.year, now.month)),
    );

    final rows = await db.rawQuery('''
      SELECT
        s.name,
        c.name || ' — ' || c.section AS class_name,
        COUNT(a.id) AS total,
        SUM(CASE WHEN a.status IN ('present', 'late') THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS on_time_count
      FROM students s
      INNER JOIN classes c ON c.id = s.class_id
      INNER JOIN attendance_records a ON a.student_id = s.id
        AND a.date >= ? AND a.date <= ?
      GROUP BY s.id
      HAVING total > 0
      ORDER BY (CAST(present_count AS REAL) / total) DESC
      LIMIT ?
    ''', [startDate, endDate, limit]);

    return rows.map((row) {
      final total = row['total'] as int;
      final presentCount = row['present_count'] as int;
      final onTimeCount = row['on_time_count'] as int;
      return {
        'name': row['name'] as String,
        'className': row['class_name'] as String,
        'rate': total > 0 ? (presentCount / total * 100).round() : 0,
        'onTimeRate': total > 0 ? (onTimeCount / total * 100).round() : 0,
      };
    }).toList();
  }

  static String _monthLabel(int month) {
    const labels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return labels[month - 1];
  }
}
