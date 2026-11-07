import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/database/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('SchemaMigrationV9 upgrades legacy database with roles missing code column', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // 1. Simulate legacy pre-v9 database schema with old roles and permissions tables
    await db.execute('''CREATE TABLE roles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT NOT NULL DEFAULT '',
      is_custom INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )''');

    await db.execute('''CREATE TABLE permissions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT NOT NULL UNIQUE,
      description TEXT NOT NULL DEFAULT '',
      module TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    )''');

    await db.execute('''CREATE TABLE role_permissions (
      role_id INTEGER NOT NULL,
      permission_id INTEGER NOT NULL,
      PRIMARY KEY (role_id, permission_id)
    )''');

    await db.execute('''CREATE TABLE user_roles (
      user_id INTEGER NOT NULL,
      role_id INTEGER NOT NULL,
      PRIMARY KEY (user_id, role_id)
    )''');

    await db.execute('''CREATE TABLE user_departments (
      user_id INTEGER NOT NULL,
      department_id INTEGER NOT NULL,
      PRIMARY KEY (user_id, department_id)
    )''');

    // Verify initial legacy state: roles has NO code column
    final initialInfo = await db.rawQuery("PRAGMA table_info('roles')");
    final initialColumns = initialInfo.map((r) => r['name'] as String).toSet();
    expect(initialColumns.contains('code'), isFalse);

    // 2. Execute SchemaMigrationV9
    await SchemaMigrationV9.execute(db);

    // 3. Verify upgraded state: roles now has 'code', 'is_institute_wide', etc.
    final upgradedInfo = await db.rawQuery("PRAGMA table_info('roles')");
    final upgradedColumns = upgradedInfo.map((r) => r['name'] as String).toSet();
    expect(upgradedColumns, containsAll({'id', 'name', 'code', 'is_institute_wide'}));

    // 4. Verify that RoleRepository can query roles by code
    final dbHelper = DatabaseHelper.forTesting(db);
    final roleRepo = RoleRepository(dbHelper: dbHelper);
    final adminRole = await roleRepo.getByCode('admin');
    expect(adminRole, isNotNull);
    expect(adminRole!.code, equals('admin'));
    expect(adminRole.name, equals('Administrator'));
    expect(adminRole.isInstituteWide, isTrue);

    // 5. Verify predefined roles were seeded
    final allRoles = await roleRepo.getAll();
    expect(allRoles.length, greaterThanOrEqualTo(10));
    final codes = allRoles.map((r) => r.code).toSet();
    expect(codes, containsAll([
      'admin',
      'principal',
      'vice_principal',
      'hod',
      'teacher',
      'student',
      'parent',
      'accountant',
      'lab_in_charge',
      'assistant',
    ]));

    await db.close();
  });
}
