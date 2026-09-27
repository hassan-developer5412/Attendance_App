import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/utils/date_utils.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

class AttendanceRepository {
  AttendanceRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<AttendanceRecord>> getForDate(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);

    final rows = await db.rawQuery('''
      SELECT
        a.id, a.uuid, a.session_id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        a.created_at, a.updated_at, a.sync_status, a.is_deleted,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.date = ? AND a.is_deleted = 0 AND s.is_deleted = 0
      ORDER BY s.name ASC
    ''', [dateStr]);

    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<void> upsertAttendance({
    required int studentId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
  }) async {
    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);
    final now = DateTime.now().toUtc().toIso8601String();

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
          'updated_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      final sessionUuid = UuidUtils.deterministic('attendance_sessions', dateStr);
      // Ensure session exists
      final sessionRow = await db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [sessionUuid],
        limit: 1,
      );
      if (sessionRow.isEmpty) {
        await db.insert('attendance_sessions', {
          'id': sessionUuid,
          'subject_code': 'GENERAL',
          'department_id': UuidUtils.deterministic('departments', 'DAE-CIT'),
          'faculty_id': '',
          'session_date': dateStr,
          'remarks': 'Daily Session',
          'created_at': now,
          'updated_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        });
      }

      final recordUuid = UuidUtils.generate();
      await db.insert('attendance_records', {
        'uuid': recordUuid,
        'session_id': sessionUuid,
        'student_id': studentId,
        'date': dateStr,
        'status': status.value,
        'check_in_time': checkInTime?.toIso8601String(),
        'check_out_time': checkOutTime?.toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
    }
  }

  Future<int> getTodayLateCount() async {
    final db = await _dbHelper.database;
    final today = AppDateUtils.dateKey(DateTime.now());
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status = 'late' AND is_deleted = 0",
      [today],
    );
    return result.first['cnt'] as int;
  }

  Future<List<Map<String, int>>> getWeeklyStats() async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));

    final stats = <Map<String, int>>[];

    for (var i = 0; i < 5; i++) {
      final day = monday.add(Duration(days: i));
      final dateStr = AppDateUtils.dateKey(day);

      final present = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status IN ('present', 'late') AND is_deleted = 0",
        [dateStr],
      );
      final absent = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date = ? AND status = 'absent' AND is_deleted = 0",
        [dateStr],
      );

      stats.add({
        'present': present.first['cnt'] as int,
        'absent': absent.first['cnt'] as int,
      });
    }

    return stats;
  }

  Future<Map<AttendanceStatus, int>> getMonthlyDistribution() async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final startDate = AppDateUtils.dateKey(DateTime(now.year, now.month, 1));
    final endDate = AppDateUtils.dateKey(
      DateTime(now.year, now.month, AppDateUtils.daysInMonth(now.year, now.month)),
    );

    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) AS cnt
      FROM attendance_records
      WHERE date >= ? AND date <= ? AND is_deleted = 0
      GROUP BY status
    ''', [startDate, endDate]);

    final map = {for (final s in AttendanceStatus.values) s: 0};
    for (final row in rows) {
      final status = AttendanceStatus.fromString(row['status'] as String);
      map[status] = row['cnt'] as int;
    }
    return map;
  }

  Future<List<AttendanceRecord>> getRecentActivity({int limit = 10}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        a.id, a.uuid, a.session_id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        a.created_at, a.updated_at, a.sync_status, a.is_deleted,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.is_deleted = 0 AND s.is_deleted = 0
      ORDER BY a.id DESC
      LIMIT ?
    ''', [limit]);

    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getMonthlyTrend() async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final trends = <Map<String, dynamic>>[];

    for (var i = 5; i >= 0; i--) {
      final target = DateTime(now.year, now.month - i, 1);
      final year = target.year;
      final month = target.month;
      final startDate = AppDateUtils.dateKey(DateTime(year, month, 1));
      final endDate = AppDateUtils.dateKey(
        DateTime(year, month, AppDateUtils.daysInMonth(year, month)),
      );

      final total = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM attendance_records WHERE date >= ? AND date <= ? AND is_deleted = 0',
        [startDate, endDate],
      );
      final present = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM attendance_records WHERE date >= ? AND date <= ? AND status IN ('present', 'late') AND is_deleted = 0",
        [startDate, endDate],
      );

      final totalCount = total.first['cnt'] as int;
      final presentCount = present.first['cnt'] as int;
      final rate = totalCount > 0 ? (presentCount / totalCount * 100) : 0.0;

      trends.add({'month': _monthLabel(month), 'rate': rate});
    }
    return trends;
  }

  Future<List<Map<String, dynamic>>> getClassComparison() async {
    final db = await _dbHelper.database;
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
      INNER JOIN students s ON s.class_id = c.id AND s.is_deleted = 0
      LEFT JOIN attendance_records a ON a.student_id = s.id
        AND a.date >= ? AND a.date <= ? AND a.is_deleted = 0
      WHERE c.is_deleted = 0
      GROUP BY c.id
      ORDER BY c.name ASC
    ''', [startDate, endDate]);

    return rows.map((row) {
      final total = row['total'] as int;
      final presentCount = (row['present_count'] as int?) ?? 0;
      final rate = total > 0 ? (presentCount / total * 100) : 0.0;
      return {'className': row['class_name'] as String, 'rate': rate};
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getTopAttenders({int limit = 5}) async {
    final db = await _dbHelper.database;
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
      INNER JOIN classes c ON c.id = s.class_id AND c.is_deleted = 0
      INNER JOIN attendance_records a ON a.student_id = s.id
        AND a.date >= ? AND a.date <= ? AND a.is_deleted = 0
      WHERE s.is_deleted = 0
      GROUP BY s.id
      HAVING total > 0
      ORDER BY (CAST(present_count AS REAL) / total) DESC
      LIMIT ?
    ''', [startDate, endDate, limit]);

    return rows.map((row) {
      final total = row['total'] as int;
      final presentCount = (row['present_count'] as int?) ?? 0;
      final onTimeCount = (row['on_time_count'] as int?) ?? 0;
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
