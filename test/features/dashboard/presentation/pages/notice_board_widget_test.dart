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
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/notice_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/dashboard_content.dart';

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
  String id = 'n1',
  String title = 'Test Notice',
  String body = 'Body text',
  String? targetRole,
  bool isPinned = false,
}) {
  return Notice(
    id: id,
    instituteId: AppConstants.defaultInstituteId,
    title: title,
    body: body,
    targetRole: targetRole,
    isPinned: isPinned,
    publishedBy: 'user_1',
    publishedByName: 'Principal',
  );
}

Widget _buildApp(
  NoticeStore noticeStore, {
  bool grantNoticeManage = false,
}) {
  final rbac = RBACStore();
  if (grantNoticeManage) {
    final role = Role(
      id: 'r_principal',
      name: 'Principal',
      code: 'principal',
      isInstituteWide: true,
    );
    PermissionService.instance.loadRoles([role]);
    PermissionService.instance.loadPermissions([
      Permission(
        id: 'p_nm',
        module: 'notice',
        code: PermissionCodes.noticeManage,
        description: 'Manage notices',
      ),
    ]);
    PermissionService.instance
        .grantPermissionToRole(role.id, PermissionCodes.noticeManage);
    PermissionService.instance.assignRoleToUser('u_principal', role.id);
    PermissionService.instance.currentUserId = 'u_principal';
  } else {
    PermissionService.instance.currentUserId = 'u_no_perm';
  }

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NoticeStore>.value(value: noticeStore),
      ChangeNotifierProvider<InstituteStore>(create: (_) => InstituteStore()),
      ChangeNotifierProvider<AttendanceStore>(
          create: (_) => AttendanceStore()),
      ChangeNotifierProvider<RBACStore>.value(value: rbac),
      ChangeNotifierProvider<AuthStore>(create: (_) => AuthStore()),
    ],
    child: const MaterialApp(
      home: Scaffold(body: DashboardContent()),
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
    // Seed a full DB so DashboardContent's queries resolve without timeout.
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    DatabaseHelper.setTestDatabase(db);
  });

  tearDownAll(() {
    DatabaseHelper.setTestDatabase(null);
  });

  setUp(() {
    PermissionService.instance.reset();
  });

  group('DashboardContent — Notice Board section', () {
    // Helper: pumps the widget inside runAsync so real async (10s timeout
    // DB calls) completes without hitting fake-async clock limits.
    Future<void> pumpDashboard(
      WidgetTester tester,
      NoticeStore store, {
      bool grantNoticeManage = false,
    }) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
            _buildApp(store, grantNoticeManage: grantNoticeManage));
        // Allow _loadDashboardData async chain to complete
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      // Let the widget tree rebuild after setState
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('section header "Institute Notice Board & Circulars" is present',
        (tester) async {
      final repo = _FakeNoticeRepository();
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store);
      expect(find.textContaining('Notice Board'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows empty-state text when no notices', (tester) async {
      final repo = _FakeNoticeRepository();
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store);
      expect(find.textContaining('No notices'), findsOneWidget);
    });

    testWidgets('renders notice title when notices present', (tester) async {
      final repo = _FakeNoticeRepository();
      await repo.insert(_notice(title: 'Annual Prize Distribution'));
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store);
      expect(
          find.textContaining('Annual Prize Distribution'),
          findsAtLeastNWidgets(1));
    });

    testWidgets('pinned notice shows pin icon', (tester) async {
      final repo = _FakeNoticeRepository();
      await repo.insert(
          _notice(id: 'p1', title: 'Pinned Notice', isPinned: true));
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store);
      expect(find.byIcon(Icons.push_pin_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets(
        '"Publish Notice" button visible when user has noticeManage permission',
        (tester) async {
      final repo = _FakeNoticeRepository();
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store, grantNoticeManage: true);
      expect(find.textContaining('Publish Notice'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        '"Publish Notice" button hidden when user lacks noticeManage permission',
        (tester) async {
      final repo = _FakeNoticeRepository();
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store, grantNoticeManage: false);
      expect(find.textContaining('Publish Notice'), findsNothing);
    });

    testWidgets('tapping a notice opens the detail dialog with title and body',
        (tester) async {
      final repo = _FakeNoticeRepository();
      await repo.insert(_notice(
        id: 'n1',
        title: 'Test Circular',
        body: 'Full circular body text here.',
      ));
      final store = NoticeStore(repository: repo);
      await store.init();

      await pumpDashboard(tester, store);

      // The dashboard is a scrollable list; the notice card may be below the
      // visible viewport. Scroll until the notice title is visible.
      await tester.scrollUntilVisible(
        find.textContaining('Test Circular').first,
        200.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      await tester.tap(find.textContaining('Test Circular').first,
          warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Test Circular'), findsAtLeastNWidgets(1));
      expect(
          find.textContaining('Full circular body text here.'), findsOneWidget);
    });
  });
}
