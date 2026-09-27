import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';


/// A class (section) in the school or institute.
class SchoolClass {
  SchoolClass({
    required this.id,
    String? uuid,
    required this.name,
    required this.section,
    required this.room,
    this.departmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : uuid = uuid ?? UuidUtils.deterministic('classes', id),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final int id;
  final String uuid;
  String name;
  String section;
  String room;
  String? departmentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  String get displayName {
    if (section.trim().isEmpty) return name;
    return '$name — $section';
  }

  /// Creates a [SchoolClass] from a database row map.
  factory SchoolClass.fromMap(Map<String, dynamic> map) {
    return SchoolClass(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse(map['id'].toString()) ?? 0,
      uuid: map['uuid']?.toString(),
      name: map['name'] as String,
      section: (map['section'] as String?) ?? '',
      room: (map['room'] as String?) ?? '',
      departmentId: map['department_id']?.toString(),
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
      'uuid': uuid,
      'name': name,
      'section': section,
      'room': room,
      'department_id': departmentId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// Server representation for future REST API.
  Map<String, dynamic> toServerJson() {
    return {
      'id': uuid,
      'name': name,
      'section': section,
      'room': room,
      'department_id': departmentId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  SchoolClass copyWith({
    int? id,
    String? uuid,
    String? name,
    String? section,
    String? room,
    String? departmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return SchoolClass(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      section: section ?? this.section,
      room: room ?? this.room,
      departmentId: departmentId ?? this.departmentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// A teacher on the institute staff (maps to canonical faculty concept).
class Teacher {
  Teacher({
    required this.id,
    String? uuid,
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
  })  : uuid = uuid ?? UuidUtils.deterministic('teachers', id),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final int id;
  final String uuid;
  String name;
  String subject;
  String email;
  String username;
  String password;
  int? classId;
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
    final rawId = map['id'];
    final idInt = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
    return Teacher(
      id: idInt,
      uuid: map['uuid']?.toString(),
      name: (map['name'] as String?) ?? (map['full_name'] as String?) ?? '',
      subject: (map['subject'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      classId: map['class_id'] is int
          ? map['class_id'] as int
          : (map['class_id'] != null
              ? int.tryParse(map['class_id'].toString())
              : null),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      employeeCode: map['employee_code'] as String?,
      designation: (map['designation'] as String?) ?? 'Instructor',
      departmentId: map['department_id']?.toString(),
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
      'uuid': uuid,
      'name': name,
      'subject': subject,
      'email': email,
      'username': username,
      'password': password,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
      'employee_code': employeeCode ?? 'FAC-$id',
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
      'id': uuid,
      'employee_code': employeeCode ?? 'FAC-$id',
      'full_name': name,
      'designation': designation,
      'department_id': departmentId,
      'subject': subject,
      'email': email,
      'username': username,
      'class_id': classId != null ? UuidUtils.deterministic('classes', classId) : null,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  Teacher copyWith({
    int? id,
    String? uuid,
    String? name,
    String? subject,
    String? email,
    String? username,
    String? password,
    int? classId,
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
      uuid: uuid ?? this.uuid,
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

/// A student enrolled in a class or department at GILT.
class Student {
  Student({
    required this.id,
    String? uuid,
    required this.name,
    required this.rollNumber,
    required this.classId,
    this.isActive = true,
    this.registrationNo,
    this.fatherName = '',
    this.departmentId,
    this.currentSemester = '1st',
    this.status = 'ACTIVE',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : uuid = uuid ?? UuidUtils.deterministic('students', id),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final int id;
  final String uuid;
  String name;
  String rollNumber;
  int classId;
  bool isActive;

  // Canonical GILT student fields
  String? registrationNo;
  String fatherName;
  String? departmentId;
  String currentSemester;
  String status;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  String get initials => _initialsFrom(name);

  /// Creates a [Student] from a database row map.
  factory Student.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final idInt = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
    final rawClassId = map['class_id'];
    final classIdInt = rawClassId is int
        ? rawClassId
        : (rawClassId != null ? int.tryParse(rawClassId.toString()) ?? 0 : 0);

    return Student(
      id: idInt,
      uuid: map['uuid']?.toString(),
      name: (map['name'] as String?) ?? (map['full_name'] as String?) ?? '',
      rollNumber: (map['roll_number'] as String?) ?? (map['roll_no'] as String?) ?? '',
      classId: classIdInt,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      registrationNo: (map['registration_no'] as String?),
      fatherName: (map['father_name'] as String?) ?? '',
      departmentId: map['department_id']?.toString(),
      currentSemester: (map['current_semester'] as String?) ?? '1st',
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
      'uuid': uuid,
      'name': name,
      'roll_number': rollNumber,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
      'roll_no': rollNumber,
      'full_name': name,
      'registration_no': registrationNo ?? 'REG-$rollNumber',
      'father_name': fatherName,
      'department_id': departmentId,
      'current_semester': currentSemester,
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
      'id': uuid,
      'roll_no': rollNumber,
      'registration_no': registrationNo ?? 'REG-$rollNumber',
      'full_name': name,
      'father_name': fatherName,
      'department_id': departmentId,
      'current_semester': currentSemester,
      'status': status,
      'class_id': UuidUtils.deterministic('classes', classId),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  Student copyWith({
    int? id,
    String? uuid,
    String? name,
    String? rollNumber,
    int? classId,
    bool? isActive,
    String? registrationNo,
    String? fatherName,
    String? departmentId,
    String currentSemester = '1st',
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Student(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      rollNumber: rollNumber ?? this.rollNumber,
      classId: classId ?? this.classId,
      isActive: isActive ?? this.isActive,
      registrationNo: registrationNo ?? this.registrationNo,
      fatherName: fatherName ?? this.fatherName,
      departmentId: departmentId ?? this.departmentId,
      currentSemester: currentSemester,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// A subject taught in a class.
class Subject {
  Subject({
    required this.id,
    String? uuid,
    required this.name,
    required this.code,
    required this.teacherName,
    required this.classId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : uuid = uuid ?? UuidUtils.deterministic('subjects', id),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final int id;
  final String uuid;
  String name;
  String code;
  String teacherName;
  int classId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Creates a [Subject] from a database row map.
  factory Subject.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final idInt = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 0;
    final rawClassId = map['class_id'];
    final classIdInt = rawClassId is int
        ? rawClassId
        : (rawClassId != null ? int.tryParse(rawClassId.toString()) ?? 0 : 0);

    return Subject(
      id: idInt,
      uuid: map['uuid']?.toString(),
      name: (map['name'] as String?) ?? '',
      code: (map['code'] as String?) ?? '',
      teacherName: (map['teacher_name'] as String?) ?? '',
      classId: classIdInt,
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
      'uuid': uuid,
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': classId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// REST API JSON format
  Map<String, dynamic> toServerJson() {
    return {
      'id': uuid,
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': UuidUtils.deterministic('classes', classId),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  Subject copyWith({
    int? id,
    String? uuid,
    String? name,
    String? code,
    String? teacherName,
    int? classId,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return Subject(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      code: code ?? this.code,
      teacherName: teacherName ?? this.teacherName,
      classId: classId ?? this.classId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

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
