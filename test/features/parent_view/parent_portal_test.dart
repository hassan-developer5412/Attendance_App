// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
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
import 'package:attendance_app/features/parent_view/presentation/parent_view_content.dart';

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

class _FakeLeaveRepo extends LeaveRepository {
  _FakeLeaveRepo(this.items);
  final List<LeaveRequest> items;

  @override
  Future<List<LeaveRequest>> getAll({
    String? studentId,
    String? departmentId,
    String? requestingUserId,
    bool includeDeleted = false,
  }) async {
    if (studentId != null && studentId.isNotEmpty) {
      return items.where((r) => r.studentId == studentId).toList();
    }
    return List.from(items);
  }
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

  group('ParentViewContent — Read-Only Portal & RBAC', () {
    late RBACStore rbacStore;
    late NoticeStore noticeStore;
    late TimetableStore timetableStore;
    late InstituteStore instituteStore;
    late LeaveStore leaveStore;
    late _FakeAttendanceStore attendanceStore;
    late String childId;
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
      childId = 'child_1';

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
        'id': 'dept_mech',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Mechanical Engineering',
        'code': 'ME',
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
        'room': 'Room 204',
        'department_id': deptId,
        'current_year': '2nd Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('teachers', {
        'id': 'tea_1',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Prof. Ayesha',
        'subject': 'Databases',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('subjects', {
        'id': 'sub_db',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Database Systems',
        'code': 'CS-301',
        'class_id': classId,
        'teacher_id': 'tea_1',
        'teacher_name': 'Prof. Ayesha',
        'subject_type': 'theory',
        'year': '2nd Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('subjects', {
        'id': 'sub_dblab',
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Database Lab',
        'code': 'CS-301L',
        'class_id': classId,
        'teacher_id': 'tea_1',
        'teacher_name': 'Prof. Ayesha',
        'subject_type': 'lab',
        'year': '2nd Year',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });
      await db.insert('students', {
        'id': childId,
        'institute_id': AppConstants.defaultInstituteId,
        'name': 'Sara Ahmed',
        'roll_number': 'CS-22',
        'roll_no': 'CS-22',
        'full_name': 'Sara Ahmed',
        'class_id': classId,
        'department_id': deptId,
        'current_year': '2nd Year',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
        'is_deleted': 0,
      });

      instituteStore = InstituteStore();
      await instituteStore.init();

      final parentRole = Role(id: 'role_parent', name: 'Parent', code: 'parent');
      PermissionService.instance.loadRoles([parentRole]);
      PermissionService.instance.grantPermissionToRole(
          parentRole.id, PermissionCodes.timetableView);
      PermissionService.instance.grantPermissionToRole(
          parentRole.id, PermissionCodes.attendanceView);
      PermissionService.instance.grantPermissionToRole(
          parentRole.id, PermissionCodes.leaveView);
      PermissionService.instance.grantPermissionToRole(
          parentRole.id, PermissionCodes.noticeView);
      PermissionService.instance.assignRoleToUser('user_parent_1', parentRole.id);
      PermissionService.instance.currentUserId = 'user_parent_1';

      rbacStore = RBACStore()..isLoaded = true;

      timetableStore = TimetableStore(
        repository: _FakeTimetableRepo([
          TimetableSlot(
            id: 'slot_p1',
            instituteId: AppConstants.defaultInstituteId,
            classId: classId,
            subjectId: 'sub_db',
            teacherId: 'tea_1',
            roomName: 'Room 204',
            dayOfWeek: 1,
            periodSlot: 1,
            startTime: '08:30',
            endTime: '09:20',
            isLab: false,
          ),
          TimetableSlot(
            id: 'slot_p2',
            instituteId: AppConstants.defaultInstituteId,
            classId: classId,
            subjectId: 'sub_dblab',
            teacherId: 'tea_1',
            roomName: 'DB Lab 2',
            dayOfWeek: 4,
            periodSlot: 3,
            startTime: '13:00',
            endTime: '14:30',
            isLab: true,
          ),
          TimetableSlot(
            id: 'slot_other',
            instituteId: AppConstants.defaultInstituteId,
            classId: 'unrelated_class',
            subjectId: 'sub_db',
            teacherId: 'tea_1',
            roomName: 'Room 505',
            dayOfWeek: 5,
            periodSlot: 1,
            startTime: '09:00',
            endTime: '09:50',
          ),
        ]),
      );
      await timetableStore.init();

      noticeStore = NoticeStore(
        repository: _FakeNoticeRepo([
          Notice(
            id: 'pn_inst',
            instituteId: AppConstants.defaultInstituteId,
            title: 'Parent-Teacher Meeting',
            body: 'Scheduled for next Saturday at 10 AM.',
            publishedBy: 'admin',
            publishedByName: 'Principal',
            targetRole: 'parent',
            departmentId: null,
            isPinned: true,
          ),
          Notice(
            id: 'pn_dept',
            instituteId: AppConstants.defaultInstituteId,
            title: 'CS Project Showcase',
            body: 'Parents are invited to the CS department showcase.',
            publishedBy: 'hod',
            publishedByName: 'CS HOD',
            targetRole: null,
            departmentId: deptId,
          ),
          Notice(
            id: 'pn_teacher',
            instituteId: AppConstants.defaultInstituteId,
            title: 'Faculty Grading Deadline',
            body: 'Submit grades by Friday.',
            publishedBy: 'admin',
            publishedByName: 'Admin',
            targetRole: 'teacher',
            departmentId: null,
          ),
          Notice(
            id: 'pn_other_dept',
            instituteId: AppConstants.defaultInstituteId,
            title: 'Mech Lab Inspection',
            body: 'Only Mechanical department.',
            publishedBy: 'hod',
            publishedByName: 'ME HOD',
            targetRole: 'all',
            departmentId: 'dept_mech',
          ),
        ]),
      );
      await noticeStore.init();

      leaveStore = LeaveStore(
        repository: _FakeLeaveRepo([
          LeaveRequest(
            id: 'lv_1',
            requesterName: 'Sara Ahmed',
            leaveType: 'Sick Leave',
            startDate: DateTime(2026, 11, 10),
            endDate: DateTime(2026, 11, 11),
            reason: 'High fever',
            status: LeaveStatus.approved,
            studentId: childId,
            remarks: 'Approved by class advisor.',
          ),
        ]),
      );
      await leaveStore.loadAll(studentId: childId);

      attendanceStore = _FakeAttendanceStore([
        // Database Systems: 4/5 = 80% (>= 75%)
        {'subject_name': 'Database Systems', 'status': 'present', 'session_date': '2026-11-18'},
        {'subject_name': 'Database Systems', 'status': 'present', 'session_date': '2026-11-19'},
        {'subject_name': 'Database Systems', 'status': 'present', 'session_date': '2026-11-20'},
        {'subject_name': 'Database Systems', 'status': 'present', 'session_date': '2026-11-21'},
        {'subject_name': 'Database Systems', 'status': 'absent', 'session_date': '2026-11-22'},
        // Database Lab: 2/4 = 50% (< 75%)
        {'subject_name': 'Database Lab', 'status': 'present', 'session_date': '2026-11-18'},
        {'subject_name': 'Database Lab', 'status': 'present', 'session_date': '2026-11-19'},
        {'subject_name': 'Database Lab', 'status': 'absent', 'session_date': '2026-11-20'},
        {'subject_name': 'Database Lab', 'status': 'absent', 'session_date': '2026-11-21'},
      ]);
    });

    Future<void> pumpParentPortal(
      WidgetTester tester, {
      int initialTab = 0,
      String? overrideStudentId,
      bool omitStudentId = false,
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
              ChangeNotifierProvider<LeaveStore>.value(value: leaveStore),
              ChangeNotifierProvider<AuthStore>(create: (_) => AuthStore()),
            ],
            child: MaterialApp(
              home: ParentViewContent(
                initialTab: initialTab,
                studentId: omitStudentId ? null : (overrideStudentId ?? childId),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('renders child weekly timetable filtered by classId with Lab & Theory badges',
        (tester) async {
      await pumpParentPortal(tester, initialTab: 0);

      expect(find.text('Parent Portal — Sara Ahmed'), findsOneWidget);
      expect(find.text('Weekly Class & Lab Timetable'), findsOneWidget);
      expect(find.text('Database Systems (CS-301)'), findsOneWidget);
      expect(find.text('Database Lab (CS-301L)'), findsOneWidget);
      expect(find.text('Theory'), findsOneWidget);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.textContaining('Room 505'), findsNothing);
    });

    testWidgets('renders child subject-wise attendance with Below 75% warning badge',
        (tester) async {
      await pumpParentPortal(tester, initialTab: 1);

      expect(find.text('Subject-wise Attendance'), findsOneWidget);
      expect(find.text('Database Systems'), findsWidgets);
      expect(find.text('80.0%'), findsOneWidget);
      expect(find.text('Database Lab'), findsWidgets);
      expect(find.text('50.0%'), findsOneWidget);
      // Overall is 6/9 = 66.7% (<75%) and Database Lab is 50.0% (<75%)
      expect(find.text('Below 75%'), findsNWidgets(2));
    });

    testWidgets('renders child leaves in read-only mode without Apply button',
        (tester) async {
      await pumpParentPortal(tester, initialTab: 2);

      expect(find.text('Child\'s Leave Applications (Read-Only)'), findsOneWidget);
      expect(find.text('High fever'), findsOneWidget);
      expect(find.text('Approved by class advisor.'), findsOneWidget);
      expect(find.text('Apply for Leave'), findsNothing);
    });

    testWidgets('renders institute-wide and child department notices, excluding teacher & other dept notices',
        (tester) async {
      await pumpParentPortal(tester, initialTab: 3);

      expect(find.text('Parent-Teacher Meeting'), findsOneWidget);
      expect(find.text('CS Project Showcase'), findsOneWidget);
      expect(find.text('Faculty Grading Deadline'), findsNothing);
      expect(find.text('Mech Lab Inspection'), findsNothing);
    });

    testWidgets('PermissionGuard blocks Attendance tab when attendance.view is revoked',
        (tester) async {
      PermissionService.instance.revokePermissionFromRole(
          'role_parent', PermissionCodes.attendanceView);

      await pumpParentPortal(tester, initialTab: 1);

      expect(find.text('Attendance Restricted'), findsOneWidget);
      expect(find.text('Subject-wise Attendance'), findsNothing);
    });

    testWidgets('shows graceful unlinked state when no child is linked',
        (tester) async {
      await pumpParentPortal(tester, initialTab: 0, omitStudentId: true);

      expect(find.text('Class Not Linked'), findsOneWidget);
    });
  });
}
