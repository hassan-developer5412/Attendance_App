import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';
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
      orderBy: 'id DESC',
    );
    return rows.map(Student.fromMap).toList();
  }

  Future<Student?> getById(int id) async {
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

  Future<Student?> getByUuid(String uuid) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: 'uuid = ? AND is_deleted = 0',
      whereArgs: [uuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Student.fromMap(rows.first);
  }

  Future<List<Student>> getByClassId(int classId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'students',
      where: 'class_id = ? AND is_deleted = 0',
      whereArgs: [classId],
      orderBy: 'name ASC',
    );
    return rows.map(Student.fromMap).toList();
  }

  Future<List<Student>> getByClassAndYear(int classId, String year) async {
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
    required int classId,
    String? registrationNo,
    String fatherName = '',
    String? departmentId,
    String? academicSessionId,
    String currentYear = '1st Year',
    String status = 'ACTIVE',
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final uuid = UuidUtils.generate();
    final rowMap = {
      'uuid': uuid,
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
    final id = await db.insert('students', rowMap);
    return Student(
      id: id,
      uuid: uuid,
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
  }

  Future<void> softDelete(int id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'students',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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
