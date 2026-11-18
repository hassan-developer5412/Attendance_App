import 'package:sqflite/sqflite.dart';

/// v12 — Weekly Class & Lab Timetable.
///
/// Adds the `timetable_slots` table which stores weekly recurring class and lab
/// sessions. Each slot maps a class, subject, teacher, and room to a specific
/// day of week and period slot with start/end times.
///
/// The table follows the same offline-first sync pipeline as every other
/// entity:
///   • `sync_status` / `is_synced` track replication to Supabase.
///   • `is_deleted` performs a soft-delete.
///   • `academic_session_id` is nullable to allow slots outside a session.
///
/// All changes are purely additive — no existing tables are modified.
class SchemaMigrationV12 {
  SchemaMigrationV12._();

  static Future<void> execute(Database db) async {
    await _createTimetableSlotsTable(db);
  }

  /// Creates the `timetable_slots` table and its supporting indexes.
  ///
  /// Uses `CREATE TABLE IF NOT EXISTS` so the migration is idempotent and safe
  /// to re-run on databases that were partially migrated.
  static Future<void> _createTimetableSlotsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS timetable_slots (
        id                TEXT PRIMARY KEY,
        institute_id      TEXT NOT NULL,
        academic_session_id TEXT,
        class_id          TEXT NOT NULL,
        subject_id        TEXT NOT NULL,
        teacher_id        TEXT NOT NULL,
        room_name         TEXT NOT NULL,
        day_of_week       INTEGER NOT NULL,
        period_slot       INTEGER NOT NULL,
        start_time        TEXT NOT NULL,
        end_time          TEXT NOT NULL,
        is_lab            INTEGER NOT NULL DEFAULT 0,
        created_at        TEXT NOT NULL,
        updated_at        TEXT NOT NULL,
        is_deleted        INTEGER NOT NULL DEFAULT 0,
        sync_status       TEXT NOT NULL DEFAULT 'PENDING',
        is_synced         INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (academic_session_id) REFERENCES academic_sessions (id) ON DELETE SET NULL
      )
    ''');

    // ── Supporting indexes ──────────────────────────────────────────────────
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_institute_id
      ON timetable_slots(institute_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_academic_session_id
      ON timetable_slots(academic_session_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_class_id
      ON timetable_slots(class_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_teacher_id
      ON timetable_slots(teacher_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_day_period
      ON timetable_slots(day_of_week, period_slot)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_timetable_slots_is_deleted
      ON timetable_slots(is_deleted)
    ''');
  }
}