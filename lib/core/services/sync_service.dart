import 'dart:async';
import 'dart:convert';

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
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Pushes local SQLite writes to Supabase. SQLite stays the source of truth:
/// every call here is best-effort and must never break the offline app.
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

  /// Pushes are only allowed when an authenticated Supabase session exists so
  /// every cloud request carries the signed-in user's JWT (auth.uid()).
  /// We never push anonymously under the anon key.
  bool get _authenticated =>
      _enabled && Supabase.instance.client.auth.currentUser != null;

  /// Cached tenant context for the current flush cycle; reset each cycle so a
  /// profile change is picked up on the next drain.
  _TenantContext? _cachedTenantContext;

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
    'leave_requests': 'id',
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

  // ===========================================================================
  // VERBOSE LOGGING HELPERS
  // ===========================================================================

  void _log(String message) {
    debugPrint('[SyncService] $message');
  }

  void _logError(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('================ [SyncService ERROR] ================');
    debugPrint(message);
    if (error != null) {
      if (error is PostgrestException) {
        debugPrint('  Type: PostgrestException');
        debugPrint('  Code: ${error.code}');
        debugPrint('  Message: ${error.message}');
        debugPrint('  Details: ${error.details}');
        debugPrint('  Hint: ${error.hint}');
      } else {
        debugPrint('  Error: $error');
      }
    }
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
    debugPrint('=====================================================');
  }

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Fire-and-forget push of the local row identified by
  /// ([idColumn], [idValue]) in [table].
  void schedulePush(
    String table, {
    required String idColumn,
    required Object? idValue,
  }) {
    if (!_enabled) {
      _log('schedulePush SKIPPED ($table/$idValue): SupabaseConfig.isReady is FALSE');
      return;
    }
    if (idValue == null) {
      _log('schedulePush SKIPPED ($table): idValue is null');
      return;
    }
    _log('schedulePush TRIGGERED for table "$table" ($idColumn =$idValue)');
    unawaited(_pushLocalRow(table, idColumn, idValue));
  }

  /// Uploads an attachment to Supabase Storage.
  /// If offline or upload fails, gracefully queues the upload into `sync_queue`
  /// and returns a queued placeholder URI.
  Future<String?> uploadAttachment({
    required String fileName,
    required List<int> bytes,
    String bucket = 'leave-attachments',
    String? contentType,
  }) async {
    final sanitizedName =
        fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'leaves/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';

    if (_authenticated) {
      try {
        final client = Supabase.instance.client;
        _log('Uploading attachment to Supabase Storage: $bucket/$storagePath');
        await client.storage.from(bucket).uploadBinary(
              storagePath,
              Uint8List.fromList(bytes),
              fileOptions: FileOptions(
                contentType: contentType ?? 'application/octet-stream',
                upsert: true,
              ),
            );
        final publicUrl = client.storage.from(bucket).getPublicUrl(storagePath);
        _log('Attachment uploaded successfully: $publicUrl');
        return publicUrl;
      } catch (e, s) {
        _logError('Supabase Storage upload failed, queuing for offline retry', e, s);
      }
    } else {
      _log('No authenticated Supabase session. Queuing storage upload offline.');
    }

    // Offline or upload failed: queue in sync_queue
    await queueStorageUpload(
      bucket: bucket,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    );

    return 'offline_queued://$storagePath';
  }

  /// Enqueues a binary attachment for background upload when connectivity returns.
  Future<void> queueStorageUpload({
    required String bucket,
    required String fileName,
    required List<int> bytes,
    String? contentType,
  }) async {
    try {
      await _queue.enqueue(
        entityType: 'storage:$bucket',
        entityId: UuidUtils.generate(),
        operation: SyncOperation.create,
        payload: {
          'bucket': bucket,
          'fileName': fileName,
          'base64Data': base64Encode(bytes),
          'contentType': contentType ?? 'application/octet-stream',
          'queued_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _log('Attachment successfully queued for offline sync: $fileName');
    } catch (e, s) {
      _logError('Failed to enqueue attachment for offline sync', e, s);
    }
  }

  /// Starts the periodic background flush. Idempotent; no-op when not enabled.
  Future<void> start() async {
    if (!_enabled) {
      _log('start() SKIPPED: SupabaseConfig.isReady is FALSE');
      return;
    }
    if (_timer != null) {
      _log('start() SKIPPED: Periodic timer is already running');
      return;
    }
    _log('Starting periodic background sync timer (Interval: ${flushInterval.inSeconds}s)');
    unawaited(flushSyncQueue());
    _timer = Timer.periodic(flushInterval, (_) => unawaited(flushSyncQueue()));
  }

  /// Stops the periodic flush (used by tests / shutdown).
  void stop() {
    if (_timer != null) {
      _log('Stopping background sync timer');
      _timer?.cancel();
      _timer = null;
    }
  }

  /// One synchronous pass: top up `sync_queue` from unsynced local rows,
  /// then drain the queue. Safe to call at any time; no-op when not enabled.
  Future<void> flushSyncQueue() async {
    if (!_enabled) {
      _log('flushSyncQueue SKIPPED: SupabaseConfig.isReady is FALSE');
      return;
    }
    if (_flushing) {
      _log('flushSyncQueue SKIPPED: A flush cycle is already in progress');
      return;
    }
    _flushing = true;
    _cachedTenantContext = null; // re-resolve tenant from the authenticated profile each cycle
    final stopwatch = Stopwatch()..start();
    _log('>>> FLUSH SYNC QUEUE CYCLE STARTED <<<');
    try {
      await _enqueueUnsyncedRows();
      await _drainQueue();
      _log('<<< FLUSH SYNC QUEUE CYCLE COMPLETED in ${stopwatch.elapsedMilliseconds}ms >>>');
    } catch (e, s) {
      _logError('Flush cycle encountered an unhandled error', e, s);
    } finally {
      _flushing = false;
    }
  }

  // ===========================================================================
  // INTERNAL IMPLEMENTATION
  // ===========================================================================

  Future<void> _pushLocalRow(
    String table,
    String idColumn,
    Object idValue,
  ) async {
    if (!_authenticated) {
      _log('_pushLocalRow ($table/$idValue) SKIPPED: no authenticated Supabase session');
      return;
    }
    Map<String, dynamic>? payload;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        table,
        where: '$idColumn = ?',
        whereArgs: [idValue],
        limit: 1,
      );
      if (rows.isEmpty) {
        _log('_pushLocalRow ($table/$idValue): Local SQLite row not found');
        return;
      }
      final converter = _converters[table];
      if (converter == null) {
        _log('_pushLocalRow ($table/$idValue): No converter found for table$table');
        return;
      }
      payload = converter(rows.first);
      _log('_pushLocalRow ($table/${payload['id']}): Payload generated with${payload.length} keys');
      final context = await _tenantContext();
      await _upsert(table, payload, context);
      await _markSynced(table, payload);
      _log('_pushLocalRow SUCCESS ($table/${payload['id']})');
    } catch (e, s) {
      _logError('Direct push failed for $table/$idValue (queuing for background retry)', e, s);
      if (payload != null) {
        await _enqueueQuietly(table, payload);
      }
    }
  }

  /// Resolves (and caches per cycle) the tenant context for the authenticated
  /// Supabase user. `institute_id`/`role` come from `public.profiles`, which is
  /// bound to `auth.users.id` — never from a client-supplied value.
  Future<_TenantContext> _tenantContext() async {
    if (_cachedTenantContext != null) return _cachedTenantContext!;
    if (!_authenticated) {
      throw StateError(
        'No authenticated Supabase session; refusing to push anonymously.',
      );
    }
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final profile = await client
        .from('profiles')
        .select('institute_id, role')
        .eq('id', userId)
        .single();
    final instituteId = (profile['institute_id'] as dynamic)?.toString();
    if (instituteId == null || instituteId.isEmpty) {
      throw StateError(
        'Authenticated user profile is missing institute_id; cannot determine tenant.',
      );
    }
    return _cachedTenantContext = _TenantContext(
      userId: userId,
      instituteId: instituteId,
      role: (profile['role'] as dynamic)?.toString() ?? '',
    );
  }

  Future<void> _upsert(
    String table,
    Map<String, dynamic> payload,
    _TenantContext context,
  ) async {
    final client = Supabase.instance.client;
    final finalPayload = <String, dynamic>{
      ...payload,
      'institute_id': context.instituteId,
    };
    _log(
      'Sending Supabase UPSERT to table "$table" '
      '(ID: ${finalPayload['id']}, Tenant:${context.instituteId}, User:${context.userId})',
    );
    await client.from(table).upsert(finalPayload);
  }

  Future<void> _markSynced(String table, Map<String, dynamic> payload) async {
    final idColumn = _idColumns[table];
    if (idColumn == null) {
      _log('_markSynced WARNING: No idColumn configured for table "$table"');
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final rowsUpdated = await db.update(
      table,
      {'is_synced': 1, 'sync_status': 'SYNCED'},
      where: '$idColumn = ? AND updated_at = ?',
      whereArgs: [payload['id'], payload['updated_at']],
    );
    if (rowsUpdated > 0) {
      _log('Marked local row as SYNCED in "$table" (id: ${payload['id']})');
    } else {
      _log('_markSynced CAS MISMATCH in "$table" (id: ${payload['id']}): Row was modified locally during push attempt');
    }
  }

  Future<void> _enqueueUnsyncedRows() async {
    final db = await DatabaseHelper.instance.database;
    final alreadyQueued = <String>{};
    final pending = await _queue.getPendingItems(limit: _queueLookupsLimit);
    for (final item in pending) {
      alreadyQueued.add('${item.entityType}:${item.entityId}');
    }

    _log('Scanning local tables for unsynced rows (${alreadyQueued.length} items currently in retry queue)...');
    int newlyEnqueued = 0;

    for (final table in _converters.keys) {
      final rows = await db.query(
        table,
        where: "is_synced = 0 OR sync_status = 'PENDING'",
        limit: _scanBatchPerTable,
      );
      if (rows.isNotEmpty) {
        _log('Found ${rows.length} unsynced rows in "$table"');
      }
      for (final row in rows) {
        final payload = _converters[table]!(row);
        final entityId = payload['id']?.toString();
        if (entityId == null || entityId.isEmpty) {
          _log('WARNING: Row in "$table" missing UUID payload id. Skipping.');
          continue;
        }
        final key = '$table:$entityId';
        if (alreadyQueued.contains(key)) continue;
        alreadyQueued.add(key);
        await _enqueueQuietly(table, payload, knownAbsent: true);
        newlyEnqueued++;
      }
    }
    if (newlyEnqueued > 0) {
      _log('Enqueued $newlyEnqueued new unsynced rows into sync_queue');
    }
  }

  Future<void> _drainQueue() async {
    // Resolve the authenticated tenant once per cycle. Throws when there is no
    // Supabase session (or no profile), so no item is ever pushed anonymously.
    final context = await _tenantContext();
    final items = await _queue.getPendingItems(limit: _drainBatch);
    if (items.isEmpty) {
      _log('Queue is empty. Nothing to drain.');
      return;
    }
    _log('Draining queue: Processing ${items.length} pending items...');
    int successCount = 0;
    int failCount = 0;

    for (final item in items) {
      try {
        _log('Processing queued item ${item.entityType}/${item.entityId} (Attempt:${item.retryCount})');
        if (item.entityType.startsWith('storage:')) {
          await _uploadQueuedStorageItem(item);
          await _queue.delete(item.id);
          _log('Queue storage upload SUCCESS for ${item.entityType}/${item.entityId}');
        } else {
          await _upsert(item.entityType, item.payload, context);
          await _queue.delete(item.id);
          await _markSynced(item.entityType, item.payload);
          _log('Queue push SUCCESS for ${item.entityType}/${item.entityId}');
        }
        successCount++;
      } catch (e, s) {
        failCount++;
        _logError('Queue push FAILED for ${item.entityType}/${item.entityId}', e, s);
        try {
          // Permanent auth/RLS/payload failures (401/403/400, RLS denial,
          // missing columns, unique/not-null violations) are quarantined
          // immediately; transient errors (offline, timeouts, 5xx) back off
          // and are quarantined only after the retry cap.
          await _queue.markFailed(
            item.id,
            e.toString(),
            permanent: SyncQueueRepository.isPermanentError(e),
          );
        } catch (markError) {
          _logError('Failed to record failure state in sync_queue DB', markError);
        }
      }
    }
    _log('Queue drain finished: $successCount succeeded,$failCount failed.');
  }

  Future<void> _uploadQueuedStorageItem(SyncQueueItem item) async {
    final client = Supabase.instance.client;
    final payload = item.payload;
    final bucket = (payload['bucket'] as String?) ?? 'leave-attachments';
    final fileName = (payload['fileName'] as String?) ?? 'file';
    final base64Data = (payload['base64Data'] as String?) ?? '';
    final contentType = payload['contentType'] as String?;
    final bytes = base64Decode(base64Data);
    final sanitizedName =
        fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'leaves/${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
    await client.storage.from(bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType ?? 'application/octet-stream',
            upsert: true,
          ),
        );
  }

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
        if (exists) {
          _log('_enqueueQuietly SKIPPED ($table/$entityId): Already in queue');
          return;
        }
      }
      await _queue.enqueue(
        entityType: table,
        entityId: entityId,
        operation: payload['is_deleted'] == true
            ? SyncOperation.delete
            : SyncOperation.update,
        payload: payload,
      );
      _log('Enqueued item into retry queue: $table/$entityId');
    } catch (e, s) {
      _logError('Failed to enqueue sync item for table $table', e, s);
    }
  }
}

/// Resolved tenant + identity context for the current Supabase session.
/// `institute_id` is read from `public.profiles` (bound to auth.users.id) so
/// a client can never forge a tenant id.
class _TenantContext {
  const _TenantContext({
    required this.userId,
    required this.instituteId,
    required this.role,
  });

  final String userId;
  final String instituteId;
  final String role;
}
