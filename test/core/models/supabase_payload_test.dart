import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/user.dart';

/// Fields that must never cross the wire: local sync bookkeeping,
/// credentials, and legacy alias columns.
const localOnlyFields = <String>{
  'sync_status',
  'is_synced',
  'password',
  'password_hash',
  'roll_no',
  'full_name',
};

void main() {
  group('toSupabaseJson payload contract', () {
    test('SchoolClass uses uuid as id, keeps local_id, and is JSON-native',
        () {
      final schoolClass = SchoolClass(
        id: 7,
        uuid: 'class-uuid-7',
        name: 'CIT',
        section: 'A',
        room: 'R-101',
        className: 'CIT',
        currentYear: '3rd Year',
      );

      final json = schoolClass.toSupabaseJson();

      expect(json['id'], 'class-uuid-7');
      expect(json['local_id'], 7);
      expect(json['is_deleted'], isA<bool>());
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
      expect(json.containsKey('display_name'), isFalse,
          reason: 'derived display fields are not stored remotely');
    });

    test('Teacher never leaks the local password column', () {
      final teacher = Teacher(
        id: 3,
        uuid: 'teacher-uuid-3',
        name: 'Ms. Khan',
        subject: 'Maths',
        password: 'plain-text-secret',
        username: 'khan',
      );

      final json = teacher.toSupabaseJson();

      expect(json.containsKey('password'), isFalse);
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
      expect(json['id'], 'teacher-uuid-3');
      expect(json['local_id'], 3);
    });

    test('Student keeps integer FK and drops legacy alias columns', () {
      final student = Student(
        id: 11,
        uuid: 'student-uuid-11',
        name: 'Ali',
        rollNumber: 'CIT-001',
        classId: 4,
      );

      final json = student.toSupabaseJson();

      expect(json['id'], 'student-uuid-11');
      expect(json['local_id'], 11);
      expect(json['class_id'], 4, reason: 'integer FKs stay integers');
      expect(json['is_active'], isA<bool>());
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
    });

    test('User excludes password_hash and carries the canonical uuid', () {
      final user = User(
        id: 'user-uuid-1',
        username: 'admin',
        displayName: 'Administrator',
        email: 'admin@institute.edu',
        role: UserRole.admin,
      );

      final json = user.toSupabaseJson();

      expect(json['id'], 'user-uuid-1');
      expect(json['role'], 'admin');
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
    });

    test('Department mirrors the row without sync bookkeeping', () {
      final department = Department(name: 'Leather Tech', code: 'DAE-LT');

      final json = department.toSupabaseJson();

      expect(json['id'], department.id);
      expect(json['is_active'], isA<bool>());
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
      expect(json['institute_id'], isNull,
          reason: 'tenant id is stamped centrally by SyncService');
    });

    test('LeaveRequest serialises its status as the enum value', () {
      final request = LeaveRequest(
        requesterName: 'Teacher A',
        leaveType: 'Sick',
        startDate: DateTime.utc(2026, 3, 1),
        endDate: DateTime.utc(2026, 3, 2),
        reason: 'Flu',
      );

      final json = request.toSupabaseJson();

      expect(json['id'], request.id);
      expect(json['status'], 'pending');
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
    });

    test('AttendanceRecord uses canonical uppercase status, no JOIN fields',
        () {
      final record = AttendanceRecord(
        studentId: 5,
        date: DateTime.utc(2026, 1, 15),
        status: AttendanceStatus.present,
        studentName: 'Joined Name',
        studentRollNumber: 'CIT-009',
      );

      final json = record.toSupabaseJson();

      expect(json['id'], record.id);
      expect(json['status'], 'PRESENT');
      expect(json['date'], '2026-01-15');
      expect(json.containsKey('student_name'), isFalse,
          reason: 'JOIN-only display fields must not be pushed');
      expect(json.containsKey('roll_number'), isFalse);
      expect(json.keys.where(localOnlyFields.contains), isEmpty);
    });

    test('default institute id is centralized in AppConstants', () {
      expect(AppConstants.defaultInstituteId, isNotEmpty);
      expect(AppConstants.prefInstituteId, isNotEmpty);
    });
  });
}