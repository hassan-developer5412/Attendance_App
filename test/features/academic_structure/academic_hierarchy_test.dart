import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/repositories/academic_session_repository.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/class_repository.dart';
import 'package:attendance_app/core/repositories/department_repository.dart';
import 'package:attendance_app/core/repositories/faculty_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/repositories/subject_repository.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('GILT Academic Structure & Subject Attendance Tests', () {
    late Database db;
    late DatabaseHelper dbHelper;
    late DepartmentRepository deptRepo;
    late AcademicSessionRepository sessionRepo;
    late ClassRepository classRepo;
    late FacultyRepository facultyRepo;
    late StudentRepository studentRepo;
    late SubjectRepository subjectRepo;
    late AttendanceRepository attendanceRepo;
    late InstituteStore instituteStore;
    late AttendanceStore attendanceStore;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await FreshDatabaseCreator.createAndSeed(db);

      dbHelper = DatabaseHelper.forTesting(db);
      deptRepo = DepartmentRepository(dbHelper: dbHelper);
      sessionRepo = AcademicSessionRepository(dbHelper: dbHelper);
      classRepo = ClassRepository(dbHelper: dbHelper);
      facultyRepo = FacultyRepository(dbHelper: dbHelper);
      studentRepo = StudentRepository(dbHelper: dbHelper);
      subjectRepo = SubjectRepository(dbHelper: dbHelper);
      attendanceRepo = AttendanceRepository(dbHelper: dbHelper);

      instituteStore = InstituteStore(
        departmentRepository: deptRepo,
        academicSessionRepository: sessionRepo,
        classRepository: classRepo,
        facultyRepository: facultyRepo,
        studentRepository: studentRepo,
        subjectRepository: subjectRepo,
      );
      await instituteStore.init();

      attendanceStore = AttendanceStore(repository: attendanceRepo);
    });

    tearDown(() async {
      await db.close();
    });

    test('1. Hierarchy: Departments and Academic Sessions seeded correctly without semesters', () async {
      expect(instituteStore.departments.isNotEmpty, isTrue);
      expect(instituteStore.academicSessions.isNotEmpty, isTrue);

      final citDept = instituteStore.departmentByCode('DAE-CIT');
      expect(citDept, isNotNull);
      expect(citDept!.name, contains('Computer Information Technology'));

      final ltDept = instituteStore.departmentByCode('DAE-LT');
      expect(ltDept, isNotNull);
      expect(ltDept!.name, contains('Leather Technology'));

      final fwDept = instituteStore.departmentByCode('DAE-FW');
      expect(fwDept, isNotNull);
      expect(fwDept!.name, contains('Footwear Technology'));

      // Verify no semester values exist in academic years
      expect(AcademicYears.labels, equals(['1st Year', '2nd Year', '3rd Year']));
      for (final label in AcademicYears.labels) {
        expect(label.toLowerCase(), isNot(contains('semester')));
      }
    });

    test('2. Class creation respects <Class_Name>-<Current_Year> format', () async {
      final dept = instituteStore.departmentByCode('DAE-CIT')!;
      final session = instituteStore.currentAcademicSession!;

      final schoolClass = await instituteStore.addClass(
        name: 'CIT-3rd Year',
        className: 'CIT',
        currentYear: '3rd Year',
        departmentId: dept.id,
        academicSessionId: session.id,
        section: 'Morning',
        room: 'Lab 2',
      );

      expect(schoolClass.displayName, equals('CIT-3rd Year'));
      expect(schoolClass.className, equals('CIT'));
      expect(schoolClass.currentYear, equals('3rd Year'));
      expect(schoolClass.departmentId, equals(dept.id));
      expect(schoolClass.academicSessionId, equals(session.id));
    });

    test('3. Subjects belong to Class & Year with Theory/Practical classification', () async {
      final dept = instituteStore.departmentByCode('DAE-CIT')!;
      final session = instituteStore.currentAcademicSession!;

      final cls = await instituteStore.addClass(
        name: 'CIT-1st Year',
        className: 'CIT',
        currentYear: '1st Year',
        departmentId: dept.id,
        academicSessionId: session.id,
        section: 'A',
        room: 'R-1',
      );

      final teacher = await facultyRepo.insert(
        name: 'Engr. Tariq Mehmood',
        subject: '',
        email: 'tariq@gilt.edu',
        username: 'tariq',
        password: 'password123',
        departmentId: dept.id,
        designation: 'Senior Instructor',
        employeeCode: 'EMP-CIT-01',
      );

      final subject1 = await instituteStore.addSubject(
        name: 'Computer Applications',
        code: 'CIT-113',
        teacherName: teacher.name,
        teacherId: teacher.id,
        classId: cls.id,
        departmentId: dept.id,
        academicSessionId: session.id,
        year: '1st Year',
        subjectType: SubjectType.both,
        contactHours: 4.0,
      );

      final subject2 = await instituteStore.addSubject(
        name: 'Basic Electronics',
        code: 'CIT-122',
        teacherName: teacher.name,
        teacherId: teacher.id,
        classId: cls.id,
        departmentId: dept.id,
        academicSessionId: session.id,
        year: '1st Year',
        subjectType: SubjectType.theory,
        contactHours: 2.0,
      );

      final classSubjects = instituteStore.subjectsForClassAndYear(cls.id, '1st Year');
      expect(classSubjects.length, equals(2));
      expect(classSubjects.map((s) => s.code), containsAll(['CIT-113', 'CIT-122']));
      expect(subject1.subjectType, equals(SubjectType.both));
      expect(subject2.subjectType, equals(SubjectType.theory));
    });

    test('4. Subject-based attendance: multiple subjects on same date for same student without conflict', () async {
      final dept = instituteStore.departmentByCode('DAE-CIT')!;
      final session = instituteStore.currentAcademicSession!;

      final cls = await instituteStore.addClass(
        name: 'CIT-2nd Year',
        className: 'CIT',
        currentYear: '2nd Year',
        departmentId: dept.id,
        academicSessionId: session.id,
        section: 'Morning',
        room: 'Lab 1',
      );

      await instituteStore.addStudent(
        name: 'Hamza Khan',
        rollNumber: 'CIT-24-01',
        registrationNo: 'REG-24-01',
        classId: cls.id,
        departmentId: dept.id,
        academicSessionId: session.id,
        currentYear: '2nd Year',
      );

      final students = instituteStore.studentsForClassAndYear(cls.id, '2nd Year');
      expect(students.length, equals(1));
      final student = students.first;

      final sub1 = await instituteStore.addSubject(
        name: 'Data Structures',
        code: 'CIT-214',
        teacherName: 'Sir Ali',
        classId: cls.id,
        departmentId: dept.id,
        academicSessionId: session.id,
        year: '2nd Year',
      );

      final sub2 = await instituteStore.addSubject(
        name: 'Database Systems',
        code: 'CIT-224',
        teacherName: 'Sir Usman',
        classId: cls.id,
        departmentId: dept.id,
        academicSessionId: session.id,
        year: '2nd Year',
      );

      final testDate = DateTime(2026, 10, 5);

      // Mark Subject 1 attendance: Present
      await attendanceStore.loadSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session.id,
        classId: cls.id,
        year: '2nd Year',
        subjectId: sub1.id,
        date: testDate,
        students: students,
        subjectCode: sub1.code,
      );
      attendanceStore.setStatus(student.id, AttendanceStatus.present);
      await attendanceStore.saveSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session.id,
        classId: cls.id,
        year: '2nd Year',
        subjectId: sub1.id,
        date: testDate,
        students: students,
        subjectCode: sub1.code,
        remarks: 'Arrays and Linked Lists',
      );

      // Mark Subject 2 attendance on the SAME date: Late
      await attendanceStore.loadSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session.id,
        classId: cls.id,
        year: '2nd Year',
        subjectId: sub2.id,
        date: testDate,
        students: students,
        subjectCode: sub2.code,
      );
      attendanceStore.setStatus(student.id, AttendanceStatus.late);
      await attendanceStore.saveSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session.id,
        classId: cls.id,
        year: '2nd Year',
        subjectId: sub2.id,
        date: testDate,
        students: students,
        subjectCode: sub2.code,
        remarks: 'ER Diagram Design',
      );

      // Verify that both attendance records exist independently
      final studentReport = await attendanceStore.getStudentAttendanceBySubject(student.id);
      expect(studentReport.length, equals(2));

      final sub1Report = studentReport.firstWhere((r) => r['subjectId'] == sub1.id);
      expect(sub1Report['totalSessions'], equals(1));
      expect(sub1Report['presentCount'], equals(1));
      expect(sub1Report['lateCount'], equals(0));

      final sub2Report = studentReport.firstWhere((r) => r['subjectId'] == sub2.id);
      expect(sub2Report['totalSessions'], equals(1));
      expect(sub2Report['presentCount'], equals(0));
      expect(sub2Report['lateCount'], equals(1));

      // Verify Subject session history
      final history1 = await attendanceStore.getSubjectSessionHistory(sub1.id);
      expect(history1.length, equals(1));
      expect(history1.first['remarks'], equals('Arrays and Linked Lists'));
      expect(history1.first['totalMarked'], equals(1));
      expect(history1.first['attendanceRate'], equals(100.0));
    });

    test('5. Promoting student updates currentYear without touching historical attendance records', () async {
      final dept = instituteStore.departmentByCode('DAE-LT')!;
      final session1 = instituteStore.academicSessions.first;

      final cls1 = await instituteStore.addClass(
        name: 'LT-1st Year',
        className: 'LT',
        currentYear: '1st Year',
        departmentId: dept.id,
        academicSessionId: session1.id,
      );

      final cls2 = await instituteStore.addClass(
        name: 'LT-2nd Year',
        className: 'LT',
        currentYear: '2nd Year',
        departmentId: dept.id,
        academicSessionId: session1.id,
      );

      await instituteStore.addStudent(
        name: 'Zeeshan Ahmed',
        rollNumber: 'LT-23-05',
        classId: cls1.id,
        departmentId: dept.id,
        academicSessionId: session1.id,
        currentYear: '1st Year',
      );
      final student = instituteStore.students.first;

      final sub = await instituteStore.addSubject(
        name: 'Tanning Technology I',
        code: 'LT-101',
        teacherName: 'Instructor LT',
        classId: cls1.id,
        departmentId: dept.id,
        academicSessionId: session1.id,
        year: '1st Year',
      );

      // Record attendance in 1st Year
      await attendanceStore.loadSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session1.id,
        classId: cls1.id,
        year: '1st Year',
        subjectId: sub.id,
        date: DateTime(2025, 11, 10),
        students: [student],
      );
      await attendanceStore.saveSubjectAttendance(
        departmentId: dept.id,
        academicSessionId: session1.id,
        classId: cls1.id,
        year: '1st Year',
        subjectId: sub.id,
        date: DateTime(2025, 11, 10),
        students: [student],
      );

      // Promote student to 2nd Year
      await instituteStore.promoteOrMoveStudent(
        studentId: student.id,
        newClassId: cls2.id,
        newYear: '2nd Year',
      );

      // Verify student's new year and class
      final updatedStudent = instituteStore.students.firstWhere((s) => s.id == student.id);
      expect(updatedStudent.currentYear, equals('2nd Year'));
      expect(updatedStudent.classId, equals(cls2.id));

      // Verify historical attendance record is still intact
      final records = await attendanceRepo.getStudentAttendanceBySubject(student.id);
      expect(records.length, equals(1));
      expect(records.first['totalSessions'], equals(1));
      expect(records.first['attendedCount'], equals(1));
    });
  });
}
