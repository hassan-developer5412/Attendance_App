import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v7.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Builds a legacy v6-shaped database: every table exists with the v6
/// columns (no v7 session-security columns) and carries sample rows.
Future<Database> openLegacyV6Database() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
  final tenant = "'${AppConstants.defaultInstituteId}'";

  await db.execute('''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      display_name TEXT NOT NULL,
      email TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'admin',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      institute_id TEXT NOT NULL DEFAULT $tenant,
      is_synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE classes (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      section TEXT NOT NULL,
      room TEXT NOT NULL,
      class_name TEXT NOT NULL DEFAULT '',
      current_year TEXT NOT NULL DEFAULT '',
      department_id TEXT,
      academic_session_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      institute_id TEXT NOT NULL DEFAULT $tenant,
      is_synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await db.execute('''
    CREATE TABLE teachers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      subject TEXT NOT NULL,
      email TEXT NOT NULL DEFAULT '',
      username TEXT NOT NULL DEFAULT '',
      password TEXT NOT NULL DEFAULT '',
      class_id TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      employee_code TEXT,
      designation TEXT NOT NULL DEFAULT 'Instructor',
      department_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      institute_id TEXT NOT NULL DEFAULT $tenant,
      is_synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE students (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      roll_number TEXT NOT NULL,
      class_id TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      roll_no TEXT,
      full_name TEXT,
      registration_no TEXT,
      father_name TEXT NOT NULL DEFAULT '',
      department_id TEXT,
      academic_session_id TEXT,
      current_year TEXT NOT NULL DEFAULT '1st Year',
      status TEXT NOT NULL DEFAULT 'ACTIVE',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      institute_id TEXT NOT NULL DEFAULT $tenant,
      is_synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE attendance_records (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      student_id TEXT NOT NULL,
      date TEXT NOT NULL,
      status TEXT NOT NULL,
      check_in_time TEXT,
      check_out_time TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      institute_id TEXT NOT NULL DEFAULT $tenant,
      is_synced INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
      UNIQUE (session_id, student_id)
    )
  ''');

  final now = DateTime.now().toUtc().toIso8601String();
  final adminPasswordHash = sha256
      .convert(utf8.encode(AppConstants.defaultAdminPassword))
      .toString();
  final adminId = UuidUtils.deterministic('users', 'admin');
  await db.insert('users', {
    'id': adminId,
    'username': AppConstants.defaultAdminUsername,
    'password_hash': adminPasswordHash,
    'display_name': AppConstants.defaultAdminDisplayName,
    'email': AppConstants.defaultAdminEmail,
    'role': 'admin',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });
  await db.insert('users', {
    'id': UuidUtils.deterministic('users', 'jdoe'),
    'username': 'jdoe',
    'password_hash': 'some-other-hash',
    'display_name': 'Jane Doe',
    'email': 'jdoe@institute.edu',
    'role': 'teacher',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });
  await db.insert('classes', {
    'id': UuidUtils.deterministic('classes', 'CIT-1'),
    'name': 'CIT',
    'section': 'A',
    'room': 'R-101',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });
  await db.insert('teachers', {
    'id': UuidUtils.deterministic('teachers', 't1'),
    'name': 'Legacy Teacher',
    'subject': 'Applied Maths',
    'email': 'teacher@gilt.edu',
    'username': 'teacher',
    'password': 'pass',
    'class_id': UuidUtils.deterministic('classes', 'CIT-1'),
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });
  await db.insert('students', {
    'id': UuidUtils.deterministic('students', 's1'),
    'name': 'Legacy Student',
    'roll_number': 'CIT-001',
    'class_id': UuidUtils.deterministic('classes', 'CIT-1'),
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });
  await db.insert('attendance_records', {
    'id': UuidUtils.deterministic('attendance_records', 'ar1'),
    'student_id': UuidUtils.deterministic('students', 's1'),
    'date': '2026-01-15',
    'status': 'present',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'SYNCED',
    'is_deleted': 0,
  });

  return db;
}

Future<Map<String, int>> rowCounts(Database db) async {
  final tables = <String>[
    'users',
    'teachers',
    'students',
    'classes',
    'attendance_records',
  ];
  final counts = <String, int>{};
  for (final table in tables) {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    counts[table] = result.first['c'] as int;
  }
  return counts;
}

Future<Set<String>> columnNames(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toSet();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SchemaMigrationV7 (v6 ? v7)', () {
    late Database db;

    setUp(() async {
      db = await openLegacyV6Database();
    });

    tearDown(() async {
      await db.close();
    });

    test('preserves every v6 row (no data loss)', () async {
      final before = await rowCounts(db);

      await SchemaMigrationV7.execute(db);

      final after = await rowCounts(db);
      expect(after, before, reason: 'row counts changed during migration');
    });

    test('adds all session-security columns to users', () async {
      await SchemaMigrationV7.execute(db);

      final columns = await columnNames(db, 'users');
      expect(columns, contains('auth_user_id'));
      expect(columns, contains('is_default_password'));
      expect(columns, contains('is_suspended'));
      expect(columns, contains('suspended_at'));
      expect(columns, contains('suspended_reason'));
      expect(columns, contains('failed_login_attempts'));
      expect(columns, contains('locked_until'));
      expect(columns, contains('password_changed_at'));
      expect(columns, contains('last_login_at'));
      expect(columns, contains('session_expires_at'));
    });

    test('adds nullable user_id FK to teachers', () async {
      await SchemaMigrationV7.execute(db);

      final columns = await columnNames(db, 'teachers');
      expect(columns, contains('user_id'));
    });

    test('creates both supporting indexes', () async {
      await SchemaMigrationV7.execute(db);

      final indexes = await db.rawQuery("""
        SELECT name FROM sqlite_master
        WHERE type = 'index'
          AND name IN ('idx_users_auth_user_id', 'idx_teachers_user_id')
      """);
      expect(indexes, hasLength(2));
    });

    test('existing users keep NULL auth_user_id and stay usable offline', () async {
      await SchemaMigrationV7.execute(db);

      final users = await db.query('users');
      for (final user in users) {
        expect(user['auth_user_id'], isNull,
            reason: 'unlinked users must have NULL auth_user_id');
      }
    });

    test('flags the pre-existing default-password admin via parameter binding',
        () async {
      final adminId = UuidUtils.deterministic('users', 'admin');

      await SchemaMigrationV7.execute(db);

      final admin = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [adminId],
        limit: 1,
      );
      expect(admin, hasLength(1));
      expect(admin.first['is_default_password'], 1);

      final other = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['jdoe'],
        limit: 1,
      );
      expect(other.first['is_default_password'], 0);
    });

    test('passes PRAGMA foreign_key_check', () async {
      await SchemaMigrationV7.execute(db);

      final violations = await db.rawQuery('PRAGMA foreign_key_check');
      expect(violations, isEmpty);
    });

    test('is idempotent when executed twice', () async {
      await SchemaMigrationV7.execute(db);
      await SchemaMigrationV7.execute(db);

      final after = await rowCounts(db);
      expect(after['users'], 2);
      expect(after['teachers'], 1);
      expect(after['students'], 1);
      expect(after['classes'], 1);
      expect(after['attendance_records'], 1);
    });
  });

  group('FreshDatabaseCreator (v7 schema)', () {
    test('creates v7 schema with empty users table and no seeded admin',
        () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(() => db.close());

      await FreshDatabaseCreator.createAndSeed(db);

      expect(await db.query('users'), isEmpty);
      expect(
        await db.query('users', where: 'username = ?', whereArgs: ['admin']),
        isEmpty,
      );

      final userColumns = await columnNames(db, 'users');
      expect(userColumns, contains('auth_user_id'));
      expect(userColumns, contains('is_suspended'));
      expect(userColumns, contains('failed_login_attempts'));

      final teacherColumns = await columnNames(db, 'teachers');
      expect(teacherColumns, contains('user_id'));

      final indexes = await db.rawQuery("""
        SELECT name FROM sqlite_master
        WHERE type = 'index'
          AND name IN ('idx_users_auth_user_id', 'idx_teachers_user_id')
      """);
      expect(indexes, hasLength(2));

      final departmentRow = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM departments');
      final departmentCount = departmentRow.first['c'] as int;
      expect(departmentCount, greaterThan(0));
    });
  });
}

