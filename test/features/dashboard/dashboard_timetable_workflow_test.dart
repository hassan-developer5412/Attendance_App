import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/academic_session_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/department_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/lab_inventory_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/core/state/user_store.dart';
import 'package:attendance_app/features/dashboard/presentation/dashboard_shell.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/attendance_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/dashboard_content.dart';

class _FakeAuthStore extends AuthStore {
  _FakeAuthStore({User? user}) : _testUser = user;
  final User? _testUser;

  @override
  User? get currentUser => _testUser;

  @override
  bool get isLoggedIn => _testUser != null;

  @override
  UserRole? get currentUserRole => _testUser?.role;
}

class _FakeTimetableRepository extends TimetableRepository {
  _FakeTimetableRepository(this.slots) : super();
  final List<TimetableSlot> slots;

  @override
  Future<List<TimetableSlot>> getAll() async => List.from(slots);

  @override
  Future<TimetableSlot> insert(TimetableSlot slot) async {
    slots.add(slot);
    return slot;
  }
}

class _FakeFacultyRepository extends FacultyRepository {
  _FakeFacultyRepository(this.teachers) : super();
  final List<Teacher> teachers;

  @override
  Future<List<Teacher>> getAll({bool includeDeleted = false}) async =>
      List.from(teachers);
}

class _FakeClassRepository extends ClassRepository {
  _FakeClassRepository(this.classes) : super();
  final List<SchoolClass> classes;

  @override
  Future<List<SchoolClass>> getAll({bool includeDeleted = false}) async =>
      List.from(classes);
}

class _FakeSubjectRepository extends SubjectRepository {
  _FakeSubjectRepository(this.subjects) : super();
  final List<Subject> subjects;

  @override
  Future<List<Subject>> getAll({bool includeDeleted = false}) async =>
      List.from(subjects);
}

class _FakeDepartmentRepository extends DepartmentRepository {
  _FakeDepartmentRepository(this.depts) : super();
  final List<Department> depts;

  @override
  Future<List<Department>> getAll({bool includeDeleted = false}) async =>
      List.from(depts);
}

class _FakeAcademicSessionRepository extends AcademicSessionRepository {
  _FakeAcademicSessionRepository(this.sessions) : super();
  final List<AcademicSession> sessions;

  @override
  Future<List<AcademicSession>> getAll({bool includeDeleted = false}) async =>
      List.from(sessions);

  @override
  Future<AcademicSession?> getCurrent() async =>
      sessions.isNotEmpty ? sessions.first : null;
}

class _FakeStudentRepository extends StudentRepository {
  _FakeStudentRepository(this.students) : super();
  final List<Student> students;

  @override
  Future<List<Student>> getAll({bool includeDeleted = false}) async =>
      List.from(students);

  @override
  Future<List<Student>> getByClassId(String classId) async =>
      students.where((s) => s.classId == classId).toList();
}

class _FakeAttendanceStore extends AttendanceStore {
  @override
  Future<int> todayLateCount() async => 0;

  @override
  Future<Map<String, dynamic>> todayOverview() async => {
        'total': 30,
        'present': 28,
        'rate': 93.3,
      };

  @override
  Future<List<Map<String, int>>> weeklyStats() async => [];

  @override
  Future<Map<AttendanceStatus, int>> monthlyDistribution() async => {};

  @override
  Future<List<AttendanceRecord>> recentActivity({int limit = 5}) async => [];

  @override
  Future<void> loadSubjectAttendance({
    required String departmentId,
    required String academicSessionId,
    required String classId,
    required String year,
    required String subjectId,
    required DateTime date,
    required List<Student> students,
    String subjectCode = '',
  }) async {}
}

void main() {
  late Department testDept;
  late AcademicSession testSession;
  late SchoolClass testClass;
  late Subject testSubject;
  late Teacher testTeacher;
  late User teacherUser;
  late TimetableSlot testSlot;

  setUp(() {
    PermissionService.instance.reset();

    testDept = Department(
      id: 'dept_cit',
      name: 'Computer Information Technology',
      code: 'CIT',
    );

    testSession = AcademicSession(
      id: 'session_2026',
      name: '2026-2027',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      isCurrent: true,
    );

    testClass = SchoolClass(
      id: 'class_2nd_cit',
      name: 'CIT 2nd Year',
      className: '2nd Year CIT',
      currentYear: '2nd Year',
      room: 'Room 4',
      section: 'A',
      departmentId: testDept.id,
      academicSessionId: testSession.id,
    );

    testSubject = Subject(
      id: 'sub_ds',
      name: 'Data Structures',
      code: 'CIT-201',
      teacherName: 'John Doe',
      classId: testClass.id,
      departmentId: testDept.id,
      year: '2nd Year',
    );

    teacherUser = User(
      id: 'user_teacher_john',
      username: 'john_doe',
      displayName: 'John Doe',
      email: 'john@institute.edu',
      role: UserRole.teacher,
    );

    testTeacher = Teacher(
      id: 'teacher_john',
      name: 'John Doe',
      subject: 'Data Structures',
      userId: teacherUser.id,
      departmentId: testDept.id,
      classId: testClass.id,
    );

    testSlot = TimetableSlot(
      id: 'slot_1',
      instituteId: AppConstants.defaultInstituteId,
      academicSessionId: testSession.id,
      classId: testClass.id,
      subjectId: testSubject.id,
      teacherId: testTeacher.id,
      roomName: 'Room 4',
      dayOfWeek: DateTime.now().weekday,
      periodSlot: 2,
      startTime: '10:30',
      endTime: '23:59', // Active / upcoming today
      isLab: false,
    );
  });

  tearDown(() {
    PermissionService.instance.reset();
  });

  InstituteStore createTestInstituteStore() {
    return InstituteStore(
      departmentRepository: _FakeDepartmentRepository([testDept]),
      academicSessionRepository:
          _FakeAcademicSessionRepository([testSession]),
      classRepository: _FakeClassRepository([testClass]),
      subjectRepository: _FakeSubjectRepository([testSubject]),
      facultyRepository: _FakeFacultyRepository([testTeacher]),
      studentRepository: _FakeStudentRepository([]),
    );
  }

  Widget createTestWidget({
    required Widget child,
    required AuthStore authStore,
    required InstituteStore instituteStore,
    required TimetableStore timetableStore,
    required AttendanceStore attendanceStore,
    RBACStore? rbacStore,
  }) {
    final rbac = rbacStore ?? RBACStore();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: authStore),
        ChangeNotifierProvider<InstituteStore>.value(value: instituteStore),
        ChangeNotifierProvider<TimetableStore>.value(value: timetableStore),
        ChangeNotifierProvider<AttendanceStore>.value(value: attendanceStore),
        ChangeNotifierProvider<RBACStore>.value(value: rbac),
        ChangeNotifierProvider<LeaveStore>(create: (_) => LeaveStore()),
        ChangeNotifierProvider<UserStore>(create: (_) => UserStore()),
        ChangeNotifierProvider<NoticeStore>(create: (_) => NoticeStore()),
        ChangeNotifierProvider<LabInventoryStore>(
            create: (_) => LabInventoryStore()),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Dashboard "Next Class" Banner & One-Tap Attendance Flow', () {
    testWidgets(
      'DashboardContent renders Next Class banner when signed in as teacher with an upcoming slot',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final authStore = _FakeAuthStore(user: teacherUser);
        final instituteStore = createTestInstituteStore();
        await instituteStore.init();

        final timetableStore = TimetableStore(
          repository: _FakeTimetableRepository([testSlot]),
        );
        await timetableStore.init();

        final attendanceStore = _FakeAttendanceStore();

        String? navigatedClassId;
        String? navigatedSubjectId;
        int? navigatedPeriodSlot;

        await tester.pumpWidget(
          createTestWidget(
            authStore: authStore,
            instituteStore: instituteStore,
            timetableStore: timetableStore,
            attendanceStore: attendanceStore,
            child: Scaffold(
              body: DashboardContent(
                onNavigateToAttendance: (
                    {required classId, required subjectId, periodSlot}) {
                  navigatedClassId = classId;
                  navigatedSubjectId = subjectId;
                  navigatedPeriodSlot = periodSlot;
                },
              ),
            ),
          ),
        );

        // Allow post-frame callback in DashboardContent to load data
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 1. Verify prominent banner texts
        expect(find.textContaining('Your next class is'), findsOneWidget);
        expect(find.textContaining('2nd Year CIT'), findsWidgets);
        expect(find.textContaining('Room 4'), findsWidgets);
        expect(find.textContaining('10:30 AM'), findsOneWidget);
        expect(find.textContaining('Data Structures'), findsWidgets);
        expect(find.text('THEORY CLASS'), findsOneWidget);

        // 2. Verify "Mark Attendance" button
        final markBtn =
            find.byKey(const ValueKey('banner_mark_attendance_button'));
        expect(markBtn, findsOneWidget);

        // 3. Tap "Mark Attendance"
        await tester.tap(markBtn);
        await tester.pump();

        expect(navigatedClassId, testClass.id);
        expect(navigatedSubjectId, testSubject.id);
        expect(navigatedPeriodSlot, 2);
      },
    );

    testWidgets(
      'DashboardContent does NOT render Next Class banner when user does not map to a teacher',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final adminUser = User(
          id: 'user_admin',
          username: 'admin',
          displayName: 'Admin User',
          email: 'admin@institute.edu',
          role: UserRole.admin,
        );

        final authStore = _FakeAuthStore(user: adminUser);
        final instituteStore = createTestInstituteStore();
        await instituteStore.init();

        final timetableStore = TimetableStore(
          repository: _FakeTimetableRepository([testSlot]),
        );
        await timetableStore.init();

        final attendanceStore = _FakeAttendanceStore();

        await tester.pumpWidget(
          createTestWidget(
            authStore: authStore,
            instituteStore: instituteStore,
            timetableStore: timetableStore,
            attendanceStore: attendanceStore,
            child: const Scaffold(
              body: DashboardContent(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Banner should not appear
        expect(find.textContaining('Your next class is'), findsNothing);
        expect(find.byKey(const ValueKey('banner_mark_attendance_button')),
            findsNothing);
      },
    );

    testWidgets(
      'DashboardShell One-Tap Mark Attendance switches to Attendance tab with preselected class and subject',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Set up permissions for Teacher role
        final teacherRole = Role(
          id: 'role_teacher',
          name: 'Teacher',
          code: 'teacher',
          isInstituteWide: false,
        );
        PermissionService.instance.loadRoles([teacherRole]);
        PermissionService.instance.loadPermissions([
          Permission(
            id: 'p_dash',
            module: 'dashboard',
            code: PermissionCodes.dashboardView,
            description: 'View dashboard',
          ),
          Permission(
            id: 'p_att',
            module: 'attendance',
            code: PermissionCodes.attendanceView,
            description: 'View attendance',
          ),
          Permission(
            id: 'p_tt',
            module: 'timetable',
            code: PermissionCodes.timetableView,
            description: 'View timetable',
          ),
        ]);
        PermissionService.instance.grantPermissionToRole(
            teacherRole.id, PermissionCodes.dashboardView);
        PermissionService.instance.grantPermissionToRole(
            teacherRole.id, PermissionCodes.attendanceView);
        PermissionService.instance.grantPermissionToRole(
            teacherRole.id, PermissionCodes.timetableView);
        PermissionService.instance
            .assignRoleToUser(teacherUser.id, teacherRole.id);
        PermissionService.instance.currentUserId = teacherUser.id;

        final authStore = _FakeAuthStore(user: teacherUser);
        final rbacStore = RBACStore();

        final instituteStore = createTestInstituteStore();
        await instituteStore.init();

        final timetableStore = TimetableStore(
          repository: _FakeTimetableRepository([testSlot]),
        );
        await timetableStore.init();

        final attendanceStore = _FakeAttendanceStore();

        await tester.pumpWidget(
          createTestWidget(
            authStore: authStore,
            rbacStore: rbacStore,
            instituteStore: instituteStore,
            timetableStore: timetableStore,
            attendanceStore: attendanceStore,
            child: const DashboardShell(),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Initial page is Dashboard, containing Next Class banner
        expect(find.textContaining('Your next class is'), findsOneWidget);

        // 2. Tap "Mark Attendance" banner button
        final markBtn =
            find.byKey(const ValueKey('banner_mark_attendance_button'));
        expect(markBtn, findsOneWidget);
        await tester.tap(markBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 3. Shell must switch to Attendance tab!
        expect(find.byType(AttendanceContent), findsOneWidget);

        // 4. Class & Subject should be pre-selected in AttendanceContent
        expect(find.textContaining(testClass.displayName), findsWidgets);
        expect(find.textContaining(testSubject.name), findsWidgets);
      },
    );
  });
}
