import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/features/dashboard/presentation/dashboard_shell.dart';

void main() {
  group('DashboardShell RBAC Menu Access Policies', () {
    test('Student menu is restricted strictly to Schedule and My Attendance', () {
      final studentMenu = DashboardShell.getMenuIdsForRole(UserRole.student);

      expect(studentMenu, equals(['schedule', 'my_attendance']));
      expect(studentMenu.contains('dashboard'), isFalse);
      expect(studentMenu.contains('teachers'), isFalse);
      expect(studentMenu.contains('user_management'), isFalse);
      expect(studentMenu.contains('institute'), isFalse);
      expect(studentMenu.contains('settings'), isFalse);
    });

    test('Teacher menu contains instructional items and excludes User Management & Settings', () {
      final teacherMenu = DashboardShell.getMenuIdsForRole(UserRole.teacher);

      expect(teacherMenu.contains('dashboard'), isTrue);
      expect(teacherMenu.contains('attendance'), isTrue);
      expect(teacherMenu.contains('classes'), isTrue);
      expect(teacherMenu.contains('students'), isTrue);
      expect(teacherMenu.contains('leave'), isTrue);

      // Must NOT contain elevated management
      expect(teacherMenu.contains('user_management'), isFalse);
      expect(teacherMenu.contains('teachers'), isFalse);
      expect(teacherMenu.contains('reports'), isFalse);
      expect(teacherMenu.contains('institute'), isFalse);
      expect(teacherMenu.contains('settings'), isFalse);
    });

    test('HOD menu contains Departmental Management & User Management, but not Settings', () {
      final hodMenu = DashboardShell.getMenuIdsForRole(UserRole.hod);

      expect(hodMenu.contains('dashboard'), isTrue);
      expect(hodMenu.contains('attendance'), isTrue);
      expect(hodMenu.contains('classes'), isTrue);
      expect(hodMenu.contains('teachers'), isTrue);
      expect(hodMenu.contains('students'), isTrue);
      expect(hodMenu.contains('user_management'), isTrue);
      expect(hodMenu.contains('leave'), isTrue);
      expect(hodMenu.contains('reports'), isTrue);

      // Must NOT contain institute-wide configuration
      expect(hodMenu.contains('institute'), isFalse);
      expect(hodMenu.contains('settings'), isFalse);
    });

    test('Admin menu has full operational access including Institute & Settings', () {
      final adminMenu = DashboardShell.getMenuIdsForRole(UserRole.admin);

      expect(adminMenu.contains('dashboard'), isTrue);
      expect(adminMenu.contains('attendance'), isTrue);
      expect(adminMenu.contains('classes'), isTrue);
      expect(adminMenu.contains('teachers'), isTrue);
      expect(adminMenu.contains('students'), isTrue);
      expect(adminMenu.contains('user_management'), isTrue);
      expect(adminMenu.contains('leave'), isTrue);
      expect(adminMenu.contains('reports'), isTrue);
      expect(adminMenu.contains('institute'), isTrue);
      expect(adminMenu.contains('settings'), isTrue);
    });
  });
}
