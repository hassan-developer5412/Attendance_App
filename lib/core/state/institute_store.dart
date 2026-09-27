import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';

/// Directory of classes, teachers, and students backed by the SQLite repositories.
class InstituteStore extends ChangeNotifier {
  InstituteStore({
    ClassRepository? classRepository,
    FacultyRepository? facultyRepository,
    StudentRepository? studentRepository,
    SubjectRepository? subjectRepository,
  })  : _classRepository = classRepository ?? ClassRepository(),
        _facultyRepository = facultyRepository ?? FacultyRepository(),
        _studentRepository = studentRepository ?? StudentRepository(),
        _subjectRepository = subjectRepository ?? SubjectRepository();

  final ClassRepository _classRepository;
  final FacultyRepository _facultyRepository;
  final StudentRepository _studentRepository;
  final SubjectRepository _subjectRepository;

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
    _classes
      ..clear()
      ..addAll(await _classRepository.getAll());

    _teachers
      ..clear()
      ..addAll(await _facultyRepository.getAll());

    _students
      ..clear()
      ..addAll(await _studentRepository.getAll());

    _subjects
      ..clear()
      ..addAll(await _subjectRepository.getAll());

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
    final schoolClass = await _classRepository.insert(
      name: name,
      section: section,
      room: room,
    );
    _classes.insert(0, schoolClass);
    notifyListeners();
  }

  Future<void> deleteClass(int id) async {
    // The repository soft-deletes the class and cascades to its students,
    // subjects, and teacher assignments.
    await _classRepository.softDelete(id);
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
    // Derive a comma-separated subject label from the selected IDs.
    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel =
        selected.isEmpty ? '' : selected.map((s) => '${s.name} (${s.code})').join(', ');

    final teacher = await _facultyRepository.insert(
      name: name,
      subject: subjectLabel,
      email: email,
      username: username,
      password: password,
    );

    // Mark selected subjects as assigned to this teacher.
    for (final subject in selected) {
      subject.teacherName = name.trim();
      await _subjectRepository.update(subject);
    }

    _teachers.insert(0, teacher);
    notifyListeners();
  }

  Future<void> deleteTeacher(int id) async {
    // Find the teacher so we can unassign their subjects.
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      for (final subject in _subjects) {
        if (subject.teacherName == teacher.name) {
          subject.teacherName = 'Unassigned';
          await _subjectRepository.update(subject);
        }
      }
    }

    await _facultyRepository.softDelete(id);
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
    // Find the existing teacher to un-assign old subjects.
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      // Un-assign subjects previously belonging to this teacher.
      for (final subject in _subjects) {
        if (subject.teacherName == teacher.name) {
          subject.teacherName = 'Unassigned';
          await _subjectRepository.update(subject);
        }
      }
    }

    // Derive a comma-separated subject label (with codes) from the selected IDs.
    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel =
        selected.isEmpty ? '' : selected.map((s) => '${s.name} (${s.code})').join(', ');

    // Update the database row and the in-memory teacher object.
    if (teacher != null) {
      teacher.name = name.trim();
      teacher.subject = subjectLabel;
      teacher.email = email.trim();
      teacher.username = username.trim();
      teacher.password = password.trim();
      await _facultyRepository.update(teacher);
    }

    // Mark selected subjects as assigned to this teacher.
    for (final subject in selected) {
      subject.teacherName = name.trim();
      await _subjectRepository.update(subject);
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
    final student = await _studentRepository.insert(
      name: name,
      rollNumber: rollNumber,
      classId: classId,
    );
    _students.insert(0, student);
    notifyListeners();
  }

  Future<void> deleteStudent(int id) async {
    await _studentRepository.softDelete(id);
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
    final subject = await _subjectRepository.insert(
      name: name,
      code: code,
      teacherName: teacherName,
      classId: classId,
    );
    _subjects.insert(0, subject);
    notifyListeners();
  }

  Future<void> deleteSubject(int id) async {
    await _subjectRepository.softDelete(id);
    _subjects.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}
