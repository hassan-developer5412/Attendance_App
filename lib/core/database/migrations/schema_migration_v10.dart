import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// v10 — Nullable `students.class_id` and deterministic join-table IDs.
///
/// 1. Makes `students.class_id` nullable so unassigned students pulled from
///    Supabase do not fail a NOT NULL constraint on the local SQLite store.
///    SQLite cannot `ALTER COLUMN ... DROP NOT NULL`, so the `students` table
///    is rebuilt in-place (data preserved, foreign key temporarily dropped).
///
/// 2. Backfills deterministic IDs (`UuidUtils.deterministic`) on the
///    composite-key join tables `user_roles` and `user_departments` so that
///    the same logical assignment always maps to the same ID across devices,
///    instead of random `UuidUtils.generate()` values.
///
/// All changes are additive / idempotent-safe; no existing data is lost.
class SchemaMigrationV10 {
  SchemaMigrationV10._();

  static Future<void> execute(Database db) async {
    // -------------------------------------------------------------------------
    // 1. students.class_id: NOT NULL → NULLABLE
    // -------------------------------------------------------------------------
    await _makeClassIdNullable(db);

    // -------------------------------------------------------------------------
    // 2. Deterministic IDs for composite-key join tables
    // -------------------------------------------------------------------------
    await _backfillDeterministicJoinIds(db);
  }

  /// Rebuilds the `students` table so `class_id` is nullable. All existing
  /// rows are preserved. Foreign key enforcement is temporarily suspended
  /// around the rebuild and re-enabled afterwards.
  static Future<void> _makeClassIdNullable(Database db) async {
    final columns = await db.rawQuery("PRAGMA table_info('students')");
    final hasClassId = columns.any((c) => c['name'] == 'class_id');
    if (!hasClassId) return; // nothing to do on very old schemas

    await db.execute('PRAGMA foreign_keys = OFF;');
    await db.execute('BEGIN TRANSACTION;');
    try {
      await db.execute('''
        CREATE TABLE students_new (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          roll_number TEXT NOT NULL,
          class_id TEXT,
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

      await db.execute('''
        INSERT INTO students_new (
          id, name, roll_number, class_id, is_active, roll_no, full_name,
          registration_no, father_name, department_id, academic_session_id,
          current_year, status, created_at, updated_at, sync_status,
          is_deleted, institute_id, is_synced
        )
        SELECT
          id, name, roll_number, class_id, is_active, roll_no, full_name,
          registration_no, father_name, department_id, academic_session_id,
          current_year, status, created_at, updated_at, sync_status,
          is_deleted, institute_id, is_synced
        FROM students
      ''');

      await db.execute('DROP TABLE students');
      await db.execute('ALTER TABLE students_new RENAME TO students');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_students_class_id
        ON students(class_id)
      ''');

      await db.execute('COMMIT;');
    } catch (e) {
      await db.execute('ROLLBACK;');
      rethrow;
    } finally {
      await db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  /// Backfills `id` with `UuidUtils.deterministic(...)` on any join-table rows
  /// that are missing one, so the same (user, role) / (user, department)
  /// pair resolves to the same ID on every device.
  static Future<void> _backfillDeterministicJoinIds(Database db) async {
    // user_roles: composite PK (user_id, role_id); the `id` column is a
    /// nullable extra identifier used by callers.
    final userRoles = await db.query(
      'user_roles',
      columns: ['id', 'user_id', 'role_id'],
    );
    for (final row in userRoles) {
      final id = row['id'];
      if (id == null || id.toString().isEmpty) {
        await db.update(
          'user_roles',
          {
            'id': UuidUtils.deterministic(
              'user_roles',
              '${row['user_id']}:${row['role_id']}',
            ),
          },
          where: 'user_id = ? AND role_id = ?',
          whereArgs: [row['user_id'], row['role_id']],
        );
      }
    }

    // user_departments: `id TEXT PRIMARY KEY`; unique on (user_id, department_id).
    final userDepts = await db.query(
      'user_departments',
      columns: ['id', 'user_id', 'department_id'],
    );
    for (final row in userDepts) {
      final id = row['id'];
      if (id == null || id.toString().isEmpty) {
        await db.update(
          'user_departments',
          {
            'id': UuidUtils.deterministic(
              'user_departments',
              '${row['user_id']}:${row['department_id']}',
            ),
          },
          where: 'user_id = ? AND department_id = ?',
          whereArgs: [row['user_id'], row['department_id']],
        );
      }
    }
  }
}