import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/user_store.dart';
import 'package:attendance_app/core/theme/theme_notifier.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/main.dart';

void main() {
  group('LoginScreen Widget Tests (no DB)', () {
    testWidgets(
        'App starts with LoginScreen as the initial screen with identifier field',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text('Sign in to manage institute attendance'), findsOneWidget);

      final identifierField = tester.widget<TextFormField>(
        find.byKey(const Key('identifierField')),
      );
      final passwordField = tester.widget<TextFormField>(
        find.byKey(const Key('passwordField')),
      );

      expect(identifierField.controller?.text, isEmpty);
      expect(passwordField.controller?.text, isEmpty);
    });

    testWidgets('Identifier field accepts roll number input',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      final identifierField = find.byKey(const Key('identifierField'));

      await tester.enterText(identifierField, 'CIT-2025-001');
      final controller = tester.widget<TextFormField>(identifierField).controller;
      expect(controller?.text, equals('CIT-2025-001'));
    });

    testWidgets('Identifier field accepts employee ID input',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      final identifierField = find.byKey(const Key('identifierField'));

      await tester.enterText(identifierField, 'EMP-10042');
      final controller = tester.widget<TextFormField>(identifierField).controller;
      expect(controller?.text, equals('EMP-10042'));
    });

    testWidgets('Password visibility toggle toggles obscureText',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
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

    testWidgets('Forgot password opens recovery dialog with email field',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      // Dialog opens on email entry step (stage 0).
      await tester.tap(find.byKey(const Key('forgotPasswordButton')));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsAtLeastNWidgets(1));
      expect(find.text('Enter the email address of your account.'), findsOneWidget);
    });

    testWidgets(
        'Quick dev sign-in section shows one button per role in debug mode',
        (tester) async {
      final app = AttendanceApp(
        authStore: AuthStore(),
        instituteStore: InstituteStore(),
        attendanceStore: AttendanceStore(),
        leaveStore: LeaveStore(),
        rbacStore: RBACStore(),
        userStore: UserStore(),
        themeNotifier: ThemeNotifier(),
      );

      await tester.pumpWidget(app);
      await tester.pump();

      final devRoleCodes = <String>[
        'admin',
        'principal',
        'vice_principal',
        'hod',
        'teacher',
        'student',
        'parent',
        'accountant',
        'lab_in_charge',
        'assistant',
      ];

      // One compact quick-login button per predefined role.
      expect(find.byType(OutlinedButton), findsNWidgets(devRoleCodes.length));
      for (final code in devRoleCodes) {
        expect(
          find.byKey(Key('devBypassButton_$code')),
          findsOneWidget,
          reason: 'Missing quick-login button for role $code',
        );
      }
    });
  });
}
