import 'package:sqflite/sqflite.dart';

/// v11 — Institute Notice Board & Circulars.
///
/// Adds the `notices` table which stores institute-wide and department-scoped
/// notices, circulars, and announcements. The table is designed for the same
/// offline-first sync pipeline used by every other entity in the schema:
///   • `sync_status` / `is_synced` track replication to Supabase.
///   • `is_deleted` performs a soft-delete so deleted notices survive until
///     the next full-sync confirms removal on the backend.
///   • `target_role` and `department_id` allow scoping notices to a specific
///     audience without duplicating rows.
///
/// All changes are purely additive — no existing tables are modified.
class SchemaMigrationV11 {
  SchemaMigrationV11._();

  static Future<void> execute(Database db) async {
    await _createNoticesTable(db);
  }

  /// Creates the `notices` table and its supporting indexes.
  ///
  /// Uses `CREATE TABLE IF NOT EXISTS` so the migration is idempotent and safe
  /// to re-run on databases that were partially migrated.
  static Future<void> _createNoticesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notices (
        id               TEXT PRIMARY KEY,
        institute_id     TEXT NOT NULL,
        title            TEXT NOT NULL,
        body             TEXT NOT NULL,
        target_role      TEXT,
        department_id    TEXT REFERENCES departments(id) ON DELETE SET NULL,
        attachment_url   TEXT,
        is_pinned        INTEGER NOT NULL DEFAULT 0,
        published_by     TEXT NOT NULL,
        published_by_name TEXT,
        created_at       TEXT NOT NULL,
        updated_at       TEXT NOT NULL,
        is_deleted       INTEGER NOT NULL DEFAULT 0,
        sync_status      TEXT NOT NULL DEFAULT 'PENDING',
        is_synced        INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── Supporting indexes ──────────────────────────────────────────────────
    // Most queries will filter by institute + soft-delete + pin status and sort
    // by created_at DESC, so a composite index on those columns is beneficial.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notices_institute_id
      ON notices(institute_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notices_department_id
      ON notices(department_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notices_target_role
      ON notices(target_role)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_notices_created_at
      ON notices(created_at)
    ''');
  }
}
