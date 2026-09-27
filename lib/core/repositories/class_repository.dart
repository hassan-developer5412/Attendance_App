import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';

class ClassRepository {
  ClassRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<SchoolClass>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'classes',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'id DESC',
    );
    return rows.map(SchoolClass.fromMap).toList();
  }

  Future<SchoolClass?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'classes',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SchoolClass.fromMap(rows.first);
  }

  Future<SchoolClass?> getByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'classes',
      where: 'uuid = ? AND is_deleted = 0',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SchoolClass.fromMap(rows.first);
  }

  Future<SchoolClass> insert({
    required String name,
    required String section,
    required String room,
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'name': name.trim(),
      'section': section.trim(),
      'room': room.trim(),
      'department_id': departmentId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    final id = await db.insert('classes', rowMap);
    final schoolClass = SchoolClass(
      id: id,
      name: name.trim(),
      section: section.trim(),
      room: room.trim(),
      departmentId: departmentId,
    );
    // Persist generated deterministic UUID
    await db.update(
      'classes',
      {'uuid': schoolClass.uuid},
      where: 'id = ?',
      whereArgs: [id],
    );
    return schoolClass;
  }

  Future<void> update(SchoolClass schoolClass) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'classes',
      {
        'name': schoolClass.name.trim(),
        'section': schoolClass.section.trim(),
        'room': schoolClass.room.trim(),
        'department_id': schoolClass.departmentId,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [schoolClass.id],
    );
  }

  Future<void> softDelete(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'classes',
        {
          'is_deleted': 1,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      // Unassign teachers from deleted class
      await txn.update(
        'teachers',
        {
          'class_id': null,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'class_id = ?',
        whereArgs: [id],
      );

      // Soft delete students belonging to this class
      await txn.update(
        'students',
        {
          'is_deleted': 1,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'class_id = ?',
        whereArgs: [id],
      );

      // Soft delete subjects belonging to this class
      await txn.update(
        'subjects',
        {
          'is_deleted': 1,
          'updated_at': now,
          'sync_status': 'PENDING',
        },
        where: 'class_id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<SchoolClass>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'classes',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(SchoolClass.fromMap).toList();
  }
}
