// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/notice_repository.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';

class _FakeNoticeRepo extends NoticeRepository {
  _FakeNoticeRepo(this.items);
  final List<Notice> items;

  @override
  Future<List<Notice>> getAll({bool includeDeleted = false}) async =>
      List.from(items.where((n) => includeDeleted || !n.isDeleted));
}

class _FakeTimetableRepo extends TimetableRepository {
  _FakeTimetableRepo(this.items);
  final List<TimetableSlot> items;

  @override
  Future<List<TimetableSlot>> getAll({bool includeDeleted = false}) async =>
      List.from(items.where((s) => includeDeleted || !s.isDeleted));
}

class _FakeAttendanceStore extends AttendanceStore {
  _FakeAttendanceStore(this.logs);
  final List<Map<String, dynamic>> logs;

  @override
  Future<List<Map<String, dynamic>>> getDetailedAttendanceForStudent(
    String studentId,
  ) async {
    return logs;
  }
}

void main() {
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    DatabaseHelper.setTestDatabase(db);
  });

  tearDownAll(() async {
    PermissionService.instance.reset();
    DatabaseHelper.setTestDatabase(null);
    await db.close();
  });

  group('StudentSelfViewContent — Full Parity & RBAC', () {
    late RBACStore rbacStore;
    late NoticeStore noticeStore;
    late TimetableStore timetableStore;
    late InstituteStore instituteStore;
    late _FakeAttendanceStore attendanceStore;
    late String studentId;
    late String classId;
    late String deptId;

    setUp(() async {
      PermissionService.instance.reset();
      await db.delete('students');
      await db.delete('classes');
      await db.delete('departments');
      await db.delete('subjects');
      await db.delete('teachers');

      deptId = 'dept_cs';
      classId = 'class_cs_1';
      studentId = 'stu_1';

      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('departments', {
        'id': deptId,
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Computer Science',
        'code': 'CS',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('departments', {
        'id': 'dept_ee',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Electrical Engineering',
        'code': 'EE',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('classes', {
        'id': classId,
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'BSCS-A',
        'section': 'A',
        'room': 'Room 101',
        'department_id': deptId,
        'current_year': '1st Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('teachers', {
        'id': 'tea_1',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Dr. Tariq',
        'subject': 'Algorithms',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('subjects', {
        'id': 'sub_alg',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Algorithms',
        'code': 'CS-201',
        'class_id': classId,
        'teacher_id': 'tea_1',
        'teacher_name': 'Dr. Tariq',
        'subject_type': 'theory',
        'year': '1st Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('subjects', {
        'id': 'sub_lab',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Algorithms Lab',
        'code': 'CS-201L',
        'class_id': classId,
        'teacher_id': 'tea_1',
        'teacher_name': 'Dr. Tariq',
        'subject_type': 'lab',
        'year': '1st Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('students', {
        'id': studentId,
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Ali Khan',
        'roll_number': 'CS-01',
        'roll_no': 'CS-01',
        'full_name': 'Ali Khan',
        'class_id': classId,
        'department_id': deptId,
        'current_year': '1st Year',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });

      instituteStore = InstituteStore();
      await instituteStore.init();

      // Configure RBAC for student
      final studentRole = Role(id: 'role_student', name: 'Student', code: 'student');
      PermissionService.instance.loadRoles([studentRole]);
      PermissionService.instance.grantPermissionToRole(
          studentRole.id, PermissionCodes.timetableView);
      PermissionService.instance.grantPermissionToRole(
          studentRole.id, PermissionCodes.attendanceView);
      PermissionService.instance.grantPermissionToRole(
          studentRole.id, PermissionCodes.leaveView);
      PermissionService.instance.grantPermissionToRole(
          studentRole.id, PermissionCodes.noticeView);
      PermissionService.instance.assignRoleToUser('user_stu_1', studentRole.id);
      PermissionService.instance.currentUserId = 'user_stu_1';

      rbacStore = RBACStore()..isLoaded = true;

      timetableStore = TimetableStore(
        repository: _FakeTimetableRepo([
          TimetableSlot(
            id: 'slot_1',
            instituteId: AppConstants.defaultInstituteId,
            classId: classId,
            subjectId: 'sub_alg',
            teacherId: 'tea_1',
            roomName: 'Room 101',
            dayOfWeek: 1,
            periodSlot: 1,
            startTime: '09:00',
            endTime: '09:50',
            isLab: false,
          ),
          TimetableSlot(
            id: 'slot_2',
            instituteId: AppConstants.defaultInstituteId,
            classId: classId,
            subjectId: 'sub_lab',
            teacherId: 'tea_1',
            roomName: 'Lab 3',
            dayOfWeek: 2,
            periodSlot: 2,
            startTime: '11:00',
            endTime: '12:30',
            isLab: true,
          ),
          TimetableSlot(
            id: 'slot_other',
            instituteId: AppConstants.defaultInstituteId,
            classId: 'other_class',
            subjectId: 'sub_alg',
            teacherId: 'tea_1',
            roomName: 'Room 999',
            dayOfWeek: 3,
            periodSlot: 1,
            startTime: '10:00',
            endTime: '10:50',
            isLab: false,
          ),
        ]),
      );
      await timetableStore.init();

      noticeStore = NoticeStore(
        repository: _FakeNoticeRepo([
          Notice(
            id: 'n_inst',
            instituteId: AppConstants.defaultInstituteId,
            title: 'Institute Holiday',
            body: 'Campus closed on Friday.',
            publishedBy: 'admin',
            publishedByName: 'Principal',
            targetRole: null,
            departmentId: null,
            isPinned: true,
          ),
          Notice(
            id: 'n_dept',
            instituteId: AppConstants.defaultInstituteId,
            title: 'CS Lab Safety Briefing',
            body: 'Mandatory for CS students.',
            publishedBy: 'hod',
            publishedByName: 'CS HOD',
            targetRole: 'student',
            departmentId: deptId,
          ),
          Notice(
            id: 'n_other_dept',
            instituteId: AppConstants.defaultInstituteId,
            title: 'EE Workshop',
            body: 'Only for EE.',
            publishedBy: 'hod',
            publishedByName: 'EE HOD',
            targetRole: 'student',
            departmentId: 'dept_ee',
          ),
        ]),
      );
      await noticeStore.init();

      attendanceStore = _FakeAttendanceStore([
        // Algorithms: 4/4 = 100%
        {'subject_name': 'Algorithms', 'status': 'present', 'session_date': '2026-11-20'},
        {'subject_name': 'Algorithms', 'status': 'present', 'session_date': '2026-11-21'},
        {'subject_name': 'Algorithms', 'status': 'present', 'session_date': '2026-11-22'},
        {'subject_name': 'Algorithms', 'status': 'late', 'session_date': '2026-11-23'},
        // Algorithms Lab: 1/4 = 25% (<75%)
        {'subject_name': 'Algorithms Lab', 'status': 'present', 'session_date': '2026-11-20'},
        {'subject_name': 'Algorithms Lab', 'status': 'absent', 'session_date': '2026-11-21'},
        {'subject_name': 'Algorithms Lab', 'status': 'absent', 'session_date': '2026-11-22'},
        {'subject_name': 'Algorithms Lab', 'status': 'absent', 'session_date': '2026-11-23'},
      ]);
    });

    Future<void> pumpPortal(
      WidgetTester tester, {
      int initialTab = 0,
      String? overrideStudentId,
    }) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<RBACStore>.value(value: rbacStore),
              ChangeNotifierProvider<NoticeStore>.value(value: noticeStore),
              ChangeNotifierProvider<TimetableStore>.value(value: timetableStore),
              ChangeNotifierProvider<InstituteStore>.value(value: instituteStore),
              ChangeNotifierProvider<AttendanceStore>.value(value: attendanceStore),
              ChangeNotifierProvider<LeaveStore>(create: (_) => LeaveStore()),
              ChangeNotifierProvider<AuthStore>(create: (_) => AuthStore()),
            ],
            child: MaterialApp(
              home: StudentSelfViewContent(
                initialTab: initialTab,
                studentId: overrideStudentId ?? studentId,
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('renders student weekly timetable filtered by classId with Lab/Theory badges',
        (tester) async {
      await pumpPortal(tester, initialTab: 0);

      expect(find.text('Weekly Class & Lab Timetable'), findsOneWidget);
      expect(find.text('Algorithms (CS-201)'), findsOneWidget);
      expect(find.text('Algorithms Lab (CS-201L)'), findsOneWidget);
      expect(find.text('Theory'), findsOneWidget);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.textContaining('Room 999'), findsNothing);
    });

    testWidgets('renders subject-wise attendance percentages and Below 75% warning badge',
        (tester) async {
      await pumpPortal(tester, initialTab: 1);

      expect(find.text('Subject-wise Attendance'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('25.0%'), findsOneWidget);
      // Overall is 5/8 = 62.5% (<75%) and Algorithms Lab is 25.0% (<75%)
      expect(find.text('Below 75%'), findsNWidgets(2));
    });

    testWidgets('filters notices to institute-wide and student department',
        (tester) async {
      await pumpPortal(tester, initialTab: 3);

      expect(find.text('Institute Holiday'), findsOneWidget);
      expect(find.text('CS Lab Safety Briefing'), findsOneWidget);
      expect(find.text('EE Workshop'), findsNothing);
    });

    testWidgets('PermissionGuard restricts tab when permission is revoked',
        (tester) async {
      PermissionService.instance.revokePermissionFromRole(
          'role_student', PermissionCodes.timetableView);

      await pumpPortal(tester, initialTab: 0);

      expect(find.text('Schedule & Timetable Restricted'), findsOneWidget);
      expect(find.text('Algorithms (CS-201)'), findsNothing);
    });

    testWidgets('shows graceful unlinked empty state when student is not linked',
        (tester) async {
      await pumpPortal(tester, initialTab: 0, overrideStudentId: '');

      expect(find.text('Class Not Linked'), findsOneWidget);
    });
  });
}
