import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/institute_models.dart';

/// Directory of classes, teachers, and students backed by SQLite.
class InstituteStore extends ChangeNotifier {
  final List<SchoolClass> _classes = [];
  final List<Teacher> _teachers = [];
  final List<Student> _students = [];
  final List<Subject> _subjects = [];

  List<SchoolClass> get classes => List.unmodifiable(_classes);
  List<Teacher> get teachers => List.unmodifiable(_teachers);
  List<Student> get students => List.unmodifiable(_students);
  List<Subject> get subjects => List.unmodifiable(_subjects);

  int get teacherCount => _teachers.length;
  int get studentCount => _students.length;
  int get classCount => _classes.length;
  int get activeTeacherCount => _teachers.where((t) => t.isActive).length;
  int get activeStudentCount => _students.where((s) => s.isActive).length;

  /// Loads all data from the database. Call once during app startup.
  Future<void> init() async {
    final db = await DatabaseHelper.instance.database;

    final classRows = await db.query('classes', orderBy: 'id DESC');
    _classes
      ..clear()
      ..addAll(classRows.map(SchoolClass.fromMap));

    final teacherRows = await db.query('teachers', orderBy: 'id DESC');
    _teachers
      ..clear()
      ..addAll(teacherRows.map(Teacher.fromMap));

    final studentRows = await db.query('students', orderBy: 'id DESC');
    _students
      ..clear()
      ..addAll(studentRows.map(Student.fromMap));

    final subjectRows = await db.query('subjects', orderBy: 'id DESC');
    _subjects
      ..clear()
      ..addAll(subjectRows.map(Subject.fromMap));

    notifyListeners();
  }

  SchoolClass? classById(int? id) {
    if (id == null) return null;
    for (final item in _classes) {
      if (item.id == id) return item;
    }
    return null;
  }

  String classLabel(int? classId) {
    return classById(classId)?.displayName ?? 'Unassigned';
  }

  // ---------------------------------------------------------------------------
  // Classes
  // ---------------------------------------------------------------------------

  Future<void> addClass({
    required String name,
    required String section,
    required String room,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('classes', {
      'name': name.trim(),
      'section': section.trim(),
      'room': room.trim(),
    });
    _classes.insert(
      0,
      SchoolClass(
        id: id,
        name: name.trim(),
        section: section.trim(),
        room: room.trim(),
      ),
    );
    notifyListeners();
  }

  Future<void> deleteClass(int id) async {
    final db = await DatabaseHelper.instance.database;
    // Foreign keys handle cascading deletes for students and SET NULL for teachers.
    await db.delete('classes', where: 'id = ?', whereArgs: [id]);
    _classes.removeWhere((item) => item.id == id);
    for (final teacher in _teachers) {
      if (teacher.classId == id) {
        teacher.classId = null;
      }
    }
    _students.removeWhere((student) => student.classId == id);
    _subjects.removeWhere((subject) => subject.classId == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Teachers
  // ---------------------------------------------------------------------------

  /// Returns all subjects sorted with unassigned ones first, then by name.
  List<Subject> get subjectsSortedByAssignment {
    final sorted = List<Subject>.from(_subjects);
    sorted.sort((a, b) {
      final aUnassigned =
          a.teacherName == 'Unassigned' || a.teacherName.trim().isEmpty;
      final bUnassigned =
          b.teacherName == 'Unassigned' || b.teacherName.trim().isEmpty;
      if (aUnassigned && !bUnassigned) return -1;
      if (!aUnassigned && bUnassigned) return 1;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  Future<void> addTeacher({
    required String name,
    required String email,
    required String username,
    required String password,
    required List<int> subjectIds,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Derive a comma-separated subject label from the selected IDs.
    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel =
        selected.isEmpty ? '' : selected.map((s) => '${s.name} (${s.code})').join(', ');

    final id = await db.insert('teachers', {
      'name': name.trim(),
      'subject': subjectLabel,
      'email': email.trim(),
      'username': username.trim(),
      'password': password.trim(),
      'is_active': 1,
    });

    // Mark selected subjects as assigned to this teacher.
    for (final subject in selected) {
      await db.update(
        'subjects',
        {'teacher_name': name.trim()},
        where: 'id = ?',
        whereArgs: [subject.id],
      );
      subject.teacherName = name.trim();
    }

    _teachers.insert(
      0,
      Teacher(
        id: id,
        name: name.trim(),
        subject: subjectLabel,
        email: email.trim(),
        username: username.trim(),
        password: password.trim(),
      ),
    );
    notifyListeners();
  }

  Future<void> deleteTeacher(int id) async {
    final db = await DatabaseHelper.instance.database;

    // Find the teacher so we can unassign their subjects.
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      await db.update(
        'subjects',
        {'teacher_name': 'Unassigned'},
        where: 'teacher_name = ?',
        whereArgs: [teacher.name],
      );
      for (final subject in _subjects) {
        if (subject.teacherName == teacher.name) {
          subject.teacherName = 'Unassigned';
        }
      }
    }

    await db.delete('teachers', where: 'id = ?', whereArgs: [id]);
    _teachers.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  Future<void> updateTeacher({
    required int id,
    required String name,
    required String email,
    required String username,
    required String password,
    required List<int> subjectIds,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // Find the existing teacher to un-assign old subjects.
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      // Un-assign subjects previously belonging to this teacher.
      await db.update(
        'subjects',
        {'teacher_name': 'Unassigned'},
        where: 'teacher_name = ?',
        whereArgs: [teacher.name],
      );
      for (final subject in _subjects) {
        if (subject.teacherName == teacher.name) {
          subject.teacherName = 'Unassigned';
        }
      }
    }

    // Derive a comma-separated subject label (with codes) from the selected IDs.
    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel =
        selected.isEmpty ? '' : selected.map((s) => '${s.name} (${s.code})').join(', ');

    // Update the database row.
    await db.update(
      'teachers',
      {
        'name': name.trim(),
        'subject': subjectLabel,
        'email': email.trim(),
        'username': username.trim(),
        'password': password.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    // Mark selected subjects as assigned to this teacher.
    for (final subject in selected) {
      await db.update(
        'subjects',
        {'teacher_name': name.trim()},
        where: 'id = ?',
        whereArgs: [subject.id],
      );
      subject.teacherName = name.trim();
    }

    // Update the in-memory teacher object.
    if (teacher != null) {
      teacher.name = name.trim();
      teacher.subject = subjectLabel;
      teacher.email = email.trim();
      teacher.username = username.trim();
      teacher.password = password.trim();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Students
  // ---------------------------------------------------------------------------

  Future<void> addStudent({
    required String name,
    required String rollNumber,
    required int classId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('students', {
      'name': name.trim(),
      'roll_number': rollNumber.trim(),
      'class_id': classId,
      'is_active': 1,
    });
    _students.insert(
      0,
      Student(
        id: id,
        name: name.trim(),
        rollNumber: rollNumber.trim(),
        classId: classId,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteStudent(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('students', where: 'id = ?', whereArgs: [id]);
    _students.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Subjects
  // ---------------------------------------------------------------------------

  List<Subject> subjectsForClass(int classId) {
    return _subjects.where((s) => s.classId == classId).toList();
  }

  Future<void> addSubject({
    required String name,
    required String code,
    required String teacherName,
    required int classId,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('subjects', {
      'name': name.trim(),
      'code': code.trim(),
      'teacher_name': teacherName.trim(),
      'class_id': classId,
    });
    _subjects.insert(
      0,
      Subject(
        id: id,
        name: name.trim(),
        code: code.trim(),
        teacherName: teacherName.trim(),
        classId: classId,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteSubject(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
    _subjects.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}
