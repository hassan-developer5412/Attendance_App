import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_session.dart';

class AttendanceSessionRepository {
  AttendanceSessionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<AttendanceSession>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'attendance_sessions',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'session_date DESC',
    );
    return rows.map(AttendanceSession.fromMap).toList();
  }

  Future<AttendanceSession?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'attendance_sessions',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceSession.fromMap(rows.first);
  }

  Future<AttendanceSession?> getByDateAndContext({
    required String date,
    String? subjectCode,
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'attendance_sessions',
      where: 'session_date = ? AND is_deleted = 0',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceSession.fromMap(rows.first);
  }

  Future<AttendanceSession> insert(AttendanceSession session) async {
    final db = await _dbHelper.database;
    await db.insert('attendance_sessions', session.toMap());
    return session;
  }

  Future<void> update(AttendanceSession session) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = session.copyWith(updatedAt: now);
    await db.update(
      'attendance_sessions',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'attendance_sessions',
        {
          'is_deleted': 1,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Soft delete associated attendance records
      await txn.update(
        'attendance_records',
        {
          'is_deleted': 1,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'session_id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<AttendanceSession>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'attendance_sessions',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(AttendanceSession.fromMap).toList();
  }
}
