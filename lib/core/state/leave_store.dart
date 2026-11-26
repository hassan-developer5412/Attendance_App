import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Manages leave requests backed by [LeaveRepository].
///
/// RBAC enforcement lives in [LeaveRepository]; this store catches
/// [PermissionDeniedException]s from the repository, records a user-facing
/// message in [errorMessage], and never leaves local state half-applied: on
/// failure the previously loaded [_requests] are kept intact and only the
/// error message is exposed.
class LeaveStore extends ChangeNotifier {
  LeaveStore({LeaveRepository? repository})
      : _repository = repository ?? LeaveRepository();

  final LeaveRepository _repository;

  List<LeaveRequest> _requests = [];

  /// Error message from the most recent failed leave operation, or `null`
  /// when the last operation succeeded or no operation has run yet.
  ///
  /// The UI can surface this to explain authorization failures without
  /// relying on exceptions propagating out of the store.
  String? get errorMessage => _errorMessage;
  String? _errorMessage;

  /// Whether the last store operation failed.
  bool get hasError => _errorMessage != null;

  /// Clears [errorMessage] ahead of a new operation.
  void _clearError() {
    _errorMessage = null;
  }

  /// Records [error] as the current [errorMessage] without touching [_requests].
  void _setError(Object error) {
    if (error is PermissionDeniedException) {
      _errorMessage =
          'Not authorized: ${error.permissionCode}'
          '${error.userId != null ? ' (user: ${error.userId})' : ''}'
          '${error.departmentId != null ? ' (department: ${error.departmentId})' : ''}';
    } else {
      _errorMessage = error.toString();
    }
  }

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
  ///
  /// On failure the previously loaded [_requests] are kept intact (no state
  /// corruption) and [errorMessage] is set instead.
  Future<void> loadAll({String? studentId}) async {
    _clearError();
    try {
      _requests = await _repository.getAll(studentId: studentId);
    } on PermissionDeniedException catch (e) {
      _setError(e);
    } catch (e, s) {
      _setError(e);
      debugPrint('LeaveStore.loadAll failed: $e');
      debugPrintStack(stackTrace: s);
    }
    notifyListeners();
  }

  /// Loads leave requests for a single student.
  ///
  /// On failure the previously loaded [_requests] are kept intact and
  /// [errorMessage] is set instead.
  Future<void> loadForStudent(String studentId) async {
    _clearError();
    try {
      _requests = await _repository.getByStudentId(studentId);
    } on PermissionDeniedException catch (e) {
      _setError(e);
    } catch (e, s) {
      _setError(e);
      debugPrint('LeaveStore.loadForStudent failed: $e');
      debugPrintStack(stackTrace: s);
    }
    notifyListeners();
  }

  /// Submits a new leave request.
  ///
  /// Authenticated students/staff may submit their own requests without
  /// administrative permissions; the repository rejects unauthenticated
  /// submission and impersonation of another user. On failure [errorMessage]
  /// is set, local state is not corrupted, and the exception is rethrown.
  Future<LeaveRequest> applyLeave({
    required String requesterName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    String? studentId,
    String? attachmentUrl,
  }) async {
    _clearError();
    try {
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
      // Refresh the caller's own list. A refresh failure must not undo a
      // successful submission.
      try {
        await loadAll(studentId: studentId);
      } catch (e, s) {
        debugPrint(
            'LeaveStore.applyLeave post-submit refresh failed: $e');
        debugPrintStack(stackTrace: s);
      }
      return inserted;
    } on PermissionDeniedException catch (e) {
      _setError(e);
      rethrow;
    } catch (e, s) {
      _setError(e);
      debugPrint('LeaveStore.applyLeave failed: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }

  /// Updates the status of a leave request (approve or reject).
  ///
  /// [id] is the canonical UUID of the request. The repository enforces
  /// [PermissionCodes.leaveApprove] and the self-approval block. On failure
  /// [errorMessage] is set, local state is not corrupted, and the exception
  /// is rethrown.
  Future<void> updateStatus(
    String id,
    LeaveStatus newStatus, {
    String? remarks,
  }) async {
    _clearError();
    try {
      await _repository.updateStatus(id, newStatus, remarks: remarks);
      await loadAll();
    } on PermissionDeniedException catch (e) {
      _setError(e);
      rethrow;
    } catch (e, s) {
      _setError(e);
      debugPrint('LeaveStore.updateStatus failed: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }
}
