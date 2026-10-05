import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/main.dart';

void main() {
  group('LoginScreen Widget Tests (no DB)', () {
    testWidgets(
        'App starts with LoginScreen as the initial screen with default credentials',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Sign in to manage institute attendance'), findsOneWidget);

      final usernameField = tester.widget<TextFormField>(
        find.byKey(const Key('usernameField')),
      );
      final passwordField = tester.widget<TextFormField>(
        find.byKey(const Key('passwordField')),
      );

      expect(usernameField.controller?.text,
          equals(AppConstants.defaultAdminUsername));
      expect(passwordField.controller?.text,
          equals(AppConstants.defaultAdminPassword));
    });

    testWidgets('Password visibility toggle toggles obscureText',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      final editableTextFinder = find.descendant(
        of: find.byKey(const Key('passwordField')),
        matching: find.byType(EditableText),
      );
      EditableText editableText =
          tester.widget<EditableText>(editableTextFinder);
      expect(editableText.obscureText, isTrue);

      await tester.tap(find.byKey(const Key('togglePasswordVisibility')));
      await tester.pump();

      editableText = tester.widget<EditableText>(editableTextFinder);
      expect(editableText.obscureText, isFalse);
    });
  });
}
