import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

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

  Future<List<Subject>> getByClassAndYear(int classId, String year) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: 'class_id = ? AND year = ? AND is_deleted = 0',
      whereArgs: [classId, year],
      orderBy: 'name ASC',
    );
    return rows.map(Subject.fromMap).toList();
  }

  /// All subjects assigned to a teacher (by integer teacher id).
  Future<List<Subject>> getByTeacherId(int teacherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'subjects',
      where: 'teacher_id = ? AND is_deleted = 0',
      whereArgs: [teacherId],
      orderBy: 'name ASC',
    );
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject> insert({
    required String name,
    required String code,
    required String teacherName,
    required int classId,
    String? departmentId,
    String? academicSessionId,
    String year = '',
    SubjectType subjectType = SubjectType.theory,
    double contactHours = 0,
    int? teacherId,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final uuid = UuidUtils.generate();
    final rowMap = {
      'uuid': uuid,
      'name': name.trim(),
      'code': code.trim(),
      'teacher_name': teacherName.trim(),
      'class_id': classId,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'year': year.trim(),
      'subject_type': subjectType.code,
      'contact_hours': contactHours,
      'teacher_id': teacherId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    final id = await db.insert('subjects', rowMap);
    return Subject(
      id: id,
      uuid: uuid,
      name: name.trim(),
      code: code.trim(),
      teacherName: teacherName.trim(),
      classId: classId,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      year: year.trim(),
      subjectType: subjectType,
      contactHours: contactHours,
      teacherId: teacherId,
    );
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
        'department_id': subject.departmentId,
        'academic_session_id': subject.academicSessionId,
        'year': subject.year.trim(),
        'subject_type': subject.subjectType.code,
        'contact_hours': subject.contactHours,
        'teacher_id': subject.teacherId,
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
