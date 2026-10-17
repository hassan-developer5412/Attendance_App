import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/services/sync_service.dart';

class LeaveRepository {
  LeaveRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<LeaveRequest>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'leave_requests',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(LeaveRequest.fromMap).toList();
  }

  /// Look up a leave request by its UUID primary key.
  Future<LeaveRequest?> getById(String id) async {
    final db = await _dbHelper.database;
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
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'id': request.id,
      'requester_name': request.requesterName.trim(),
      'leave_type': request.leaveType,
      'start_date': request.startDate.toIso8601String(),
      'end_date': request.endDate.toIso8601String(),
      'reason': request.reason.trim(),
      'status': request.status.value,
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

  Future<void> updateStatus(String id, LeaveStatus newStatus) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'leave_requests',
      {
        'status': newStatus.value,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
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
    final rows = await db.query(
      'leave_requests',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(LeaveRequest.fromMap).toList();
  }
}
