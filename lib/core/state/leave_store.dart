import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Manages leave requests backed by [LeaveRepository].
class LeaveStore extends ChangeNotifier {
  LeaveStore({LeaveRepository? repository})
      : _repository = repository ?? LeaveRepository();

  final LeaveRepository _repository;

  List<LeaveRequest> _requests = [];

  /// Whether the current user holds an active institute-wide role.
  /// Institute-wide users bypass department scoping and see all requests.
  bool get _isInstituteWide {
    final uid = PermissionService.instance.currentUserId;
    if (uid == null) return false;
    return PermissionService.instance.roleIdsForUser(uid).any((roleId) {
      final role = PermissionService.instance.roleById(roleId);
      return role != null && !role.isDeleted && role.isInstituteWide;
    });
  }

  /// Department ids the current user is assigned to.
  /// Empty when unauthenticated, suspended, or not assigned to any department.
  List<String> get _departmentIds {
    final uid = PermissionService.instance.currentUserId;
    if (uid == null) return const <String>[];
    return PermissionService.instance.departmentIdsForUser(uid).toList();
  }

  /// All non-deleted leave requests, most recent first.
  ///
  /// Department-scoped: institute-wide users see all requests. Non-institute-wide
  /// users receive an empty list when they are not assigned to any department
  /// (fail-closed). Leave requests are associated with students via [studentId]
  /// and students belong to departments, so leave requests cannot be filtered by
  /// department without resolving the student's department; callers requiring
  /// student-level scoping should use [loadForStudent].
  List<LeaveRequest> get requests {
    if (_isInstituteWide) {
      return List.unmodifiable(_requests.where((r) => !r.isDeleted).toList());
    }
    final depts = _departmentIds;
    if (depts.isEmpty) return const <LeaveRequest>[];
    return List.unmodifiable(_requests.where((r) => !r.isDeleted).toList());
  }

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
