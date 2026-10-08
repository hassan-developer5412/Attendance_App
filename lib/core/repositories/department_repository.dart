import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/department.dart';
import 'package:attendance_app/core/services/sync_service.dart';

class DepartmentRepository {
  DepartmentRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Department>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'departments',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'code ASC',
    );
    return rows.map(Department.fromMap).toList();
  }

  /// Only active, non-deleted departments (used for pickers and dashboards).
  Future<List<Department>> getActive() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'departments',
      where: 'is_deleted = 0 AND is_active = 1',
      orderBy: 'code ASC',
    );
    return rows.map(Department.fromMap).toList();
  }

  Future<Department?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'departments',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Department.fromMap(rows.first);
  }

  Future<Department?> getByCode(String code) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'departments',
      where: 'code = ? AND is_deleted = 0',
      whereArgs: [code.toUpperCase()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Department.fromMap(rows.first);
  }

  Future<Department> insert(Department department) async {
    final db = await _dbHelper.database;
    await db.insert('departments', department.toMap());
    SyncService.instance.schedulePush(
      'departments',
      idColumn: 'id',
      idValue: department.id,
    );
    return department;
  }

  Future<void> update(Department department) async {
    final db = await _dbHelper.database;
    final updated = department.copyWith(
      updatedAt: DateTime.now().toUtc(),
    );
    await db.update(
      'departments',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [department.id],
    );
    SyncService.instance.schedulePush(
      'departments',
      idColumn: 'id',
      idValue: department.id,
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'departments',
      {
        'is_deleted': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush('departments', idColumn: 'id', idValue: id);
  }

  Future<void> restore(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'departments',
      {
        'is_deleted': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush('departments', idColumn: 'id', idValue: id);
  }

  Future<List<Department>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'departments',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Department.fromMap).toList();
  }
}
