/// A class (section) in the school or institute.
class SchoolClass {
  SchoolClass({
    required this.id,
    required this.name,
    required this.section,
    required this.room,
  });

  final int id;
  String name;
  String section;
  String room;

  String get displayName {
    if (section.trim().isEmpty) return name;
    return '$name — $section';
  }

  /// Creates a [SchoolClass] from a database row map.
  factory SchoolClass.fromMap(Map<String, dynamic> map) {
    return SchoolClass(
      id: map['id'] as int,
      name: map['name'] as String,
      section: map['section'] as String,
      room: map['room'] as String,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'section': section,
      'room': room,
    };
  }
}

/// A teacher on the institute staff.
class Teacher {
  Teacher({
    required this.id,
    required this.name,
    required this.subject,
    this.email = '',
    this.username = '',
    this.password = '',
    this.classId,
    this.isActive = true,
  });

  final int id;
  String name;
  String subject;
  String email;
  String username;
  String password;
  int? classId;
  bool isActive;

  String get initials => _initialsFrom(name);

  /// Creates a [Teacher] from a database row map.
  factory Teacher.fromMap(Map<String, dynamic> map) {
    return Teacher(
      id: map['id'] as int,
      name: map['name'] as String,
      subject: map['subject'] as String,
      email: (map['email'] as String?) ?? '',
      username: (map['username'] as String?) ?? '',
      password: (map['password'] as String?) ?? '',
      classId: map['class_id'] as int?,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'subject': subject,
      'email': email,
      'username': username,
      'password': password,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
    };
  }
}

/// A student enrolled in a class.
class Student {
  Student({
    required this.id,
    required this.name,
    required this.rollNumber,
    required this.classId,
    this.isActive = true,
  });

  final int id;
  String name;
  String rollNumber;
  int classId;
  bool isActive;

  String get initials => _initialsFrom(name);

  /// Creates a [Student] from a database row map.
  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int,
      name: map['name'] as String,
      rollNumber: map['roll_number'] as String,
      classId: map['class_id'] as int,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'roll_number': rollNumber,
      'class_id': classId,
      'is_active': isActive ? 1 : 0,
    };
  }
}

/// A subject taught in a class.
class Subject {
  Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.teacherName,
    required this.classId,
  });

  final int id;
  String name;
  String code;
  String teacherName;
  int classId;

  /// Creates a [Subject] from a database row map.
  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'] as int,
      name: map['name'] as String,
      code: map['code'] as String,
      teacherName: map['teacher_name'] as String,
      classId: map['class_id'] as int,
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'teacher_name': teacherName,
      'class_id': classId,
    };
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
