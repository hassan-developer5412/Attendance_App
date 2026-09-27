import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v3.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

Future<Database> openLegacyV2Database() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      display_name TEXT NOT NULL,
      email TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'admin',
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE classes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      section TEXT NOT NULL,
      room TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE teachers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      subject TEXT NOT NULL,
      email TEXT NOT NULL DEFAULT '',
      username TEXT NOT NULL DEFAULT '',
      password TEXT NOT NULL DEFAULT '',
      class_id INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('''
    CREATE TABLE students (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      roll_number TEXT NOT NULL,
      class_id INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('''
    CREATE TABLE subjects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      teacher_name TEXT NOT NULL,
      class_id INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE attendance_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      student_id INTEGER NOT NULL,
      date TEXT NOT NULL,
      status TEXT NOT NULL,
      check_in_time TEXT,
      check_out_time TEXT,
      UNIQUE (student_id, date)
    )
  ''');
  await db.execute('''
    CREATE TABLE leave_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      requester_name TEXT NOT NULL,
      leave_type TEXT NOT NULL,
      start_date TEXT NOT NULL,
      end_date TEXT NOT NULL,
      reason TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');

  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('users', {
    'username': AppConstants.defaultAdminUsername,
    'password_hash': 'legacy-hash',
    'display_name': AppConstants.defaultAdminDisplayName,
    'email': AppConstants.defaultAdminEmail,
    'role': UserRole.admin.value,
    'created_at': now,
  });
  await db.insert('classes', {'name': 'CIT-1', 'section': 'A', 'room': 'R-101'});
  await db.insert('teachers', {
    'name': 'Legacy Teacher',
    'subject': 'Applied Maths',
    'email': 'teacher@gilt.edu',
    'username': 'teacher',
    'password': 'pass',
    'class_id': 1,
    'is_active': 1,
  });
  await db.insert('students', {
    'name': 'Legacy Student',
    'roll_number': 'CIT-001',
    'class_id': 1,
    'is_active': 1,
  });
  await db.insert('subjects', {
    'name': 'Applied Maths',
    'code': 'MTH-101',
    'teacher_name': 'Legacy Teacher',
    'class_id': 1,
  });
  await db.insert('attendance_records', {
    'student_id': 1,
    'date': '2026-01-15',
    'status': 'present',
    'check_in_time': '2026-01-15T08:55:00.000Z',
    'check_out_time': null,
  });
  await db.insert('leave_requests', {
    'requester_name': 'Legacy Teacher',
    'leave_type': 'Casual',
    'start_date': '2026-02-01T00:00:00.000Z',
    'end_date': '2026-02-02T00:00:00.000Z',
    'reason': 'Family event',
    'status': 'pending',
  });

  return db;
}

Future<int> _count(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM $table');
  return rows.first['cnt'] as int;
}

Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
  );
  return rows.map((row) => row['name'] as String).toList();
}
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('FreshDatabaseCreator', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await FreshDatabaseCreator.createAndSeed(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('creates every canonical table including the new V3 entities', () async {
      final tables = await _tableNames(db);
      for (final table in const [
        'users',
        'classes',
        'teachers',
        'students',
        'subjects',
        'attendance_records',
        'leave_requests',
        'departments',
        'attendance_sessions',
        'lab_inventory',
      ]) {
        expect(tables, contains(table), reason: 'missing table $table');
      }
    });

    test('seeds the default admin with a canonical UUID', () async {
      final rows = await db.query('users');
      expect(rows, hasLength(1));
      final admin = rows.first;
      expect(admin['username'], AppConstants.defaultAdminUsername);
      expect(admin['password_hash'], isNot(AppConstants.defaultAdminPassword));
      expect(admin['uuid'], UuidUtils.deterministic('users', 'admin'));
      expect(admin['sync_status'], 'SYNCED');
      expect(admin['is_deleted'], 0);
    });

    test('seeds every GILT academic department idempotently', () async {
      final rows = await db.query('departments');
      expect(rows, hasLength(AcademicDepartment.values.length));
      final codes = rows.map((row) => row['code']).toSet();
      for (final department in AcademicDepartment.values) {
        expect(codes, contains(department.code));
      }
    });
  });

  group('SchemaMigrationV3', () {
    late Database db;

    setUp(() async {
      db = await openLegacyV2Database();
    });

    tearDown(() async {
      await db.close();
    });

    test('preserves every v2 row (no data loss)', () async {
      final before = <String, int>{
        'users': await _count(db, 'users'),
        'classes': await _count(db, 'classes'),
        'teachers': await _count(db, 'teachers'),
        'students': await _count(db, 'students'),
        'subjects': await _count(db, 'subjects'),
        'attendance_records': await _count(db, 'attendance_records'),
        'leave_requests': await _count(db, 'leave_requests'),
      };

      await SchemaMigrationV3.execute(db);

      for (final entry in before.entries) {
        expect(
          await _count(db, entry.key),
          entry.value,
          reason: 'row count changed for ${entry.key}',
        );
      }

      final student = (await db.query('students')).first;
      expect(student['name'], 'Legacy Student');
      expect(student['roll_number'], 'CIT-001');

      final leave = (await db.query('leave_requests')).first;
      expect(leave['reason'], 'Family event');
      expect(leave['status'], 'pending');
    });

    test('adds canonical tables and backfills UUIDs for legacy rows', () async {
      await SchemaMigrationV3.execute(db);

      final tables = await _tableNames(db);
      expect(tables, contains('departments'));
      expect(tables, contains('attendance_sessions'));
      expect(tables, contains('lab_inventory'));
      expect(tables, contains('sync_queue'));

      final user = (await db.query('users')).first;
      expect(user['uuid'], UuidUtils.deterministic('users', user['id']));

      final schoolClass = (await db.query('classes')).first;
      expect(
        schoolClass['uuid'],
        UuidUtils.deterministic('classes', schoolClass['id']),
      );

      final teacher = (await db.query('teachers')).first;
      expect(
        teacher['uuid'],
        UuidUtils.deterministic('teachers', teacher['id']),
      );
      expect(teacher['employee_code'], 'FAC-1');

      final subject = (await db.query('subjects')).first;
      expect(
        subject['uuid'],
        UuidUtils.deterministic('subjects', subject['id']),
      );
    });

    test('links legacy attendance rows to a deterministic session', () async {
      await SchemaMigrationV3.execute(db);

      final record = (await db.query('attendance_records')).first;
      final expectedSessionId =
          UuidUtils.deterministic('attendance_sessions', '2026-01-15');
      expect(record['uuid'], isNotNull);
      expect((record['uuid'] as String), isNotEmpty);
      expect(record['session_id'], expectedSessionId);
      expect(record['status'], 'present');

      final session = await db.query(
        'attendance_sessions',
        where: 'id = ?',
        whereArgs: [expectedSessionId],
      );
      expect(session, hasLength(1));
      expect(session.first['session_date'], '2026-01-15');
    });

    test('is idempotent when executed twice', () async {
      await SchemaMigrationV3.execute(db);
      await SchemaMigrationV3.execute(db);

      expect(await _count(db, 'users'), 1);
      expect(await _count(db, 'classes'), 1);
      expect(await _count(db, 'attendance_records'), 1);
      expect(await _count(db, 'leave_requests'), 1);
      expect(await _count(db, 'attendance_sessions'), 1);
      expect(
        await _count(db, 'departments'),
        AcademicDepartment.values.length,
      );
    });
  });
}
