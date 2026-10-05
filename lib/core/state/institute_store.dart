import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/academic_session_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/department_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';

/// Directory of departments, sessions, classes, teachers, students, and subjects
/// backed by SQLite repositories.
class InstituteStore extends ChangeNotifier {
  InstituteStore({
    ClassRepository? classRepository,
    FacultyRepository? facultyRepository,
    StudentRepository? studentRepository,
    SubjectRepository? subjectRepository,
    DepartmentRepository? departmentRepository,
    AcademicSessionRepository? academicSessionRepository,
  })  : _classRepository = classRepository ?? ClassRepository(),
        _facultyRepository = facultyRepository ?? FacultyRepository(),
        _studentRepository = studentRepository ?? StudentRepository(),
        _subjectRepository = subjectRepository ?? SubjectRepository(),
        _departmentRepository = departmentRepository ?? DepartmentRepository(),
        _academicSessionRepository =
            academicSessionRepository ?? AcademicSessionRepository();

  final ClassRepository _classRepository;
  final FacultyRepository _facultyRepository;
  final StudentRepository _studentRepository;
  final SubjectRepository _subjectRepository;
  final DepartmentRepository _departmentRepository;
  final AcademicSessionRepository _academicSessionRepository;

  final List<Department> _departments = [];
  final List<AcademicSession> _academicSessions = [];
  final List<SchoolClass> _classes = [];
  final List<Teacher> _teachers = [];
  final List<Student> _students = [];
  final List<Subject> _subjects = [];

  List<Department> get departments => List.unmodifiable(_departments);
  List<Department> get activeDepartments =>
      List.unmodifiable(_departments.where((d) => d.isActive && !d.isDeleted));
  List<AcademicSession> get academicSessions =>
      List.unmodifiable(_academicSessions);
  AcademicSession? get currentAcademicSession =>
      _academicSessions.where((s) => s.isCurrent && !s.isDeleted).firstOrNull ??
      _academicSessions.where((s) => !s.isDeleted).firstOrNull;

  List<SchoolClass> get classes => List.unmodifiable(_classes);
  List<Teacher> get teachers => List.unmodifiable(_teachers);
  List<Student> get students => List.unmodifiable(_students);
  List<Subject> get subjects => List.unmodifiable(_subjects);

  int get departmentCount => _departments.where((d) => !d.isDeleted).length;
  int get activeDepartmentCount =>
      _departments.where((d) => d.isActive && !d.isDeleted).length;
  int get teacherCount => _teachers.length;
  int get studentCount => _students.length;
  int get classCount => _classes.length;
  int get subjectCount => _subjects.length;
  int get activeTeacherCount => _teachers.where((t) => t.isActive).length;
  int get activeStudentCount => _students.where((s) => s.isActive).length;

  /// Loads all data from the database. Call once during app startup.
  Future<void> init() async {
    // 1. Departments
    var depts = await _departmentRepository.getAll();
    if (depts.isEmpty) {
      final db = await DatabaseHelper.instance.database;
      await MigrationHelpers.seedDepartments(db);
      depts = await _departmentRepository.getAll();
    }
    _departments
      ..clear()
      ..addAll(depts);

    // 2. Academic Sessions
    var sessions = await _academicSessionRepository.getAll();
    if (sessions.isEmpty) {
      final db = await DatabaseHelper.instance.database;
      await MigrationHelpers.seedAcademicSessions(db);
      sessions = await _academicSessionRepository.getAll();
    }
    _academicSessions
      ..clear()
      ..addAll(sessions);

    // 3. Classes
    _classes
      ..clear()
      ..addAll(await _classRepository.getAll());

    // 4. Teachers
    _teachers
      ..clear()
      ..addAll(await _facultyRepository.getAll());

    // 5. Students
    _students
      ..clear()
      ..addAll(await _studentRepository.getAll());

    // 6. Subjects
    _subjects
      ..clear()
      ..addAll(await _subjectRepository.getAll());

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Lookups & Helpers
  // ---------------------------------------------------------------------------

  Department? departmentById(String? id) {
    if (id == null || id.isEmpty) return null;
    return _departments.where((d) => d.id == id).firstOrNull;
  }

  Department? departmentByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final upper = code.toUpperCase();
    return _departments.where((d) => d.code.toUpperCase() == upper).firstOrNull;
  }

  String departmentName(String? id) {
    final dept = departmentById(id);
    return dept != null ? '${dept.code} — ${dept.name}' : 'General';
  }

  AcademicSession? academicSessionById(String? id) {
    if (id == null || id.isEmpty) return null;
    return _academicSessions.where((s) => s.id == id).firstOrNull;
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

  Subject? subjectById(int? id) {
    if (id == null) return null;
    return _subjects.where((s) => s.id == id).firstOrNull;
  }

  List<SchoolClass> classesForDepartment(String? departmentId) {
    if (departmentId == null || departmentId.isEmpty) return _classes;
    return _classes.where((c) => c.departmentId == departmentId).toList();
  }

  List<SchoolClass> classesForContext({
    String? departmentId,
    String? academicSessionId,
  }) {
    return _classes.where((c) {
      if (departmentId != null &&
          departmentId.isNotEmpty &&
          c.departmentId != departmentId) {
        return false;
      }
      if (academicSessionId != null &&
          academicSessionId.isNotEmpty &&
          c.academicSessionId != academicSessionId) {
        return false;
      }
      return true;
    }).toList();
  }

  List<Subject> subjectsForClass(int classId) {
    return _subjects.where((s) => s.classId == classId).toList();
  }

  List<Subject> subjectsForClassAndYear(int classId, String year) {
    final normYear = AcademicYears.normalise(year);
    return _subjects
        .where((s) => s.classId == classId && (s.year.isEmpty || AcademicYears.normalise(s.year) == normYear))
        .toList();
  }

  List<Subject> subjectsForTeacher(int teacherId) {
    return _subjects.where((s) => s.teacherId == teacherId).toList();
  }

  List<SchoolClass> classesForTeacher(int teacherId) {
    final classIds = _subjects
        .where((s) => s.teacherId == teacherId)
        .map((s) => s.classId)
        .toSet();
    return _classes.where((c) => classIds.contains(c.id)).toList();
  }

  List<Student> studentsForClass(int classId) {
    return _students.where((s) => s.classId == classId).toList();
  }

  List<Student> studentsForClassAndYear(int classId, String year) {
    final normYear = AcademicYears.normalise(year);
    return _students
        .where((s) => s.classId == classId && (s.currentYear.isEmpty || AcademicYears.normalise(s.currentYear) == normYear))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Academic Sessions
  // ---------------------------------------------------------------------------

  Future<void> setCurrentAcademicSession(String id) async {
    await _academicSessionRepository.setCurrent(id);
    for (final s in _academicSessions) {
      s.isCurrent = s.id == id;
    }
    notifyListeners();
  }

  Future<void> addAcademicSession(AcademicSession session) async {
    await _academicSessionRepository.insert(session);
    _academicSessions.insert(0, session);
    if (session.isCurrent) {
      for (final s in _academicSessions) {
        if (s.id != session.id) s.isCurrent = false;
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Departments
  // ---------------------------------------------------------------------------

  Future<void> addDepartment(Department department) async {
    await _departmentRepository.insert(department);
    _departments.add(department);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Classes
  // ---------------------------------------------------------------------------

  Future<SchoolClass> addClass({
    required String name,
    String section = 'A',
    String room = 'General',
    String? departmentId,
    String? academicSessionId,
    String? className,
    String currentYear = '',
  }) async {
    final schoolClass = await _classRepository.insert(
      name: name,
      section: section,
      room: room,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      className: className,
      currentYear: currentYear,
    );
    _classes.insert(0, schoolClass);
    notifyListeners();
    return schoolClass;
  }

  Future<void> updateClass(SchoolClass updated) async {
    await _classRepository.update(updated);
    final idx = _classes.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) {
      _classes[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteClass(int id) async {
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
    String? departmentId,
    String? employeeCode,
    String designation = 'Instructor',
    int? classId,
  }) async {
    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel = selected.isEmpty
        ? ''
        : selected.map((s) => '${s.name} (${s.code})').join(', ');

    final teacher = await _facultyRepository.insert(
      name: name,
      subject: subjectLabel,
      email: email,
      username: username,
      password: password,
      departmentId: departmentId,
      employeeCode: employeeCode,
      designation: designation,
      classId: classId,
    );

    // Mark selected subjects as assigned to this teacher
    for (final subject in selected) {
      subject.teacherId = teacher.id;
      subject.teacherName = name.trim();
      await _subjectRepository.update(subject);
    }

    _teachers.insert(0, teacher);
    notifyListeners();
  }

  Future<void> deleteTeacher(int id) async {
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      for (final subject in _subjects) {
        if (subject.teacherId == id || subject.teacherName == teacher.name) {
          subject.teacherId = null;
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
    String? departmentId,
    String? employeeCode,
    String designation = 'Instructor',
    int? classId,
  }) async {
    final teacher = _teachers.where((t) => t.id == id).firstOrNull;
    if (teacher != null) {
      for (final subject in _subjects) {
        if (subject.teacherId == id || subject.teacherName == teacher.name) {
          subject.teacherId = null;
          subject.teacherName = 'Unassigned';
          await _subjectRepository.update(subject);
        }
      }
    }

    final selected =
        _subjects.where((s) => subjectIds.contains(s.id)).toList();
    final subjectLabel = selected.isEmpty
        ? ''
        : selected.map((s) => '${s.name} (${s.code})').join(', ');

    if (teacher != null) {
      teacher.name = name.trim();
      teacher.subject = subjectLabel;
      teacher.email = email.trim();
      teacher.username = username.trim();
      teacher.password = password.trim();
      if (departmentId != null) teacher.departmentId = departmentId;
      if (employeeCode != null) teacher.employeeCode = employeeCode;
      teacher.designation = designation;
      teacher.classId = classId;
      await _facultyRepository.update(teacher);
    }

    for (final subject in selected) {
      subject.teacherId = id;
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
    String? registrationNo,
    String fatherName = '',
    String? departmentId,
    String? academicSessionId,
    String currentYear = '1st Year',
    String status = 'ACTIVE',
  }) async {
    final student = await _studentRepository.insert(
      name: name,
      rollNumber: rollNumber,
      classId: classId,
      registrationNo: registrationNo,
      fatherName: fatherName,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      currentYear: currentYear,
      status: status,
    );
    _students.insert(0, student);
    notifyListeners();
  }

  Future<void> updateStudent(Student updated) async {
    await _studentRepository.update(updated);
    final idx = _students.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) {
      _students[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> promoteOrMoveStudent({
    required int studentId,
    required int newClassId,
    required String newYear,
    String? newAcademicSessionId,
    String? newDepartmentId,
  }) async {
    final student = _students.where((s) => s.id == studentId).firstOrNull;
    if (student != null) {
      final updated = student.copyWith(
        classId: newClassId,
        currentYear: newYear,
        academicSessionId: newAcademicSessionId ?? student.academicSessionId,
        departmentId: newDepartmentId ?? student.departmentId,
      );
      await updateStudent(updated);
    }
  }

  Future<void> deleteStudent(int id) async {
    await _studentRepository.softDelete(id);
    _students.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Subjects
  // ---------------------------------------------------------------------------

  Future<Subject> addSubject({
    required String name,
    required String code,
    required String teacherName,
    required int classId,
    String? departmentId,
    String? academicSessionId,
    String year = '',
    SubjectType subjectType = SubjectType.theory,
    double contactHours = 0,
    int? teacherId,
  }) async {
    final subject = await _subjectRepository.insert(
      name: name,
      code: code,
      teacherName: teacherName,
      classId: classId,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      year: year,
      subjectType: subjectType,
      contactHours: contactHours,
      teacherId: teacherId,
    );
    _subjects.insert(0, subject);
    notifyListeners();
    return subject;
  }

  Future<void> updateSubject(Subject updated) async {
    await _subjectRepository.update(updated);
    final idx = _subjects.indexWhere((s) => s.id == updated.id);
    if (idx >= 0) {
      _subjects[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> deleteSubject(int id) async {
    await _subjectRepository.softDelete(id);
    _subjects.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}
