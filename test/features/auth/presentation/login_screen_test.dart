import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/main.dart';

/// Creates an [AttendanceApp] with fully initialized stores for testing.
Future<AttendanceApp> buildTestApp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  await DatabaseHelper.instance.database;

  final authStore = AuthStore();
  await authStore.init();

  final instituteStore = InstituteStore();
  await instituteStore.init();

  final attendanceStore = AttendanceStore();

  final leaveStore = LeaveStore();
  await leaveStore.loadAll();

  return AttendanceApp(
    authStore: authStore,
    instituteStore: instituteStore,
    attendanceStore: attendanceStore,
    leaveStore: leaveStore,
  );
}

void main() {
  group('LoginScreen Widget Tests', () {
    testWidgets(
        'App starts with LoginScreen as the initial screen with default credentials',
        (tester) async {
      final app = await buildTestApp();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify LoginScreen is shown as the first screen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(
          find.text('Sign in to manage institute attendance'), findsOneWidget);

      // Verify default credentials prefilled
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
      final app = await buildTestApp();
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Initially password is obscured
      final editableTextFinder = find.descendant(
        of: find.byKey(const Key('passwordField')),
        matching: find.byType(EditableText),
      );
      EditableText editableText =
          tester.widget<EditableText>(editableTextFinder);
      expect(editableText.obscureText, isTrue);

      // Tap eye toggle
      await tester.tap(find.byKey(const Key('togglePasswordVisibility')));
      await tester.pumpAndSettle();

      // ObscureText should now be false
      editableText = tester.widget<EditableText>(editableTextFinder);
      expect(editableText.obscureText, isFalse);
    });
  });
}
