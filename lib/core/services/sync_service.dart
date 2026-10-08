import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/attendance_session.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/sync_queue_item.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/sync_queue_repository.dart';

/// Pushes local SQLite writes to Supabase. SQLite stays the source of truth:
/// every call here is best-effort and must never break the offline app.
///
/// Design:
///  * [schedulePush] — called by repositories right after a local write.
///    Fire-and-forget: re-reads the written row, upserts it to Supabase and
///    marks it synced. On any failure the row is enqueued into `sync_queue`
///    for background retry (and stays unsynced regardless).
///  * [flushSyncQueue] — runs periodically (see [start]). First tops up the
///    queue from unsynced local rows (covers initial backfill after the v5
///    migration and writes made while offline), then drains the queue
///    FIFO with idempotent upserts.
///  * Rows are marked synced with a compare-and-set on `updated_at` so an
///    edit racing a push is never silently lost.
///
/// All pushes upsert on the canonical `id` (uuid / TEXT PK), stamp the
/// central `institute_id`, and treat remote soft-deletes as data
/// (`is_deleted = true` payloads) — the queue's [SyncOperation] is advisory
/// only, never a hard `DELETE`.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  /// Cadence of the background queue flush.
  static const Duration flushInterval = Duration(seconds: 60);

  /// Max rows scanned per table per flush cycle when topping up the queue.
  static const int _scanBatchPerTable = 100;

  /// Max queue items pushed per flush cycle.
  static const int _drainBatch = 100;

  /// Upper bound when checking the queue for duplicate entities.
  static const int _queueLookupsLimit = 1000;

  final SyncQueueRepository _queue = SyncQueueRepository();

  Timer? _timer;
  bool _flushing = false;

  /// Master gate: never touch `Supabase.instance` (it asserts) unless the
  /// app configured credentials AND `Supabase.initialize()` succeeded.
  bool get _enabled => SupabaseConfig.isReady;

  /// Local column used to compare-and-set a row as synced, per table.
  /// Legacy INTEGER-PK tables sync via their `uuid` column; the rest via `id`.
  static const Map<String, String> _idColumns = <String, String>{
    'departments': 'id',
    'academic_sessions': 'id',
    'users': 'uuid',
    'classes': 'uuid',
    'teachers': 'uuid',
    'students': 'uuid',
    'subjects': 'uuid',
    'attendance_sessions': 'id',
    'attendance_records': 'uuid',
    'leave_requests': 'uuid',
    'lab_inventory': 'id',
  };

  /// Row → Supabase payload converters. Keys double as the list of tables
  /// scanned for unsynced rows (keep in sync with SchemaMigrationV5).
  static final Map<String, Map<String, dynamic> Function(Map<String, dynamic>)>
      _converters =
      <String, Map<String, dynamic> Function(Map<String, dynamic>)>{
    'departments': (row) => Department.fromMap(row).toSupabaseJson(),
    'academic_sessions': (row) => AcademicSession.fromMap(row).toSupabaseJson(),
    'users': (row) => User.fromMap(row).toSupabaseJson(),
    'classes': (row) => SchoolClass.fromMap(row).toSupabaseJson(),
    'teachers': (row) => Teacher.fromMap(row).toSupabaseJson(),
    'students': (row) => Student.fromMap(row).toSupabaseJson(),
    'subjects': (row) => Subject.fromMap(row).toSupabaseJson(),
    'attendance_sessions': (row) =>
        AttendanceSession.fromMap(row).toSupabaseJson(),
    'attendance_records': (row) =>
        AttendanceRecord.fromMap(row).toSupabaseJson(),
    'leave_requests': (row) => LeaveRequest.fromMap(row).toSupabaseJson(),
    'lab_inventory': (row) => LabInventory.fromMap(row).toSupabaseJson(),
  };

  /// Fire-and-forget push of the local row identified by
  /// ([idColumn], [idValue]) in [table].
  ///
  /// Called by repositories immediately after a local write. Never throws
  /// and never blocks the caller; a no-op when Supabase is not ready or
  /// [idValue] is null.
  void schedulePush(
    String table, {
    required String idColumn,
    required Object? idValue,
  }) {
    if (!_enabled || idValue == null) return;
    unawaited(_pushLocalRow(table, idColumn, idValue));
  }

  /// Starts the periodic background flush. Idempotent; no-op when not enabled.
  Future<void> start() async {
    if (!_enabled || _timer != null) return;
    unawaited(flushSyncQueue());
    _timer = Timer.periodic(flushInterval, (_) => unawaited(flushSyncQueue()));
  }

  /// Stops the periodic flush (used by tests / shutdown).
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One synchronous pass: top up `sync_queue` from unsynced local rows,
  /// then drain the queue. Safe to call at any time; no-op when not enabled.
  Future<void> flushSyncQueue() async {
    if (!_enabled || _flushing) return;
    _flushing = true;
    try {
      await _enqueueUnsyncedRows();
      await _drainQueue();
    } catch (e, s) {
      debugPrint('Supabase sync flush failed: $e');
      debugPrintStack(stackTrace: s);
    } finally {
      _flushing = false;
    }
  }

  /// Re-tags every local row to [instituteId] (single-institute-per-device
  /// model) and marks them unsynced so the next flush re-pushes the dataset
  /// under the new tenant. Idempotent and local-only — safe when offline.
  void retagLocalRows(String instituteId) {
    if (instituteId.isEmpty) return;
    unawaited(_retagLocalRows(instituteId));
  }

  Future<void> _retagLocalRows(String instituteId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      for (final table in _converters.keys) {
        await db.update(
          table,
          {
            'institute_id': instituteId,
            'is_synced': 0,
            'sync_status': 'PENDING',
          },
          where: 'institute_id != ?',
          whereArgs: [instituteId],
        );
      }
    } catch (e) {
      debugPrint('Failed to retag local rows for institute $instituteId: $e');
    }
  }

  /// Reads the just-written row, pushes it, and compare-and-sets the synced
  /// flags against the payload's `updated_at`.
  Future<void> _pushLocalRow(
    String table,
    String idColumn,
    Object idValue,
  ) async {
    Map<String, dynamic>? payload;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        table,
        where: '$idColumn = ?',
        whereArgs: [idValue],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final converter = _converters[table];
      if (converter == null) return;
      payload = converter(rows.first);
      await _upsert(table, payload);
      await _markSynced(table, payload);
    } catch (e) {
      debugPrint('Supabase push failed for $table/$idValue '
          '(queued for background retry): $e');
      if (payload != null) {
        await _enqueueQuietly(table, payload);
      }
    }
  }

  /// Upserts [payload] into Supabase, stamping the central tenant id.
  Future<void> _upsert(String table, Map<String, dynamic> payload) async {
    final client = Supabase.instance.client;
    await client.from(table).upsert(<String, dynamic>{
      ...payload,
      'institute_id': SupabaseConfig.instituteId,
    });
  }

  /// Marks the local row as synced only if it has not been edited since
  /// [payload] was built (CAS on `updated_at`).
  Future<void> _markSynced(String table, Map<String, dynamic> payload) async {
    final idColumn = _idColumns[table];
    if (idColumn == null) return;
    final db = await DatabaseHelper.instance.database;
    await db.update(
      table,
      {'is_synced': 1, 'sync_status': 'SYNCED'},
      where: '$idColumn = ? AND updated_at = ?',
      whereArgs: [payload['id'], payload['updated_at']],
    );
  }

  /// Scans every synced table for rows needing upload (`is_synced = 0` covers
  /// the post-migration backfill; `sync_status = 'PENDING'` covers writes that
  /// predate or bypass the `is_synced` flag) and enqueues them, skipping
  /// entities already waiting in the queue.
  Future<void> _enqueueUnsyncedRows() async {
    final db = await DatabaseHelper.instance.database;
    final alreadyQueued = <String>{};
    final pending = await _queue.getPendingItems(limit: _queueLookupsLimit);
    for (final item in pending) {
      alreadyQueued.add('${item.entityType}:${item.entityId}');
    }

    for (final table in _converters.keys) {
      final rows = await db.query(
        table,
        where: "is_synced = 0 OR sync_status = 'PENDING'",
        limit: _scanBatchPerTable,
      );
      for (final row in rows) {
        final payload = _converters[table]!(row);
        final entityId = payload['id']?.toString();
        if (entityId == null || entityId.isEmpty) continue;
        final key = '$table:$entityId';
        if (alreadyQueued.contains(key)) continue;
        alreadyQueued.add(key);
        await _enqueueQuietly(table, payload, knownAbsent: true);
      }
    }
  }

  /// Drains the queue FIFO, upserting each payload and deleting the item on
  /// success. Failures are recorded via `markFailed` and retried next cycle;
  /// one bad item never blocks the items behind it.
  Future<void> _drainQueue() async {
    final items = await _queue.getPendingItems(limit: _drainBatch);
    for (final item in items) {
      try {
        await _upsert(item.entityType, item.payload);
        await _queue.delete(item.id);
        await _markSynced(item.entityType, item.payload);
      } catch (e) {
        debugPrint('Supabase queue push failed for '
            '${item.entityType}/${item.entityId}: $e');
        try {
          await _queue.markFailed(item.id, e.toString());
        } catch (markError) {
          debugPrint('Failed to record sync failure: $markError');
        }
      }
    }
  }

  /// Enqueues [payload] for background retry unless the same entity is
  /// already waiting. Never throws.
  Future<void> _enqueueQuietly(
    String table,
    Map<String, dynamic> payload, {
    bool knownAbsent = false,
  }) async {
    try {
      final entityId = payload['id']?.toString();
      if (entityId == null || entityId.isEmpty) return;
      if (!knownAbsent) {
        final pending =
            await _queue.getPendingItems(limit: _queueLookupsLimit);
        final exists = pending.any(
          (item) => item.entityType == table && item.entityId == entityId,
        );
        if (exists) return;
      }
      await _queue.enqueue(
        entityType: table,
        entityId: entityId,
        operation: payload['is_deleted'] == true
            ? SyncOperation.delete
            : SyncOperation.update,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Failed to enqueue sync item for $table: $e');
    }
  }
}