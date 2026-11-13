import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/schema_migration_v9.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
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

    test('devBypassLogin grants RBAC permissions to admin user', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});

      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        roll_no TEXT,
        employee_id TEXT UNIQUE,
        password_hash TEXT NOT NULL,
        display_name TEXT NOT NULL,
        email TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'admin',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        institute_id TEXT NOT NULL DEFAULT 'default_institute',
        is_synced INTEGER NOT NULL DEFAULT 0,
        auth_user_id TEXT,
        is_default_password INTEGER DEFAULT 0,
        is_suspended INTEGER DEFAULT 0,
        suspended_at TEXT,
        suspended_reason TEXT,
        failed_login_attempts INTEGER DEFAULT 0,
        locked_until TEXT,
        password_changed_at TEXT,
        last_login_at TEXT,
        session_expires_at TEXT
      )''');
      await SchemaMigrationV9.execute(db);

      final dbHelper = DatabaseHelper.forTesting(db);
      final rbacStore = RBACStore();
      final authStore = AuthStore(
        userRepository: UserRepository(dbHelper: dbHelper),
        secureStorage: FakeSecureStorage(),
        databaseHelper: dbHelper,
      );
      authStore.attachRbacStore(rbacStore);

      await authStore.devBypassLogin();

      expect(authStore.isLoggedIn, isTrue);
      expect(authStore.currentUserRole, equals(UserRole.admin));
      expect(rbacStore.isAuthenticated, isTrue);
      expect(rbacStore.hasPermission(PermissionCodes.dashboardView), isTrue);
      expect(rbacStore.hasPermission(PermissionCodes.attendanceView), isTrue);
      expect(rbacStore.hasPermission(PermissionCodes.userView), isTrue);
      expect(rbacStore.hasPermission(PermissionCodes.settingManage), isTrue);

      await db.close();
    });
  });
}
