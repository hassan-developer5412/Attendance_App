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

  // -------------------------------------------------------------------------
  // Access control helpers
  // -------------------------------------------------------------------------

  /// The id of the user making the request, resolved from [requestingUserId]
  /// when given or [PermissionService.instance.currentUserId] otherwise.
  ///
  /// Returns null when no authenticated, non-suspended user is known —
  /// callers must treat that as fail-closed.
  String? _effectiveUserId({String? requestingUserId}) {
    final uid = requestingUserId ?? PermissionService.instance.currentUserId;
    if (uid == null || PermissionService.instance.isUserSuspended(uid)) {
      return null;
    }
    return uid;
  }

  /// True when [request] belongs to [uid] (an own leave request).
  bool _isOwner(LeaveRequest request, String uid) {
    final studentId = request.studentId;
    return studentId != null &&
        studentId.isNotEmpty &&
        studentId == uid;
  }

  /// True when [uid] may view or modify a request owned by someone else,
  /// optionally scoped to [departmentId]. Holds `leave.view` or
  /// `leave.approve` (department-scoped where applicable) is sufficient.
  bool _mayAccessOthers(String uid, {String? departmentId}) {
    return PermissionService.instance.hasPermission(
            PermissionCodes.leaveView,
            userId: uid,
            departmentId: departmentId) ||
        PermissionService.instance.hasPermission(
            PermissionCodes.leaveApprove,
            userId: uid,
            departmentId: departmentId);
  }

  /// Throws [PermissionDeniedException] when [uid] is not the owner of
  /// [request] and holds no `leave.view` / `leave.approve` grant (optionally
  /// department-scoped).
  void _requireOwnershipOrAccess(
    LeaveRequest request,
    String uid, {
    String? departmentId,
  }) {
    if (_isOwner(request, uid)) return;
    if (!_mayAccessOthers(uid, departmentId: departmentId)) {
      throw PermissionDeniedException(
        PermissionCodes.leaveView,
        userId: uid,
        departmentId: departmentId,
      );
    }
  }

  Future<List<LeaveRequest>> getAll({
    String? studentId,
    bool includeDeleted = false,
    String? requestingUserId,
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);

    final uid = _effectiveUserId(requestingUserId: requestingUserId);
    if (uid == null) {
      // Fail-closed: unauthenticated or suspended users see nothing.
      return const <LeaveRequest>[];
    }

    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (!includeDeleted) {
      whereClauses.add('is_deleted = 0');
    }
    if (studentId != null && studentId.isNotEmpty) {
      whereClauses.add('student_id = ?');
      whereArgs.add(studentId);
    }

    // A user may always list their own requests. Listing anyone else's
    // requests (or all requests when no student filter is given) requires
    // leave.view or leave.approve, honoring department scoping where
    // applicable.
    final isOwnRequest = studentId != null &&
        studentId.isNotEmpty &&
        studentId == uid;
    if (!isOwnRequest && !_mayAccessOthers(uid, departmentId: departmentId)) {
      if (studentId != null && studentId.isNotEmpty) {
        throw PermissionDeniedException(
          PermissionCodes.leaveView,
          userId: uid,
          departmentId: departmentId,
        );
      }
      return const <LeaveRequest>[];
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
    String? requestingUserId,
    String? departmentId,
  }) =>
      getAll(
        studentId: studentId,
        includeDeleted: includeDeleted,
        requestingUserId: requestingUserId,
        departmentId: departmentId,
      );

  /// Look up a leave request by its UUID primary key.
  ///
  /// Owners may always read their own request; any other caller must hold
  /// `leave.view` or `leave.approve` (department-scoped where applicable).
  Future<LeaveRequest?> getById(String id, {
    String? requestingUserId,
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;
    await _ensureSchema(db);
    final rows = await db.query(
      'leave_requests',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final request = LeaveRequest.fromMap(rows.first);

    final uid = _effectiveUserId(requestingUserId: requestingUserId);
    if (uid == null) return null; // Fail-closed: nothing to show.

    _requireOwnershipOrAccess(request, uid, departmentId: departmentId);
    return request;
  }

  Future<LeaveRequest> insert(LeaveRequest request, {
    String? requestingUserId,
  }) async {
    final uid = _effectiveUserId(requestingUserId: requestingUserId);
    if (uid == null) {
      // Fail-closed: submission requires an authenticated user. leave.view is
      // the leave-module access gate; no administrative (leave.approve) grant
      // is required to submit one's own request.
      throw PermissionDeniedException(
        PermissionCodes.leaveView,
        userId: null,
      );
    }

    // Users may submit their own requests without administrative permissions.
    // Submitting on behalf of another user requires leave.view / leave.approve.
    final requestStudentId = request.studentId;
    if (requestStudentId != null &&
        requestStudentId.isNotEmpty &&
        requestStudentId != uid &&
        !_mayAccessOthers(uid)) {
      throw PermissionDeniedException(
        PermissionCodes.leaveView,
        userId: uid,
      );
    }

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
    String? requestingUserId,
    String? departmentId,
  }) async {
    final currentUserId = _effectiveUserId(requestingUserId: requestingUserId);

    if (currentUserId == null ||
        !PermissionService.instance.hasPermission(
          PermissionCodes.leaveApprove,
          userId: currentUserId,
          departmentId: departmentId,
        )) {
      throw PermissionDeniedException(
        PermissionCodes.leaveApprove,
        userId: currentUserId,
        departmentId: departmentId,
      );
    }

    // Prevent users with leave.approve from approving their own requests.
    final request = await getById(
      id,
      requestingUserId: currentUserId,
      departmentId: departmentId,
    );
    if (request != null) {
      if (request.studentId != null && request.studentId == currentUserId) {
        throw PermissionDeniedException(
          PermissionCodes.leaveApprove,
          userId: currentUserId,
          departmentId: departmentId,
        );
      }
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

  Future<void> softDelete(String id, {
    String? requestingUserId,
    String? departmentId,
  }) async {
    final uid = _effectiveUserId(requestingUserId: requestingUserId);
    if (uid == null) {
      throw PermissionDeniedException(
        PermissionCodes.leaveView,
        userId: null,
        departmentId: departmentId,
      );
    }

    // Deleting is a modification: owners may delete their own request; anyone
    // else needs leave.view or leave.approve (department-scoped where applicable).
    final request = await getById(
      id,
      requestingUserId: uid,
      departmentId: departmentId,
    );
    if (request == null) return; // Nothing to delete.

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
