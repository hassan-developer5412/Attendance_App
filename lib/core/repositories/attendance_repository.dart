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

  /// Deterministic session id for an academic context + date.
  static String sessionIdFor({
    required String academicSessionId,
    required int classId,
    required int subjectId,
    required DateTime date,
  }) {
    return UuidUtils.deterministic(
      'attendance_sessions',
      '$academicSessionId|$classId|$subjectId|${AppDateUtils.dateKey(date)}',
    );
  }

  /// Finds (or lazily creates) the attendance session for a subject on a date.
  Future<String> ensureSession({
    required String departmentId,
    required String academicSessionId,
    required int classId,
    required String year,
    required int subjectId,
    required DateTime date,
    String subjectCode = '',
    String? teacherId,
    String remarks = '',
  }) async {
    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);
    final sessionId = sessionIdFor(
      academicSessionId: academicSessionId,
      classId: classId,
      subjectId: subjectId,
      date: date,
    );
    final existing = await db.query(
      'attendance_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (existing.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('attendance_sessions', {
        'id': sessionId,
        'subject_code': subjectCode,
        'department_id': departmentId,
        'faculty_id': teacherId ?? '',
        'session_date': dateStr,
        'academic_session_id': academicSessionId,
        'class_id': classId,
        'year': year,
        'subject_id': subjectId,
        'remarks': remarks,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
    }
    return sessionId;
  }

  /// All attendance records for a session, joined with student details.
  Future<List<AttendanceRecord>> getForSession(String sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        a.id, a.uuid, a.session_id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        a.created_at, a.updated_at, a.sync_status, a.is_deleted,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.session_id = ? AND a.is_deleted = 0 AND s.is_deleted = 0
      ORDER BY s.name ASC
    ''', [sessionId]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  /// Inserts or updates a single student's status within a session.
  Future<void> upsertAttendanceForSession({
    required String sessionId,
    required int studentId,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await db.query(
      'attendance_records',
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
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
      // Reuse the session's date so records keep a consistent date key.
      final sessionRow = await db.query(
        'attendance_sessions',
        columns: ['session_date'],
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      final recordDate = sessionRow.isNotEmpty
          ? (sessionRow.first['session_date'] as String? ??
              AppDateUtils.dateKey(DateTime.now()))
          : AppDateUtils.dateKey(DateTime.now());
      await db.insert('attendance_records', {
        'uuid': UuidUtils.generate(),
        'session_id': sessionId,
        'student_id': studentId,
        'date': recordDate,
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

  /// Backward-compatible upsert by student and date.
  /// If [sessionId] is provided, delegates to [upsertAttendanceForSession].
  /// Otherwise, updates any existing record for that student on that date,
  /// or creates/finds a daily session to attach the record to.
  Future<void> upsertAttendance({
    required int studentId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    String? sessionId,
  }) async {
    if (sessionId != null && sessionId.isNotEmpty) {
      return upsertAttendanceForSession(
        sessionId: sessionId,
        studentId: studentId,
        status: status,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
      );
    }

    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);
    final now = DateTime.now().toUtc().toIso8601String();

    final existing = await db.query(
      'attendance_records',
      where: 'student_id = ? AND date = ? AND is_deleted = 0',
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
      final defaultSessionId = UuidUtils.deterministic(
        'attendance_sessions',
        'daily|$dateStr',
      );
      final sessionCheck = await db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [defaultSessionId],
        limit: 1,
      );
      if (sessionCheck.isEmpty) {
        await db.insert('attendance_sessions', {
          'id': defaultSessionId,
          'subject_code': 'GENERAL',
          'department_id': '',
          'faculty_id': '',
          'session_date': dateStr,
          'academic_session_id': '',
          'remarks': 'Daily attendance',
          'created_at': now,
          'updated_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        });
      }

      await db.insert('attendance_records', {
        'uuid': UuidUtils.generate(),
        'session_id': defaultSessionId,
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

  /// Convenience wrapper that marks attendance directly from the academic
  /// context (department → session → class → year → subject → date).
  Future<void> upsertAttendanceForContext({
    required String departmentId,
    required String academicSessionId,
    required int classId,
    required String year,
    required int subjectId,
    required int studentId,
    required DateTime date,
    required AttendanceStatus status,
    String subjectCode = '',
    String? teacherId,
  }) async {
    final sessionId = await ensureSession(
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      classId: classId,
      year: year,
      subjectId: subjectId,
      subjectCode: subjectCode,
      teacherId: teacherId,
      date: date,
    );
    final checkIn =
        (status == AttendanceStatus.present || status == AttendanceStatus.late)
            ? DateTime.now()
            : null;
    await upsertAttendanceForSession(
      sessionId: sessionId,
      studentId: studentId,
      status: status,
      checkInTime: checkIn,
    );
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
        CASE WHEN c.class_name <> '' AND c.current_year <> ''
             THEN c.class_name || '-' || c.current_year
             ELSE c.name END AS class_name,
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
        CASE WHEN c.class_name <> '' AND c.current_year <> ''
             THEN c.class_name || '-' || c.current_year
             ELSE c.name END AS class_name,
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

  // ---------------------------------------------------------------------------
  // Subject-based reporting
  // ---------------------------------------------------------------------------

  /// Per-student attendance for a subject (present/late over total sessions).
  ///
  /// Returns rows `{studentId, name, rollNumber, classId, total, present,
  /// percentage}`.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceByStudent({
    required int subjectId,
    int? classId,
  }) async {
    final db = await _dbHelper.database;
    final args = <Object?>[subjectId];
    var classFilter = '';
    if (classId != null) {
      classFilter = ' AND s.class_id = ?';
      args.add(classId);
    }
    final rows = await db.rawQuery('''
      SELECT s.id AS student_id, s.name, s.roll_number, s.class_id,
        COUNT(a.id) AS total,
        SUM(CASE WHEN a.status IN ('present','late') THEN 1 ELSE 0 END) AS present
      FROM students s
      LEFT JOIN attendance_records a
        ON a.student_id = s.id AND a.is_deleted = 0
        AND a.session_id IN (
          SELECT id FROM attendance_sessions
          WHERE subject_id = ? AND is_deleted = 0
        )
      WHERE s.is_deleted = 0$classFilter
      GROUP BY s.id
      ORDER BY s.name ASC
    ''', args);
    return rows.map((row) {
      final total = (row['total'] as int?) ?? 0;
      final present = (row['present'] as int?) ?? 0;
      return {
        'studentId': row['student_id'],
        'name': row['name'],
        'rollNumber': row['roll_number'],
        'classId': row['class_id'],
        'total': total,
        'present': present,
        'percentage': total > 0 ? (present / total * 100) : 0.0,
      };
    }).toList();
  }

  /// Aggregate attendance for each subject within an academic session.
  Future<List<Map<String, dynamic>>> getSubjectAttendanceSummary({
    String? academicSessionId,
    int? classId,
  }) async {
    final db = await _dbHelper.database;
    final where = <String>['sub.is_deleted = 0'];
    final args = <Object?>[];
    if (academicSessionId != null && academicSessionId.isNotEmpty) {
      where.add('sub.academic_session_id = ?');
      args.add(academicSessionId);
    }
    if (classId != null) {
      where.add('sub.class_id = ?');
      args.add(classId);
    }
    final rows = await db.rawQuery('''
      SELECT sub.id AS subject_id, sub.name, sub.code, sub.class_id, sub.year,
        COUNT(a.id) AS total,
        SUM(CASE WHEN a.status IN ('present','late') THEN 1 ELSE 0 END) AS present
      FROM subjects sub
      LEFT JOIN attendance_sessions ses
        ON ses.subject_id = sub.id AND ses.is_deleted = 0
      LEFT JOIN attendance_records a
        ON a.session_id = ses.id AND a.is_deleted = 0
      WHERE ${where.join(' AND ')}
      GROUP BY sub.id
      ORDER BY sub.name ASC
    ''', args);
    return rows.map((row) {
      final total = (row['total'] as int?) ?? 0;
      final present = (row['present'] as int?) ?? 0;
      return {
        'subjectId': row['subject_id'],
        'name': row['name'],
        'code': row['code'],
        'classId': row['class_id'],
        'year': row['year'],
        'total': total,
        'present': present,
        'percentage': total > 0 ? (present / total * 100) : 0.0,
      };
    }).toList();
  }

  /// List of past attendance sessions recorded for [subjectId] with aggregate counts.
  Future<List<Map<String, dynamic>>> getSubjectSessionHistory(int subjectId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT
        s.id AS session_id,
        s.session_date,
        s.subject_code,
        s.department_id,
        s.academic_session_id,
        s.class_id,
        s.year,
        s.faculty_id,
        s.remarks,
        COUNT(a.id) AS total_marked,
        SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN a.status = 'late' THEN 1 ELSE 0 END) AS late_count,
        SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
        SUM(CASE WHEN a.status = 'leave' THEN 1 ELSE 0 END) AS leave_count
      FROM attendance_sessions s
      LEFT JOIN attendance_records a ON a.session_id = s.id AND a.is_deleted = 0
      WHERE s.subject_id = ? AND s.is_deleted = 0
      GROUP BY s.id
      ORDER BY s.session_date DESC, s.created_at DESC
    ''', [subjectId]);

    return rows.map((r) {
      final total = (r['total_marked'] as int?) ?? 0;
      final present = (r['present_count'] as int?) ?? 0;
      final late = (r['late_count'] as int?) ?? 0;
      final attended = present + late;
      final rate = total > 0 ? (attended / total * 100) : 0.0;
      return {
        'sessionId': r['session_id'],
        'sessionDate': r['session_date'] as String,
        'subjectCode': r['subject_code'] as String,
        'departmentId': r['department_id'],
        'academicSessionId': r['academic_session_id'],
        'classId': r['class_id'],
        'year': r['year'],
        'facultyId': r['faculty_id'],
        'remarks': r['remarks'] as String,
        'totalMarked': total,
        'presentCount': present,
        'lateCount': late,
        'absentCount': (r['absent_count'] as int?) ?? 0,
        'leaveCount': (r['leave_count'] as int?) ?? 0,
        'attendanceRate': rate,
      };
    }).toList();
  }

  /// Breakdown of attendance by subject for a given student.
  Future<List<Map<String, dynamic>>> getStudentAttendanceBySubject(int studentId) async {
    final db = await _dbHelper.database;
    final studentRow = await db.query(
      'students',
      columns: ['class_id', 'current_year'],
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [studentId],
      limit: 1,
    );
    if (studentRow.isEmpty) return [];
    final classId = studentRow.first['class_id'] as int;

    final rows = await db.rawQuery('''
      SELECT
        sub.id AS subject_id,
        sub.name AS subject_name,
        sub.code AS subject_code,
        sub.year AS subject_year,
        sub.subject_type,
        COUNT(a.id) AS total_sessions,
        SUM(CASE WHEN a.status IN ('present', 'late') THEN 1 ELSE 0 END) AS attended_count,
        SUM(CASE WHEN a.status = 'present' THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN a.status = 'late' THEN 1 ELSE 0 END) AS late_count,
        SUM(CASE WHEN a.status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
        SUM(CASE WHEN a.status = 'leave' THEN 1 ELSE 0 END) AS leave_count
      FROM subjects sub
      LEFT JOIN attendance_sessions ses ON ses.subject_id = sub.id AND ses.is_deleted = 0
      LEFT JOIN attendance_records a ON a.session_id = ses.id AND a.student_id = ? AND a.is_deleted = 0
      WHERE (sub.class_id = ? OR a.id IS NOT NULL) AND sub.is_deleted = 0
      GROUP BY sub.id
      ORDER BY sub.name ASC
    ''', [studentId, classId]);

    return rows.map((r) {
      final total = (r['total_sessions'] as int?) ?? 0;
      final attended = (r['attended_count'] as int?) ?? 0;
      final rate = total > 0 ? (attended / total * 100) : 0.0;
      return {
        'subjectId': r['subject_id'],
        'subjectName': r['subject_name'] as String,
        'subjectCode': r['subject_code'] as String,
        'subjectYear': r['subject_year'] as String,
        'subjectType': r['subject_type'] as String? ?? 'THEORY',
        'totalSessions': total,
        'attendedCount': attended,
        'presentCount': (r['present_count'] as int?) ?? 0,
        'lateCount': (r['late_count'] as int?) ?? 0,
        'absentCount': (r['absent_count'] as int?) ?? 0,
        'leaveCount': (r['leave_count'] as int?) ?? 0,
        'attendanceRate': rate,
      };
    }).toList();
  }

  /// Today's institute-wide attendance summary: total marked, present, late, absent, leave, rate.
  Future<Map<String, dynamic>> getTodayOverview() async {
    final db = await _dbHelper.database;
    final today = AppDateUtils.dateKey(DateTime.now());
    final rows = await db.rawQuery('''
      SELECT
        COUNT(id) AS total,
        SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END) AS present_count,
        SUM(CASE WHEN status = 'late' THEN 1 ELSE 0 END) AS late_count,
        SUM(CASE WHEN status = 'absent' THEN 1 ELSE 0 END) AS absent_count,
        SUM(CASE WHEN status = 'leave' THEN 1 ELSE 0 END) AS leave_count
      FROM attendance_records
      WHERE date = ? AND is_deleted = 0
    ''', [today]);

    if (rows.isEmpty) {
      return {
        'total': 0,
        'present': 0,
        'late': 0,
        'absent': 0,
        'leave': 0,
        'rate': 0.0,
      };
    }

    final total = (rows.first['total'] as int?) ?? 0;
    final present = (rows.first['present_count'] as int?) ?? 0;
    final late = (rows.first['late_count'] as int?) ?? 0;
    final attended = present + late;
    final rate = total > 0 ? (attended / total * 100) : 0.0;

    return {
      'total': total,
      'present': present,
      'late': late,
      'absent': (rows.first['absent_count'] as int?) ?? 0,
      'leave': (rows.first['leave_count'] as int?) ?? 0,
      'rate': rate,
    };
  }
}
