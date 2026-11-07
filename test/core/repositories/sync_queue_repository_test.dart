import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/sync_queue_item.dart';
import 'package:attendance_app/core/repositories/sync_queue_repository.dart';

class _InMemoryDbHelper implements DatabaseHelper {
  _InMemoryDbHelper(this._db);
  final Database _db;

  @override
  Future<Database> get database async => _db;

  @override
  Future<int> insert(String table, Map<String, dynamic> data) async =>
      _db.insert(table, data);

  @override
  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async =>
      _db.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);

  @override
  Future<int> update(
    String table, {
    required Map<String, dynamic> data,
    required String where,
    List<Object?>? whereArgs,
  }) async =>
      _db.update(table, data, where: where, whereArgs: whereArgs);

  @override
  Future<int> delete(
    String table, {
    required String where,
    List<Object?>? whereArgs,
  }) async =>
      _db.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> close() async => _db.close();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncQueueRepository', () {
    late Database db;
    late SyncQueueRepository repo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await FreshDatabaseCreator.createAndSeed(db);
      repo = SyncQueueRepository(dbHelper: _InMemoryDbHelper(db));
    });

    tearDown(() async {
      await db.close();
    });

    test('enqueues mutations and retrieves them in FIFO order', () async {
      await repo.enqueue(
        entityType: 'classes',
        entityId: 'class-uuid-1',
        operation: SyncOperation.create,
        payload: {'name': 'CIT-1', 'section': 'A'},
      );

      await repo.enqueue(
        entityType: 'students',
        entityId: 'student-uuid-1',
        operation: SyncOperation.update,
        payload: {'name': 'Zahid', 'status': 'ACTIVE'},
      );

      expect(await repo.getPendingCount(), 2);

      final items = await repo.getPendingItems();
      expect(items, hasLength(2));
      expect(items[0].entityType, 'classes');
      expect(items[0].entityId, 'class-uuid-1');
      expect(items[0].operation, SyncOperation.create);
      expect(items[0].payload['name'], 'CIT-1');

      expect(items[1].entityType, 'students');
      expect(items[1].entityId, 'student-uuid-1');
      expect(items[1].operation, SyncOperation.update);
      expect(items[1].payload['name'], 'Zahid');
    });

    test('deletes processed item from the queue', () async {
      await repo.enqueue(
        entityType: 'attendance_records',
        entityId: 'att-uuid-1',
        operation: SyncOperation.create,
        payload: {'status': 'PRESENT'},
      );

      final items = await repo.getPendingItems();
      expect(items, hasLength(1));

      await repo.delete(items.first.id);
      expect(await repo.getPendingCount(), 0);
    });

    test('markFailed increments retry_count and stores last_error', () async {
      await repo.enqueue(
        entityType: 'leave_requests',
        entityId: 'leave-uuid-1',
        operation: SyncOperation.create,
        payload: {'reason': 'Sick'},
      );

      var items = await repo.getPendingItems();
      final itemId = items.first.id;

      await repo.markFailed(itemId, '500 Internal Server Error');

      // Item is in backoff (next_retry_at in the future), so getPendingItems()
      // excludes it — use getItem() to inspect it directly.
      final item = await repo.getItem(itemId);
      expect(item, isNotNull);
      expect(item!.retryCount, 1);
      expect(item.lastError, '500 Internal Server Error');
      expect(item.status, SyncStatus.pending);
      expect(item.nextRetryAt, isNotNull);
    });

    test('permanent errors quarantine the item immediately (no retry)', () async {
      await repo.enqueue(
        entityType: 'students',
        entityId: 'student-uuid-1',
        operation: SyncOperation.update,
        payload: {'name': 'Zahid'},
      );
      final itemId = (await repo.getPendingItems()).first.id;

      await repo.markFailed(itemId, '403 Forbidden: RLS denial', permanent: true);

      // Quarantined items are never returned for draining.
      expect(await repo.getPendingItems(), isEmpty);
      final item = await repo.getItem(itemId);
      expect(item, isNotNull);
      expect(item!.retryCount, 1);
      expect(item.lastError, '403 Forbidden: RLS denial');
      expect(item.status, SyncStatus.quarantined);
    });

    test('transient failures back off and quarantine after the retry cap', () async {
      await repo.enqueue(
        entityType: 'attendance_records',
        entityId: 'att-uuid-1',
        operation: SyncOperation.create,
        payload: {'status': 'PRESENT'},
      );
      final itemId = (await repo.getPendingItems()).first.id;

      // First four transient failures: retried with backoff, never quarantined.
      for (var attempt = 1; attempt <= 4; attempt++) {
        await repo.markFailed(itemId, 'timeout (attempt $attempt)');
        final item = await repo.getItem(itemId);
        expect(item!.status, SyncStatus.pending);
        expect(item.retryCount, attempt);
        expect(item.nextRetryAt, isNotNull);
        expect(item.nextRetryAt!.isAfter(DateTime.now()), isTrue);
        // Not yet due for draining while the backoff window is open.
        final due = await repo.getPendingItems();
        expect(due, isEmpty, reason: 'attempt $attempt is in backoff');
      }

      // The fifth failure hits the cap: quarantined, never retried again.
      await repo.markFailed(itemId, 'timeout (attempt 5)');
      expect(await repo.getPendingItems(), isEmpty);
      final item = await repo.getItem(itemId);
      expect(item, isNotNull);
      expect(item!.retryCount, 5);
      expect(item.status, SyncStatus.quarantined);
      expect(item.nextRetryAt, isNull);
    });
  });
}
