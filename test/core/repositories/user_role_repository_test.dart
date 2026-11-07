import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';
import 'package:attendance_app/core/repositories/user_role_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Tests for [UserRoleRepository].
void main() {
  late DatabaseHelper dbHelper;
  late UserRoleRepository repo;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMigrationV9.execute(db);
    dbHelper = DatabaseHelper.forTesting(db);
    repo = UserRoleRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
  });

  group('assign / revoke roles', () {
    test('assignRoleToUser mirrors in-memory cache and persists', () async {
      const roleId = 'r1';
      await repo.assignRoleToUser(userId: 'u1', roleId: roleId);

      final assignments = await repo.getAssignmentsForUser('u1');
      expect(assignments.length, equals(1));
      expect(assignments.first.roleId, equals(roleId));

      // Revoke.
      await repo.revokeRoleFromUser('u1', roleId);
      final after = await repo.getAssignmentsForUser('u1');
      expect(after, isEmpty);
    });

    test('revokeAllRolesForUser clears all', () async {
      // Assign two roles.
      await repo.assignRoleToUser(userId: 'u2', roleId: 'r1');
      await repo.assignRoleToUser(userId: 'u2', roleId: 'r2');

      await repo.revokeAllRolesForUser('u2');

      final assignments = await repo.getAssignmentsForUser('u2');
      expect(assignments, isEmpty);
    });
  });

  group('department scopes', () {
    test('setUserDepartments persists and mirrors cache', () async {
      await repo.setUserDepartments(userId: 'u3', departmentIds: <String>{'d1', 'd2'});

      final depts = await repo.getDepartmentsForUser('u3');
      expect(depts, containsAll(<String>['d1', 'd2']));
    });
  });
}
