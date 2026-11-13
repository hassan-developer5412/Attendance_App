import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/date_utils.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Repository handling all attendance‑related DB operations.
class AttendanceRepository {
  AttendanceRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  // -------------------------------------------------------------------------
  // Helper / ID generation
  // -------------------------------------------------------------------------
  static String sessionIdFor({
    required String academicSessionId,
    required String classId,
    required String subjectId,
    required DateTime date,
  }) {
    return UuidUtils.deterministic(
      'attendance_sessions',
      '$academicSessionId|$classId|$subjectId|${AppDateUtils.dateKey(date)}',
    );
  }

  // -------------------------------------------------------------------------
  // Upsert methods
  // -------------------------------------------------------------------------
  Future<void> upsertAttendanceForSession({
    required String sessionId,
    required String studentId,
    required AttendanceStatus status,
    DateTime? checkInTime,
    bool isOverride = false,
  }) async {
    final db = await _dbHelper.database;
    final existing = await db.query(
      'attendance_records',
      where: 'session_id = ? AND student_id = ?',
      whereArgs: [sessionId, studentId],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isNotEmpty) {
      await db.update(
        'attendance_records',
        {
          'status': status.name,
          if (checkInTime != null) 'check_in_time': checkInTime.toUtc().toIso8601String(),
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'session_id = ? AND student_id = ?',
        whereArgs: [sessionId, studentId],
      );
    } else {
      await db.insert('attendance_records', {
        'id': UuidUtils.deterministic('attendance_records', '$sessionId|$studentId'),
        'session_id': sessionId,
        'student_id': studentId,
        'date': AppDateUtils.dateKey(DateTime.now()),
        'status': status.name,
        if (checkInTime != null) 'check_in_time': checkInTime.toUtc().toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
    }
    SyncService.instance.schedulePush(
      'attendance_records',
      idColumn: 'id',
      idValue: existing.isNotEmpty ? existing.first['id'] as String : UuidUtils.deterministic('attendance_records', '$sessionId|$studentId'),
    );
  }

  Future<void> upsertAttendance({
    required String studentId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkInTime,
    DateTime? checkOutTime,
  }) async {
    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);
    final existing = await db.query(
      'attendance_records',
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, dateStr],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    if (existing.isNotEmpty) {
      await db.update(
        'attendance_records',
        {
          'status': status.name,
          if (checkInTime != null) 'check_in_time': checkInTime.toUtc().toIso8601String(),
          if (checkOutTime != null) 'check_out_time': checkOutTime.toUtc().toIso8601String(),
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert('attendance_records', {
        'id': UuidUtils.deterministic('attendance_records', '$studentId|$dateStr'),
        'session_id': null,
        'student_id': studentId,
        'date': dateStr,
        'status': status.name,
        if (checkInTime != null) 'check_in_time': checkInTime.toUtc().toIso8601String(),
        if (checkOutTime != null) 'check_out_time': checkOutTime.toUtc().toIso8601String(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
      });
    }
    SyncService.instance.schedulePush(
      'attendance_records',
      idColumn: 'id',
      idValue: existing.isNotEmpty ? existing.first['id'] as String : UuidUtils.deterministic('attendance_records', '$studentId|$dateStr'),
    );
  }

  // -------------------------------------------------------------------------
  // Core query helpers used by store layer
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getStudentSubjectAnalytics(String studentId) async {
    final db = await _dbHelper.database;
    return await db.rawQuery('''
      SELECT
        sub.id AS subjectId,
        sub.name AS subjectName,
        sub.code AS subjectCode,
        sub.year AS subjectYear,
        sub.subject_type AS subjectType,
        COUNT(DISTINCT sess.id) AS totalSessions,
        SUM(CASE WHEN rec.status IN ('present','late') THEN 1 ELSE 0 END) AS attendedCount,
        SUM(CASE WHEN rec.status = 'present' THEN 1 ELSE 0 END) AS presentCount,
        SUM(CASE WHEN rec.status = 'late' THEN 1 ELSE 0 END) AS lateCount,
        SUM(CASE WHEN rec.status = 'absent' THEN 1 ELSE 0 END) AS absentCount,
        SUM(CASE WHEN rec.status = 'leave' THEN 1 ELSE 0 END) AS leaveCount,
        (SUM(CASE WHEN rec.status IN ('present','late') THEN 1 ELSE 0 END) * 100.0) / NULLIF(COUNT(rec.id), 0) AS attendanceRate
      FROM attendanceSessions sess
      JOIN attendanceRecords rec ON rec.session_id = sess.id
      JOIN subjects sub ON sub.id = sess.subject_id
      WHERE rec.student_id = ?
        AND rec.is_deleted = 0
        AND sess.is_deleted = 0
      GROUP BY sub.id;
    ''', [studentId]);
  }

  Future<List<AttendanceRecord>> getForDate(DateTime date) async {
    final db = await _dbHelper.database;
    final dateStr = AppDateUtils.dateKey(date);
    final rows = await db.rawQuery('''
      SELECT a.id, a.session_id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        a.created_at, a.updated_at, a.sync_status, a.is_deleted,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.date = ? AND a.is_deleted = 0 AND s.is_deleted = 0
      ORDER BY s.name ASC;
    ''', [dateStr]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<String> ensureSession({
    required String departmentId,
    required String academicSessionId,
    required String classId,
    required String year,
    required String subjectId,
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
      SyncService.instance.schedulePush('attendance_sessions', idColumn: 'id', idValue: sessionId);
    }
    return sessionId;
  }

  Future<List<AttendanceRecord>> getForSession(String sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT a.id, a.session_id, a.student_id, a.date, a.status,
        a.check_in_time, a.check_out_time,
        a.created_at, a.updated_at, a.sync_status, a.is_deleted,
        s.name AS student_name, s.roll_number, s.class_id
      FROM attendance_records a
      INNER JOIN students s ON s.id = a.student_id
      WHERE a.session_id = ? AND a.is_deleted = 0 AND s.is_deleted = 0
      ORDER BY s.name ASC;
    ''', [sessionId]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  static const Duration defaultEditDeadline = Duration(hours: 24);

  Future<bool> isSessionLocked(String sessionId, {Duration deadline = defaultEditDeadline}) async {
    final db = await _dbHelper.database;
    final rows = await db.query('attendance_sessions', where: 'id = ?', whereArgs: [sessionId]);
    if (rows.isEmpty) return true;
    final createdAt = DateTime.tryParse(rows.first['created_at'] as String? ?? '');
    if (createdAt == null) return true;
    return DateTime.now().toUtc().difference(createdAt) > deadline;
  }

  // -------------------------------------------------------------------------
  // Dashboard / reporting queries
  // -------------------------------------------------------------------------
  Future<int> getTodayLateCount() async {
    final db = await _dbHelper.database;
    final today = AppDateUtils.dateKey(DateTime.now());
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt FROM attendanceRecords
      WHERE date = ? AND status = 'late' AND isDeleted = 0
    ''', [today]);
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<Map<String, int>> getTodayOverview() async {
    final db = await _dbHelper.database;
    final today = AppDateUtils.dateKey(DateTime.now());
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) AS cnt FROM attendanceRecords
      WHERE date = ? AND isDeleted = 0
      GROUP BY status
    ''', [today]);
    final map = <String, int>{};
    for (final r in rows) {
      map[r['status'] as String] = r['cnt'] as int;
    }
    return map;
  }

  Future<List<Map<String, int>>> getWeeklyStats() async {
    final db = await _dbHelper.database;
    final start = DateTime.now().subtract(const Duration(days: 7));
    final startKey = AppDateUtils.dateKey(start);
    final rows = await db.rawQuery('''
      SELECT date, COUNT(*) AS cnt FROM attendanceRecords
      WHERE date >= ? AND isDeleted = 0
      GROUP BY date ORDER BY date ASC
    ''', [startKey]);
    return rows.map((r) => {r['date'] as String: r['cnt'] as int}).toList();
  }

  Future<Map<AttendanceStatus, int>> getMonthlyDistribution() async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final startKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final rows = await db.rawQuery('''
      SELECT status, COUNT(*) AS cnt FROM attendanceRecords
      WHERE date >= ? AND isDeleted = 0
      GROUP BY status
    ''', [startKey]);
    final map = <AttendanceStatus, int>{};
    for (final r in rows) {
      final statusStr = r['status'] as String;
      final status = AttendanceStatus.values.firstWhere((e) => e.name == statusStr, orElse: () => AttendanceStatus.present);
      map[status] = r['cnt'] as int;
    }
    return map;
  }

  Future<List<AttendanceRecord>> getRecentActivity({int limit = 5}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT * FROM attendance_records
      WHERE isDeleted = 0
      ORDER BY created_at DESC LIMIT ?
    ''', [limit]);
    return rows.map(AttendanceRecord.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getMonthlyTrend({int months = 6}) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final startMonth = DateTime(now.year, now.month - 5, 1);
    final startKey = AppDateUtils.dateKey(startMonth);
    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m', date) AS month, COUNT(*) AS cnt
      FROM attendanceRecords
      WHERE date >= ? AND isDeleted = 0
      GROUP BY month ORDER BY month ASC
    ''', [startKey]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getClassComparison() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT c.id AS classId, c.name AS className,
        (SUM(CASE WHEN r.status IN ('present','late') THEN 1 ELSE 0 END) * 100.0) / NULLIF(COUNT(r.id),0) AS attendanceRate
      FROM classes c
      JOIN attendance_sessions s ON s.class_id = c.id AND s.is_deleted = 0
      JOIN attendanceRecords r ON r.session_id = s.id AND r.is_deleted = 0
      GROUP BY c.id;
    ''');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getTopAttenders({int limit = 5}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT st.id, st.name, COUNT(r.id) AS attendedSessions
      FROM students st
      JOIN attendance_records r ON r.student_id = st.id AND r.is_deleted = 0 AND r.status IN ('present','late')
      GROUP BY st.id
      ORDER BY attendedSessions DESC
      LIMIT ?
    ''', [limit]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getSubjectSessionHistory(String subjectId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT s.id, s.session_date, s.remarks
      FROM attendance_sessions s
      WHERE s.subject_id = ? AND s.is_deleted = 0
      ORDER BY s.session_date DESC;
    ''', [subjectId]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getSubjectAttendanceByStudent({required String subjectId, String? classId}) async {
    final db = await _dbHelper.database;
    final whereClause = classId != null ? 'AND s.class_id = ?' : '';
    final args = <dynamic>[subjectId];
    if (classId != null) args.add(classId);
    final rows = await db.rawQuery('''
      SELECT st.id AS studentId, st.name, r.status, r.date
      FROM attendance_records r
      JOIN attendanceSessions s ON r.session_id = s.id AND s.is_deleted = 0
      JOIN students st ON r.student_id = st.id AND st.is_deleted = 0
      WHERE s.subject_id = ? $whereClause AND r.is_deleted = 0
      ORDER BY st.name ASC;
    ''', args);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getSubjectAttendanceSummary({String? academicSessionId, String? classId}) async {
    final db = await _dbHelper.database;
    final conditions = <String>[];
    final args = <dynamic>[];
    if (academicSessionId != null) {
      conditions.add('s.academic_session_id = ?');
      args.add(academicSessionId);
    }
    if (classId != null) {
      conditions.add('s.class_id = ?');
      args.add(classId);
    }
    final where = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final rows = await db.rawQuery('''
      SELECT sub.id AS subjectId, sub.name AS subjectName,
        COUNT(DISTINCT s.id) AS totalSessions,
        SUM(CASE WHEN r.status IN ('present','late') THEN 1 ELSE 0 END) AS attended,
        SUM(CASE WHEN r.status = 'absent' THEN 1 ELSE 0 END) AS absent
      FROM subjects sub
      JOIN attendance_sessions s ON s.subject_id = sub.id AND s.is_deleted = 0
      JOIN attendanceRecords r ON r.session_id = s.id AND r.is_deleted = 0
      $where
      GROUP BY sub.id;
    ''', args);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getStudentAttendanceBySubject(String studentId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT sub.id AS subjectId, sub.name AS subjectName,
        COUNT(*) AS totalSessions,
        SUM(CASE WHEN r.status IN ('present','late') THEN 1 ELSE 0 END) AS attended
      FROM attendanceRecords r
      JOIN attendance_sessions s ON r.session_id = s.id AND s.is_deleted = 0
      JOIN subjects sub ON s.subject_id = sub.id
      WHERE r.student_id = ? AND r.is_deleted = 0
      GROUP BY sub.id;
    ''', [studentId]);
    return rows;
  }

  Future<List<Map<String, dynamic>>> getDetailedAttendanceForStudent(String studentId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT r.*, s.session_date, sub.name AS subject_name
      FROM attendance_records r
      JOIN attendanceSessions s ON r.session_id = s.id AND s.is_deleted = 0
      JOIN subjects sub ON s.subject_id = sub.id
      WHERE r.student_id = ? AND r.is_deleted = 0
      ORDER BY s.session_date DESC;
    ''', [studentId]);
    return rows;
  }

  // -------------------------------------------------------------------------
  // Recent per‑subject stats for a student
  // -------------------------------------------------------------------------
  Future<Map<String, dynamic>> getSubjectRecentStats(String studentId, String subjectId, {int limit = 5}) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT r.status
      FROM attendanceRecords r
      JOIN attendance_sessions s ON r.session_id = s.id
      WHERE r.student_id = ?
        AND s.subject_id = ?
        AND r.is_deleted = 0
        AND s.is_deleted = 0
      ORDER BY s.session_date DESC
      LIMIT ?
    ''', [studentId, subjectId, limit]);
    final total = rows.length;
    int attended = 0;
    for (final row in rows) {
      final status = row['status'] as String? ?? '';
      if (status == 'present' || status == 'late') attended++;
    }
    final double? rate = total > 0 ? attended * 100.0 / total : null;
    return {'recentSessions': total, 'recentRate': rate};
  }
}
