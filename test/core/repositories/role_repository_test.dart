import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/permission_repository.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Integration-style tests for [RoleRepository].
void main() {
  late DatabaseHelper dbHelper;
  late RoleRepository repo;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Open an in-memory database fresh for each test.
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMigrationV9.execute(db);
    dbHelper = DatabaseHelper.forTesting(db);
    repo = RoleRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
  });

  group('CRUD', () {
    test('insert and get by code', () async {
      final id = await repo.insert(
        name: 'Head of IT',
        code: 'hod_it',
        description: 'Head of IT department',
        isCustom: true,
        isInstituteWide: false,
      );
      expect(id.isNotEmpty, isTrue);

      final role = await repo.getByCode('hod_it');
      expect(role, isNotNull);
      expect(role?.name, equals('Head of IT'));
      expect(role?.code, equals('hod_it'));
      expect(role?.isCustom, isTrue);
    });

    test('update', () async {
      final id = await repo.insert(name: 'Temp', code: 'temp', description: 'x');
      await repo.update(Role(
        id: id,
        name: 'Renamed',
        code: 'temp',
        description: 'y',
        isCustom: true,
      ));
      final updated = await repo.getByCode('temp');
      expect(updated?.description, equals('y'));
    });

    test('soft delete removes from getAll (includeDeleted: true)', () async {
      final id = await repo.insert(name: 'ToDelete', code: 'del', description: 'x');
      await repo.softDelete(id);
      final withDeleted = await repo.getAll(includeDeleted: true);
      expect(withDeleted.any((r) => r.code == 'del'), isTrue);
      final active = await repo.getAll(includeDeleted: false);
      expect(active.any((r) => r.code == 'del'), isFalse);
    });
  });

  group('role → permission grants', () {
    test('grant and revoke permission', () async {
      final roleId = await repo.insert(name: 'Test', code: 'testrole', description: 'x');
      final permRepo = PermissionRepository(dbHelper: dbHelper);
      await permRepo.insert(
        code: 'testperm',
        module: 'test',
        description: 'Test permission',
      );

      // Grant.
      await repo.grantPermission(roleId, 'testperm');
      final codes = await repo.getPermissionCodesForRole(roleId);
      expect(codes.contains('testperm'), isTrue);

      // Revoke.
      await repo.revokePermission(roleId, 'testperm');
      final codesAfter = await repo.getPermissionCodesForRole(roleId);
      expect(codesAfter.contains('testperm'), isFalse);
    });

    test('replaceRolePermissions', () async {
      final roleId = await repo.insert(name: 'Multi', code: 'multi', description: 'x');
      await repo.replaceRolePermissions(roleId, <String>['perm_a', 'perm_b']);

      final codes = await repo.getPermissionCodesForRole(roleId);
      expect(codes, containsAll(<String>['perm_a', 'perm_b']));

      // Replace again.
      await repo.replaceRolePermissions(roleId, <String>['perm_a']);
      final codesAfter = await repo.getPermissionCodesForRole(roleId);
      expect(codesAfter, equals(<String>{'perm_a'}));
    });
  });
}
