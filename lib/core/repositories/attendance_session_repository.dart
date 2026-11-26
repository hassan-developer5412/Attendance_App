import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_session.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Local persistence for [AttendanceSession] rows with RBAC enforcement.
///
/// Session creation, updates (which also cover locking/unlocking session
/// state), and deletion are guarded by the attendance permission codes in
/// [PermissionCodes]. Teacher-assigned class/subject restrictions are
/// preserved by delegating to
/// [AttendanceRepository.ensureClassAndSubjectAuthorized], so a regular teacher
/// can only manage sessions for classes and subjects they teach; institute-wide
/// and department-wide attendance users are unrestricted.
class AttendanceSessionRepository {
  AttendanceSessionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _attendanceRepository = AttendanceRepository(
          dbHelper: dbHelper ?? DatabaseHelper.instance,
        );

  final DatabaseHelper _dbHelper;
  /// Used for teacher class/subject authorization checks on session writes.
  final AttendanceRepository _attendanceRepository;

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

  /// Requires [code] from the current user
  /// ([PermissionService.instance.currentUserId]). Fail-closed: unauthenticated
  /// or suspended users, and users missing the grant, are denied.
  void _requirePermission(String code) {
    final uid = PermissionService.instance.currentUserId;
    if (!PermissionService.instance.hasPermission(code, userId: uid)) {
      throw PermissionDeniedException(code, userId: uid);
    }
  }

  /// Enforces teacher-assigned class/subject restrictions for [session].
  /// No-op when the session carries no class/subject or the user holds
  /// institute-wide / department-wide attendance authority.
  Future<void> _ensureClassAndSubjectAuthorized(
      AttendanceSession session) async {
    final classId = session.classId;
    final subjectId = session.subjectId;
    if ((classId == null || classId.isEmpty) ||
        (subjectId == null || subjectId.isEmpty)) {
      return;
    }
    await _attendanceRepository
        .ensureClassAndSubjectAuthorized(classId, subjectId);
  }

  Future<AttendanceSession> insert(AttendanceSession session) async {
    // Creating a session is part of marking attendance.
    _requirePermission(PermissionCodes.attendanceMark);
    await _ensureClassAndSubjectAuthorized(session);
    final db = await _dbHelper.database;
    await db.insert('attendance_sessions', session.toMap());
    SyncService.instance.schedulePush(
      'attendance_sessions',
      idColumn: 'id',
      idValue: session.id,
    );
    return session;
  }

  Future<void> update(AttendanceSession session) async {
    // Updates include any session state change, e.g. locking or unlocking a
    // session for further edits.
    _requirePermission(PermissionCodes.attendanceEdit);
    await _ensureClassAndSubjectAuthorized(session);
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = session.copyWith(updatedAt: now);
    await db.update(
      'attendance_sessions',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
    SyncService.instance.schedulePush(
      'attendance_sessions',
      idColumn: 'id',
      idValue: session.id,
    );
  }

  Future<void> softDelete(String id) async {
    _requirePermission(PermissionCodes.attendanceDelete);
    // Preserve class/subject restrictions on the row being deleted.
    final session = await getById(id);
    if (session != null) {
      await _ensureClassAndSubjectAuthorized(session);
    }
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
    SyncService.instance.schedulePush(
      'attendance_sessions',
      idColumn: 'id',
      idValue: id,
    );
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
