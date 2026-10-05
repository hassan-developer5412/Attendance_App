import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/sync_queue_item.dart';

/// Repository managing offline queue mutations in SQLite.
class SyncQueueRepository {
  SyncQueueRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

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

  /// Retrieves all pending items in FIFO order.
  Future<List<SyncQueueItem>> getPendingItems({int limit = 100}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'sync_queue',
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

  /// Increments retry count and sets last error message upon failed sync attempt.
  Future<void> markFailed(String id, String error) async {
    final db = await _dbHelper.database;
    await db.rawUpdate('''
      UPDATE sync_queue
      SET retry_count = retry_count + 1,
          last_error = ?
      WHERE id = ?
    ''', [error, id]);
  }

  /// Gets the total number of items currently awaiting sync.
  Future<int> getPendingCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sync_queue');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Clears the queue (e.g. for testing or reset).
  Future<void> clear() async {
    final db = await _dbHelper.database;
    await db.delete('sync_queue');
  }
}
