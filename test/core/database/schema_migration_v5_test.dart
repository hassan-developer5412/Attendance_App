import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v5.dart';

/// Builds an in-memory v4-shaped database: every synced table exists but
/// lacks the `institute_id` / `is_synced` replication columns.
Future<Database> openLegacyV4Database() async {
  final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

  const textPkTables = <String>[
    'departments',
    'academic_sessions',
    'attendance_sessions',
    'lab_inventory',
  ];
  const intPkTables = <String>[
    'users',
    'classes',
    'teachers',
    'students',
    'subjects',
    'attendance_records',
    'leave_requests',
  ];

  for (final table in textPkTables) {
    await db.execute('''
      CREATE TABLE $table (
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
  for (final table in intPkTables) {
    await db.execute('''
      CREATE TABLE $table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // Local-only queue: must NOT receive the replication columns.
  await db.execute('''
    CREATE TABLE sync_queue (
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

  return db;
}

Future<Set<String>> columnNames(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((row) => row['name'] as String).toSet();
}

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  group('SchemaMigrationV5', () {
    late Database db;

    setUp(() async {
      db = await openLegacyV4Database();
    });

    tearDown(() async {
      await db.close();
    });

    test('adds institute_id and is_synced to every synced table', () async {
      await SchemaMigrationV5.execute(db);

      for (final table in SchemaMigrationV5.syncedTables) {
        final columns = await columnNames(db, table);
        expect(columns, contains('institute_id'),
            reason: '$table is missing institute_id');
        expect(columns, contains('is_synced'),
            reason: '$table is missing is_synced');
      }
    });

    test('defaults existing rows to the tenant default and unsynced',
        () async {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('students', {
        'uuid': 'legacy-student-uuid',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'SYNCED',
        'is_deleted': 0,
      });

      await SchemaMigrationV5.execute(db);

      final row = (await db.query('students')).single;
      expect(row['institute_id'], AppConstants.defaultInstituteId);
      expect(row['is_synced'], 0,
          reason: 'existing rows must start unsynced for the first backfill');
    });

    test('leaves sync_queue untouched (local-only table)', () async {
      await SchemaMigrationV5.execute(db);

      final columns = await columnNames(db, 'sync_queue');
      expect(columns, isNot(contains('institute_id')));
      expect(columns, isNot(contains('is_synced')));
    });

    test('is idempotent when executed twice', () async {
      await SchemaMigrationV5.execute(db);
      await SchemaMigrationV5.execute(db);

      final info = await db.rawQuery('PRAGMA table_info(students)');
      final syncedCount =
          info.where((row) => row['name'] == 'is_synced').length;
      expect(syncedCount, 1, reason: 'is_synced must not be duplicated');
    });

    test('primary keys are preserved (TEXT stays TEXT, INTEGER stays INTEGER)',
        () async {
      await SchemaMigrationV5.execute(db);

      final deptInfo = await db.rawQuery('PRAGMA table_info(departments)');
      expect(deptInfo.first['type'], 'TEXT');
      final studentInfo = await db.rawQuery('PRAGMA table_info(students)');
      expect(studentInfo.first['type'], 'INTEGER');
    });
  });

  group('FreshDatabaseCreator (v5 schema)', () {
    test('creates every synced table with both replication columns', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      addTearDown(() => db.close());

      await FreshDatabaseCreator.createAndSeed(db);

      for (final table in SchemaMigrationV5.syncedTables) {
        final columns = await columnNames(db, table);
        expect(columns, contains('institute_id'),
            reason: '$table is missing institute_id on a fresh install');
        expect(columns, contains('is_synced'),
            reason: '$table is missing is_synced on a fresh install');
      }
    });
  });
}