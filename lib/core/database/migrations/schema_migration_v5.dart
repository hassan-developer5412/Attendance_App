import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';

/// Non-destructive migration adding the Supabase replication columns:
///
///  * `institute_id` — tenant ownership stamped on rows and mirrored to
///    Supabase payloads (see `SupabaseConfig.instituteId`).
///  * `is_synced` — `0` = needs upload, `1` = acknowledged by Supabase.
///
/// Existing rows are kept untouched and start unsynced (`is_synced = 0`), so
/// the first background flush uploads the full local dataset using idempotent
/// upserts. Primary keys are NOT modified: TEXT-uuid tables keep their uuid
/// PK and legacy INTEGER tables keep their `uuid` column, so no local schema
/// routine is wiped or rewritten.
class SchemaMigrationV5 {
  SchemaMigrationV5._();

  /// Every table replicated to Supabase. `sync_queue` is local-only and is
  /// intentionally excluded.
  static const List<String> syncedTables = <String>[
    'departments',
    'academic_sessions',
    'users',
    'classes',
    'teachers',
    'students',
    'subjects',
    'attendance_sessions',
    'attendance_records',
    'leave_requests',
    'lab_inventory',
  ];

  static Future<void> execute(Database db) async {
    for (final table in syncedTables) {
      await MigrationHelpers.addColumnIfNotExists(
        db,
        table,
        'institute_id',
        "TEXT NOT NULL DEFAULT '${AppConstants.defaultInstituteId}'",
      );
      await MigrationHelpers.addColumnIfNotExists(
        db,
        table,
        'is_synced',
        'INTEGER NOT NULL DEFAULT 0',
      );
    }
  }
}