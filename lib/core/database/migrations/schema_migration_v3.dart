import 'package:sqflite/sqflite.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

class SchemaMigrationV3 {
  SchemaMigrationV3._();

  static Future<void> execute(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _createCanonicalTables(db);
    await _addSyncAndCanonicalColumns(db, now);
    await _populateExistingRecords(db, now);
    await MigrationHelpers.seedDepartments(db);
  }

  static Future<void> _createCanonicalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS departments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance_sessions (
        id TEXT PRIMARY KEY,
        subject_code TEXT NOT NULL DEFAULT '',
        department_id TEXT NOT NULL DEFAULT '',
        faculty_id TEXT NOT NULL DEFAULT '',
        session_date TEXT NOT NULL,
        remarks TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lab_inventory (
        id TEXT PRIMARY KEY,
        item_name TEXT NOT NULL,
        department_id TEXT NOT NULL,
        category TEXT NOT NULL,
        current_stock REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        reorder_level REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
  }

  static Future<void> _addSyncAndCanonicalColumns(Database db, String now) async {
    await MigrationHelpers.addColumnIfNotExists(db, 'users', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'users', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'users', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'users', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'department_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'classes', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'employee_code', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'designation', "TEXT NOT NULL DEFAULT 'Instructor'");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'department_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'teachers', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'roll_no', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'full_name', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'registration_no', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'father_name', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'department_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'current_semester', "TEXT NOT NULL DEFAULT '1st'");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'status', "TEXT NOT NULL DEFAULT 'ACTIVE'");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'students', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'subjects', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'subjects', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'subjects', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'subjects', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'subjects', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'session_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'attendance_records', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");

    await MigrationHelpers.addColumnIfNotExists(db, 'leave_requests', 'uuid', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(db, 'leave_requests', 'created_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'leave_requests', 'updated_at', "TEXT NOT NULL DEFAULT '$now'");
    await MigrationHelpers.addColumnIfNotExists(db, 'leave_requests', 'sync_status', "TEXT NOT NULL DEFAULT 'PENDING'");
    await MigrationHelpers.addColumnIfNotExists(db, 'leave_requests', 'is_deleted', "INTEGER NOT NULL DEFAULT 0");
  }

  static Future<void> _populateExistingRecords(Database db, String now) async {
    await db.transaction((txn) async {
      final userRows = await txn.query('users');
      for (final row in userRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        if (currentUuid == null || currentUuid.isEmpty) {
          final newUuid = UuidUtils.deterministic('users', id);
          await txn.update('users', {'uuid': newUuid}, where: 'id = ?', whereArgs: [id]);
        }
      }

      final classRows = await txn.query('classes');
      for (final row in classRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        if (currentUuid == null || currentUuid.isEmpty) {
          final newUuid = UuidUtils.deterministic('classes', id);
          await txn.update('classes', {'uuid': newUuid}, where: 'id = ?', whereArgs: [id]);
        }
      }

      final teacherRows = await txn.query('teachers');
      for (final row in teacherRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        final empCode = row['employee_code'] as String?;
        final updates = <String, dynamic>{};
        if (currentUuid == null || currentUuid.isEmpty) {
          updates['uuid'] = UuidUtils.deterministic('teachers', id);
        }
        if (empCode == null || empCode.isEmpty) {
          updates['employee_code'] = 'FAC-$id';
        }
        if (updates.isNotEmpty) {
          await txn.update('teachers', updates, where: 'id = ?', whereArgs: [id]);
        }
      }

      final studentRows = await txn.query('students');
      for (final row in studentRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        final roll = (row['roll_number'] as String?) ?? '';
        final name = (row['name'] as String?) ?? '';
        final regNo = row['registration_no'] as String?;

        final updates = <String, dynamic>{
          'roll_no': roll,
          'full_name': name,
        };
        if (currentUuid == null || currentUuid.isEmpty) {
          updates['uuid'] = UuidUtils.deterministic('students', id);
        }
        if (regNo == null || regNo.isEmpty) {
          updates['registration_no'] = 'REG-$roll';
        }
        await txn.update('students', updates, where: 'id = ?', whereArgs: [id]);
      }

      final subjectRows = await txn.query('subjects');
      for (final row in subjectRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        if (currentUuid == null || currentUuid.isEmpty) {
          final newUuid = UuidUtils.deterministic('subjects', id);
          await txn.update('subjects', {'uuid': newUuid}, where: 'id = ?', whereArgs: [id]);
        }
      }

      final attendanceRows = await txn.query('attendance_records');
      for (final row in attendanceRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        final currentSessionId = row['session_id'] as String?;
        final date = (row['date'] as String?) ?? '';

        final updates = <String, dynamic>{};
        if (currentUuid == null || currentUuid.isEmpty) {
          updates['uuid'] = UuidUtils.deterministic('attendance_records', id);
        }
        if (currentSessionId == null || currentSessionId.isEmpty) {
          final sessionUuid = UuidUtils.deterministic('attendance_sessions', date);
          updates['session_id'] = sessionUuid;

          final existingSession = await txn.query(
            'attendance_sessions',
            where: 'id = ?',
            whereArgs: [sessionUuid],
            limit: 1,
          );
          if (existingSession.isEmpty) {
            await txn.insert('attendance_sessions', {
              'id': sessionUuid,
              'subject_code': 'GENERAL',
              'department_id': UuidUtils.deterministic('departments', 'DAE-CIT'),
              'faculty_id': '',
              'session_date': date,
              'remarks': 'Migrated session from date $date',
              'created_at': now,
              'updated_at': now,
              'sync_status': 'PENDING',
              'is_deleted': 0,
            });
          }
        }
        if (updates.isNotEmpty) {
          await txn.update('attendance_records', updates, where: 'id = ?', whereArgs: [id]);
        }
      }

      final leaveRows = await txn.query('leave_requests');
      for (final row in leaveRows) {
        final id = row['id'];
        final currentUuid = row['uuid'] as String?;
        if (currentUuid == null || currentUuid.isEmpty) {
          final newUuid = UuidUtils.deterministic('leave_requests', id);
          await txn.update('leave_requests', {'uuid': newUuid}, where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }
}
