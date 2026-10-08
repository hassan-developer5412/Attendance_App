import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/academic_session.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Repository for academic sessions (e.g. `2025-26`, `2026-27`).
///
/// This app does **not** use semesters — sessions represent full academic
/// years. Previous sessions are retained for historic reporting.
class AcademicSessionRepository {
  AcademicSessionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<AcademicSession>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'academic_sessions',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'start_date DESC',
    );
    return rows.map(AcademicSession.fromMap).toList();
  }

  Future<AcademicSession?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'academic_sessions',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AcademicSession.fromMap(rows.first);
  }

  /// Returns the session currently marked active, if any.
  Future<AcademicSession?> getCurrent() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'academic_sessions',
      where: 'is_current = 1 AND is_deleted = 0',
      orderBy: 'start_date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AcademicSession.fromMap(rows.first);
  }

  Future<AcademicSession> insert(AcademicSession session) async {
    final db = await _dbHelper.database;
    await db.insert('academic_sessions', session.toMap());
    if (session.isCurrent) {
      await _clearCurrentExcept(session.id);
    }
    SyncService.instance.schedulePush(
      'academic_sessions',
      idColumn: 'id',
      idValue: session.id,
    );
    return session;
  }

  Future<void> update(AcademicSession session) async {
    final db = await _dbHelper.database;
    final updated = session.copyWith(updatedAt: DateTime.now().toUtc());
    await db.update(
      'academic_sessions',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
    if (session.isCurrent) {
      await _clearCurrentExcept(session.id);
    }
    SyncService.instance.schedulePush(
      'academic_sessions',
      idColumn: 'id',
      idValue: session.id,
    );
  }

  /// Marks [id] as the current session and clears the flag on all others.
  Future<void> setCurrent(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'academic_sessions',
      {'is_current': 0, 'updated_at': now, 'sync_status': 'PENDING'},
    );
    await db.update(
      'academic_sessions',
      {'is_current': 1, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id = ?',
      whereArgs: [id],
    );
    // The demoted sessions are marked PENDING for the background flush;
    // push the newly-current session immediately.
    SyncService.instance.schedulePush(
      'academic_sessions',
      idColumn: 'id',
      idValue: id,
    );
  }

  /// Soft deletes (archives) a session. Existing records keep referencing it.
  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'academic_sessions',
      {
        'is_deleted': 1,
        'is_current': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'academic_sessions',
      idColumn: 'id',
      idValue: id,
    );
  }

  Future<void> restore(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'academic_sessions',
      {
        'is_deleted': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'academic_sessions',
      idColumn: 'id',
      idValue: id,
    );
  }

  Future<List<AcademicSession>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'academic_sessions',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(AcademicSession.fromMap).toList();
  }

  Future<void> _clearCurrentExcept(String keepId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'academic_sessions',
      {'is_current': 0, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id <> ?',
      whereArgs: [keepId],
    );
  }
}
