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

  /// Schema version history:
  /// 1 — original schema
  /// 2 — teacher credentials
  /// 3 — UUID / sync metadata + departments, sessions, inventory, sync queue
  /// 4 — academic sessions, class year structure, subject-based attendance
  /// 5 — Supabase replication columns (institute_id, is_synced)
  static const int databaseVersion = 5;

  // Default seeded admin credentials (used on first launch only)
  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'Admin@123';
  static const String defaultAdminDisplayName = 'Administrator';
  static const String defaultAdminEmail = 'admin@institute.edu';

  /// Tenant id used for all local rows and Supabase payloads until a
  /// signed-in user's `institute_id` metadata overrides it.
  static const String defaultInstituteId = 'default_institute';

  /// SharedPreferences key holding the active institute (tenant) id.
  static const String prefInstituteId = 'pref_institute_id';
}

/// Academic departments supported at GILT.
///
/// The institute is organised by department → academic session → class → year.
/// It does **not** use a semester system.
enum AcademicDepartment {
  daeCit(
    'DAE-CIT',
    'Computer Information Technology',
    ['CIT'],
  ),
  daeLt(
    'DAE-LT',
    'Leather Technology',
    ['LT'],
  ),
  daeFw(
    'DAE-FW',
    'Footwear Technology',
    ['FW'],
  ),
  shortCourses(
    'SHORT-COURSES',
    'Vocational & Certificate Programs',
    <String>[],
  );

  const AcademicDepartment(this.code, this.title, this.classPrograms);

  final String code;
  final String title;

  /// Canonical class/program codes offered by this department
  /// (e.g. DAE-CIT teaches the [CIT] program).
  final List<String> classPrograms;

  static AcademicDepartment? fromCode(String code) {
    for (final d in AcademicDepartment.values) {
      if (d.code.toUpperCase() == code.toUpperCase()) return d;
    }
    return null;
  }
}

/// The academic years an institute class can run for.
///
/// `CIT` / `LT` / `FW` represent the class/program; `1st Year`, `2nd Year`
/// and `3rd Year` represent the student's current academic year. These are
/// **not** semesters.
class AcademicYears {
  AcademicYears._();

  static const String firstYear = '1st Year';
  static const String secondYear = '2nd Year';
  static const String thirdYear = '3rd Year';

  /// Standard year labels offered by GILT diploma programs.
  static const List<String> labels = <String>[
    firstYear,
    secondYear,
    thirdYear,
  ];

  static const String defaultValue = firstYear;

  /// Normalises a stored/legacy value into a canonical year label.
  ///
  /// Unknown or blank values fall back to [defaultValue].
  static String normalise(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return defaultValue;
    for (final label in labels) {
      if (label.toLowerCase() == trimmed.toLowerCase()) return label;
    }
    // Accept short forms like "1", "1st", "year 2", "2nd".
    final digit = RegExp(r'(\d)').firstMatch(trimmed)?.group(1);
    switch (digit) {
      case '1':
        return '1st Year';
      case '2':
        return '2nd Year';
      case '3':
        return '3rd Year';
      default:
        return defaultValue;
    }
  }
}

/// The type of a subject offering.
enum SubjectType {
  theory('THEORY', 'Theory'),
  practical('PRACTICAL', 'Practical'),
  both('BOTH', 'Theory & Practical');

  const SubjectType(this.code, this.label);

  final String code;
  final String label;

  static SubjectType fromString(String? value) {
    final raw = value?.trim().toUpperCase() ?? '';
    for (final type in SubjectType.values) {
      if (type.code == raw || type.name.toUpperCase() == raw) return type;
    }
    return SubjectType.theory;
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
