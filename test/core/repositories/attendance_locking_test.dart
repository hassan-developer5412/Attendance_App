import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

void main() {
  late DatabaseHelper dbHelper;
  late Database db;
  late AttendanceRepository attendanceRepo;
  late StudentRepository studentRepo;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);
    attendanceRepo = AttendanceRepository(dbHelper: dbHelper);
    studentRepo = StudentRepository(dbHelper: dbHelper);
    PermissionService.instance.reset();
  });

  tearDown(() async {
    PermissionService.instance.reset();
    await db.close();
  });

  group('Attendance Correction & Locking UI/Logic', () {
    test('isSessionLocked returns false for fresh session (<24h)', () async {
      final freshDate = DateTime.now().toUtc().subtract(const Duration(hours: 2));
      final freshDateStr = freshDate.toIso8601String();

      // Insert recent attendance_session
      await db.insert('attendance_sessions', {
        'id': 'sess_fresh',
        'session_date': freshDateStr.split('T')[0],
        'sync_status': 'synced',
        'created_at': freshDateStr,
        'updated_at': freshDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      final isLocked = await attendanceRepo.isSessionLocked('sess_fresh');
      expect(isLocked, isFalse);
    });

    test('isSessionLocked returns true for old session (>24h)', () async {
      final oldDate = DateTime.now().toUtc().subtract(const Duration(hours: 30));
      final oldDateStr = oldDate.toIso8601String();

      // Insert old attendance_session
      await db.insert('attendance_sessions', {
        'id': 'sess_old',
        'session_date': oldDateStr.split('T')[0],
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      final isLocked = await attendanceRepo.isSessionLocked('sess_old');
      expect(isLocked, isTrue);
    });

    test('upsertAttendanceForSession blocks teacher modification when locked', () async {
      final oldDate = DateTime.now().toUtc().subtract(const Duration(hours: 48));
      final oldDateStr = oldDate.toIso8601String();

      await db.insert('attendance_sessions', {
        'id': 'sess_locked_teacher',
        'session_date': oldDateStr.split('T')[0],
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Insert existing attendance record created in that session
      await db.insert('attendance_records', {
        'id': 'rec_locked_1',
        'session_id': 'sess_locked_teacher',
        'student_id': 'student1',
        'date': oldDateStr.split('T')[0],
        'status': 'absent',
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Modifying attendance without override should throw PermissionDeniedException
      expect(
        () => attendanceRepo.upsertAttendanceForSession(
          sessionId: 'sess_locked_teacher',
          studentId: 'student1',
          status: AttendanceStatus.present,
          isOverride: false,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('upsertAttendanceForSession allows HOD/Admin override for locked session', () async {
      final oldDate = DateTime.now().toUtc().subtract(const Duration(hours: 48));
      final oldDateStr = oldDate.toIso8601String();

      await db.insert('attendance_sessions', {
        'id': 'sess_locked_admin',
        'session_date': oldDateStr.split('T')[0],
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Insert student record first to satisfy foreign key / relationships
      await db.insert('students', {
        'id': 'std_override',
        'name': 'Override Student',
        'roll_number': 'OVR-1',
        'roll_no': 'OVR-1',
        'class_id': 'class1',
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Insert existing attendance record created in that session
      await db.insert('attendance_records', {
        'id': 'rec_locked_admin_1',
        'session_id': 'sess_locked_admin',
        'student_id': 'std_override',
        'date': oldDateStr.split('T')[0],
        'status': 'absent',
        'sync_status': 'synced',
        'created_at': oldDateStr,
        'updated_at': oldDateStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Override is true -> must succeed
      await attendanceRepo.upsertAttendanceForSession(
        sessionId: 'sess_locked_admin',
        studentId: 'std_override',
        status: AttendanceStatus.present,
        isOverride: true,
      );

      // Verify the record was updated to present
      final savedRecords = await attendanceRepo.getForSession('sess_locked_admin');
      expect(savedRecords.length, equals(1));
      expect(savedRecords.first.studentId, equals('std_override'));
      expect(savedRecords.first.status, equals(AttendanceStatus.present));
    });

    test('Student self-view detailed attendance and roll number lookup', () async {
      final nowStr = DateTime.now().toUtc().toIso8601String();

      // Insert student
      await db.insert('students', {
        'id': 'std_self',
        'name': 'Self Student',
        'roll_number': 'CS-2026-001',
        'roll_no': 'CS-2026-001',
        'class_id': 'class_cs',
        'sync_status': 'synced',
        'created_at': nowStr,
        'updated_at': nowStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      // Test StudentRepository getByRollNumber
      final foundStudent = await studentRepo.getByRollNumber('CS-2026-001');
      expect(foundStudent, isNotNull);
      expect(foundStudent!.id, equals('std_self'));
      expect(foundStudent.name, equals('Self Student'));

      // Insert subject & session
      await db.insert('subjects', {
        'id': 'sub_algo',
        'name': 'Algorithms',
        'code': 'CS301',
        'teacher_name': 'Prof. Turing',
        'class_id': 'class_cs',
        'sync_status': 'synced',
        'created_at': nowStr,
        'updated_at': nowStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      await db.insert('attendance_sessions', {
        'id': 'sess_algo_1',
        'subject_id': 'sub_algo',
        'subject_code': 'CS301',
        'class_id': 'class_cs',
        'session_date': '2026-11-01',
        'sync_status': 'synced',
        'created_at': nowStr,
        'updated_at': nowStr,
        'institute_id': AppConstants.defaultInstituteId,
      });

      await attendanceRepo.upsertAttendanceForSession(
        sessionId: 'sess_algo_1',
        studentId: 'std_self',
        status: AttendanceStatus.present,
      );

      // Verify getDetailedAttendanceForStudent
      final detailedRecords = await attendanceRepo.getDetailedAttendanceForStudent('std_self');
      expect(detailedRecords.isNotEmpty, isTrue);
      expect(detailedRecords.first['status'], equals('present'));
      expect(detailedRecords.first['subject_name'], equals('Algorithms'));
      expect(detailedRecords.first['subject_code'], equals('CS301'));
      expect(detailedRecords.first['date'], equals('2026-11-01'));
    });
  });
}
