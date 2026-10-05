import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';

class LabInventoryRepository {
  LabInventoryRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<LabInventory>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'item_name ASC',
    );
    return rows.map(LabInventory.fromMap).toList();
  }

  Future<LabInventory?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return LabInventory.fromMap(rows.first);
  }

  Future<List<LabInventory>> getByDepartment(String departmentId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: 'department_id = ? AND is_deleted = 0',
      whereArgs: [departmentId],
      orderBy: 'item_name ASC',
    );
    return rows.map(LabInventory.fromMap).toList();
  }

  Future<List<LabInventory>> getByCategory(InventoryCategory category) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: 'category = ? AND is_deleted = 0',
      whereArgs: [category.code],
      orderBy: 'item_name ASC',
    );
    return rows.map(LabInventory.fromMap).toList();
  }

  Future<LabInventory> insert(LabInventory item) async {
    final db = await _dbHelper.database;
    await db.insert('lab_inventory', item.toMap());
    return item;
  }

  Future<void> update(LabInventory item) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = item.copyWith(updatedAt: now);
    await db.update(
      'lab_inventory',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'lab_inventory',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<LabInventory>> getLowStockItems() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: 'current_stock <= reorder_level AND is_deleted = 0',
      orderBy: 'current_stock ASC',
    );
    return rows.map(LabInventory.fromMap).toList();
  }

  Future<List<LabInventory>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'lab_inventory',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(LabInventory.fromMap).toList();
  }
}
