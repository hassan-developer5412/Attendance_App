import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/user_role.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Assigns and revokes user↔role assignments plus user→department scopes.
///
/// Writes are mirrored into the in-memory [PermissionService] cache so
/// `hasPermission` reflects assignments immediately without a restart.
class UserRoleRepository {
  UserRoleRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Roles currently assigned to [userId] (as full [Role] objects).
  Future<List<Role>> getRolesForUser(
    String userId, {
    RoleRepository? roleRepository,
  }) async {
    final repo = roleRepository ?? RoleRepository(dbHelper: _dbHelper);
    final assignments = await getAssignmentsForUser(userId);
    final roles = <Role>[];
    for (final assignment in assignments) {
      final role = await repo.getById(assignment.roleId);
      if (role != null && !role.isDeleted) roles.add(role);
    }
    roles.sort((a, b) => a.name.compareTo(b.name));
    return roles;
  }

  /// All assignment rows for [userId].
  Future<List<UserRoleAssignment>> getAssignmentsForUser(String userId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'user_roles',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
    );
    return rows.map(UserRoleAssignment.fromMap).toList();
  }

  /// Users currently assigned to [roleId].
  Future<List<UserRoleAssignment>> getUsersForRole(String roleId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'user_roles',
      where: 'role_id = ? AND is_deleted = 0',
      whereArgs: [roleId],
    );
    return rows.map(UserRoleAssignment.fromMap).toList();
  }

  /// Assigns [roleId] to [userId]. Returns the assignment id.
  Future<String> assignRoleToUser({
    required String userId,
    required String roleId,
    String? assignedBy,
    String? instituteId,
  }) async {
    if (PermissionService.instance.currentUserId != null &&
        !PermissionService.instance.canManageRoles()) {
      throw PermissionDeniedException(
        PermissionCodes.userManageRoles,
        userId: PermissionService.instance.currentUserId,
      );
    }

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = UuidUtils.generate();
    await db.insert(
      'user_roles',
      {
        'id': id,
        'user_id': userId,
        'role_id': roleId,
        'institute_id': instituteId ?? 'default_institute',
        'assigned_at': now,
        'assigned_by': assignedBy,
        'sync_status': 'PENDING',
        'is_deleted': 0,
        'is_synced': 0,
      },
    );
    SyncService.instance.schedulePush(
      'user_roles',
      idColumn: 'id',
      idValue: id,
    );
    PermissionService.instance.assignRoleToUser(userId, roleId);
    return id;
  }

  /// Revokes [roleId] from [userId].
  Future<void> revokeRoleFromUser(String userId, String roleId) async {
    if (PermissionService.instance.currentUserId != null &&
        !PermissionService.instance.canManageRoles()) {
      throw PermissionDeniedException(
        PermissionCodes.userManageRoles,
        userId: PermissionService.instance.currentUserId,
      );
    }

    final db = await _dbHelper.database;
    await db.delete(
      'user_roles',
      where: 'user_id = ? AND role_id = ? AND is_deleted = 0',
      whereArgs: [userId, roleId],
    );
    SyncService.instance.schedulePush(
      'user_roles',
      idColumn: 'user_id',
      idValue: userId,
    );
    PermissionService.instance.revokeRoleFromUser(userId, roleId);
  }

  /// Revokes every role from [userId].
  Future<void> revokeAllRolesForUser(String userId) async {
    if (PermissionService.instance.currentUserId != null &&
        !PermissionService.instance.canManageRoles()) {
      throw PermissionDeniedException(
        PermissionCodes.userManageRoles,
        userId: PermissionService.instance.currentUserId,
      );
    }

    final db = await _dbHelper.database;
    await db.update(
      'user_roles',
      {'is_deleted': 1, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
    );
    SyncService.instance.schedulePush(
      'user_roles',
      idColumn: 'user_id',
      idValue: userId,
    );
    PermissionService.instance.setUserRoles(userId, <String>{});
  }

  // -----------------------------------------------------------------------
  // User → department scopes (department-scoped roles such as HOD)
  // -----------------------------------------------------------------------

  /// Departments [userId] is scoped to.
  Future<Set<String>> getDepartmentsForUser(String userId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'user_departments',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
    );
    return rows.map((r) => r['department_id'] as String).toSet();
  }

  /// Replaces the departments [userId] is scoped to with [departmentIds].
  Future<void> setUserDepartments({
    required String userId,
    required Iterable<String> departmentIds,
  }) async {
    if (PermissionService.instance.currentUserId != null &&
        !PermissionService.instance.canManageRoles()) {
      throw PermissionDeniedException(
        PermissionCodes.userManageRoles,
        userId: PermissionService.instance.currentUserId,
      );
    }

    final ids = Set<String>.from(departmentIds);
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = db.batch();
    batch.delete(
      'user_departments',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    for (final deptId in ids) {
      batch.insert(
        'user_departments',
        {
          'id': UuidUtils.generate(),
          'user_id': userId,
          'department_id': deptId,
          'created_at': now,
          'sync_status': 'PENDING',
          'is_deleted': 0,
        },
      );
    }
    await batch.commit(noResult: true);
    SyncService.instance.schedulePush(
      'user_departments',
      idColumn: 'user_id',
      idValue: userId,
    );
    PermissionService.instance.setUserDepartments(userId, ids);
  }
}
