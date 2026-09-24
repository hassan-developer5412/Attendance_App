import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/leave_request.dart';

/// Manages leave requests backed by the SQLite leave_requests table.
class LeaveStore extends ChangeNotifier {
  List<LeaveRequest> _requests = [];

  /// All leave requests, most recent first.
  List<LeaveRequest> get requests => List.unmodifiable(_requests);

  int get pendingCount =>
      _requests.where((r) => r.status == LeaveStatus.pending).length;

  int get approvedCount =>
      _requests.where((r) => r.status == LeaveStatus.approved).length;

  int get rejectedCount =>
      _requests.where((r) => r.status == LeaveStatus.rejected).length;

  /// Loads all leave requests from the database.
  Future<void> loadAll() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'leave_requests',
      orderBy: 'id DESC',
    );
    _requests = rows.map(LeaveRequest.fromMap).toList();
    notifyListeners();
  }

  /// Submits a new leave request.
  Future<void> applyLeave({
    required String requesterName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final request = LeaveRequest(
      requesterName: requesterName.trim(),
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: reason.trim().isNotEmpty ? reason.trim() : 'Personal leave',
    );

    await db.insert('leave_requests', request.toMap());
    await loadAll();
  }

  /// Updates the status of a leave request (approve or reject).
  Future<void> updateStatus(int id, LeaveStatus newStatus) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      'leave_requests',
      {'status': newStatus.value},
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadAll();
  }
}
