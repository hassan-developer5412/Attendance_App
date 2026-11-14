import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';

class LeaveRepository {
  LeaveRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  static bool _schemaEnsured = false;

  Future<void> _ensureSchema(Database db) async {
    if (_schemaEnsured) return;
    await MigrationHelpers.addColumnIfNotExists(
      db,
      'leave_requests',
      'student_id',
      'TEXT',
    );
    await MigrationHelpers.addColumnIfNotExists(
      db,
      'leave_requests',
      'remarks',
      'TEXT',
    );
    await MigrationHelpers.addColumnIfNotExists(
      db,
      'leave_requests',
      'attachment_url',
      'TEXT',
    );
    _schemaEnsured = true;
  }

  Future<List<LeaveRequest>> getAll({
    String? studentId,
    bool includeDeleted = false,
  }) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (!includeDeleted) {
      whereClauses.add('is_deleted = 0');
    }
    if (studentId != null && studentId.isNotEmpty) {
      whereClauses.add('student_id = ?');
      whereArgs.add(studentId);
    }

    final rows = await db.query(
      'leave_requests',
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows.map(LeaveRequest.fromMap).toList();
  }

  /// Convenience lookup filtered by student ID.
  Future<List<LeaveRequest>> getByStudentId(
    String studentId, {
    bool includeDeleted = false,
  }) =>
      getAll(studentId: studentId, includeDeleted: includeDeleted);

  /// Look up a leave request by its UUID primary key.
  Future<LeaveRequest?> getById(String id) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final rows = await db.query(
      'leave_requests',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LeaveRequest.fromMap(rows.first);
  }

  Future<LeaveRequest> insert(LeaveRequest request) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'id': request.id,
      'requester_name': request.requesterName.trim(),
      'leave_type': request.leaveType,
      'start_date': request.startDate.toIso8601String(),
      'end_date': request.endDate.toIso8601String(),
      'reason': request.reason.trim(),
      'status': request.status.value,
      'student_id': request.studentId,
      'remarks': request.remarks,
      'attachment_url': request.attachmentUrl,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    await db.insert('leave_requests', rowMap);
    SyncService.instance.schedulePush(
      'leave_requests',
      idColumn: 'id',
      idValue: request.id,
    );
    return request;
  }

  Future<void> updateStatus(
    String id,
    LeaveStatus newStatus, {
    String? remarks,
  }) async {
    if (PermissionService.instance.currentUserId != null &&
        !PermissionService.instance.hasPermission(PermissionCodes.leaveApprove)) {
      throw PermissionDeniedException(
        PermissionCodes.leaveApprove,
        userId: PermissionService.instance.currentUserId,
      );
    }

    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final now = DateTime.now().toUtc().toIso8601String();
    final updateData = <String, dynamic>{
      'status': newStatus.value,
      'updated_at': now,
      'sync_status': 'PENDING',
    };
    if (remarks != null) {
      updateData['remarks'] = remarks.trim();
    }
    await db.update(
      'leave_requests',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'leave_requests',
      idColumn: 'id',
      idValue: id,
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'leave_requests',
      {'is_deleted': 1, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'leave_requests',
      idColumn: 'id',
      idValue: id,
    );
  }

  Future<List<LeaveRequest>> getPendingSync() async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final rows = await db.query(
      'leave_requests',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(LeaveRequest.fromMap).toList();
  }
}
