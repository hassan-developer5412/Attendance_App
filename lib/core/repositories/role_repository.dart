import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// CRUD operations for the `roles` catalogue and `role_permissions` grants.
///
/// Writes are mirrored into the in-memory [PermissionService] cache so
/// `hasPermission` reflects grants immediately without a restart.
class RoleRepository {
  RoleRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// All roles, optionally including soft-deleted ones.
  Future<List<Role>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'roles',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Role.fromMap).toList();
  }

  /// Finds a role by its primary key [id].
  Future<Role?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'roles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Role.fromMap(rows.first);
  }

  /// Finds a role by its unique [code].
  Future<Role?> getByCode(String code) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'roles',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Role.fromMap(rows.first);
  }

  /// Inserts a new role into the catalogue and mirrors to cache.
  Future<String> insert({
    required String name,
    required String code,
    String description = '',
    bool isCustom = true,
    bool isInstituteWide = false,
    String instituteId = AppConstants.defaultInstituteId,
  }) async {
    final db = await _dbHelper.database;
    final id = UuidUtils.generate();
    final now = DateTime.now().toUtc().toIso8601String();

    final role = Role(
      id: id,
      name: name,
      code: code,
      description: description,
      isCustom: isCustom,
      isInstituteWide: isInstituteWide,
      instituteId: instituteId,
    );

    await db.insert('roles', {
      'id': id,
      'name': name,
      'code': code,
      'description': description,
      'is_custom': isCustom ? 1 : 0,
      'is_institute_wide': isInstituteWide ? 1 : 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
      'is_synced': 0,
      'institute_id': instituteId,
    });

    SyncService.instance.schedulePush(
      'roles',
      idColumn: 'id',
      idValue: id,
    );

    final currentRoles = PermissionService.instance.roles.toList();
    currentRoles.add(role);
    PermissionService.instance.loadRoles(currentRoles);

    return id;
  }

  /// Updates an existing role's details.
  Future<void> update(Role role) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'roles',
      {
        'name': role.name,
        'description': role.description,
        'is_institute_wide': role.isInstituteWide ? 1 : 0,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [role.id],
    );

    SyncService.instance.schedulePush(
      'roles',
      idColumn: 'id',
      idValue: role.id,
    );

    final allRoles = await getAll();
    PermissionService.instance.loadRoles(allRoles);
  }

  /// Soft deletes a role by [id].
  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      'roles',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    SyncService.instance.schedulePush(
      'roles',
      idColumn: 'id',
      idValue: id,
    );

    final allRoles = await getAll();
    PermissionService.instance.loadRoles(allRoles);
  }

  // -------------------------------------------------------------------------
  // Role → Permission Grants
  // -------------------------------------------------------------------------

  /// Returns the set of permission codes currently granted to [roleId].
  Future<Set<String>> getPermissionCodesForRole(String roleId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'role_permissions',
      columns: ['permission_code'],
      where: 'role_id = ?',
      whereArgs: [roleId],
    );
    return rows.map((r) => r['permission_code'] as String).toSet();
  }

  /// Grants [permissionCode] to [roleId] and mirrors to cache.
  Future<void> grantPermission(String roleId, String permissionCode) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.insert(
      'role_permissions',
      {
        'role_id': roleId,
        'permission_code': permissionCode,
        'created_at': now,
      },
    );

    PermissionService.instance.grantPermissionToRole(roleId, permissionCode);
  }

  /// Revokes [permissionCode] from [roleId] and mirrors to cache.
  Future<void> revokePermission(String roleId, String permissionCode) async {
    final db = await _dbHelper.database;

    await db.delete(
      'role_permissions',
      where: 'role_id = ? AND permission_code = ?',
      whereArgs: [roleId, permissionCode],
    );

    PermissionService.instance.revokePermissionFromRole(roleId, permissionCode);
  }

  /// Replaces all permissions for [roleId] atomically and mirrors to cache.
  Future<void> replaceRolePermissions(
    String roleId,
    Iterable<String> permissionCodes,
  ) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'role_permissions',
        where: 'role_id = ?',
        whereArgs: [roleId],
      );

      for (final code in permissionCodes) {
        await txn.insert('role_permissions', {
          'role_id': roleId,
          'permission_code': code,
          'created_at': now,
        });
      }
    });

    final currentGrants = <String, Set<String>>{};
    for (final role in PermissionService.instance.roles) {
      if (role.id == roleId) {
        currentGrants[role.id] = permissionCodes.toSet();
      } else {
        currentGrants[role.id] = await getPermissionCodesForRole(role.id);
      }
    }
    PermissionService.instance.loadRolePermissions(currentGrants);
  }
}
