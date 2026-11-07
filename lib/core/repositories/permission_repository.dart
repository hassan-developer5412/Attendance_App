import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// CRUD operations for the `permissions` catalogue.
///
/// Writes are mirrored into the in-memory [PermissionService] cache so
/// `hasPermission` reflects grants immediately without a restart.
class PermissionRepository {
  PermissionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// All non-deleted permissions, ordered by module then code.
  Future<List<Permission>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'permissions',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'module ASC, code ASC',
    );
    return rows.map(Permission.fromMap).toList();
  }

  /// Look up a permission by its UUID primary key.
  Future<Permission?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'permissions',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Permission.fromMap(rows.first);
  }

  /// Look up a permission by its machine-readable code (e.g. `student.create`).
  Future<Permission?> getByCode(String code) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'permissions',
      where: 'code = ? AND is_deleted = 0',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Permission.fromMap(rows.first);
  }

  Future<String> insert({
    required String code,
    required String module,
    required String description,
    String? instituteId,
  }) async {
    final existing = await getByCode(code);
    if (existing != null) return existing.id;

    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = UuidUtils.generate();
    await db.insert(
      'permissions',
      {
        'id': id,
        'code': code.trim(),
        'module': module.trim(),
        'description': description.trim(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'PENDING',
        'is_deleted': 0,
        'is_synced': 0,
        'institute_id': instituteId ?? 'default_institute',
      },
    );
    SyncService.instance.schedulePush(
      'permissions',
      idColumn: 'id',
      idValue: id,
    );
    return id;
  }

  Future<void> update(Permission permission) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'permissions',
      {
        'code': permission.code.trim(),
        'module': permission.module.trim(),
        'description': permission.description.trim(),
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [permission.id],
    );
    SyncService.instance.schedulePush(
      'permissions',
      idColumn: 'id',
      idValue: permission.id,
    );
    PermissionService.instance.loadPermissions([permission]);
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'permissions',
      {'is_deleted': 1, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'permissions',
      idColumn: 'id',
      idValue: id,
    );
    PermissionService.instance
        .loadPermissions((await getAll(includeDeleted: true)));
  }
}
