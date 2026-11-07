import 'dart:async';
import 'dart:io';

import 'package:postgrest/postgrest.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/sync_queue_item.dart';

/// Repository managing offline queue mutations in SQLite.
///
/// Failed items are categorized into transient errors (offline, timeouts,
/// 5xx) which are retried with exponential backoff up to
/// [maxTransientRetries], and permanent errors (401 Unauthorized, 403
/// Forbidden / RLS denial, 400 Bad Request, missing columns) which are moved
/// to `QUARANTINED` immediately and never retried automatically.
class SyncQueueRepository {
  SyncQueueRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Maximum transient-retry attempts before an item is quarantined.
  static const int maxTransientRetries = 5;

  /// Cap for the exponential backoff delay (seconds).
  static const int _maxBackoffSeconds = 3600;

  /// Enqueues a sync operation for an entity.
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = await _dbHelper.database;
    final item = SyncQueueItem(
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
    );
    await db.insert('sync_queue', item.toMap());
  }

  /// Retrieves due `PENDING` items in FIFO order.
  ///
  /// Items in backoff (`next_retry_at` in the future) and quarantined items
  /// are excluded — they are never drained by the sync loop.
  Future<List<SyncQueueItem>> getPendingItems({int limit = 100}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sync_queue',
      where: 'status = ? AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      whereArgs: [
        SyncStatus.pending.value,
        DateTime.now().toUtc().toIso8601String(),
      ],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(SyncQueueItem.fromMap).toList();
  }

  /// Removes an item once successfully synced.
  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Looks a single queue item up by id (used for tests / admin inspection).
  Future<SyncQueueItem?> getItem(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncQueueItem.fromMap(rows.first);
  }

  /// Records a failed sync attempt for [id].
  ///
  /// When [permanent] is true (401/403/400 or RLS denial) the item is moved
  /// to `QUARANTINED` immediately. Otherwise `retry_count` is incremented and
  /// the item stays `PENDING` with an exponential backoff until it hits
  /// [maxTransientRetries], at which point it is quarantined too.
  Future<void> markFailed(String id, String error, {bool permanent = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sync_queue',
      columns: ['retry_count'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final nextCount = ((rows.firstOrNull?['retry_count'] as int?) ?? 0) + 1;

    final shouldQuarantine = permanent || nextCount >= maxTransientRetries;
    final now = DateTime.now().toUtc();
    String? nextRetryAt;
    if (!shouldQuarantine) {
      final delaySeconds = (1 << nextCount); // 2, 4, 8, 16 ...
      final capped = delaySeconds > _maxBackoffSeconds
          ? _maxBackoffSeconds
          : delaySeconds;
      nextRetryAt = now.add(Duration(seconds: capped)).toIso8601String();
    }

    await db.update(
      'sync_queue',
      {
        'retry_count': nextCount,
        'last_error': error,
        'status': shouldQuarantine
            ? SyncStatus.quarantined.value
            : SyncStatus.pending.value,
        'next_retry_at': nextRetryAt,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Whether [error] is a permanent failure that must not be retried:
  /// HTTP 401 Unauthorized, 403 Forbidden (includes Postgres RLS denial,
  /// SQLSTATE `42501`), 400 Bad Request, or any schema/payload error Postgres
  /// can never resolve by retrying. Network, timeout, and 5xx errors are
  /// transient (retried with backoff, then quarantined after the cap).
  static bool isPermanentError(Object error) {
    if (error is PostgrestException) {
      final code = error.code;
      if (code == '42501' ||      // insufficient_privilege — RLS denial
          code == '42P01' ||      // undefined_table
          code == '42703' ||      // undefined_column
          code == '23502' ||      // not_null_violation
          code == '23505') {      // unique_violation
        return true;
      }
      final message = error.message.toLowerCase();
      if (message.contains('401') ||
          message.contains('unauthorized') ||
          message.contains('invalid jwt') ||
          message.contains('jwt') ||
          message.contains('403') ||
          message.contains('forbidden') ||
          message.contains('400') ||
          message.contains('bad request')) {
        return true;
      }
      return false; // 5xx / other postgres errors → transient
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return false;
    }
    // Unknown error types are treated as transient (bounded by the retry cap
    // so they cannot loop forever).
    return false;
  }

  /// Gets the total number of items currently awaiting sync (PENDING only;
  /// quarantined items are held separately).
  Future<int> getPendingCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM sync_queue WHERE status = ?',
      [SyncStatus.pending.value],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Clears the queue (e.g. for testing or reset).
  Future<void> clear() async {
    final db = await _dbHelper.database;
    await db.delete('sync_queue');
  }
}
