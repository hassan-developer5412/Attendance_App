import 'package:sqflite/sqflite.dart';

/// v8 — Sync queue dead-letter queue and retry capping.
///
/// Adds `status` (PENDING | QUARANTINED) and `next_retry_at` to the local
/// `sync_queue` table so failed cloud pushes can be:
///   * retried with exponential backoff for transient errors (offline,
///     timeouts, 5xx), up to a capped attempt count;
///   * quarantined immediately for permanent errors (401 Unauthorized,
///     403 Forbidden / RLS denial, 400 Bad Request) so they are never retried
///     indefinitely.
///
/// All changes are additive: no existing row is modified or deleted.
class SchemaMigrationV8 {
  SchemaMigrationV8._();

  static Future<void> execute(Database db) async {
    await db.execute(
      "ALTER TABLE sync_queue ADD COLUMN status TEXT NOT NULL DEFAULT 'PENDING'",
    );
    await db.execute('ALTER TABLE sync_queue ADD COLUMN next_retry_at TEXT');
  }
}
