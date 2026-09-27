import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';

class FacultyRepository {
  FacultyRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Teacher>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'teachers',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'id DESC',
    );
    return rows.map(Teacher.fromMap).toList();
  }

  Future<Teacher?> getById(int id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'teachers',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Teacher.fromMap(rows.first);
  }

  Future<Teacher?> getByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'teachers',
      where: 'uuid = ? AND is_deleted = 0',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Teacher.fromMap(rows.first);
  }

  Future<Teacher> insert({
    required String name,
    required String subject,
    String email = '',
    String username = '',
    String password = '',
    int? classId,
    String? employeeCode,
    String designation = 'Instructor',
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rowMap = {
      'name': name.trim(),
      'subject': subject.trim(),
      'email': email.trim(),
      'username': username.trim(),
      'password': password.trim(),
      'class_id': classId,
      'is_active': 1,
      'employee_code': employeeCode,
      'designation': designation,
      'department_id': departmentId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    final id = await db.insert('teachers', rowMap);
    final teacher = Teacher(
      id: id,
      name: name.trim(),
      subject: subject.trim(),
      email: email.trim(),
      username: username.trim(),
      password: password.trim(),
      classId: classId,
      employeeCode: employeeCode ?? 'FAC-$id',
      designation: designation,
      departmentId: departmentId,
    );
    // Persist deterministic UUID and employee code
    await db.update(
      'teachers',
      {
        'uuid': teacher.uuid,
        'employee_code': teacher.employeeCode,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return teacher;
  }

  Future<void> update(Teacher teacher) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'teachers',
      {
        'name': teacher.name.trim(),
        'subject': teacher.subject.trim(),
        'email': teacher.email.trim(),
        'username': teacher.username.trim(),
        'password': teacher.password.trim(),
        'class_id': teacher.classId,
        'is_active': teacher.isActive ? 1 : 0,
        'employee_code': teacher.employeeCode,
        'designation': teacher.designation,
        'department_id': teacher.departmentId,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [teacher.id],
    );
  }

  Future<void> softDelete(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'teachers',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Teacher>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'teachers',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Teacher.fromMap).toList();
  }
}
