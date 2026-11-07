import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/user_role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

void main() {
  late DatabaseHelper dbHelper;
  late Database db;
  late StudentRepository studentRepo;
  late FacultyRepository facultyRepo;
  late UserRoleRepository userRoleRepo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);

    studentRepo = StudentRepository(dbHelper: dbHelper);
    facultyRepo = FacultyRepository(dbHelper: dbHelper);
    userRoleRepo = UserRoleRepository(dbHelper: dbHelper);

    PermissionService.instance.reset();
  });

  tearDown(() async {
    PermissionService.instance.reset();
    await db.close();
  });

  group('StudentRepository permission enforcement', () {
    test('insert throws PermissionDeniedException if user lacks student.create', () async {
      final studentRole = Role(
        id: 'r_student',
        name: 'Student',
        code: 'student',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([studentRole]);
      PermissionService.instance.grantPermissionToRole(studentRole.id, PermissionCodes.studentView);
      PermissionService.instance.assignRoleToUser('u_unauthorized', studentRole.id);
      PermissionService.instance.currentUserId = 'u_unauthorized';

      expect(
        () => studentRepo.insert(
          name: 'Jane Doe',
          rollNumber: 'JD101',
          classId: 'c1',
          departmentId: 'dept_cs',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.permissionCode,
          'permissionCode',
          equals(PermissionCodes.studentCreate),
        )),
      );
    });

    test('insert succeeds when user has student.create permission', () async {
      final teacherRole = Role(
        id: 'r_teacher',
        name: 'Teacher',
        code: 'teacher',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([teacherRole]);
      PermissionService.instance.grantPermissionToRole(teacherRole.id, PermissionCodes.studentCreate);
      PermissionService.instance.assignRoleToUser('u_teacher', teacherRole.id);
      PermissionService.instance.currentUserId = 'u_teacher';

      final created = await studentRepo.insert(
        name: 'Jane Doe',
        rollNumber: 'JD101',
        classId: 'c1',
      );

      expect(created.name, equals('Jane Doe'));
      expect(created.rollNumber, equals('JD101'));
    });

    test('HOD cannot insert student for a department outside assigned department', () async {
      final hodRole = Role(
        id: 'r_hod',
        name: 'HOD',
        code: 'hod',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([hodRole]);
      PermissionService.instance.grantPermissionToRole(hodRole.id, PermissionCodes.studentCreate);
      PermissionService.instance.assignRoleToUser('u_hod', hodRole.id);
      PermissionService.instance.setUserDepartments('u_hod', {'dept_math'});
      PermissionService.instance.currentUserId = 'u_hod';

      // Insert for dept_physics should fail for Math HOD
      expect(
        () => studentRepo.insert(
          name: 'Physics Student',
          rollNumber: 'PS001',
          classId: 'c1',
          departmentId: 'dept_physics',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Insert for dept_math should succeed
      final created = await studentRepo.insert(
        name: 'Math Student',
        rollNumber: 'MS001',
        classId: 'c1',
        departmentId: 'dept_math',
      );
      expect(created.name, equals('Math Student'));
    });
  });

  group('FacultyRepository permission enforcement', () {
    test('insert throws PermissionDeniedException if user lacks teacher.create', () async {
      PermissionService.instance.currentUserId = 'u_guest';

      expect(
        () => facultyRepo.insert(
          name: 'Prof. Smith',
          subject: 'Computer Science',
          employeeCode: 'EMP001',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.permissionCode,
          'permissionCode',
          equals(PermissionCodes.teacherCreate),
        )),
      );
    });

    test('Principal bypasses department restrictions and has all permissions', () async {
      final principalRole = Role(
        id: 'r_principal',
        name: 'Principal',
        code: 'principal',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([principalRole]);
      PermissionService.instance.assignRoleToUser('u_principal', principalRole.id);
      PermissionService.instance.currentUserId = 'u_principal';

      final teacher = await facultyRepo.insert(
        name: 'Prof. Principal Hire',
        subject: 'Administration',
        employeeCode: 'EMP777',
      );
      expect(teacher.name, equals('Prof. Principal Hire'));
    });
  });

  group('UserRoleRepository permission enforcement', () {
    test('assignRoleToUser throws PermissionDeniedException without user.manage_roles', () async {
      PermissionService.instance.currentUserId = 'u_teacher';

      expect(
        () => userRoleRepo.assignRoleToUser(
          userId: 'u_target',
          roleId: 'r_some',
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.permissionCode,
          'permissionCode',
          equals(PermissionCodes.userManageRoles),
        )),
      );
    });

    test('assignRoleToUser succeeds when user is Admin or has user.manage_roles', () async {
      final adminRole = Role(
        id: 'r_admin',
        name: 'Admin',
        code: 'admin',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([adminRole]);
      PermissionService.instance.assignRoleToUser('u_admin', adminRole.id);
      PermissionService.instance.currentUserId = 'u_admin';

      await userRoleRepo.assignRoleToUser(
        userId: 'u_target',
        roleId: 'r_some',
      );

      final assignments = await userRoleRepo.getAssignmentsForUser('u_target');
      expect(assignments.any((a) => a.roleId == 'r_some'), isTrue);
    });
  });
}
