import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

class StudentRepository {
  StudentRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  Future<List<Student>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'name ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  /// Look up a student by its UUID primary key.
  Future<Student?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Student.fromMap(rows.first);
  }

  /// All students in a class (by class UUID).
  Future<List<Student>> getByClassId(String classId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: 'class_id = ? AND is_deleted = 0',
      whereArgs: [classId],
      orderBy: 'name ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  Future<List<Student>> getByClassAndYear(String classId, String year) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: 'class_id = ? AND current_year = ? AND is_deleted = 0',
      whereArgs: [classId, year],
      orderBy: 'name ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  Future<Student> insert({
    required String name,
    required String rollNumber,
    required String classId,
    String? registrationNo,
    String fatherName = '',
    String? departmentId,
    String? academicSessionId,
    String currentYear = '1st Year',
    String status = 'ACTIVE',
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = UuidUtils.generate();
    final rowMap = {
      'id': id,
      'name': name.trim(),
      'roll_number': rollNumber.trim(),
      'class_id': classId,
      'is_active': 1,
      'roll_no': rollNumber.trim(),
      'full_name': name.trim(),
      'registration_no': registrationNo ?? 'REG-${rollNumber.trim()}',
      'father_name': fatherName.trim(),
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'current_year': currentYear,
      'status': status,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    await db.insert('students', rowMap);
    SyncService.instance.schedulePush('students', idColumn: 'id', idValue: id);
    return Student(
      id: id,
      name: name.trim(),
      rollNumber: rollNumber.trim(),
      classId: classId,
      registrationNo: registrationNo ?? 'REG-${rollNumber.trim()}',
      fatherName: fatherName.trim(),
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      currentYear: currentYear,
      status: status,
    );
  }

  Future<void> update(Student student) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'students',
      {
        'name': student.name.trim(),
        'roll_number': student.rollNumber.trim(),
        'class_id': student.classId,
        'is_active': student.isActive ? 1 : 0,
        'roll_no': student.rollNumber.trim(),
        'full_name': student.name.trim(),
        'registration_no': student.registrationNo,
        'father_name': student.fatherName.trim(),
        'department_id': student.departmentId,
        'academic_session_id': student.academicSessionId,
        'current_year': student.currentYear,
        'status': student.status,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [student.id],
    );
    SyncService.instance.schedulePush(
      'students',
      idColumn: 'id',
      idValue: student.id,
    );
  }

  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'students',
      {'is_deleted': 1, 'updated_at': now, 'sync_status': 'PENDING'},
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush('students', idColumn: 'id', idValue: id);
  }

  Future<List<Student>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Student.fromMap).toList();
  }
}
