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
import 'package:attendance_app/core/repositories/notice_repository.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';

// ---------------------------------------------------------------------------
// Fake in-memory NoticeRepository (no DB / SyncService)
// ---------------------------------------------------------------------------

class _FakeNoticeRepository extends NoticeRepository {
  _FakeNoticeRepository() : super();
  final List<Notice> _data = [];

  @override
  Future<List<Notice>> getAll({bool includeDeleted = false}) async =>
      List.from(_data.where((n) => includeDeleted || !n.isDeleted));

  @override
  Future<Notice> insert(Notice notice) async {
    _data.add(notice);
    return notice;
  }

  @override
  Future<void> update(Notice notice) async {
    final idx = _data.indexWhere((n) => n.id == notice.id);
    if (idx >= 0) _data[idx] = notice;
  }

  @override
  Future<void> softDelete(String id) async {
    final idx = _data.indexWhere((n) => n.id == id);
    if (idx >= 0) _data[idx] = _data[idx].copyWith(isDeleted: true);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Notice _notice({
  required String id,
  required String title,
  String body = 'Notice body content.',
  String? targetRole,
  String? departmentId,
  bool isPinned = false,
}) {
  return Notice(
    id: id,
    instituteId: AppConstants.defaultInstituteId,
    title: title,
    body: body,
    targetRole: targetRole,
    departmentId: departmentId,
    isPinned: isPinned,
    publishedBy: 'admin_user',
    publishedByName: 'Principal',
  );
}

Widget _buildApp({
  required NoticeStore noticeStore,
  int initialTab = 3,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NoticeStore>.value(value: noticeStore),
      ChangeNotifierProvider<InstituteStore>(create: (_) => InstituteStore()),
      ChangeNotifierProvider<AttendanceStore>(
          create: (_) => AttendanceStore()),
      ChangeNotifierProvider<LeaveStore>(create: (_) => LeaveStore()),
      ChangeNotifierProvider<AuthStore>(create: (_) => AuthStore()),
      ChangeNotifierProvider<RBACStore>(create: (_) => RBACStore()),
    ],
    child: MaterialApp(
      home: StudentSelfViewContent(initialTab: initialTab),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    // Open a shared in-memory DB and seed all tables so the student view's
    // async queries (attendance, leave, student lookup) don't fail on
    // missing tables.
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    DatabaseHelper.setTestDatabase(db);
  });

  tearDownAll(() {
    DatabaseHelper.setTestDatabase(null);
  });

  group('StudentSelfViewContent — Notices tab (tab index 3)', () {
    late _FakeNoticeRepository repo;
    late NoticeStore noticeStore;

    setUp(() async {
      repo = _FakeNoticeRepository();

      // Pinned notice for all audiences
      await repo.insert(_notice(
        id: 'pin1',
        title: 'Prize Distribution Circular',
        body: 'All students are requested to attend the annual prize distribution.',
        targetRole: null, // visible to all
        isPinned: true,
      ));

      // Unpinned notice for students only
      await repo.insert(_notice(
        id: 'stu1',
        title: 'Student Fee Payment Reminder',
        body: 'Please pay the semester fee before the due date.',
        targetRole: 'student',
        isPinned: false,
      ));

      // Teacher-only notice — must NOT appear in student view
      await repo.insert(_notice(
        id: 'tea1',
        title: 'Staff Meeting Announcement',
        body: 'All teaching staff must attend the meeting.',
        targetRole: 'teacher',
        isPinned: false,
      ));

      noticeStore = NoticeStore(repository: repo);
      await noticeStore.init();
    });

    // Pumps the student view using real async so DB timeouts don't interfere
    // with the fake-async clock.
    Future<void> pumpStudentView(
      WidgetTester tester,
      NoticeStore store, {
      int tab = 3,
    }) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(_buildApp(noticeStore: store, initialTab: tab));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('"Notices" tab label is present in the tab bar', (tester) async {
      await pumpStudentView(tester, noticeStore, tab: 0);
      expect(find.text('Notices'), findsAtLeastNWidgets(1));
    });

    testWidgets('pinned notice title is visible on Notices tab', (tester) async {
      await pumpStudentView(tester, noticeStore);
      expect(
        find.textContaining('Prize Distribution Circular'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('student-targeted notice is visible on Notices tab',
        (tester) async {
      await pumpStudentView(tester, noticeStore);
      expect(
        find.textContaining('Student Fee Payment Reminder'),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('teacher-targeted notice is NOT visible on Notices tab',
        (tester) async {
      await pumpStudentView(tester, noticeStore);
      expect(find.textContaining('Staff Meeting Announcement'), findsNothing);
    });

    testWidgets('pin icon appears for pinned notices', (tester) async {
      await pumpStudentView(tester, noticeStore);
      expect(find.byIcon(Icons.push_pin_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping a notice opens detail dialog with full body',
        (tester) async {
      await pumpStudentView(tester, noticeStore);

      await tester.tap(
        find.textContaining('Prize Distribution Circular').first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.textContaining(
            'All students are requested to attend the annual prize distribution.'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('empty state shown when no notices exist for student',
        (tester) async {
      final emptyRepo = _FakeNoticeRepository();
      await emptyRepo.insert(_notice(
        id: 'tea2',
        title: 'Teachers Only',
        targetRole: 'teacher',
      ));
      final emptyStore = NoticeStore(repository: emptyRepo);
      await emptyStore.init();

      await pumpStudentView(tester, emptyStore);
      expect(
        find.textContaining('No notices for you right now'),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
