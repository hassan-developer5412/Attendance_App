import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/leave_content.dart';

class _FakeLeaveRepo extends LeaveRepository {
  final List<LeaveRequest> items = [];

  @override
  Future<List<LeaveRequest>> getAll({bool includeDeleted = false}) async =>
      List.from(items);

  @override
  Future<LeaveRequest> insert(LeaveRequest request) async {
    items.insert(0, request);
    return request;
  }

  @override
  Future<void> updateStatus(String id, LeaveStatus newStatus) async {
    final idx = items.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      items[idx].status = newStatus;
    }
  }
}

void main() {
  late _FakeLeaveRepo fakeRepo;
  late LeaveStore leaveStore;
  late AuthStore authStore;

  setUp(() async {
    fakeRepo = _FakeLeaveRepo();
    final now = DateTime.now();

    fakeRepo.items.addAll([
      LeaveRequest(
        requesterName: 'Alex Morgan',
        leaveType: 'Sick Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 1)),
        reason: 'Flu symptoms',
        status: LeaveStatus.pending,
      ),
      LeaveRequest(
        requesterName: 'Sophia Chen',
        leaveType: 'Casual Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 2)),
        reason: 'Personal work',
        status: LeaveStatus.pending,
      ),
      LeaveRequest(
        requesterName: 'Marcus Vance',
        leaveType: 'Emergency Leave',
        startDate: now,
        endDate: now.add(const Duration(days: 3)),
        reason: 'Family emergency',
        status: LeaveStatus.pending,
      ),
      ...List.generate(
        8,
        (i) => LeaveRequest(
          requesterName: 'Approved Teacher $i',
          leaveType: 'Casual Leave',
          startDate: now,
          endDate: now,
          reason: 'Reason $i',
          status: LeaveStatus.approved,
        ),
      ),
      LeaveRequest(
        requesterName: 'Rejected Teacher',
        leaveType: 'Sick Leave',
        startDate: now,
        endDate: now,
        reason: 'Not eligible',
        status: LeaveStatus.rejected,
      ),
    ]);

    leaveStore = LeaveStore(repository: fakeRepo);
    await leaveStore.loadAll();

    authStore = AuthStore();
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LeaveStore>.value(value: leaveStore),
        ChangeNotifierProvider<AuthStore>.value(value: authStore),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: LeaveContent(),
        ),
      ),
    );
  }

  group('LeaveContent Widget Tests', () {
    testWidgets('displays header with title and Apply Leave button',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Leave Management'), findsOneWidget);
      expect(find.text('Apply Leave'), findsOneWidget);
    });

    testWidgets(
        'displays summary row with Pending: 3, Approved: 8, Rejected: 1',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pending: 3'), findsOneWidget);
      expect(find.text('Approved: 8'), findsOneWidget);
      expect(find.text('Rejected: 1'), findsOneWidget);
    });

    testWidgets('displays sample leave requests with details and chips',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Sophia Chen'), findsOneWidget);
      expect(find.text('Marcus Vance'), findsOneWidget);

      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Reject'), findsWidgets);
    });

    testWidgets(
        'tapping Approve on a pending request updates status and counts',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pending: 3'), findsOneWidget);
      expect(find.text('Approved: 8'), findsOneWidget);

      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();

      expect(find.text('Pending: 2'), findsOneWidget);
      expect(find.text('Approved: 9'), findsOneWidget);
    });

    testWidgets('tapping Reject on a pending request updates status and counts',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pending: 3'), findsOneWidget);
      expect(find.text('Rejected: 1'), findsOneWidget);

      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();

      expect(find.text('Pending: 2'), findsOneWidget);
      expect(find.text('Rejected: 2'), findsOneWidget);
    });

    testWidgets('opening Apply Leave dialog and submitting creates a request',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Apply Leave'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Requester name'),
          'Tariq Mehmood');

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Reason (optional)'),
          'Doctor appointment');

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Pending: 4'), findsOneWidget);
      expect(find.text('Tariq Mehmood'), findsOneWidget);
    });
  });
}
