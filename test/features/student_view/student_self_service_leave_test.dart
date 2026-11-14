import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/repositories/sync_queue_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/leave_content.dart';
import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';

void main() {
  late Database sharedDb;
  late DatabaseHelper dbHelper;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    sharedDb = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(sharedDb);
    DatabaseHelper.setTestDatabase(sharedDb);
    dbHelper = DatabaseHelper.forTesting(sharedDb);
  });

  tearDownAll(() async {
    DatabaseHelper.setTestDatabase(null);
    await sharedDb.close();
  });

  group('LeaveRepository Student Filtering', () {
    late LeaveRepository leaveRepo;

    setUp(() async {
      await sharedDb.delete('leave_requests');
      leaveRepo = LeaveRepository(dbHelper: dbHelper);
      PermissionService.instance.reset();
    });

    tearDown(() async {
      PermissionService.instance.reset();
    });

    test('getAll filters by studentId when provided and returns all when omitted', () async {
      final now = DateTime.now().toUtc();

      await leaveRepo.insert(LeaveRequest(
        requesterName: 'Student Alpha',
        leaveType: 'Sick Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 1)),
        reason: 'Flu symptoms',
        studentId: 'std_alpha',
        status: LeaveStatus.pending,
      ));

      await leaveRepo.insert(LeaveRequest(
        requesterName: 'Student Beta',
        leaveType: 'Casual Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        reason: 'Family trip',
        studentId: 'std_beta',
        status: LeaveStatus.approved,
        remarks: 'Approved by Class Teacher',
      ));

      // 1. Filter by Student Alpha
      final alphaLeaves = await leaveRepo.getAll(studentId: 'std_alpha');
      expect(alphaLeaves.length, 1);
      expect(alphaLeaves.first.requesterName, 'Student Alpha');
      expect(alphaLeaves.first.studentId, 'std_alpha');

      // 2. Filter by Student Beta
      final betaLeaves = await leaveRepo.getAll(studentId: 'std_beta');
      expect(betaLeaves.length, 1);
      expect(betaLeaves.first.requesterName, 'Student Beta');
      expect(betaLeaves.first.remarks, 'Approved by Class Teacher');

      // 3. getByStudentId convenience method
      final betaByMethod = await leaveRepo.getByStudentId('std_beta');
      expect(betaByMethod.length, 1);
      expect(betaByMethod.first.studentId, 'std_beta');

      // 4. Staff view (no studentId filter) returns all leaves
      final allLeaves = await leaveRepo.getAll();
      expect(allLeaves.length, 2);
    });

    test('updateStatus updates remarks and status correctly', () async {
      final now = DateTime.now().toUtc();
      final req = await leaveRepo.insert(LeaveRequest(
        requesterName: 'Student Gamma',
        leaveType: 'Medical Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 3)),
        reason: 'Doctor advised bed rest',
        studentId: 'std_gamma',
        attachmentUrl: 'leaves/medical_note.pdf',
        status: LeaveStatus.pending,
      ));

      // With null current user (bypasses permission check in test mode)
      await leaveRepo.updateStatus(
        req.id,
        LeaveStatus.approved,
        remarks: 'Approved with medical certificate attached',
      );

      final updated = await leaveRepo.getById(req.id);
      expect(updated, isNotNull);
      expect(updated!.status, LeaveStatus.approved);
      expect(updated.remarks, 'Approved with medical certificate attached');
      expect(updated.attachmentUrl, 'leaves/medical_note.pdf');
    });
  });

  group('SyncService Supabase Storage & Offline Queuing', () {
    test('uploadAttachment gracefully enqueues to sync_queue when offline', () async {
      final syncQueueRepo = SyncQueueRepository(dbHelper: dbHelper);
      final dummyBytes = utf8.encode('Sample medical certificate content');

      // Direct call to uploadAttachment without cloud credentials queues it offline
      final uri = await SyncService.instance.uploadAttachment(
        fileName: 'doctor_note_2026.pdf',
        bytes: dummyBytes,
        bucket: 'leave-attachments',
      );

      expect(uri, isNotNull);
      expect(uri!.startsWith('offline_queued://'), isTrue);

      // Verify that item is placed in sync_queue for background drain
      final pending = await syncQueueRepo.getPendingItems();
      final queuedStorage = pending.where((i) => i.entityType == 'storage:leave-attachments').toList();
      expect(queuedStorage.isNotEmpty, isTrue);
      expect(queuedStorage.first.payload['fileName'], 'doctor_note_2026.pdf');
    });
  });

  group('StudentSelfViewContent UI & Self-Service Leave Flow', () {
    late _MockLeaveRepo mockRepo;
    late LeaveStore leaveStore;
    late AuthStore authStore;

    setUp(() async {
      mockRepo = _MockLeaveRepo();
      final now = DateTime.now();

      mockRepo.items.addAll([
        LeaveRequest(
          id: 'leave_1',
          requesterName: 'Zainab Ahmed',
          leaveType: 'Sick Leave',
          startDate: now,
          endDate: now.add(const Duration(days: 1)),
          reason: 'Severe migraine',
          status: LeaveStatus.pending,
          studentId: 'student_123',
        ),
        LeaveRequest(
          id: 'leave_2',
          requesterName: 'Zainab Ahmed',
          leaveType: 'Medical Leave',
          startDate: now.subtract(const Duration(days: 5)),
          endDate: now.subtract(const Duration(days: 3)),
          reason: 'Dental surgery',
          status: LeaveStatus.approved,
          studentId: 'student_123',
          remarks: 'Medical certificate accepted. Take care!',
          attachmentUrl: 'leaves/dental_cert.pdf',
        ),
        LeaveRequest(
          id: 'leave_3',
          requesterName: 'Zainab Ahmed',
          leaveType: 'Casual Leave',
          startDate: now.subtract(const Duration(days: 12)),
          endDate: now.subtract(const Duration(days: 10)),
          reason: 'Personal trip',
          status: LeaveStatus.rejected,
          studentId: 'student_123',
          remarks: 'Exams scheduled on these dates. Request rejected.',
        ),
        LeaveRequest(
          id: 'leave_4',
          requesterName: 'Other Student',
          leaveType: 'Sick Leave',
          startDate: now,
          endDate: now,
          reason: 'Other reason',
          status: LeaveStatus.pending,
          studentId: 'other_student_999',
        ),
      ]);

      leaveStore = LeaveStore(repository: mockRepo);
      await leaveStore.loadAll(studentId: 'student_123');

      authStore = AuthStore();
    });

    Widget createTestWidget({int initialTab = 2}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<LeaveStore>.value(value: leaveStore),
          ChangeNotifierProvider<AuthStore>.value(value: authStore),
        ],
        child: MaterialApp(
          home: StudentSelfViewContent(
            initialTab: initialTab,
            studentId: 'student_123',
          ),
        ),
      );
    }

    testWidgets('displays Schedule, Attendance, and My Leaves tabs', (tester) async {
      await tester.pumpWidget(createTestWidget(initialTab: 0));
      await tester.pumpAndSettle();

      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('My Leaves'), findsOneWidget);
    });

    testWidgets('My Leaves tab shows student submitted leave requests with status badges and remarks',
        (tester) async {
      await tester.pumpWidget(createTestWidget(initialTab: 2));
      await tester.pumpAndSettle();

      // Check header and apply button
      expect(find.text('My Leave Applications'), findsOneWidget);
      expect(find.text('Apply for Leave'), findsOneWidget);

      // Check status counts
      expect(find.text('Pending: 1'), findsOneWidget);
      expect(find.text('Approved: 1'), findsOneWidget);
      expect(find.text('Rejected: 1'), findsOneWidget);

      // Check leave types and reasons
      expect(find.text('Severe migraine'), findsOneWidget);
      expect(find.text('Dental surgery'), findsOneWidget);
      expect(find.text('Personal trip'), findsOneWidget);

      // Does NOT show other student's leave
      expect(find.text('Other reason'), findsNothing);

      // Check status badges
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Rejected'), findsWidgets);

      // Check teacher/admin remarks
      expect(find.text('Medical certificate accepted. Take care!'), findsOneWidget);
      expect(find.text('Exams scheduled on these dates. Request rejected.'), findsOneWidget);
      expect(find.text('Awaiting review and remarks from faculty or administration.'), findsOneWidget);
    });

    testWidgets('Apply for Leave modal allows filling dates, reason, attaching medical note and submitting',
        (tester) async {
      await tester.pumpWidget(createTestWidget(initialTab: 2));
      await tester.pumpAndSettle();

      // Tap "Apply for Leave"
      await tester.tap(find.text('Apply for Leave').first);
      await tester.pumpAndSettle();

      // Modal is visible
      expect(find.text('Reason for Leave'), findsOneWidget);
      expect(find.text('Submit Leave Request'), findsOneWidget);

      // Enter Reason
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reason for Leave'),
        'High fever, doctor recommended 2 days rest',
      );

      // Tap Attach Medical Certificate
      await tester.ensureVisible(find.text('Attach Medical Certificate'));
      await tester.tap(find.text('Attach Medical Certificate'));
      await tester.pumpAndSettle();

      expect(find.textContaining('medical_certificate'), findsOneWidget);

      // Submit
      await tester.ensureVisible(find.text('Submit Leave Request'));
      await tester.tap(find.text('Submit Leave Request'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));

      // Verify the new request was added
      expect(find.text('High fever, doctor recommended 2 days rest'), findsOneWidget);
    });
  });

  group('Staff Approval Flow and PermissionGuard', () {
    late _MockLeaveRepo mockRepo;
    late LeaveStore leaveStore;
    late AuthStore authStore;
    late RBACStore rbacStore;

    setUp(() async {
      mockRepo = _MockLeaveRepo();
      final now = DateTime.now();

      mockRepo.items.add(LeaveRequest(
        id: 'leave_pending_1',
        requesterName: 'Bilal Khan',
        leaveType: 'Sick Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 1)),
        reason: 'Viral fever',
        status: LeaveStatus.pending,
      ));

      leaveStore = LeaveStore(repository: mockRepo);
      await leaveStore.loadAll();
      authStore = AuthStore();
      rbacStore = RBACStore();
    });

    testWidgets('Teacher/Admin with leave.approve permission can see and click Approve/Reject',
        (tester) async {
      PermissionService.instance.reset();
      final adminRole = Role(
        id: 'r_admin',
        name: 'Administrator',
        code: 'admin',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([adminRole]);
      PermissionService.instance.grantPermissionToRole(adminRole.id, PermissionCodes.leaveView);
      PermissionService.instance.grantPermissionToRole(adminRole.id, PermissionCodes.leaveApprove);
      PermissionService.instance.assignRoleToUser('admin_user_1', adminRole.id);
      PermissionService.instance.currentUserId = 'admin_user_1';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LeaveStore>.value(value: leaveStore),
            ChangeNotifierProvider<AuthStore>.value(value: authStore),
            ChangeNotifierProvider<RBACStore>.value(value: rbacStore),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LeaveContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(find.text('Approved: 1'), findsOneWidget);
      expect(find.text('Pending: 0'), findsOneWidget);
    });

    testWidgets('Student without leave.approve permission does NOT see Approve/Reject buttons',
        (tester) async {
      PermissionService.instance.reset();
      final studentRole = Role(
        id: 'r_student',
        name: 'Student',
        code: 'student',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([studentRole]);
      PermissionService.instance.grantPermissionToRole(studentRole.id, PermissionCodes.leaveView);
      PermissionService.instance.assignRoleToUser('student_user_1', studentRole.id);
      PermissionService.instance.currentUserId = 'student_user_1';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LeaveStore>.value(value: leaveStore),
            ChangeNotifierProvider<AuthStore>.value(value: authStore),
            ChangeNotifierProvider<RBACStore>.value(value: rbacStore),
          ],
          child: const MaterialApp(
            home: Scaffold(body: LeaveContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Approve/Reject should be hidden by PermissionGuard fallback
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });
  });
}

class _MockLeaveRepo extends LeaveRepository {
  final List<LeaveRequest> items = [];

  @override
  Future<List<LeaveRequest>> getAll({
    String? studentId,
    bool includeDeleted = false,
  }) async {
    if (studentId != null && studentId.isNotEmpty) {
      return items.where((r) => r.studentId == studentId).toList();
    }
    return List.from(items);
  }

  @override
  Future<LeaveRequest> insert(LeaveRequest request) async {
    items.insert(0, request);
    return request;
  }

  @override
  Future<void> updateStatus(
    String id,
    LeaveStatus newStatus, {
    String? remarks,
  }) async {
    final idx = items.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      items[idx].status = newStatus;
      if (remarks != null) {
        items[idx] = items[idx].copyWith(remarks: remarks);
      }
    }
  }
}
