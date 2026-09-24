import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/features/dashboard/presentation/pages/leave_content.dart';

void main() {
  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: Scaffold(
        body: LeaveContent(),
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

    testWidgets('displays summary row with Pending (3), Approved (8), Rejected (1)',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pending (3)'), findsOneWidget);
      expect(find.text('Approved (8)'), findsOneWidget);
      expect(find.text('Rejected (1)'), findsOneWidget);
    });

    testWidgets('displays sample leave requests with details and chips',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Sophia Chen'), findsOneWidget);
      expect(find.text('Marcus Vance'), findsOneWidget);

      // Status and leave type chips
      expect(find.text('Sick'), findsWidgets);
      expect(find.text('Casual'), findsWidgets);
      expect(find.text('Annual'), findsWidgets);

      // Pending action buttons
      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Reject'), findsWidgets);
    });

    testWidgets('tapping Approve on a pending request updates status and counts',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Initially Pending (3) and Approved (8)
      expect(find.text('Pending (3)'), findsOneWidget);
      expect(find.text('Approved (8)'), findsOneWidget);

      // Tap first Approve button
      await tester.tap(find.text('Approve').first);
      await tester.pumpAndSettle();

      // Counts should update to Pending (2) and Approved (9)
      expect(find.text('Pending (2)'), findsOneWidget);
      expect(find.text('Approved (9)'), findsOneWidget);

      // SnackBar should be displayed
      expect(find.textContaining('approved'), findsOneWidget);
    });

    testWidgets('tapping Reject on a pending request updates status and counts',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Initially Pending (3) and Rejected (1)
      expect(find.text('Pending (3)'), findsOneWidget);
      expect(find.text('Rejected (1)'), findsOneWidget);

      // Tap first Reject button
      await tester.tap(find.text('Reject').first);
      await tester.pumpAndSettle();

      // Counts should update to Pending (2) and Rejected (2)
      expect(find.text('Pending (2)'), findsOneWidget);
      expect(find.text('Rejected (2)'), findsOneWidget);

      // SnackBar should be displayed
      expect(find.textContaining('rejected'), findsOneWidget);
    });

    testWidgets('opening Apply Leave dialog and submitting creates a request',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Apply Leave
      await tester.tap(find.text('Apply Leave'));
      await tester.pumpAndSettle();

      // Dialog is shown with fields
      expect(find.text('Leave Type'), findsOneWidget);
      expect(find.text('Start Date'), findsOneWidget);
      expect(find.text('End Date'), findsOneWidget);
      expect(find.text('Reason'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);

      // Fill reason
      await tester.enterText(
          find.widgetWithText(TextField, 'Enter reason for leave...'),
          'Doctor appointment');

      // Submit
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // SnackBar shown
      expect(find.text('Leave request submitted'), findsOneWidget);

      // Pending count incremented from 3 to 4
      expect(find.text('Pending (4)'), findsOneWidget);
    });
  });
}
