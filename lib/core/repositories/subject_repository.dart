import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';

class SubjectRepository {
  SubjectRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Subject>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'id DESC',
    );
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Subject.fromMap(rows.first);
  }

  Future<List<Subject>> getByClassId(int classId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: 'class_id = ? AND is_deleted = 0',
      whereArgs: [classId],
      orderBy: 'name ASC',
    );
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject> insert({
    required String name,
    required String code,
    required String teacherName,
    required int classId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'name': name.trim(),
      'code': code.trim(),
      'teacher_name': teacherName.trim(),
      'class_id': classId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    final id = await db.insert('subjects', rowMap);
    final subject = Subject(
      id: id,
      name: name.trim(),
      code: code.trim(),
      teacherName: teacherName.trim(),
      classId: classId,
    );
    // Persist deterministic UUID
    await db.update(
      'subjects',
      {'uuid': subject.uuid},
      where: 'id = ?',
      whereArgs: [id],
    );
    return subject;
  }

  Future<void> update(Subject subject) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'subjects',
      {
        'name': subject.name.trim(),
        'code': subject.code.trim(),
        'teacher_name': subject.teacherName.trim(),
        'class_id': subject.classId,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [subject.id],
    );
  }

  Future<void> softDelete(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'subjects',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Subject>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Subject.fromMap).toList();
  }
}
