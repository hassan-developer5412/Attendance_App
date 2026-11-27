import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';
import 'package:attendance_app/core/models/attendance_session.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/attendance_session_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/lab_inventory_repository.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/repositories/user_role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Comprehensive RBAC repository guard tests.
///
/// Verifies:
/// 1. Unauthenticated and suspended users fail closed (throw
///    [PermissionDeniedException]) on write methods across all guarded
///    repositories.
/// 2. Department-scoped roles (e.g. HOD assigned to Dept A) can write to
///    Dept A but throw [PermissionDeniedException] when writing to Dept B.
/// 3. Institute-wide roles (Admin / Principal) succeed across departments.
/// 4. [LeaveRepository] allows students/teachers to submit their own leave
///    requests, requires `leave.approve` to approve/reject, and blocks
///    self-approval.
void main() {
  late DatabaseHelper dbHelper;
  late Database db;

  late StudentRepository studentRepo;
  late FacultyRepository facultyRepo;
  late ClassRepository classRepo;
  late SubjectRepository subjectRepo;
  late TimetableRepository timetableRepo;
  late LabInventoryRepository labInventoryRepo;
  late RoleRepository roleRepo;
  late UserRoleRepository userRoleRepo;
  late AttendanceSessionRepository sessionRepo;
  late AttendanceRepository attendanceRepo;
  late LeaveRepository leaveRepo;

  const deptA = 'dept_a';
  const deptB = 'dept_b';

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    await SchemaMigrationV9.execute(db);
    dbHelper = DatabaseHelper.forTesting(db);

    studentRepo = StudentRepository(dbHelper: dbHelper);
    facultyRepo = FacultyRepository(dbHelper: dbHelper);
    classRepo = ClassRepository(dbHelper: dbHelper);
    subjectRepo = SubjectRepository(dbHelper: dbHelper);
    timetableRepo = TimetableRepository(dbHelper: dbHelper);
    labInventoryRepo = LabInventoryRepository(dbHelper: dbHelper);
    roleRepo = RoleRepository(dbHelper: dbHelper);
    userRoleRepo = UserRoleRepository(dbHelper: dbHelper);
    sessionRepo = AttendanceSessionRepository(dbHelper: dbHelper);
    attendanceRepo = AttendanceRepository(dbHelper: dbHelper);
    leaveRepo = LeaveRepository(dbHelper: dbHelper);

    PermissionService.instance.reset();
  });

  tearDown(() async {
    PermissionService.instance.reset();
    await db.close();
  });

  void signInAsAdmin({String userId = 'u_admin', bool suspended = false}) {
    final adminRole = Role(
      id: 'r_admin',
      name: 'Administrator',
      code: 'admin',
      isInstituteWide: true,
    );
    PermissionService.instance.loadRoles([adminRole]);
    PermissionService.instance.assignRoleToUser(userId, adminRole.id);
    PermissionService.instance.currentUserId = userId;
    if (suspended) {
      PermissionService.instance.setUserSuspended(userId, true);
    }
  }

  void signInAsPrincipal({String userId = 'u_principal'}) {
    final principalRole = Role(
      id: 'r_principal',
      name: 'Principal',
      code: 'principal',
      isInstituteWide: true,
    );
    PermissionService.instance.loadRoles([principalRole]);
    PermissionService.instance.assignRoleToUser(userId, principalRole.id);
    PermissionService.instance.currentUserId = userId;
  }

  void signInAsHod({
    String userId = 'u_hod',
    Set<String> departments = const {deptA},
    Iterable<String> permissions = const [
      PermissionCodes.studentCreate,
      PermissionCodes.studentEdit,
      PermissionCodes.studentDelete,
      PermissionCodes.teacherCreate,
      PermissionCodes.teacherEdit,
      PermissionCodes.teacherDelete,
      PermissionCodes.classManage,
      PermissionCodes.labManage,
      PermissionCodes.leaveView,
      PermissionCodes.leaveApprove,
    ],
  }) {
    final hodRole = Role(
      id: 'r_hod',
      name: 'Head of Department',
      code: 'hod',
      isInstituteWide: false,
    );
    PermissionService.instance.loadRoles([hodRole]);
    for (final code in permissions) {
      PermissionService.instance.grantPermissionToRole(hodRole.id, code);
    }
    PermissionService.instance.assignRoleToUser(userId, hodRole.id);
    PermissionService.instance.setUserDepartments(userId, departments);
    PermissionService.instance.currentUserId = userId;
  }

  TimetableSlot buildSlot({String id = 'slot_1'}) => TimetableSlot(
        id: id,
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 'sub1',
        teacherId: 't1',
        roomName: 'Room 101',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:45',
      );

  LabInventory buildLabItem({
    String id = 'lab_1',
    String departmentId = deptA,
  }) =>
      LabInventory(
        id: id,
        itemName: 'Oscilloscope',
        departmentId: departmentId,
        category: InventoryCategory.hardwareEquipment,
        currentStock: 5,
        unit: 'pcs',
        reorderLevel: 2,
      );

  AttendanceSession buildSession({
    String id = 'sess_1',
    String departmentId = deptA,
  }) =>
      AttendanceSession(
        id: id,
        subjectCode: 'CS101',
        departmentId: departmentId,
        facultyId: 't1',
        sessionDate: '2026-11-26',
      );

  group('Fail-closed for unauthenticated and suspended users', () {
    Future<void> verifyAllRepositoriesDenyWrites() async {
      // StudentRepository
      await expectLater(
        studentRepo.insert(
          name: 'S1',
          rollNumber: 'R1',
          classId: 'c1',
          departmentId: deptA,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        studentRepo.update(Student(
          id: 's_1',
          name: 'S1',
          rollNumber: 'R1',
          classId: 'c1',
          departmentId: deptA,
        )),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        studentRepo.softDelete('s_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // FacultyRepository
      await expectLater(
        facultyRepo.insert(
          name: 'F1',
          subject: 'CS',
          departmentId: deptA,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        facultyRepo.update(Teacher(
          id: 'f_1',
          name: 'F1',
          subject: 'CS',
          departmentId: deptA,
        )),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        facultyRepo.softDelete('f_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // ClassRepository
      await expectLater(
        classRepo.insert(name: 'Class A', departmentId: deptA),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        classRepo.update(SchoolClass(
          id: 'c_1',
          name: 'Class A',
          section: 'A',
          room: '101',
          departmentId: deptA,
        )),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        classRepo.softDelete('c_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // SubjectRepository
      await expectLater(
        subjectRepo.insert(
          name: 'Algorithms',
          code: 'CS201',
          teacherName: 'Prof. X',
          classId: 'c1',
          departmentId: deptA,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        subjectRepo.update(Subject(
          id: 'sub_1',
          name: 'Algorithms',
          code: 'CS201',
          teacherName: 'Prof. X',
          classId: 'c1',
          departmentId: deptA,
        )),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        subjectRepo.softDelete('sub_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // TimetableRepository
      await expectLater(
        timetableRepo.insert(buildSlot()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        timetableRepo.update(buildSlot()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        timetableRepo.softDelete('slot_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // LabInventoryRepository
      await expectLater(
        labInventoryRepo.insert(buildLabItem()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        labInventoryRepo.update(buildLabItem()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        labInventoryRepo.softDelete('lab_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // RoleRepository
      await expectLater(
        roleRepo.insert(name: 'Custom', code: 'custom_role'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        roleRepo.update(Role(id: 'r_1', name: 'Custom', code: 'custom_role')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        roleRepo.softDelete('r_1'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        roleRepo.grantPermission('r_1', PermissionCodes.studentView),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        roleRepo.revokePermission('r_1', PermissionCodes.studentView),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        roleRepo.replaceRolePermissions('r_1', [PermissionCodes.studentView]),
        throwsA(isA<PermissionDeniedException>()),
      );

      // UserRoleRepository
      await expectLater(
        userRoleRepo.assignRoleToUser(userId: 'u_target', roleId: 'r_1'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        userRoleRepo.revokeRoleFromUser('u_target', 'r_1'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        userRoleRepo.revokeAllRolesForUser('u_target'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        userRoleRepo.setUserDepartments(
          userId: 'u_target',
          departmentIds: [deptA],
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // AttendanceSessionRepository
      await expectLater(
        sessionRepo.insert(buildSession()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        sessionRepo.update(buildSession()),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        sessionRepo.softDelete('sess_1'),
        throwsA(isA<PermissionDeniedException>()),
      );

      // AttendanceRepository
      await expectLater(
        attendanceRepo.ensureSession(
          departmentId: deptA,
          academicSessionId: 'acad_1',
          classId: 'c1',
          year: '1st Year',
          subjectId: 'sub1',
          date: DateTime.utc(2026, 11, 26),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: 'sess_1',
          studentId: 's_1',
          status: AttendanceStatus.present,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: 's_1',
          date: DateTime.utc(2026, 11, 26),
          status: AttendanceStatus.present,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    }

    test('unauthenticated user (currentUserId == null) fails closed on all guarded repositories', () async {
      expect(PermissionService.instance.currentUserId, isNull);
      await verifyAllRepositoriesDenyWrites();
    });

    test('suspended user fails closed on all guarded repositories even with Admin role', () async {
      signInAsAdmin(userId: 'u_suspended_admin', suspended: true);
      expect(PermissionService.instance.isUserSuspended(), isTrue);
      await verifyAllRepositoriesDenyWrites();
    });
  });

  group('Department-scoped role (HOD assigned to Dept A)', () {
    test('allows writes to Dept A and throws PermissionDeniedException for Dept B', () async {
      // Seed one Dept B record per repository as admin before switching to HOD
      // so we can also verify update/softDelete fail on Dept B.
      signInAsAdmin();
      final deptBStudent = await studentRepo.insert(
        name: 'Dept B Student',
        rollNumber: 'B001',
        classId: 'c_b',
        departmentId: deptB,
      );
      final deptBTeacher = await facultyRepo.insert(
        name: 'Dept B Teacher',
        subject: 'Physics',
        departmentId: deptB,
      );
      final deptBClass = await classRepo.insert(
        name: 'Physics 101',
        departmentId: deptB,
      );
      final deptBSubject = await subjectRepo.insert(
        name: 'Mechanics',
        code: 'PHY101',
        teacherName: 'Dept B Teacher',
        classId: deptBClass.id,
        departmentId: deptB,
      );
      final deptBLab = await labInventoryRepo.insert(
        buildLabItem(id: 'lab_b', departmentId: deptB),
      );

      // Now sign in as HOD scoped strictly to Dept A.
      PermissionService.instance.reset();
      signInAsHod(departments: const {deptA});

      // --- StudentRepository ---
      final deptAStudent = await studentRepo.insert(
        name: 'Dept A Student',
        rollNumber: 'A001',
        classId: 'c_a',
        departmentId: deptA,
      );
      expect(deptAStudent.departmentId, equals(deptA));
      await studentRepo.update(deptAStudent.copyWith(name: 'Dept A Student Updated'));
      await studentRepo.softDelete(deptAStudent.id);

      await expectLater(
        studentRepo.insert(
          name: 'Blocked Student',
          rollNumber: 'B002',
          classId: 'c_b',
          departmentId: deptB,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        studentRepo.update(deptBStudent.copyWith(name: 'Tamper')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        studentRepo.softDelete(deptBStudent.id),
        throwsA(isA<PermissionDeniedException>()),
      );

      // --- FacultyRepository ---
      final deptATeacher = await facultyRepo.insert(
        name: 'Dept A Teacher',
        subject: 'CS',
        departmentId: deptA,
      );
      expect(deptATeacher.departmentId, equals(deptA));
      await facultyRepo.update(deptATeacher.copyWith(subject: 'AI'));
      await facultyRepo.softDelete(deptATeacher.id);

      await expectLater(
        facultyRepo.insert(
          name: 'Blocked Teacher',
          subject: 'Physics',
          departmentId: deptB,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        facultyRepo.update(deptBTeacher.copyWith(name: 'Tamper')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        facultyRepo.softDelete(deptBTeacher.id),
        throwsA(isA<PermissionDeniedException>()),
      );

      // --- ClassRepository ---
      final deptAClass = await classRepo.insert(
        name: 'CS 101',
        departmentId: deptA,
      );
      expect(deptAClass.departmentId, equals(deptA));
      await classRepo.update(deptAClass.copyWith(room: 'Room 12'));
      await classRepo.softDelete(deptAClass.id);

      await expectLater(
        classRepo.insert(name: 'Blocked Class', departmentId: deptB),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        classRepo.update(deptBClass.copyWith(room: 'Tamper')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        classRepo.softDelete(deptBClass.id),
        throwsA(isA<PermissionDeniedException>()),
      );

      // --- SubjectRepository ---
      final deptASubject = await subjectRepo.insert(
        name: 'Data Structures',
        code: 'CS102',
        teacherName: 'Dept A Teacher',
        classId: deptAClass.id,
        departmentId: deptA,
      );
      expect(deptASubject.departmentId, equals(deptA));
      await subjectRepo.update(deptASubject.copyWith(name: 'DS & Algo'));
      await subjectRepo.softDelete(deptASubject.id);

      await expectLater(
        subjectRepo.insert(
          name: 'Blocked Subject',
          code: 'PHY102',
          teacherName: 'Dept B Teacher',
          classId: deptBClass.id,
          departmentId: deptB,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        subjectRepo.update(deptBSubject.copyWith(name: 'Tamper')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        subjectRepo.softDelete(deptBSubject.id),
        throwsA(isA<PermissionDeniedException>()),
      );

      // --- LabInventoryRepository ---
      final deptALab = await labInventoryRepo.insert(
        buildLabItem(id: 'lab_a', departmentId: deptA),
      );
      expect(deptALab.departmentId, equals(deptA));
      await labInventoryRepo.update(deptALab.copyWith(currentStock: 8));
      await labInventoryRepo.softDelete(deptALab.id);

      await expectLater(
        labInventoryRepo.insert(
          buildLabItem(id: 'lab_b2', departmentId: deptB),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        labInventoryRepo.update(deptBLab.copyWith(currentStock: 99)),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        labInventoryRepo.softDelete(deptBLab.id),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('Institute-wide role (Admin / Principal) across departments', () {
    test('Admin succeeds across Dept A and Dept B and manages roles/sessions/timetables', () async {
      signInAsAdmin();

      // Cross-department writes
      final sA = await studentRepo.insert(
        name: 'Student A',
        rollNumber: 'SA1',
        classId: 'c_a',
        departmentId: deptA,
      );
      final sB = await studentRepo.insert(
        name: 'Student B',
        rollNumber: 'SB1',
        classId: 'c_b',
        departmentId: deptB,
      );
      expect(sA.departmentId, equals(deptA));
      expect(sB.departmentId, equals(deptB));

      await facultyRepo.insert(
        name: 'Teacher A',
        subject: 'Math',
        departmentId: deptA,
      );
      await facultyRepo.insert(
        name: 'Teacher B',
        subject: 'Physics',
        departmentId: deptB,
      );

      await classRepo.insert(name: 'Class A', departmentId: deptA);
      await classRepo.insert(name: 'Class B', departmentId: deptB);

      await subjectRepo.insert(
        name: 'Sub A',
        code: 'A101',
        teacherName: 'Teacher A',
        classId: 'c_a',
        departmentId: deptA,
      );
      await subjectRepo.insert(
        name: 'Sub B',
        code: 'B101',
        teacherName: 'Teacher B',
        classId: 'c_b',
        departmentId: deptB,
      );

      await labInventoryRepo.insert(
        buildLabItem(id: 'admin_lab_a', departmentId: deptA),
      );
      await labInventoryRepo.insert(
        buildLabItem(id: 'admin_lab_b', departmentId: deptB),
      );

      // Institute-wide modules: Timetable, AttendanceSession, Role, UserRole
      final slot = await timetableRepo.insert(buildSlot(id: 'admin_slot'));
      expect(slot.id, equals('admin_slot'));

      final sess = await sessionRepo.insert(buildSession(id: 'admin_sess'));
      expect(sess.id, equals('admin_sess'));

      final roleId = await roleRepo.insert(
        name: 'Coordinator',
        code: 'coordinator',
      );
      await roleRepo.grantPermission(roleId, PermissionCodes.studentView);
      await userRoleRepo.assignRoleToUser(
        userId: 'u_coord',
        roleId: roleId,
      );
      final assigned = await userRoleRepo.getAssignmentsForUser('u_coord');
      expect(assigned.any((a) => a.roleId == roleId), isTrue);
    });

    test('Principal succeeds across Dept A and Dept B', () async {
      signInAsPrincipal();

      final sA = await studentRepo.insert(
        name: 'Principal Student A',
        rollNumber: 'PSA1',
        classId: 'c_a',
        departmentId: deptA,
      );
      final sB = await studentRepo.insert(
        name: 'Principal Student B',
        rollNumber: 'PSB1',
        classId: 'c_b',
        departmentId: deptB,
      );
      expect(sA.departmentId, equals(deptA));
      expect(sB.departmentId, equals(deptB));

      final labA = await labInventoryRepo.insert(
        buildLabItem(id: 'p_lab_a', departmentId: deptA),
      );
      final labB = await labInventoryRepo.insert(
        buildLabItem(id: 'p_lab_b', departmentId: deptB),
      );
      expect(labA.departmentId, equals(deptA));
      expect(labB.departmentId, equals(deptB));
    });
  });

  group('LeaveRepository ownership, approval permission, and self-approval blocking', () {
    LeaveRequest buildLeave({
      String id = 'leave_1',
      required String requesterName,
      String? studentId,
    }) =>
        LeaveRequest(
          id: id,
          requesterName: requesterName,
          leaveType: 'Medical',
          startDate: DateTime.utc(2026, 11, 27),
          endDate: DateTime.utc(2026, 11, 28),
          reason: 'Fever',
          studentId: studentId,
        );

    test('unauthenticated and suspended users fail closed on LeaveRepository', () async {
      // Unauthenticated
      await expectLater(
        leaveRepo.insert(buildLeave(requesterName: 'Anon', studentId: 'u1')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        leaveRepo.updateStatus('leave_1', LeaveStatus.approved),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Suspended
      signInAsAdmin(userId: 'u_susp', suspended: true);
      await expectLater(
        leaveRepo.insert(
          buildLeave(requesterName: 'Susp', studentId: 'u_susp'),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        leaveRepo.updateStatus('leave_1', LeaveStatus.approved),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('student and teacher can submit their own leave request without leave.approve', () async {
      final studentRole = Role(
        id: 'r_student',
        name: 'Student',
        code: 'student',
        isInstituteWide: false,
      );
      final teacherRole = Role(
        id: 'r_teacher',
        name: 'Teacher',
        code: 'teacher',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([studentRole, teacherRole]);
      PermissionService.instance.assignRoleToUser('u_student', studentRole.id);
      PermissionService.instance.assignRoleToUser('u_teacher', teacherRole.id);

      // Student submits own request
      PermissionService.instance.currentUserId = 'u_student';
      final studentLeave = await leaveRepo.insert(
        buildLeave(
          id: 'leave_student',
          requesterName: 'Alice Student',
          studentId: 'u_student',
        ),
      );
      expect(studentLeave.status, equals(LeaveStatus.pending));

      // Student cannot submit on behalf of someone else
      await expectLater(
        leaveRepo.insert(
          buildLeave(
            id: 'leave_other',
            requesterName: 'Bob Student',
            studentId: 'u_other',
          ),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Teacher submits own request
      PermissionService.instance.currentUserId = 'u_teacher';
      final teacherLeave = await leaveRepo.insert(
        buildLeave(
          id: 'leave_teacher',
          requesterName: 'Prof. Teacher',
          studentId: 'u_teacher',
        ),
      );
      expect(teacherLeave.status, equals(LeaveStatus.pending));
    });

    test('approving or rejecting leave requires leave.approve and blocks self-approval', () async {
      final studentRole = Role(
        id: 'r_student',
        name: 'Student',
        code: 'student',
        isInstituteWide: false,
      );
      final teacherRole = Role(
        id: 'r_teacher',
        name: 'Teacher',
        code: 'teacher',
        isInstituteWide: false,
      );
      final hodRole = Role(
        id: 'r_hod',
        name: 'HOD',
        code: 'hod',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([studentRole, teacherRole, hodRole]);
      PermissionService.instance.grantPermissionToRole(
        teacherRole.id,
        PermissionCodes.leaveView,
      );
      PermissionService.instance.grantPermissionToRole(
        hodRole.id,
        PermissionCodes.leaveView,
      );
      PermissionService.instance.grantPermissionToRole(
        hodRole.id,
        PermissionCodes.leaveApprove,
      );

      PermissionService.instance.assignRoleToUser('u_student', studentRole.id);
      PermissionService.instance.assignRoleToUser('u_teacher', teacherRole.id);
      PermissionService.instance.assignRoleToUser('u_hod', hodRole.id);
      PermissionService.instance.setUserDepartments('u_hod', {deptA});

      // Student submits own request
      PermissionService.instance.currentUserId = 'u_student';
      await leaveRepo.insert(
        buildLeave(
          id: 'leave_s1',
          requesterName: 'Alice Student',
          studentId: 'u_student',
        ),
      );

      // Teacher with only leave.view (no leave.approve) cannot approve or reject
      PermissionService.instance.currentUserId = 'u_teacher';
      await expectLater(
        leaveRepo.updateStatus('leave_s1', LeaveStatus.approved),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.permissionCode,
          'permissionCode',
          equals(PermissionCodes.leaveApprove),
        )),
      );
      await expectLater(
        leaveRepo.updateStatus('leave_s1', LeaveStatus.rejected),
        throwsA(isA<PermissionDeniedException>()),
      );

      // HOD assigned to Dept A cannot approve for Dept B
      PermissionService.instance.currentUserId = 'u_hod';
      await expectLater(
        leaveRepo.updateStatus(
          'leave_s1',
          LeaveStatus.approved,
          departmentId: deptB,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // HOD assigned to Dept A can approve student's request in Dept A
      await leaveRepo.updateStatus(
        'leave_s1',
        LeaveStatus.approved,
        remarks: 'Approved by HOD',
        departmentId: deptA,
      );
      final approved = await leaveRepo.getById('leave_s1', departmentId: deptA);
      expect(approved?.status, equals(LeaveStatus.approved));
      expect(approved?.remarks, equals('Approved by HOD'));

      // HOD submits their own leave request and tries to self-approve -> blocked!
      await leaveRepo.insert(
        buildLeave(
          id: 'leave_hod_own',
          requesterName: 'Dr. HOD',
          studentId: 'u_hod',
        ),
      );
      await expectLater(
        leaveRepo.updateStatus(
          'leave_hod_own',
          LeaveStatus.approved,
          departmentId: deptA,
        ),
        throwsA(isA<PermissionDeniedException>().having(
          (e) => e.permissionCode,
          'permissionCode',
          equals(PermissionCodes.leaveApprove),
        )),
      );
      await expectLater(
        leaveRepo.updateStatus(
          'leave_hod_own',
          LeaveStatus.rejected,
          departmentId: deptA,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Even an institute-wide Admin cannot self-approve their own leave request
      PermissionService.instance.reset();
      signInAsAdmin(userId: 'u_admin');
      await leaveRepo.insert(
        buildLeave(
          id: 'leave_admin_own',
          requesterName: 'Admin User',
          studentId: 'u_admin',
        ),
      );
      await expectLater(
        leaveRepo.updateStatus('leave_admin_own', LeaveStatus.approved),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('AttendanceRepository RBAC and department scoping', () {
    Future<({String classAId, String classBId, String studentAId, String studentBId, String sessionBId})>
        seedTwoDepartmentsAsAdmin() async {
      signInAsAdmin();
      final classA = await classRepo.insert(
        name: 'CIT-1st Year',
        departmentId: deptA,
      );
      final classB = await classRepo.insert(
        name: 'LT-1st Year',
        departmentId: deptB,
      );
      final studentA = await studentRepo.insert(
        name: 'Student Dept A',
        rollNumber: 'A-101',
        classId: classA.id,
        departmentId: deptA,
      );
      final studentB = await studentRepo.insert(
        name: 'Student Dept B',
        rollNumber: 'B-101',
        classId: classB.id,
        departmentId: deptB,
      );
      final sessionBId = await attendanceRepo.ensureSession(
        departmentId: deptB,
        academicSessionId: 'acad_2026',
        classId: classB.id,
        year: '1st Year',
        subjectId: 'sub_b',
        date: DateTime.utc(2026, 11, 26),
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: sessionBId,
        studentId: studentB.id,
        status: AttendanceStatus.present,
      );
      await attendanceRepo.upsertAttendance(
        studentId: studentB.id,
        date: DateTime.utc(2026, 11, 25),
        status: AttendanceStatus.present,
      );
      PermissionService.instance.reset();
      return (
        classAId: classA.id,
        classBId: classB.id,
        studentAId: studentA.id,
        studentBId: studentB.id,
        sessionBId: sessionBId,
      );
    }

    test('unauthenticated and suspended users fail closed on AttendanceRepository writes', () async {
      final seeded = await seedTwoDepartmentsAsAdmin();

      // Unauthenticated
      expect(PermissionService.instance.currentUserId, isNull);
      await expectLater(
        attendanceRepo.ensureSession(
          departmentId: deptA,
          academicSessionId: 'acad_2026',
          classId: seeded.classAId,
          year: '1st Year',
          subjectId: 'sub_a',
          date: DateTime.utc(2026, 11, 26),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: seeded.sessionBId,
          studentId: seeded.studentBId,
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: seeded.studentAId,
          date: DateTime.utc(2026, 11, 26),
          status: AttendanceStatus.present,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // Suspended Admin
      signInAsAdmin(userId: 'u_susp_att', suspended: true);
      await expectLater(
        attendanceRepo.ensureSession(
          departmentId: deptA,
          academicSessionId: 'acad_2026',
          classId: seeded.classAId,
          year: '1st Year',
          subjectId: 'sub_a',
          date: DateTime.utc(2026, 11, 26),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: seeded.sessionBId,
          studentId: seeded.studentBId,
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: seeded.studentAId,
          date: DateTime.utc(2026, 11, 26),
          status: AttendanceStatus.present,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('cross-department HOD can mark/edit Dept A but is blocked on Dept B', () async {
      final seeded = await seedTwoDepartmentsAsAdmin();

      signInAsHod(
        userId: 'u_hod_a',
        departments: const {deptA},
        permissions: const [
          PermissionCodes.attendanceView,
          PermissionCodes.attendanceMark,
          PermissionCodes.attendanceEdit,
        ],
      );

      // Dept A succeeds
      final sessionAId = await attendanceRepo.ensureSession(
        departmentId: deptA,
        academicSessionId: 'acad_2026',
        classId: seeded.classAId,
        year: '1st Year',
        subjectId: 'sub_a',
        date: DateTime.utc(2026, 11, 26),
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: sessionAId,
        studentId: seeded.studentAId,
        status: AttendanceStatus.present,
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: sessionAId,
        studentId: seeded.studentAId,
        status: AttendanceStatus.late,
      );
      await attendanceRepo.upsertAttendance(
        studentId: seeded.studentAId,
        date: DateTime.utc(2026, 11, 25),
        status: AttendanceStatus.present,
      );

      // Dept B throws PermissionDeniedException
      await expectLater(
        attendanceRepo.ensureSession(
          departmentId: deptB,
          academicSessionId: 'acad_2026',
          classId: seeded.classBId,
          year: '1st Year',
          subjectId: 'sub_b2',
          date: DateTime.utc(2026, 11, 27),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: seeded.sessionBId,
          studentId: seeded.studentBId,
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: seeded.studentBId,
          date: DateTime.utc(2026, 11, 25),
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('authorized teacher succeeds in assigned dept, fails in other dept or without mark permission', () async {
      final seeded = await seedTwoDepartmentsAsAdmin();

      final teacherRole = Role(
        id: 'r_teacher_att',
        name: 'Teacher',
        code: 'teacher',
        isInstituteWide: false,
      );
      final viewOnlyRole = Role(
        id: 'r_viewer_att',
        name: 'Viewer',
        code: 'student',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([teacherRole, viewOnlyRole]);
      PermissionService.instance.grantPermissionToRole(
        teacherRole.id,
        PermissionCodes.attendanceView,
      );
      PermissionService.instance.grantPermissionToRole(
        teacherRole.id,
        PermissionCodes.attendanceMark,
      );
      PermissionService.instance.grantPermissionToRole(
        viewOnlyRole.id,
        PermissionCodes.attendanceView,
      );

      // Teacher assigned to Dept A
      PermissionService.instance.assignRoleToUser('u_teacher_a', teacherRole.id);
      PermissionService.instance.setUserDepartments('u_teacher_a', {deptA});
      PermissionService.instance.currentUserId = 'u_teacher_a';

      final sessionAId = await attendanceRepo.ensureSession(
        departmentId: deptA,
        academicSessionId: 'acad_2026',
        classId: seeded.classAId,
        year: '1st Year',
        subjectId: 'sub_a',
        date: DateTime.utc(2026, 11, 26),
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: sessionAId,
        studentId: seeded.studentAId,
        status: AttendanceStatus.present,
      );
      await attendanceRepo.upsertAttendance(
        studentId: seeded.studentAId,
        date: DateTime.utc(2026, 11, 26),
        status: AttendanceStatus.late,
      );

      // Same teacher cannot mark/alter Dept B attendance
      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: seeded.sessionBId,
          studentId: seeded.studentBId,
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: seeded.studentBId,
          date: DateTime.utc(2026, 11, 26),
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      // User with only attendance.view cannot mark/edit even in Dept A
      PermissionService.instance.assignRoleToUser('u_view_only', viewOnlyRole.id);
      PermissionService.instance.setUserDepartments('u_view_only', {deptA});
      PermissionService.instance.currentUserId = 'u_view_only';

      await expectLater(
        attendanceRepo.upsertAttendanceForSession(
          sessionId: sessionAId,
          studentId: seeded.studentAId,
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendanceRepo.upsertAttendance(
          studentId: seeded.studentAId,
          date: DateTime.utc(2026, 11, 26),
          status: AttendanceStatus.absent,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('authorized Admin succeeds across Dept A and Dept B', () async {
      final seeded = await seedTwoDepartmentsAsAdmin();
      signInAsAdmin();

      final sessionAId = await attendanceRepo.ensureSession(
        departmentId: deptA,
        academicSessionId: 'acad_2026',
        classId: seeded.classAId,
        year: '1st Year',
        subjectId: 'sub_a',
        date: DateTime.utc(2026, 11, 26),
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: sessionAId,
        studentId: seeded.studentAId,
        status: AttendanceStatus.present,
      );
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: seeded.sessionBId,
        studentId: seeded.studentBId,
        status: AttendanceStatus.late,
      );
      await attendanceRepo.upsertAttendance(
        studentId: seeded.studentBId,
        date: DateTime.utc(2026, 11, 26),
        status: AttendanceStatus.present,
      );

      final deptBRecords = await attendanceRepo.getForSession(seeded.sessionBId);
      expect(deptBRecords.single.status, equals(AttendanceStatus.present));
    });
  });
}
