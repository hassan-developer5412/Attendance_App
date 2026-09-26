/// Centralized constants used across the Attendance Management System.
class AppConstants {
  AppConstants._();

  static const String appName = 'Institute Attendance';

  // SharedPreferences keys
  static const String prefUserId = 'pref_user_id';
  static const String prefUserRole = 'pref_user_role';

  // Business rules
  /// Students or teachers checking in after this time are marked as "late".
  static const int lateHour = 9;
  static const int lateMinute = 30;

  // Database
  static const String databaseName = 'attendance_app.db';
  static const int databaseVersion = 2;

  // Default seeded admin credentials (used on first launch only)
  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'Admin@123';
  static const String defaultAdminDisplayName = 'Administrator';
  static const String defaultAdminEmail = 'admin@institute.edu';
}

/// The role a user can have inside the app.
enum UserRole {
  admin,
  teacher,
  student;

  String get value => name;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => UserRole.teacher,
    );
  }
}

/// The daily attendance status for a given record.
enum AttendanceStatus {
  present,
  late,
  absent,
  leave;

  String get value => name;

  static AttendanceStatus fromString(String value) {
    return AttendanceStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => AttendanceStatus.absent,
    );
  }

  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
        return 'Leave';
    }
  }
}