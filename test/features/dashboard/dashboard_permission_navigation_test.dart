import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/academic_session_repository.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/department_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/dashboard/presentation/dashboard_shell.dart';
import 'package:attendance_app/features/parent_view/presentation/parent_view_content.dart';
import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';

class _FakeAuthStore extends AuthStore {
  _FakeAuthStore({User? user}) : _user = user;
  final User? _user;

  @override
  User? get currentUser => _user;

  @override
  bool get isLoggedIn => _user != null;

  @override
  UserRole? get currentUserRole => _user?.role;
}

class _FakeAttendanceRepository extends AttendanceRepository {
  @override
  Future<List<Map<String, dynamic>>> getDetailedAttendanceForStudent(String studentId) async => [];
}

void main() {
  setUp(() {
    PermissionService.instance.reset();
  });

  tearDown(() {
    PermissionService.instance.reset();
  });

  Widget buildTestShell({
    required AuthStore authStore,
    required RBACStore rbacStore,
    InstituteStore? instituteStore,
    AttendanceStore? attendanceStore,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: authStore),
        ChangeNotifierProvider<RBACStore>.value(value: rbacStore),
        if (instituteStore != null)
          ChangeNotifierProvider<InstituteStore>.value(value: instituteStore),
        if (attendanceStore != null)
          ChangeNotifierProvider<AttendanceStore>.value(value: attendanceStore),
      ],
      child: const MaterialApp(
        home: DashboardShell(),
      ),
    );
  }

  group('DashboardShell Permission-Derived Routing & Items', () {
    testWidgets('Authenticated student without staff permissions routes directly to StudentSelfViewContent', (tester) async {
      final studentUser = User(
        id: 'student_1',
        username: 'student1',
        displayName: 'Alice Student',
        email: 'alice@student.gilt.edu',
        role: UserRole.student,
      );

      final authStore = _FakeAuthStore(user: studentUser);
      final rbacStore = RBACStore();

      await tester.pumpWidget(buildTestShell(authStore: authStore, rbacStore: rbacStore));
      await tester.pump();

      expect(find.byType(StudentSelfViewContent), findsOneWidget);
      expect(find.byType(ParentViewContent), findsNothing);
      expect(find.text('Alice Student'), findsOneWidget);
    });

    testWidgets('Authenticated parent without staff permissions routes directly to ParentViewContent', (tester) async {
      final parentUser = User(
        id: 'parent_1',
        username: 'parent1',
        displayName: 'Bob Parent',
        email: 'bob@parent.gilt.edu',
        role: UserRole.parent,
      );

      final authStore = _FakeAuthStore(user: parentUser);
      final rbacStore = RBACStore();

      await tester.pumpWidget(buildTestShell(authStore: authStore, rbacStore: rbacStore));
      await tester.pump();

      expect(find.byType(ParentViewContent), findsOneWidget);
      expect(find.byType(StudentSelfViewContent), findsOneWidget);
    });

    testWidgets('Visible navigation items derive purely from rbacStore.hasPermission', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final customUser = User(
        id: 'custom_staff_1',
        username: 'custom_clerk',
        displayName: 'Clerk User',
        email: 'clerk@institute.edu',
        role: UserRole.assistant,
      );

      final customRole = Role(
        id: 'role_clerk',
        name: 'Clerk',
        code: 'clerk',
        isInstituteWide: false,
      );

      PermissionService.instance.loadRoles([customRole]);
      PermissionService.instance.loadPermissions([
        Permission(
          id: 'p_att',
          module: 'attendance',
          code: PermissionCodes.attendanceView,
          description: 'View attendance',
        ),
        Permission(
          id: 'p_lab',
          module: 'lab',
          code: PermissionCodes.labView,
          description: 'View lab inventory',
        ),
      ]);
      PermissionService.instance.grantPermissionToRole(customRole.id, PermissionCodes.attendanceView);
      PermissionService.instance.grantPermissionToRole(customRole.id, PermissionCodes.labView);
      PermissionService.instance.assignRoleToUser(customUser.id, customRole.id);
      PermissionService.instance.currentUserId = customUser.id;

      final authStore = _FakeAuthStore(user: customUser);
      final rbacStore = RBACStore();

      final instituteStore = InstituteStore(
        departmentRepository: DepartmentRepository(),
        academicSessionRepository: AcademicSessionRepository(),
        classRepository: ClassRepository(),
        subjectRepository: SubjectRepository(),
        facultyRepository: FacultyRepository(),
        studentRepository: StudentRepository(),
      );

      final attendanceStore = AttendanceStore(
        repository: _FakeAttendanceRepository(),
      );

      await tester.pumpWidget(
        buildTestShell(
          authStore: authStore,
          rbacStore: rbacStore,
          instituteStore: instituteStore,
          attendanceStore: attendanceStore,
        ),
      );
      await tester.pump();

      // Only Attendance and Lab Inventory should be present in the sidebar
      final sidebarList = find.byType(ListView);
      expect(find.descendant(of: sidebarList, matching: find.text('Attendance')), findsOneWidget);
      expect(find.descendant(of: sidebarList, matching: find.text('Lab Inventory')), findsOneWidget);

      // Other modules must NOT be present in the sidebar
      expect(find.descendant(of: sidebarList, matching: find.text('Dashboard')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Timetable')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Classes')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Teachers')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Students')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Reports')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('Settings')), findsNothing);
      expect(find.descendant(of: sidebarList, matching: find.text('User & Staff Management')), findsNothing);
    });
  });
}
