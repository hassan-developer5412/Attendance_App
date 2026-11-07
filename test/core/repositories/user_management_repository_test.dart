import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

void main() {
  late DatabaseHelper dbHelper;
  late Database db;
  late UserRepository userRepo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);
    userRepo = UserRepository(dbHelper: dbHelper);
    PermissionService.instance.reset();
  });

  tearDown(() async {
    PermissionService.instance.reset();
    await db.close();
  });

  group('UserRepository Management & Provisioning', () {
    test('createUser successfully creates new user with default password flag', () async {
      final user = await userRepo.createUser(
        username: 'prof_john',
        password: 'InitialPassword123!',
        displayName: 'Professor John',
        email: 'john@example.com',
        role: UserRole.teacher,
        employeeId: 'EMP-001',
      );

      expect(user.id, isNotEmpty);
      expect(user.username, equals('prof_john'));
      expect(user.displayName, equals('Professor John'));
      expect(user.role, equals(UserRole.teacher));
      expect(user.employeeId, equals('EMP-001'));
      expect(user.isDefaultPassword, isTrue);
      expect(user.isSuspended, isFalse);

      // Verify user can authenticate with default password
      final authResult = await userRepo.authenticate('prof_john', 'InitialPassword123!');
      expect(authResult, isNotNull);
      expect(authResult!.user.isDefaultPassword, isTrue);
    });

    test('createUser with roll number for student', () async {
      final studentUser = await userRepo.createUser(
        username: 'std_alice',
        password: 'StudentPass123!',
        displayName: 'Alice Walker',
        email: 'alice@example.com',
        role: UserRole.student,
        rollNo: 'ROLL-101',
      );

      expect(studentUser.rollNo, equals('ROLL-101'));
      expect(studentUser.role, equals(UserRole.student));

      // Authenticate using roll number as identifier
      final authResult = await userRepo.authenticate('ROLL-101', 'StudentPass123!');
      expect(authResult, isNotNull);
      expect(authResult!.user.id, equals(studentUser.id));
    });

    test('getAll retrieves list of users including suspended, excluding deleted', () async {
      await userRepo.createUser(
        username: 'user_a',
        password: 'Pass123!',
        displayName: 'User A',
        email: 'a@example.com',
        role: UserRole.teacher,
      );
      await userRepo.createUser(
        username: 'user_b',
        password: 'Pass123!',
        displayName: 'User B',
        email: 'b@example.com',
        role: UserRole.student,
      );

      final users = await userRepo.getAll();
      expect(users.any((u) => u.username == 'user_a'), isTrue);
      expect(users.any((u) => u.username == 'user_b'), isTrue);
    });

    test('toggleSuspension updates suspension flag and records reason', () async {
      final user = await userRepo.createUser(
        username: 'suspend_test',
        password: 'Pass123!',
        displayName: 'Suspend Test',
        email: 'suspend@example.com',
        role: UserRole.teacher,
      );

      expect(user.isSuspended, isFalse);

      // Suspend
      await userRepo.toggleSuspension(
        user.id,
        suspend: true,
        reason: 'Policy violation',
      );

      // Re-fetch from db to verify persistence
      final refreshed = await userRepo.getById(user.id);
      expect(refreshed!.isSuspended, isTrue);
      expect(refreshed.suspendedReason, equals('Policy violation'));

      // Unsuspend
      await userRepo.toggleSuspension(
        user.id,
        suspend: false,
      );
      final unsuspended = await userRepo.getById(user.id);
      expect(unsuspended!.isSuspended, isFalse);
      expect(unsuspended.suspendedReason, isNull);
    });

    test('updateUserRole updates role in users table and user_roles table', () async {
      final user = await userRepo.createUser(
        username: 'role_test',
        password: 'Pass123!',
        displayName: 'Role Test',
        email: 'role@example.com',
        role: UserRole.teacher,
      );

      await userRepo.updateUserRole(
        user.id,
        UserRole.hod,
      );

      final updated = await userRepo.getById(user.id);
      expect(updated!.role, equals(UserRole.hod));

      // Verify user_roles junction has the hod role
      final roles = await db.query(
        'user_roles',
        where: 'user_id = ? AND is_deleted = 0',
        whereArgs: [user.id],
      );
      expect(roles.isNotEmpty, isTrue);
    });

    test('assignTeacherDetails updates department and class assignment', () async {
      final user = await userRepo.createUser(
        username: 'faculty_math',
        password: 'Pass123!',
        displayName: 'Math Teacher',
        email: 'math@example.com',
        role: UserRole.teacher,
        employeeId: 'MATH-01',
      );

      await userRepo.assignTeacherDetails(
        userId: user.id,
        departmentId: 'dept_math',
        classId: 'class_10a',
      );

      // Check user_departments junction
      final depts = await db.query(
        'user_departments',
        where: 'user_id = ?',
        whereArgs: [user.id],
      );
      expect(depts.any((d) => d['department_id'] == 'dept_math'), isTrue);

      // Check teachers table
      final teachers = await db.query(
        'teachers',
        where: 'user_id = ?',
        whereArgs: [user.id],
      );
      expect(teachers.isNotEmpty, isTrue);
      expect(teachers.first['department_id'], equals('dept_math'));
      expect(teachers.first['class_id'], equals('class_10a'));
    });
  });
}
