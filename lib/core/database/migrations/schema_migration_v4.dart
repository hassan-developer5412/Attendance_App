import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Non-destructive migration that introduces the academic structure
/// (Department → Academic Session → Class → Year → Subject) and switches
/// attendance to be **subject based**.
///
/// Every step preserves existing rows:
///  * new tables/columns are added with safe defaults,
///  * legacy values are copied into their new columns before anything is
///    removed,
///  * `attendance_records` is rebuilt to allow one row per
///    `(session, student)` while copying every existing record across,
///  * the obsolete semester column is copied to `current_year` and only then
///    dropped, and only when the SQLite engine supports it.
class SchemaMigrationV4 {
  SchemaMigrationV4._();

  static Future<void> execute(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _createAcademicSessionsTable(db);
    await _addCanonicalColumns(db);
    await _migrateStudentYears(db);
    await _rebuildAttendanceRecords(db, now);
    await MigrationHelpers.seedAcademicSessions(db);
    await _backfillAcademicContext(db);
    await MigrationHelpers.dropColumnIfExists(db, 'students', 'current_semester');
  }

  static Future<void> _createAcademicSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS academic_sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        is_current INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _addCanonicalColumns(Database db) async {
    // Departments gain a description and an active flag.
    await MigrationHelpers.addColumnIfNotExists(
      db, 'departments', 'description', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'departments', 'is_active', "INTEGER NOT NULL DEFAULT 1");

    // Classes now carry the class/program code, the current academic year and
    // the academic session they belong to.
    await MigrationHelpers.addColumnIfNotExists(
      db, 'classes', 'class_name', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'classes', 'current_year', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'classes', 'academic_session_id', "TEXT");

    // Subjects gain their full academic context plus theory/practical metadata.
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'department_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'academic_session_id', "TEXT");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'year', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'subject_type', "TEXT NOT NULL DEFAULT 'THEORY'");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'contact_hours', "REAL NOT NULL DEFAULT 0");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'subjects', 'teacher_id', "INTEGER");

    // Students carry their current year and academic session.
    await MigrationHelpers.addColumnIfNotExists(
      db, 'students', 'current_year', "TEXT NOT NULL DEFAULT '1st Year'");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'students', 'academic_session_id', "TEXT");

    // Attendance sessions capture the exact academic context.
    await MigrationHelpers.addColumnIfNotExists(
      db, 'attendance_sessions', 'academic_session_id',
      "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'attendance_sessions', 'class_id', "INTEGER");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'attendance_sessions', 'year', "TEXT NOT NULL DEFAULT ''");
    await MigrationHelpers.addColumnIfNotExists(
      db, 'attendance_sessions', 'subject_id', "INTEGER");
  }

  /// Copies any legacy year indicator into `current_year` before the obsolete
  /// column is dropped.
  static Future<void> _migrateStudentYears(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(students)');
    final hasLegacyColumn =
        info.any((row) => row['name'] == 'current_semester');
    if (!hasLegacyColumn) return;

    final rows = await db.query('students');
    for (final row in rows) {
      final legacy = row['current_semester'] as String?;
      final year = AcademicYears.normalise(legacy);
      await db.update(
        'students',
        {'current_year': year},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Rebuilds `attendance_records` so uniqueness is per `(session, student)`.
  ///
  /// The historic `UNIQUE (student_id, date)` constraint prevented a student
  /// from having more than one subject marked per day. Every existing record is
  /// copied verbatim into the rebuilt table before the old one is dropped.
  static Future<void> _rebuildAttendanceRecords(Database db, String now) async {
    final tableInfo = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'attendance_records'",
    );
    if (tableInfo.isEmpty) return;
    final createSql = (tableInfo.first['sql'] as String?) ?? '';
    if (!createSql.contains('UNIQUE (student_id, date)')) return; // already v4

    final existingRows = await db.query('attendance_records');

    await db.execute('''
      CREATE TABLE attendance_records_v4 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        session_id TEXT,
        student_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        check_in_time TEXT,
        check_out_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE (session_id, student_id)
      )
    ''');

    final batch = db.batch();
    for (final row in existingRows) {
      final rawUuid = (row['uuid'] as String?)?.trim();
      batch.insert('attendance_records_v4', {
        'uuid': (rawUuid == null || rawUuid.isEmpty)
            ? UuidUtils.deterministic('attendance_records', row['id'])
            : rawUuid,
        'session_id': row['session_id'],
        'student_id': row['student_id'],
        'date': row['date'],
        'status': row['status'],
        'check_in_time': row['check_in_time'],
        'check_out_time': row['check_out_time'],
        'created_at': row['created_at'] ?? now,
        'updated_at': row['updated_at'] ?? now,
        'sync_status': row['sync_status'] ?? 'PENDING',
        'is_deleted': row['is_deleted'] ?? 0,
      });
    }
    await batch.commit(noResult: true);

    await db.execute('DROP TABLE attendance_records');
    await db.execute(
      'ALTER TABLE attendance_records_v4 RENAME TO attendance_records',
    );
  }

  /// Links existing rows to the current academic session and fills in the new
  /// class/subject context columns without overwriting user values.
  static Future<void> _backfillAcademicContext(Database db) async {
    final sessions = await db.query(
      'academic_sessions',
      where: 'is_deleted = 0',
      orderBy: 'start_date DESC',
    );
    if (sessions.isEmpty) return;
    final currentSession = sessions.firstWhere(
      (row) => (row['is_current'] as int? ?? 0) == 1,
      orElse: () => sessions.first,
    );
    final currentSessionId = currentSession['id'] as String;

    // Classes: backfill class_name from the historic name and attach the
    // current session when none is set.
    final classRows = await db.query('classes');
    final classById = <int, Map<String, Object?>>{};
    for (final row in classRows) {
      final id = row['id'] as int;
      classById[id] = row;
      final updates = <String, dynamic>{};
      final className = (row['class_name'] as String?) ?? '';
      if (className.trim().isEmpty) {
        updates['class_name'] = row['name'];
      }
      final sessionId = (row['academic_session_id'] as String?) ?? '';
      if (sessionId.isEmpty) {
        updates['academic_session_id'] = currentSessionId;
      }
      if (updates.isNotEmpty) {
        await db.update('classes', updates, where: 'id = ?', whereArgs: [id]);
      }
    }

    // Subjects: inherit department/year/session from their class.
    final subjectRows = await db.query('subjects');
    for (final row in subjectRows) {
      final classId = row['class_id'] is int
          ? row['class_id'] as int
          : int.tryParse(row['class_id'].toString());
      final parentClass = classId != null ? classById[classId] : null;
      final updates = <String, dynamic>{};
      if (((row['academic_session_id'] as String?) ?? '').isEmpty) {
        updates['academic_session_id'] = currentSessionId;
      }
      if ((((row['year'] as String?) ?? '').trim()).isEmpty &&
          parentClass != null) {
        updates['year'] = parentClass['current_year'] ?? '';
      }
      if ((((row['department_id'] as String?) ?? '')).isEmpty &&
          parentClass != null) {
        updates['department_id'] = parentClass['department_id'];
      }
      if (updates.isNotEmpty) {
        await db.update(
          'subjects',
          updates,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }

    // Students & attendance sessions: attach the current session when unset.
    await db.update(
      'students',
      {'academic_session_id': currentSessionId},
      where: "academic_session_id IS NULL OR academic_session_id = ''",
    );
    await db.update(
      'attendance_sessions',
      {'academic_session_id': currentSessionId},
      where: "academic_session_id IS NULL OR academic_session_id = ''",
    );
  }
}
