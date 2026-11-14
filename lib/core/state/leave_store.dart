import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';

/// Manages leave requests backed by [LeaveRepository].
class LeaveStore extends ChangeNotifier {
  LeaveStore({LeaveRepository? repository})
      : _repository = repository ?? LeaveRepository();

  final LeaveRepository _repository;

  List<LeaveRequest> _requests = [];

  /// All leave requests, most recent first.
  List<LeaveRequest> get requests => List.unmodifiable(_requests);

  int get pendingCount =>
      _requests.where((r) => r.status == LeaveStatus.pending).length;

  int get approvedCount =>
      _requests.where((r) => r.status == LeaveStatus.approved).length;

  int get rejectedCount =>
      _requests.where((r) => r.status == LeaveStatus.rejected).length;

  /// Loads leave requests from the database.
  /// If [studentId] is specified, only that student's records are loaded.
  Future<void> loadAll({String? studentId}) async {
    _requests = await _repository.getAll(studentId: studentId);
    notifyListeners();
  }

  /// Loads leave requests for a single student.
  Future<void> loadForStudent(String studentId) async {
    _requests = await _repository.getByStudentId(studentId);
    notifyListeners();
  }

  /// Submits a new leave request.
  Future<LeaveRequest> applyLeave({
    required String requesterName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? studentId,
    String? attachmentUrl,
  }) async {
    final request = LeaveRequest(
      requesterName: requesterName.trim(),
      leaveType: leaveType,
      startDate: startDate,
      endDate: endDate,
      reason: reason.trim().isNotEmpty ? reason.trim() : 'Personal leave',
      studentId: studentId,
      attachmentUrl: attachmentUrl,
    );

    final inserted = await _repository.insert(request);
    await loadAll(studentId: studentId);
    return inserted;
  }

  /// Updates the status of a leave request (approve or reject).
  ///
  /// [id] is the canonical UUID of the request.
  Future<void> updateStatus(
    String id,
    LeaveStatus newStatus, {
    String? remarks,
  }) async {
    await _repository.updateStatus(id, newStatus, remarks: remarks);
    await loadAll();
  }
}
