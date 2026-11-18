import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Path for an in-memory SQLite database via FFI.
const _kInMemoryPath = ':memory:';

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    db = await databaseFactory.openDatabase(_kInMemoryPath);
    DatabaseHelper.setTestDatabase(db);

    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        email TEXT NOT NULL,
        role TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT 'default_institute',
        roll_no TEXT,
        employee_id TEXT,
        is_suspended INTEGER NOT NULL DEFAULT 0,
        suspended_at TEXT,
        suspended_reason TEXT,
        failed_login_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        password_changed_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE departments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT 'default_institute',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE permissions (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT 'default_institute',
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE role_permissions (
        role_id TEXT NOT NULL,
        permission_code TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        is_synced INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT 'default_institute',
        updated_at TEXT NOT NULL,
        PRIMARY KEY (role_id, permission_code)
      )
    ''');
  });

  tearDown(() async {
    await db.delete('users');
    await db.delete('departments');
    await db.delete('permissions');
    await db.delete('role_permissions');
    DatabaseHelper.setTestDatabase(null);
  });

  // -----------------------------------------------------------------------
  // normalizeRemoteRowForSqlite
  // -----------------------------------------------------------------------

  test('normalizeRemoteRowForSqlite converts PostgreSQL bools to SQLite ints', () async {
    final remoteRow = <String, dynamic>{
      'id': 'user-1',
      'username': 'jdoe',
      'display_name': 'John Doe',
      'email': 'john@example.com',
      'role': 'teacher',
      'is_suspended': true,
      'failed_login_attempts': 3,
      'is_deleted': false,
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'users',
      remoteRow,
    );

    expect(normalized!['is_suspended'], 1);
    expect(normalized['is_deleted'], 0);
    expect(normalized['sync_status'], 'SYNCED');
    expect(normalized['is_synced'], 1);
  });

  test('normalizeRemoteRowForSqlite drops Supabase-only columns', () async {
    final remoteRow = <String, dynamic>{
      'id': 'user-1',
      'username': 'jdoe',
      'display_name': 'John Doe',
      'email': 'john@example.com',
      'role': 'teacher',
      'local_id': 'supabase-only-column',
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'users',
      remoteRow,
    );

    expect(normalized!.containsKey('local_id'), isFalse);
    expect(normalized['id'], 'user-1');
  });

  test('normalizeRemoteRowForSqlite preserves is_deleted soft-delete flag', () async {
    final remoteRow = <String, dynamic>{
      'id': 'user-deleted',
      'username': 'deleted_user',
      'display_name': 'Deleted User',
      'email': 'deleted@example.com',
      'role': 'student',
      'is_deleted': true,
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'users',
      remoteRow,
    );

    expect(normalized!['is_deleted'], 1);
  });

  // -----------------------------------------------------------------------
  // role_permissions normalization
  // -----------------------------------------------------------------------

  test('normalizeRemoteRowForSqlite returns null for role_permissions when permission_id is null', () async {
    await db.insert(
      'permissions',
      {
        'id': 'perm-view',
        'code': 'view_reports',
        'name': 'View Reports',
        'is_deleted': 0,
        'sync_status': 'SYNCED',
        'is_synced': 1,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final remoteRow = <String, dynamic>{
      'role_id': 'role-admin',
      'permission_id': null,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'role_permissions',
      remoteRow,
    );

    expect(normalized, isNull);
  });

  test('normalizeRemoteRowForSqlite returns null for role_permissions when permission_id is unknown', () async {
    await db.insert(
      'permissions',
      {
        'id': 'perm-view',
        'code': 'view_reports',
        'name': 'View Reports',
        'is_deleted': 0,
        'sync_status': 'SYNCED',
        'is_synced': 1,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final remoteRow = <String, dynamic>{
      'role_id': 'role-admin',
      'permission_id': 'perm-nonexistent',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'role_permissions',
      remoteRow,
    );

    expect(normalized, isNull);
  });

  test('normalizeRemoteRowForSqlite resolves permission_code for role_permissions when permission_id exists', () async {
    await db.insert(
      'permissions',
      {
        'id': 'perm-view',
        'code': 'view_reports',
        'name': 'View Reports',
        'is_deleted': 0,
        'sync_status': 'SYNCED',
        'is_synced': 1,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final remoteRow = <String, dynamic>{
      'role_id': 'role-admin',
      'permission_id': 'perm-view',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'role_permissions',
      remoteRow,
    );

    expect(normalized, isNotNull);
    expect(normalized!['permission_code'], 'view_reports');
    expect(normalized['role_id'], 'role-admin');
  });

  // -----------------------------------------------------------------------
  // Remote row upsert into SQLite
  // -----------------------------------------------------------------------

  test('remote row upsert writes to SQLite via ConflictAlgorithm.replace', () async {
    final remoteRow = <String, dynamic>{
      'id': 'user-upsert',
      'username': 'upserted',
      'display_name': 'Upserted User',
      'email': 'upsert@example.com',
      'role': 'teacher',
      'is_deleted': false,
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'users',
      remoteRow,
    );

    await db.insert(
      'users',
      normalized!,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: ['user-upsert'],
    );

    expect(rows.length, 1);
    expect(rows.first['username'], 'upserted');
    expect(rows.first['is_synced'], 1);
    expect(rows.first['sync_status'], 'SYNCED');
  });

  test('is_deleted soft-delete row is synced to SQLite', () async {
    final remoteRow = <String, dynamic>{
      'id': 'user-soft-delete',
      'username': 'soft_deleted',
      'display_name': 'Soft Deleted',
      'email': 'soft@example.com',
      'role': 'student',
      'is_deleted': true,
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'users',
      remoteRow,
    );

    await db.insert(
      'users',
      normalized!,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: ['user-soft-delete'],
    );

    expect(rows.length, 1);
    expect(rows.first['is_deleted'], 1);
  });

  // -----------------------------------------------------------------------
  // PENDING local edit protection
  // -----------------------------------------------------------------------

  test('localRowIsPending returns true for a PENDING local row', () async {
    await db.insert(
      'users',
      {
        'id': 'user-pending',
        'username': 'pending_local',
        'display_name': 'Pending Local',
        'email': 'pending@example.com',
        'role': 'student',
        'is_deleted': 0,
        'sync_status': 'PENDING',
        'is_synced': 0,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final isPending = await SyncService.instance.localRowIsPending(
      db,
      'users',
      {'id': 'user-pending'},
    );

    expect(isPending, true);
  });

  test('localRowIsPending returns false for a SYNCED local row', () async {
    await db.insert(
      'users',
      {
        'id': 'user-synced',
        'username': 'synced_local',
        'display_name': 'Synced Local',
        'email': 'synced@example.com',
        'role': 'student',
        'is_deleted': 0,
        'sync_status': 'SYNCED',
        'is_synced': 1,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final isPending = await SyncService.instance.localRowIsPending(
      db,
      'users',
      {'id': 'user-synced'},
    );

    expect(isPending, false);
  });

  test('localRowIsPending returns false when no local row exists', () async {
    final isPending = await SyncService.instance.localRowIsPending(
      db,
      'users',
      {'id': 'nonexistent'},
    );

    expect(isPending, false);
  });

  test('PENDING local row is not overwritten by remote upsert (simulated pull logic)', () async {
    await db.insert(
      'users',
      {
        'id': 'user-protected',
        'username': 'protected_local',
        'display_name': 'Protected Local',
        'email': 'protected@example.com',
        'role': 'student',
        'is_deleted': 0,
        'sync_status': 'PENDING',
        'is_synced': 0,
        'institute_id': 'default_institute',
        'updated_at': '2026-01-01T00:00:00Z',
      },
    );

    final isPending = await SyncService.instance.localRowIsPending(
      db,
      'users',
      {'id': 'user-protected'},
    );

    expect(isPending, true);

    final rows = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: ['user-protected'],
    );

    expect(rows.length, 1);
    expect(rows.first['sync_status'], 'PENDING');
    expect(rows.first['username'], 'protected_local');
  });

  // -----------------------------------------------------------------------
  // Cross-table: departments
  // -----------------------------------------------------------------------

  test('department remote row upserts correctly', () async {
    final remoteRow = <String, dynamic>{
      'id': 'dept-cs',
      'name': 'Computer Science',
      'code': 'CS',
      'is_deleted': false,
      'updated_at': '2026-01-01T00:00:00Z',
    };

    final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
      db,
      'departments',
      remoteRow,
    );

    await db.insert(
      'departments',
      normalized!,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final rows = await db.query(
      'departments',
      where: 'id = ?',
      whereArgs: ['dept-cs'],
    );

    expect(rows.length, 1);
    expect(rows.first['name'], 'Computer Science');
    expect(rows.first['is_synced'], 1);
  });

  // Close the database after all tests complete
  tearDownAll(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });
}