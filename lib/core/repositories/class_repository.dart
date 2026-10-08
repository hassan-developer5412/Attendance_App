import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

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

  /// Classes filtered by department and/or academic session.
  Future<List<SchoolClass>> getByContext({
    String? departmentId,
    String? academicSessionId,
  }) async {
    final db = await _dbHelper.database;
    final where = <String>['is_deleted = 0'];
    final args = <Object?>[];
    if (departmentId != null && departmentId.isNotEmpty) {
      where.add('department_id = ?');
      args.add(departmentId);
    }
    if (academicSessionId != null && academicSessionId.isNotEmpty) {
      where.add('academic_session_id = ?');
      args.add(academicSessionId);
    }
    final rows = await db.query(
      'classes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'class_name ASC, current_year ASC',
    );
    return rows.map(SchoolClass.fromMap).toList();
  }

  Future<SchoolClass> insert({
    required String name,
    String section = '',
    String room = '',
    String? departmentId,
    String? academicSessionId,
    String? className,
    String currentYear = '',
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final resolvedClassName = (className ?? name).trim();
    final uuid = UuidUtils.generate();
    final rowMap = {
      'uuid': uuid,
      'name': name.trim(),
      'section': section.trim(),
      'room': room.trim(),
      'class_name': resolvedClassName,
      'current_year': currentYear.trim(),
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'PENDING',
      'is_deleted': 0,
    };
    final id = await db.insert('classes', rowMap);
    SyncService.instance.schedulePush('classes', idColumn: 'id', idValue: id);
    return SchoolClass(
      id: id,
      uuid: uuid,
      name: name.trim(),
      section: section.trim(),
      room: room.trim(),
      className: resolvedClassName,
      currentYear: currentYear.trim(),
      departmentId: departmentId,
      academicSessionId: academicSessionId,
    );
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
        'class_name': schoolClass.className.trim(),
        'current_year': schoolClass.currentYear.trim(),
        'department_id': schoolClass.departmentId,
        'academic_session_id': schoolClass.academicSessionId,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [schoolClass.id],
    );
    SyncService.instance.schedulePush(
      'classes',
      idColumn: 'id',
      idValue: schoolClass.id,
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
    // Cascaded teachers/students/subjects rows are marked PENDING above and
    // are picked up by the background flush; push the class row itself now.
    SyncService.instance.schedulePush('classes', idColumn: 'id', idValue: id);
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
