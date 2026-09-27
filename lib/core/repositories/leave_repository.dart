import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/leave_request.dart';

class LeaveRepository {
  LeaveRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<LeaveRequest>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'leave_requests',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'id DESC',
    );
    return rows.map(LeaveRequest.fromMap).toList();
  }

  Future<LeaveRequest?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'leave_requests',
      where: '(uuid = ? OR CAST(id AS TEXT) = ?) AND is_deleted = 0',
      whereArgs: [id, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LeaveRequest.fromMap(rows.first);
  }

  Future<LeaveRequest> insert(LeaveRequest request) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'uuid': request.id,
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
    final intId = await db.insert('leave_requests', rowMap);
    // Keep the canonical UUID as the model id; the legacy auto-increment value is only the physical row key.
    assert(intId > 0);
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
      where: 'uuid = ? OR CAST(id AS TEXT) = ?',
      whereArgs: [id, id],
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'leave_requests',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'uuid = ? OR CAST(id AS TEXT) = ?',
      whereArgs: [id, id],
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
