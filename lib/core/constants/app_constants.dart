/// Centralized constants used across the Attendance Management System.
class AppConstants {
  AppConstants._();

  static const String appName = 'GILT Institute Management';
  static const String instituteFullName =
      'Govt. Institute of Leather Technology (GILT)';

  // SharedPreferences keys
  static const String prefUserId = 'pref_user_id';
  static const String prefUserRole = 'pref_user_role';

  // Business rules
  /// Students or teachers checking in after this time are marked as "late".
  static const int lateHour = 9;
  static const int lateMinute = 30;

  // Database
  static const String databaseName = 'attendance_app.db';
  static const int databaseVersion = 3;

  // Default seeded admin credentials (used on first launch only)
  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'Admin@123';
  static const String defaultAdminDisplayName = 'Administrator';
  static const String defaultAdminEmail = 'admin@institute.edu';
}

/// Academic departments supported at GILT.
enum AcademicDepartment {
  daeCit('DAE-CIT', 'Computer Information Technology'),
  daeLt('DAE-LT', 'Leather Technology'),
  daeFw('DAE-FW', 'Footwear Technology'),
  shortCourses('SHORT-COURSES', 'Vocational & Certificate Programs');

  const AcademicDepartment(this.code, this.title);

  final String code;
  final String title;

  static AcademicDepartment? fromCode(String code) {
    for (final d in AcademicDepartment.values) {
      if (d.code.toUpperCase() == code.toUpperCase()) return d;
    }
    return null;
  }
}

/// Synchronization status for offline-first replication.
enum SyncStatus {
  pending('PENDING'),
  synced('SYNCED'),
  failed('FAILED');

  const SyncStatus(this.value);

  final String value;

  static SyncStatus fromString(String? val) {
    if (val == null) return SyncStatus.pending;
    return SyncStatus.values.firstWhere(
      (s) => s.value == val.toUpperCase() || s.name == val.toLowerCase(),
      orElse: () => SyncStatus.pending,
    );
  }
}

/// Allowed lab inventory categories.
enum InventoryCategory {
  hardwareEquipment('HARDWARE_EQUIPMENT', 'Hardware / Equipment'),
  chemical('CHEMICAL', 'Chemical'),
  rawMaterial('RAW_MATERIAL', 'Raw Material'),
  machineryPart('MACHINERY_PART', 'Machinery Part');

  const InventoryCategory(this.code, this.label);

  final String code;
  final String label;

  static InventoryCategory fromString(String val) {
    for (final c in InventoryCategory.values) {
      if (c.code == val || c.name == val) return c;
    }
    return InventoryCategory.hardwareEquipment;
  }
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

  /// Returns canonical uppercase status for GILT backend schema: PRESENT, ABSENT, LATE, LEAVE
  String get serverValue => name.toUpperCase();

  static AttendanceStatus fromString(String value) {
    final lower = value.toLowerCase().trim();
    return AttendanceStatus.values.firstWhere(
      (status) => status.name == lower,
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
