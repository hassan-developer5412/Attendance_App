import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

export 'academic_session.dart';
export 'department.dart';

/// Returns true when the string is a plain integer (legacy INTEGER PK).
bool _looksLikeInteger(String s) => RegExp(r'^\d+$').hasMatch(s);

/// Resolves a raw map value that may be either an integer (legacy) or a UUID
/// string (v6) into a canonical UUID string. Returns null when the value is
/// absent or an empty-string equivalent.
String? _resolveId(dynamic raw, String namespace) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty || s == '0' || s == 'null') return null;
  if (_looksLikeInteger(s)) return UuidUtils.deterministic(namespace, s);
  return s;
}

// ─────────────────────────────────────────────────────────────────────────────
// SchoolClass
// ─────────────────────────────────────────────────────────────────────────────

/// A class offering at GILT — a class/program (e.g. `CIT`) running for a
/// specific academic [currentYear] (e.g. `3rd Year`) inside a department and
/// an academic session.
///
/// The display label is generated as `<className>-<currentYear>`, e.g.
/// `CIT-3rd Year`. This is **not** a semester.
class SchoolClass {
  SchoolClass({
    String? id,
    required this.name,
    required this.section,
    required this.room,
    this.departmentId,
    this.academicSessionId,
    String? className,
    String? currentYear,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        className = className ?? name,
        currentYear = currentYear ?? '',
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;
  String section;
  String room;
  String? departmentId;
  String? academicSessionId;

  /// Class/program code, e.g. `CIT`, `LT`, `FW`.
  String className;

  /// The current academic year of this class, e.g. `3rd Year`.
  String currentYear;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Human-readable class label: `<className>-<currentYear>`.
  String get displayName {
    final cls = className.trim();
    final year = currentYear.trim();
    if (cls.isNotEmpty && year.isNotEmpty) return '$cls-$year';
    final base = name.trim().isNotEmpty ? name.trim() : cls;
    if (base.isEmpty) return 'Unnamed class';
    if (section.trim().isEmpty) return base;
    return '$base — ${section.trim()}';
  }

  /// Creates a [SchoolClass] from a database row map.
  ///
  /// Handles both the old schema (integer id + uuid column) and the new v6
  /// schema (TEXT uuid as id).
  factory SchoolClass.fromMap(Map<String, dynamic> map) {
    // v6: id is already a UUID string; v5: uuid column holds the canonical id.
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInteger(rawUuid))
        ? rawUuid
        : (rawId != null && !_looksLikeInteger(rawId))
            ? rawId
            : UuidUtils.deterministic('classes', rawId ?? '0');

    return SchoolClass(
      id: canonicalId,
      name: map['name'] as String,
      section: (map['section'] as String?) ?? '',
      room: (map['room'] as String?) ?? '',
      departmentId: _resolveId(map['department_id'], 'departments'),
      academicSessionId: _resolveId(map['academic_session_id'], 'academic_sessions'),
      className: map['class_name']?.toString(),
      currentYear: map['current_year']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'section': section,
      'room': room,
      'class_name': className,
      'current_year': currentYear,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Server representation for REST API.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'name': name,
      'section': section,
      'room': room,
      'class_name': className,
      'current_year': currentYear,
      'display_name': displayName,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  /// Supabase replication payload.
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'name': name,
      'section': section,
      'room': room,
      'class_name': className,
      'current_year': currentYear,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  SchoolClass copyWith({
    String? id,
    String? name,
    String? section,
    String? room,
    String? departmentId,
    String? academicSessionId,
    String? className,
    String? currentYear,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return SchoolClass(
      id: id ?? this.id,
      name: name ?? this.name,
      section: section ?? this.section,
      room: room ?? this.room,
      departmentId: departmentId ?? this.departmentId,
      academicSessionId: academicSessionId ?? this.academicSessionId,
      className: className ?? this.className,
      currentYear: currentYear ?? this.currentYear,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Teacher
// ─────────────────────────────────────────────────────────────────────────────

/// A teacher on the institute staff (maps to canonical faculty concept).
class Teacher {
  Teacher({
    String? id,
    required this.name,
    required this.subject,
    this.email = '',
    this.username = '',
    this.password = '',
    this.classId,
    this.isActive = true,
    this.employeeCode,
    this.designation = 'Instructor',
    this.departmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;
  String subject;
  String email;
  String username;
  String password;

  /// UUID of the class this teacher is primarily assigned to (nullable).
  String? classId;
  bool isActive;

  // Canonical faculty fields
  String? employeeCode;
  String designation;
  String? departmentId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  String get initials => _initialsFrom(name);

  /// Creates a [Teacher] from a database row map.
  factory Teacher.fromMap(Map<String, dynamic> map) {
    // v6: id is already a UUID; v5: uuid column holds canonical id.
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInteger(rawUuid))
        ? rawUuid
        : (rawId != null && !_looksLikeInteger(rawId))
            ? rawId
            : UuidUtils.deterministic('teachers', rawId ?? '0');

    return Teacher(
      id: canonicalId,
      name: (map['name'] as String?) ?? (map['full_name'] as String?) ?? '',
      subject: (map['subject'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      classId: _resolveId(map['class_id'], 'classes'),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      employeeCode: map['employee_code'] as String?,
      designation: (map['designation'] as String?) ?? 'Instructor',
      departmentId: _resolveId(map['department_id'], 'departments'),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject': subject,
      'email': email,
      'username': username,
      'password': password,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
      'employee_code': employeeCode ?? 'FAC-${id.substring(0, 8)}',
      'designation': designation,
      'department_id': departmentId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Canonical faculty representation for REST API.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'employee_code': employeeCode ?? 'FAC-${id.substring(0, 8)}',
      'full_name': name,
      'designation': designation,
      'department_id': departmentId,
      'subject': subject,
      'email': email,
      'username': username,
      'class_id': classId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  /// Supabase replication payload.
  /// The local `password` column is **never** included.
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'name': name,
      'subject': subject,
      'email': email,
      'username': username,
      'class_id': classId,
      'is_active': isActive,
      'employee_code': employeeCode ?? 'FAC-${id.substring(0, 8)}',
      'designation': designation,
      'department_id': departmentId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  Teacher copyWith({
    String? id,
    String? name,
    String? subject,
    String? email,
    String? username,
    String? password,
    String? classId,
    bool? isActive,
    String? employeeCode,
    String? designation,
    String? departmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Teacher(
      id: id ?? this.id,
      name: name ?? this.name,
      subject: subject ?? this.subject,
      email: email ?? this.email,
      username: username ?? this.username,
      password: password ?? this.password,
      classId: classId ?? this.classId,
      isActive: isActive ?? this.isActive,
      employeeCode: employeeCode ?? this.employeeCode,
      designation: designation ?? this.designation,
      departmentId: departmentId ?? this.departmentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student
// ─────────────────────────────────────────────────────────────────────────────

/// A student enrolled in a class or department at GILT.
class Student {
  Student({
    String? id,
    required this.name,
    required this.rollNumber,
    required this.classId,
    this.isActive = true,
    this.registrationNo,
    this.fatherName = '',
    this.departmentId,
    this.academicSessionId,
    String? currentYear,
    this.status = 'ACTIVE',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        currentYear = currentYear ?? AcademicYears.defaultValue,
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;

  /// UUID of the class this student belongs to.
  String classId;

  String name;
  String rollNumber;
  bool isActive;

  // Canonical GILT student fields
  String? registrationNo;
  String fatherName;
  String? departmentId;
  String? academicSessionId;

  /// The student's current academic year, e.g. `3rd Year`.
  String currentYear;
  String status;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  String get initials => _initialsFrom(name);

  /// Creates a [Student] from a database row map.
  factory Student.fromMap(Map<String, dynamic> map) {
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInteger(rawUuid))
        ? rawUuid
        : (rawId != null && !_looksLikeInteger(rawId))
            ? rawId
            : UuidUtils.deterministic('students', rawId ?? '0');

    // class_id may be integer (v5) or UUID (v6).
    final classId = _resolveId(map['class_id'], 'classes') ?? '';

    return Student(
      id: canonicalId,
      name: (map['name'] as String?) ?? (map['full_name'] as String?) ?? '',
      rollNumber: (map['roll_number'] as String?) ?? (map['roll_no'] as String?) ?? '',
      classId: classId,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      registrationNo: (map['registration_no'] as String?),
      fatherName: (map['father_name'] as String?) ?? '',
      departmentId: _resolveId(map['department_id'], 'departments'),
      academicSessionId: _resolveId(map['academic_session_id'], 'academic_sessions'),
      currentYear: AcademicYears.normalise(map['current_year'] as String?),
      status: (map['status'] as String?) ?? 'ACTIVE',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'roll_number': rollNumber,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
      'roll_no': rollNumber,
      'full_name': name,
      'registration_no': registrationNo ?? 'REG-$rollNumber',
      'father_name': fatherName,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'current_year': currentYear,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Canonical REST API representation.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'roll_no': rollNumber,
      'registration_no': registrationNo ?? 'REG-$rollNumber',
      'full_name': name,
      'father_name': fatherName,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'current_year': currentYear,
      'status': status,
      'class_id': classId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  /// Supabase replication payload.
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'name': name,
      'roll_number': rollNumber,
      'class_id': classId.isEmpty ? null : classId,
      'is_active': isActive,
      'registration_no': registrationNo ?? 'REG-$rollNumber',
      'father_name': fatherName,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'current_year': currentYear,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  Student copyWith({
    String? id,
    String? name,
    String? rollNumber,
    String? classId,
    bool? isActive,
    String? registrationNo,
    String? fatherName,
    String? departmentId,
    String? academicSessionId,
    String? currentYear,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      rollNumber: rollNumber ?? this.rollNumber,
      classId: classId ?? this.classId,
      isActive: isActive ?? this.isActive,
      registrationNo: registrationNo ?? this.registrationNo,
      fatherName: fatherName ?? this.fatherName,
      departmentId: departmentId ?? this.departmentId,
      academicSessionId: academicSessionId ?? this.academicSessionId,
      currentYear: currentYear ?? this.currentYear,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subject
// ─────────────────────────────────────────────────────────────────────────────

/// A subject taught in a class for a specific academic year.
class Subject {
  Subject({
    String? id,
    required this.name,
    required this.code,
    required this.teacherName,
    required this.classId,
    this.departmentId,
    this.academicSessionId,
    this.year = '',
    this.subjectType = SubjectType.theory,
    this.contactHours = 0,
    this.teacherId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name;
  String code;
  String teacherName;

  /// UUID of the class this subject belongs to.
  String classId;

  String? departmentId;
  String? academicSessionId;

  /// Academic year this subject belongs to, e.g. `3rd Year`.
  String year;

  /// Theory / practical classification.
  SubjectType subjectType;

  /// Contact hours per week where applicable.
  double contactHours;

  double get contactHoursPerWeek => contactHours;

  /// UUID of the teacher assigned to this subject (nullable).
  String? teacherId;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Creates a [Subject] from a database row map.
  factory Subject.fromMap(Map<String, dynamic> map) {
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty && !_looksLikeInteger(rawUuid))
        ? rawUuid
        : (rawId != null && !_looksLikeInteger(rawId))
            ? rawId
            : UuidUtils.deterministic('subjects', rawId ?? '0');

    return Subject(
      id: canonicalId,
      name: (map['name'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      teacherName: (map['teacher_name'] as String?) ?? '',
      classId: _resolveId(map['class_id'], 'classes') ?? '',
      departmentId: _resolveId(map['department_id'], 'departments'),
      academicSessionId: _resolveId(map['academic_session_id'], 'academic_sessions'),
      year: (map['year'] as String?) ?? '',
      subjectType: SubjectType.fromString(map['subject_type'] as String?),
      contactHours: (map['contact_hours'] as num?)?.toDouble() ?? 0,
      teacherId: _resolveId(map['teacher_id'], 'teachers'),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': classId,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'year': year,
      'subject_type': subjectType.code,
      'contact_hours': contactHours,
      'teacher_id': teacherId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// REST API JSON format.
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': classId,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'year': year,
      'subject_type': subjectType.code,
      'contact_hours': contactHours,
      'teacher_id': teacherId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  /// Supabase replication payload.
  /// `institute_id` is stamped centrally by `SyncService` at send time.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': classId.isEmpty ? null : classId,
      'department_id': departmentId,
      'academic_session_id': academicSessionId,
      'year': year,
      'subject_type': subjectType.code,
      'contact_hours': contactHours,
      'teacher_id': teacherId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  Subject copyWith({
    String? id,
    String? name,
    String? code,
    String? teacherName,
    String? classId,
    String? departmentId,
    String? academicSessionId,
    String? year,
    SubjectType? subjectType,
    double? contactHours,
    String? teacherId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      teacherName: teacherName ?? this.teacherName,
      classId: classId ?? this.classId,
      departmentId: departmentId ?? this.departmentId,
      academicSessionId: academicSessionId ?? this.academicSessionId,
      year: year ?? this.year,
      subjectType: subjectType ?? this.subjectType,
      contactHours: contactHours ?? this.contactHours,
      teacherId: teacherId ?? this.teacherId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

String _initialsFrom(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts[0].isNotEmpty) {
    return parts[0][0].toUpperCase();
  }
  return '';
}
