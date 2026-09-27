import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

      items = await repo.getPendingItems();
      expect(items.first.retryCount, 1);
      expect(items.first.lastError, '500 Internal Server Error');
    });
  });
}
