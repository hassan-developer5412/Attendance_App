import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Full UUID migration — v6.
///
/// Converts every table that previously used `INTEGER PRIMARY KEY AUTOINCREMENT`
/// to `TEXT PRIMARY KEY` holding a client-generated v4 UUID.
///
/// Tables migrated:
///   users, classes, teachers, students, subjects,
///   attendance_records, leave_requests
///
/// All foreign-key columns that referenced the old integer PKs are updated
/// in the same transaction so referential integrity is never broken.
///
/// Strategy (per table):
///   1. Map each old integer `id` → deterministic UUID (same algorithm used
///      in v3 back-fill, so rows that already had a `uuid` column get the
///      same value and old sync-queue entries keep working).
///   2. Create a `*_v6` shadow table with the new TEXT-PK schema.
///   3. Bulk-INSERT all rows, substituting integer PKs/FKs with their UUIDs.
///   4. DROP the old table and RENAME the shadow.
///
/// The migration runs inside a single SQLite transaction so a mid-flight
/// crash leaves the database intact on the next launch.
class SchemaMigrationV6 {
  SchemaMigrationV6._();

  static Future<void> execute(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      // ------------------------------------------------------------------
      // 1. Build UUID maps for every old integer PK
      // ------------------------------------------------------------------
      final classUuids = await _buildUuidMap(txn, 'classes');
      final teacherUuids = await _buildUuidMap(txn, 'teachers');
      final studentUuids = await _buildUuidMap(txn, 'students');
      final subjectUuids = await _buildUuidMap(txn, 'subjects');
      final userUuids = await _buildUuidMap(txn, 'users');
      final leaveUuids = await _buildUuidMap(txn, 'leave_requests');
      final attendanceUuids = await _buildUuidMap(txn, 'attendance_records');

      // ------------------------------------------------------------------
      // 2. Migrate: users
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE users_v6 (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          display_name TEXT NOT NULL,
          email TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'admin',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final userRows = await txn.query('users');
      for (final row in userRows) {
        final oldId = row['id'];
        final newId = userUuids[oldId]!;
        await txn.insert('users_v6', {
          'id': newId,
          'username': row['username'],
          'password_hash': row['password_hash'],
          'display_name': row['display_name'] ?? '',
          'email': row['email'] ?? '',
          'role': row['role'] ?? 'admin',
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE users');
      await txn.execute('ALTER TABLE users_v6 RENAME TO users');

      // ------------------------------------------------------------------
      // 3. Migrate: classes
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE classes_v6 (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          section TEXT NOT NULL,
          room TEXT NOT NULL,
          class_name TEXT NOT NULL DEFAULT '',
          current_year TEXT NOT NULL DEFAULT '',
          department_id TEXT,
          academic_session_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final classRows = await txn.query('classes');
      for (final row in classRows) {
        final oldId = row['id'];
        final newId = classUuids[oldId]!;
        await txn.insert('classes_v6', {
          'id': newId,
          'name': row['name'] ?? '',
          'section': row['section'] ?? '',
          'room': row['room'] ?? '',
          'class_name': row['class_name'] ?? row['name'] ?? '',
          'current_year': row['current_year'] ?? '',
          'department_id': row['department_id'],
          'academic_session_id': row['academic_session_id'],
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE classes');
      await txn.execute('ALTER TABLE classes_v6 RENAME TO classes');

      // ------------------------------------------------------------------
      // 4. Migrate: teachers  (FK: class_id → classes.id)
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE teachers_v6 (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          subject TEXT NOT NULL,
          email TEXT NOT NULL DEFAULT '',
          username TEXT NOT NULL DEFAULT '',
          password TEXT NOT NULL DEFAULT '',
          class_id TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          employee_code TEXT,
          designation TEXT NOT NULL DEFAULT 'Instructor',
          department_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
        )
      ''');
      final teacherRows = await txn.query('teachers');
      for (final row in teacherRows) {
        final oldId = row['id'];
        final newId = teacherUuids[oldId]!;
        final oldClassId = row['class_id'];
        final newClassId = oldClassId != null
            ? classUuids[oldClassId]
            : null;
        await txn.insert('teachers_v6', {
          'id': newId,
          'name': row['name'] ?? '',
          'subject': row['subject'] ?? '',
          'email': row['email'] ?? '',
          'username': row['username'] ?? '',
          'password': row['password'] ?? '',
          'class_id': newClassId,
          'is_active': row['is_active'] ?? 1,
          'employee_code': row['employee_code'] ?? 'FAC-$newId',
          'designation': row['designation'] ?? 'Instructor',
          'department_id': row['department_id'],
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE teachers');
      await txn.execute('ALTER TABLE teachers_v6 RENAME TO teachers');

      // ------------------------------------------------------------------
      // 5. Migrate: students  (FK: class_id → classes.id)
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE students_v6 (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          roll_number TEXT NOT NULL,
          class_id TEXT NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1,
          roll_no TEXT,
          full_name TEXT,
          registration_no TEXT,
          father_name TEXT NOT NULL DEFAULT '',
          department_id TEXT,
          academic_session_id TEXT,
          current_year TEXT NOT NULL DEFAULT '1st Year',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');
      final studentRows = await txn.query('students');
      for (final row in studentRows) {
        final oldId = row['id'];
        final newId = studentUuids[oldId]!;
        final oldClassId = row['class_id'];
        final newClassId = oldClassId != null
            ? (classUuids[oldClassId] ?? classUuids[oldClassId.toString()])
            : null;
        await txn.insert('students_v6', {
          'id': newId,
          'name': row['name'] ?? '',
          'roll_number': row['roll_number'] ?? '',
          'class_id': newClassId ?? '',
          'is_active': row['is_active'] ?? 1,
          'roll_no': row['roll_no'] ?? row['roll_number'],
          'full_name': row['full_name'] ?? row['name'],
          'registration_no': row['registration_no'],
          'father_name': row['father_name'] ?? '',
          'department_id': row['department_id'],
          'academic_session_id': row['academic_session_id'],
          'current_year': row['current_year'] ?? '1st Year',
          'status': row['status'] ?? 'ACTIVE',
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE students');
      await txn.execute('ALTER TABLE students_v6 RENAME TO students');

      // ------------------------------------------------------------------
      // 6. Migrate: subjects  (FK: class_id → classes.id)
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE subjects_v6 (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          code TEXT NOT NULL,
          teacher_name TEXT NOT NULL,
          class_id TEXT NOT NULL,
          department_id TEXT,
          academic_session_id TEXT,
          year TEXT NOT NULL DEFAULT '',
          subject_type TEXT NOT NULL DEFAULT 'THEORY',
          contact_hours REAL NOT NULL DEFAULT 0,
          teacher_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');
      final subjectRows = await txn.query('subjects');
      for (final row in subjectRows) {
        final oldId = row['id'];
        final newId = subjectUuids[oldId]!;
        final oldClassId = row['class_id'];
        final newClassId = oldClassId != null
            ? (classUuids[oldClassId] ?? classUuids[oldClassId.toString()])
            : null;
        final oldTeacherId = row['teacher_id'];
        final newTeacherId = oldTeacherId != null
            ? teacherUuids[oldTeacherId]
            : null;
        await txn.insert('subjects_v6', {
          'id': newId,
          'name': row['name'] ?? '',
          'code': row['code'] ?? '',
          'teacher_name': row['teacher_name'] ?? '',
          'class_id': newClassId ?? '',
          'department_id': row['department_id'],
          'academic_session_id': row['academic_session_id'],
          'year': row['year'] ?? '',
          'subject_type': row['subject_type'] ?? 'THEORY',
          'contact_hours': row['contact_hours'] ?? 0,
          'teacher_id': newTeacherId,
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE subjects');
      await txn.execute('ALTER TABLE subjects_v6 RENAME TO subjects');

      // ------------------------------------------------------------------
      // 7. Update attendance_sessions FK columns:
      //    class_id (INTEGER → TEXT), subject_id (INTEGER → TEXT)
      //    These columns existed as INTEGER in v4; we update them in-place
      //    by rebuilding the table.
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE attendance_sessions_v6 (
          id TEXT PRIMARY KEY,
          subject_code TEXT NOT NULL DEFAULT '',
          department_id TEXT NOT NULL DEFAULT '',
          faculty_id TEXT NOT NULL DEFAULT '',
          session_date TEXT NOT NULL,
          academic_session_id TEXT NOT NULL DEFAULT '',
          class_id TEXT,
          year TEXT NOT NULL DEFAULT '',
          subject_id TEXT,
          remarks TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final sessionRows = await txn.query('attendance_sessions');
      for (final row in sessionRows) {
        final oldClassId = row['class_id'];
        final newClassId = oldClassId != null
            ? (classUuids[oldClassId] ?? classUuids[oldClassId.toString()])
            : null;
        final oldSubjectId = row['subject_id'];
        final newSubjectId = oldSubjectId != null
            ? (subjectUuids[oldSubjectId] ?? subjectUuids[oldSubjectId.toString()])
            : null;
        await txn.insert('attendance_sessions_v6', {
          'id': row['id'],
          'subject_code': row['subject_code'] ?? '',
          'department_id': row['department_id'] ?? '',
          'faculty_id': row['faculty_id'] ?? '',
          'session_date': row['session_date'] ?? '',
          'academic_session_id': row['academic_session_id'] ?? '',
          'class_id': newClassId,
          'year': row['year'] ?? '',
          'subject_id': newSubjectId,
          'remarks': row['remarks'] ?? '',
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE attendance_sessions');
      await txn.execute('ALTER TABLE attendance_sessions_v6 RENAME TO attendance_sessions');

      // ------------------------------------------------------------------
      // 8. Migrate: attendance_records
      //    Old: INTEGER PK + uuid column + INTEGER student_id
      //    New: TEXT PK (was uuid), TEXT student_id
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE attendance_records_v6 (
          id TEXT PRIMARY KEY,
          session_id TEXT,
          student_id TEXT NOT NULL,
          date TEXT NOT NULL,
          status TEXT NOT NULL,
          check_in_time TEXT,
          check_out_time TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          UNIQUE (session_id, student_id)
        )
      ''');
      final attendanceRows = await txn.query('attendance_records');
      for (final row in attendanceRows) {
        final oldId = row['id'];
        final newId = attendanceUuids[oldId]!;
        final oldStudentId = row['student_id'];
        final newStudentId = oldStudentId != null
            ? (studentUuids[oldStudentId] ?? studentUuids[oldStudentId.toString()])
            : null;
        if (newStudentId == null) continue; // orphaned record — skip
        try {
          await txn.insert('attendance_records_v6', {
            'id': newId,
            'session_id': row['session_id'],
            'student_id': newStudentId,
            'date': row['date'] ?? '',
            'status': row['status'] ?? 'absent',
            'check_in_time': row['check_in_time'],
            'check_out_time': row['check_out_time'],
            'created_at': row['created_at'] ?? now,
            'updated_at': row['updated_at'] ?? now,
            'sync_status': row['sync_status'] ?? 'PENDING',
            'is_deleted': row['is_deleted'] ?? 0,
            'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
            'is_synced': 0,
          });
        } catch (_) {
          // Duplicate (session_id, student_id) pair — skip the older record.
        }
      }
      await txn.execute('DROP TABLE attendance_records');
      await txn.execute('ALTER TABLE attendance_records_v6 RENAME TO attendance_records');

      // ------------------------------------------------------------------
      // 9. Migrate: leave_requests
      // ------------------------------------------------------------------
      await txn.execute('''
        CREATE TABLE leave_requests_v6 (
          id TEXT PRIMARY KEY,
          requester_name TEXT NOT NULL,
          leave_type TEXT NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT NOT NULL,
          reason TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          institute_id TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}',
          is_synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final leaveRows = await txn.query('leave_requests');
      for (final row in leaveRows) {
        final oldId = row['id'];
        final newId = leaveUuids[oldId]!;
        await txn.insert('leave_requests_v6', {
          'id': newId,
          'requester_name': row['requester_name'] ?? '',
          'leave_type': row['leave_type'] ?? '',
          'start_date': row['start_date'] ?? now,
          'end_date': row['end_date'] ?? now,
          'reason': row['reason'] ?? '',
          'status': row['status'] ?? 'pending',
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'sync_status': row['sync_status'] ?? 'PENDING',
          'is_deleted': row['is_deleted'] ?? 0,
          'institute_id': row['institute_id'] ?? AppConstants.defaultInstituteId,
          'is_synced': 0,
        });
      }
      await txn.execute('DROP TABLE leave_requests');
      await txn.execute('ALTER TABLE leave_requests_v6 RENAME TO leave_requests');
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Reads all rows of [table] and returns a map of {oldId → uuid}.
  ///
  /// Preference order for the UUID value:
  ///   1. The existing `uuid` column (populated by v3 back-fill) when non-empty.
  ///   2. A new deterministic UUID derived from the namespace and integer id.
  static Future<Map<Object, String>> _buildUuidMap(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.query(table, columns: ['id', 'uuid']);
    final map = <Object, String>{};
    for (final row in rows) {
      final oldId = row['id']!;
      final existingUuid = (row['uuid'] as String?)?.trim();
      final uuid = (existingUuid != null && existingUuid.isNotEmpty)
          ? existingUuid
          : UuidUtils.deterministic(table, oldId);
      map[oldId] = uuid;
      // Also key by string representation for robustness.
      if (oldId is! String) map[oldId.toString()] = uuid;
    }
    return map;
  }

  /// Hashes an admin password to SHA-256 (used in seeder fallback only).
  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();
}
