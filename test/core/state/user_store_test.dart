import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/user_store.dart';

void main() {
  late DatabaseHelper dbHelper;
  late Database db;
  late UserRepository userRepo;
  late UserStore userStore;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);
    userRepo = UserRepository(dbHelper: dbHelper);
    userStore = UserStore(userRepository: userRepo);
    PermissionService.instance.reset();
  });

  tearDown(() async {
    PermissionService.instance.reset();
    await db.close();
  });

  group('UserStore state operations', () {
    test('loadUsers fetches users and manages loading flags', () async {
      expect(userStore.isLoading, isFalse);
      expect(userStore.users, isEmpty);

      // Insert a user first to verify loading
      await userRepo.createUser(
        username: 'seed_user',
        displayName: 'Seed User',
        password: 'Pass123!',
        role: UserRole.admin,
      );

      await userStore.loadUsers();

      expect(userStore.isLoading, isFalse);
      expect(userStore.users.isNotEmpty, isTrue);
      expect(userStore.users.any((u) => u.username == 'seed_user'), isTrue);
    });

    test('createUser successfully adds user and updates list in state', () async {
      await userStore.loadUsers();
      final initialCount = userStore.users.length;

      final created = await userStore.createUser(
        username: 'prof_new',
        displayName: 'Professor New',
        password: 'Pass12345!',
        role: UserRole.teacher,
        employeeId: 'EMP-99',
      );

      expect(created, isNotNull);
      expect(created!.username, equals('prof_new'));
      expect(userStore.users.length, equals(initialCount + 1));
      expect(userStore.users.any((u) => u.username == 'prof_new'), isTrue);
    });

    test('updateUserRole updates user in database and state', () async {
      final created = await userStore.createUser(
        username: 'teacher_to_hod',
        displayName: 'Teacher To HOD',
        password: 'Pass12345!',
        role: UserRole.teacher,
      );

      await userStore.updateUserRole(
        created!.id,
        UserRole.hod,
      );

      final updated = userStore.users.firstWhere((u) => u.id == created.id);
      expect(updated.role, equals(UserRole.hod));
    });

    test('toggleSuspension updates user suspension state', () async {
      final created = await userStore.createUser(
        username: 'to_suspend',
        displayName: 'To Suspend',
        password: 'Pass12345!',
        role: UserRole.student,
      );

      expect(created!.isSuspended, isFalse);

      await userStore.toggleSuspension(
        created.id,
        suspend: true,
        reason: 'Misconduct',
      );

      final suspended = userStore.users.firstWhere((u) => u.id == created.id);
      expect(suspended.isSuspended, isTrue);
      expect(suspended.suspendedReason, equals('Misconduct'));
    });

    test('assignTeacher links department and class', () async {
      final teacher = await userStore.createUser(
        username: 'assigned_teacher',
        displayName: 'Assigned Teacher',
        password: 'Pass12345!',
        role: UserRole.teacher,
        employeeId: 'EMP-ASSIGN',
      );

      await userStore.assignTeacher(
        userId: teacher!.id,
        departmentId: 'dept_physics',
        classId: 'class_phys_1',
      );

      final depts = await db.query(
        'user_departments',
        where: 'user_id = ?',
        whereArgs: [teacher.id],
      );
      expect(depts.any((d) => d['department_id'] == 'dept_physics'), isTrue);
    });
  });
}
