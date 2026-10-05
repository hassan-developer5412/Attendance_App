import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/theme/app_theme.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/classes_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/students_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/teachers_content.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

class _FakeClassRepo extends ClassRepository {
  final List<SchoolClass> items = [];
  int _nextId = 1;

  @override
  Future<List<SchoolClass>> getAll({bool includeDeleted = false}) async =>
      List.from(items);

  @override
  Future<SchoolClass> insert({
    required String name,
    String section = '',
    String room = '',
    String? departmentId,
    String? academicSessionId,
    String? className,
    String currentYear = '',
  }) async {
    final c = SchoolClass(
      id: _nextId++,
      name: name,
      section: section,
      room: room,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      className: className ?? name,
      currentYear: currentYear,
    );
    items.insert(0, c);
    return c;
  }

  @override
  Future<void> softDelete(int id) async {
    items.removeWhere((i) => i.id == id);
  }
}

class _FakeFacultyRepo extends FacultyRepository {
  final List<Teacher> items = [];
  int _nextId = 1;

  @override
  Future<List<Teacher>> getAll({bool includeDeleted = false}) async =>
      List.from(items);

  @override
  Future<Teacher> insert({
    required String name,
    required String subject,
    String email = '',
    String username = '',
    String password = '',
    int? classId,
    String? employeeCode,
    String designation = 'Instructor',
    String? departmentId,
  }) async {
    final t = Teacher(
      id: _nextId++,
      name: name,
      subject: subject,
      email: email,
      username: username,
      password: password,
      classId: classId,
      employeeCode: employeeCode ?? 'FAC-$_nextId',
      designation: designation,
      departmentId: departmentId,
    );
    items.insert(0, t);
    return t;
  }

  @override
  Future<void> update(Teacher teacher) async {
    final idx = items.indexWhere((t) => t.id == teacher.id);
    if (idx >= 0) items[idx] = teacher;
  }

  @override
  Future<void> softDelete(int id) async {
    items.removeWhere((t) => t.id == id);
  }
}

class _FakeStudentRepo extends StudentRepository {
  final List<Student> items = [];
  int _nextId = 1;

  @override
  Future<List<Student>> getAll({bool includeDeleted = false}) async =>
      List.from(items);

  @override
  Future<Student> insert({
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
    final s = Student(
      id: _nextId++,
      name: name,
      rollNumber: rollNumber,
      classId: classId,
      registrationNo: registrationNo ?? 'REG-$rollNumber',
      fatherName: fatherName,
      departmentId: departmentId,
      academicSessionId: academicSessionId,
      currentYear: currentYear,
      status: status,
    );
    items.insert(0, s);
    return s;
  }

  @override
  Future<void> softDelete(int id) async {
    items.removeWhere((s) => s.id == id);
  }
}

class _FakeSubjectRepo extends SubjectRepository {
  final List<Subject> items = [];
  int _nextId = 1;

  @override
  Future<List<Subject>> getAll({bool includeDeleted = false}) async =>
      List.from(items);

  @override
  Future<Subject> insert({
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
    final s = Subject(
      id: _nextId++,
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
    items.insert(0, s);
    return s;
  }

  @override
  Future<void> update(Subject subject) async {
    final idx = items.indexWhere((s) => s.id == subject.id);
    if (idx >= 0) items[idx] = subject;
  }

  @override
  Future<void> softDelete(int id) async {
    items.removeWhere((s) => s.id == id);
  }
}

void main() {
  late InstituteStore store;

  setUp(() async {
    store = InstituteStore(
      classRepository: _FakeClassRepo(),
      facultyRepository: _FakeFacultyRepo(),
      studentRepository: _FakeStudentRepo(),
      subjectRepository: _FakeSubjectRepo(),
    );
    await store.addClass(name: 'Grade 10', section: 'A', room: 'R-101');
  });

  Widget wrap(Widget child) {
    return ChangeNotifierProvider<InstituteStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('add class dialog submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const ClassesContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add class'));
    await tester.pumpAndSettle();

    expect(find.text('Add class'), findsWidgets);

    await tester.enterText(find.byKey(const Key('classNameField')), 'Grade 7');
    await tester.enterText(find.byKey(const Key('classSectionField')), 'B');
    await tester.enterText(find.byKey(const Key('classRoomField')), 'Room 9');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Grade 7 — B'), findsOneWidget);
  });

  testWidgets('add teacher dialog opens and submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const TeachersContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add teacher'));
    await tester.pumpAndSettle();

    expect(find.byType(AddTeacherDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('teacherNameField')), 'Nadia Ali');
    await tester.enterText(find.byKey(const Key('teacherEmailField')), 'nadia@gilt.edu');
    await tester.enterText(find.byKey(const Key('teacherUsernameField')), 'nadia');
    await tester.enterText(find.byKey(const Key('teacherPasswordField')), 'pass123');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Teacher added'), findsOneWidget);
    expect(find.text('Nadia Ali'), findsOneWidget);
  });

  testWidgets('add student dialog opens and submits without crashing', (tester) async {
    await tester.pumpWidget(wrap(const StudentsContent()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add student'));
    await tester.pumpAndSettle();

    expect(find.byType(AddStudentDialog), findsOneWidget);

    await tester.enterText(find.byKey(const Key('studentNameField')), 'Bilal Hussain');
    await tester.enterText(find.byKey(const Key('studentRollField')), '09A-99');

    await tester.ensureVisible(find.byKey(const Key('confirmAddButton')));
    await tester.tap(find.byKey(const Key('confirmAddButton')));
    await tester.pumpAndSettle();

    expect(find.text('Student added'), findsOneWidget);
    expect(find.text('Bilal Hussain'), findsOneWidget);
  });
}
