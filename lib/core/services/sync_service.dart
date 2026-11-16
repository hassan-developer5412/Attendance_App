import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
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

/// Lifecycle state of the sync engine.
///
/// Distinct from `SyncStatus` in `app_constants.dart`, which describes the
/// lifecycle of a single queue row (`pending` / `synced` / `quarantined`).
enum SyncState {
  /// No cycle running and nothing outstanding.
  idle,
  /// A push/pull cycle is in progress.
  syncing,
  /// Supabase is not configured or not initialized (offline-only mode).
  offline,
  /// The last cycle failed; see [SyncService.lastError].
  error,
}

/// Pushes local SQLite writes to Supabase and pulls remote changes down.
/// Supabase is the source of truth; SQLite is the offline cache.
/// Every call here is best-effort and must never break the offline app.
class SyncService with ChangeNotifier {
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

  /// Lifecycle state of the sync engine, exposed reactively so the UI can
  /// render a live badge without polling the database.
  SyncState _state =
      SupabaseConfig.isReady ? SyncState.idle : SyncState.offline;

  /// Queue rows awaiting push (PENDING, including items in backoff).
  int _pendingCount = 0;

  /// Permanently failed (quarantined) queue rows.
  int _failedCount = 0;

  /// Timestamp of the most recent successful pull cycle.
  DateTime? _lastSyncedAt;

  /// Error captured during the last failed sync cycle, if any.
  Object? _lastError;

  /// Coalesces concurrent count-refresh passes.
  bool _countsRefreshing = false;

  /// Master gate: never touch `Supabase.instance` (it asserts) unless the
  /// app configured credentials AND `Supabase.initialize()` succeeded.
  bool get _enabled => SupabaseConfig.isReady;

  /// Pushes are only allowed when an authenticated Supabase session exists so
  /// every cloud request carries the signed-in user's JWT (auth.uid()).
  /// We never push anonymously under the anon key.
  bool get _authenticated =>
      _enabled && Supabase.instance.client.auth.currentUser != null;

  /// Current engine lifecycle state: `idle`, `syncing`, `offline`, `error`.
  SyncState get syncState => _state;

  /// Convenience: `true` while a push/pull cycle is running.
  bool get isSyncing => _state == SyncState.syncing;

  /// Number of queue items awaiting push (PENDING).
  int get pendingCount => _pendingCount;

  /// Number of permanently failed (quarantined) queue items.
  int get failedCount => _failedCount;

  /// Timestamp of the most recent successful pull cycle.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Error captured during the last failed sync cycle, if any.
  Object? get lastError => _lastError;

  /// Cached tenant context for the current flush cycle; reset each cycle so a
  /// profile change is picked up on the next drain.
  _TenantContext? _cachedTenantContext;

  /// Callback fired after [pullAll] writes remote changes into SQLite.
  /// Stores subscribe to this to reload their in-memory state from the local
  /// database so the UI reflects the canonical (Supabase-synced) data.
  Future<void> Function()? onPullCompleted;

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
  /// Each cycle pushes pending local rows to Supabase (`_drainQueue`) then pulls
  /// remote changes down into SQLite (`pullAll`), making Supabase the source of
  /// truth while SQLite remains the offline cache.
  Future<void> start() async {
    if (!_enabled) {
      _log('start() SKIPPED: SupabaseConfig.isReady is FALSE');
      _setState(SyncState.offline);
      return;
    }
    if (_timer != null) {
      _log('start() SKIPPED: Periodic timer is already running');
      return;
    }
    _log('Starting periodic background sync timer (Interval: ${flushInterval.inSeconds}s)');
    _setState(SyncState.syncing);
    try {
      await _drainQueue();
      await pullAll();
      if (_state != SyncState.error) _setState(SyncState.idle);
      unawaited(_refreshCounts());
    } catch (e, s) {
      _logError('Initial sync cycle failed', e, s);
      _setError(e);
      _setState(SyncState.error);
    }
    _timer = Timer.periodic(flushInterval, (_) async {
      _setState(SyncState.syncing);
      try {
        await _drainQueue();
        await pullAll();
        if (_state != SyncState.error) _setState(SyncState.idle);
        unawaited(_refreshCounts());
      } catch (e, s) {
        _logError('Background sync cycle failed', e, s);
        _setError(e);
        _setState(SyncState.error);
      }
    });
  }

  /// Stops the periodic flush (used by tests / shutdown).
  void stop() {
    if (_timer != null) {
      _log('Stopping background sync timer');
      _timer?.cancel();
      _timer = null;
    }
  }

  void _setState(SyncState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  void _setError(Object? error) {
    if (_lastError == error) return;
    _lastError = error;
    notifyListeners();
  }

  void _setLastSynced(DateTime? time) {
    if (_lastSyncedAt == time) return;
    _lastSyncedAt = time;
    notifyListeners();
  }

  /// Refreshes [pendingCount] and [failedCount] from [SyncQueueRepository].
  /// Overlapping calls are coalesced so call sites can fire and forget.
  Future<void> _refreshCounts() async {
    if (_countsRefreshing) return;
    _countsRefreshing = true;
    try {
      final pending = await _queue.getPendingCount();
      final failed = await _queue.getQuarantinedCount();
      var changed = false;
      if (pending != _pendingCount) {
        _pendingCount = pending;
        changed = true;
      }
      if (failed != _failedCount) {
        _failedCount = failed;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (e) {
      _log('Refreshing sync counts failed: $e');
    } finally {
      _countsRefreshing = false;
    }
  }

  /// Manual push/pull triggered from the UI: top up `sync_queue` from unsynced
  /// local rows, drain it to Supabase, then pull remote changes into SQLite.
  Future<void> syncNow() async {
    if (!_enabled) {
      _log('syncNow SKIPPED: Supabase is not ready');
      _setState(SyncState.offline);
      return;
    }
    if (_flushing) {
      _log('syncNow SKIPPED: A flush cycle is already in progress');
      return;
    }
    _flushing = true;
    _cachedTenantContext = null;
    _setState(SyncState.syncing);
    _setError(null);
    try {
      await _enqueueUnsyncedRows();
      await _drainQueue();
      await pullAll();
    } catch (e, s) {
      _logError('syncNow failed', e, s);
      _setError(e);
      _setState(SyncState.error);
    } finally {
      _flushing = false;
      if (_state != SyncState.error) _setState(SyncState.idle);
      unawaited(_refreshCounts());
    }
  }

  /// Re-queues a quarantined (permanently failed) queue item so the next
  /// drain cycle retries it. Returns `false` when [id] is unknown or is not
  /// currently quarantined.
  Future<bool> retryItem(String id) async {
    final ok = await _queue.retryItem(id);
    if (ok) {
      _log('Re-queued quarantined item $id for retry');
      unawaited(_refreshCounts());
    }
    return ok;
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
    _setState(SyncState.syncing);
    _setError(null);
    final stopwatch = Stopwatch()..start();
    _log('>>> FLUSH SYNC QUEUE CYCLE STARTED <<<');
    try {
      await _enqueueUnsyncedRows();
      await _drainQueue();
      _log('<<< FLUSH SYNC QUEUE CYCLE COMPLETED in ${stopwatch.elapsedMilliseconds}ms >>>');
    } catch (e, s) {
      _logError('Flush cycle encountered an unhandled error', e, s);
      _setError(e);
      _setState(SyncState.error);
    } finally {
      _flushing = false;
      if (_state != SyncState.error) _setState(SyncState.idle);
      unawaited(_refreshCounts());
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
      unawaited(_refreshCounts());
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
    unawaited(_refreshCounts());
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
          final permanent = SyncQueueRepository.isPermanentError(e);
          await _queue.markFailed(
            item.id,
            e.toString(),
            permanent: permanent,
          );
          // On a permanent rejection (4xx / RLS / payload error), the local
          // row can never win against Supabase. Re-fetch the canonical row
          // from Supabase so SQLite reflects the source of truth, then notify
          // stores via onPullCompleted so they reload from the local DB.
          if (permanent && !item.entityType.startsWith('storage:')) {
            await _reconcileRejectedRow(item.entityType, item.payload);
          }
        } catch (markError) {
          _logError('Failed to record failure state in sync_queue DB', markError);
        }
      }
    }
    _log('Queue drain finished: $successCount succeeded,$failCount failed.');
    unawaited(_refreshCounts());
  }

  /// When a push is permanently rejected by Supabase (4xx / RLS / payload
  /// error), re-fetches the canonical row from Supabase and overwrites the
  /// rejected local row so SQLite reflects the source of truth. Then fires
  /// [onPullCompleted] so stores reload from the local database.
  Future<void> _reconcileRejectedRow(String table, Map<String, dynamic> payload) async {
    if (!_enabled) {
      _log('_reconcileRejectedRow SKIPPED: SupabaseConfig.isReady is FALSE');
      return;
    }
    try {
      final id = payload['id'];
      if (id == null) return;

      final client = Supabase.instance.client;
      final remoteRow = await client.from(table).select('*').eq('id', id).single();

      final db = await DatabaseHelper.instance.database;
      final normalized = await normalizeRemoteRowForSqlite(
        db,
        table,
        Map<String, dynamic>.from(remoteRow),
      );
      if (normalized == null) return;

      await db.insert(
        table,
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _log('Reconciled rejected row $table/$id from Supabase into SQLite');

      // Notify stores so they reload from SQLite now that the canonical row
      // has been written into the local cache.
      if (onPullCompleted != null) {
        await onPullCompleted!();
      }
    } catch (e, s) {
      _logError('Failed to reconcile rejected row $table', e, s);
    }
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

  // ===========================================================================
  // PULL: Supabase -> SQLite (Supabase is the source of truth)
  // ===========================================================================

  /// Foreign-key-safe order for pulling tables from Supabase. Parent tables are
  /// pulled before their children so inserts never violate FK constraints.
  static final List<String> _pullOrder = <String>[
    'departments',
    'academic_sessions',
    'users',
    'roles',
    'permissions',
    'role_permissions',
    'user_roles',
    'user_departments',
    'classes',
    'teachers',
    'students',
    'subjects',
    'attendance_sessions',
    'attendance_records',
    'leave_requests',
    'lab_inventory',
  ];

  /// Pulls incremental changes from Supabase into SQLite for every table in
  /// [_pullOrder]. Per-table `last_synced_at` timestamps are tracked in
  /// SharedPreferences so only rows with `updated_at` newer than the last sync
  /// are fetched. Local rows whose `sync_status == 'PENDING'` are never
  /// overwritten — they are left alone until `drainQueue()` pushes them.
  Future<void> pullAll() async {
    if (!_enabled) {
      _log('pullAll SKIPPED: SupabaseConfig.isReady is FALSE');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();

    for (final table in _pullOrder) {
      try {
        final lastSynced = prefs.getString('last_synced_at_$table');
        var builder = Supabase.instance.client.from(table).select('*');
        if (lastSynced != null && lastSynced.isNotEmpty) {
          builder = builder.gt('updated_at', lastSynced);
        }
        final rows = await builder;
        _log('pullAll: fetched ${rows.length} row(s) from "$table" '
            '(last_synced_at=$lastSynced)');

        for (final remoteRow in rows) {
          final normalized = await normalizeRemoteRowForSqlite(
            db,
            table,
            Map<String, dynamic>.from(remoteRow),
          );

          // normalizeRemoteRowForSqlite returns null when a required NOT NULL
          // column (e.g. role_permissions.permission_code) cannot be resolved.
          if (normalized == null) {
            final id = remoteRow['id']?.toString() ?? '<no-id>';
            _log('pullAll SKIP $table/$id: normalized row is null (missing required column)');
            continue;
          }

          // Never clobber a locally-modified row that is still pending push.
          final row = normalized;
          if (await localRowIsPending(db, table, row)) {
            final id = row['id']?.toString() ?? '<no-id>';
            _log('pullAll SKIP $table/$id: local sync_status is PENDING');
            continue;
          }

          await db.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Advance the watermark only after this table's rows are applied.
        await prefs.setString('last_synced_at_$table', now);
      } catch (e, s) {
        _logError('pullAll failed for table "$table"', e, s);
      }
    }
    _log('pullAll: pull cycle complete (watermark=$now)');

    _setLastSynced(DateTime.now());

    // Notify stores so they can reload from SQLite now that Supabase data has
    // been written into the local cache.
    if (onPullCompleted != null) {
      try {
        await onPullCompleted!();
      } catch (e, s) {
        _logError('onPullCompleted callback threw', e, s);
      }
    }
  }

  /// Strips Supabase-only columns, coerces PostgreSQL bools to SQLite ints,
  /// injects sync bookkeeping, and derives deterministic IDs for the
  /// composite-key join tables. Only columns that exist locally are kept.
  /// Returns `null` for `role_permissions` rows whose `permission_code` cannot
  /// be resolved (e.g. missing `permission_id` or unknown permission), so the
  /// caller can skip the upsert and avoid a NOT NULL constraint error.
  /// Public for testing.
  Future<Map<String, dynamic>?> normalizeRemoteRowForSqlite(
    Database db,
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    final localColumns = await _getLocalColumnNames(db, table);
    final normalized = <String, dynamic>{};

    // Map Supabase role_permissions.permission_id -> local permission_code.
    if (table == 'role_permissions') {
      final permissionId = remoteRow['permission_id'];
      if (permissionId != null) {
        final perms = await db.query(
          'permissions',
          columns: ['code'],
          where: 'id = ?',
          whereArgs: [permissionId],
          limit: 1,
        );
        if (perms.isNotEmpty) {
          normalized['permission_code'] = perms.first['code'] as String?;
        }
      }
      // If permission_code could not be resolved, skip this row entirely —
      // the local column is NOT NULL and we cannot insert without it.
      final permissionCode = normalized['permission_code'];
      if (permissionCode == null || permissionCode.toString().isEmpty) {
        return null;
      }
    }

    for (final entry in remoteRow.entries) {
      final col = entry.key;
      if (!localColumns.contains(col)) {
        // Drop Supabase-only columns (e.g. local_id) not present in SQLite.
        continue;
      }
      var value = entry.value;
      // Coerce PostgreSQL bool (true/false) to SQLite int (1/0).
      if (value is bool) {
        value = value ? 1 : 0;
      }
      normalized[col] = value;
    }

    // Deterministic IDs for composite-key join tables so the same assignment
    // resolves to the same ID on every device.
    if (table == 'user_roles' && localColumns.contains('id')) {
      final userId = remoteRow['user_id'];
      final roleId = remoteRow['role_id'];
      if (userId != null && roleId != null) {
        normalized['id'] =
            UuidUtils.deterministic('user_roles', '${userId}_$roleId');
      }
    } else if (table == 'user_departments' && localColumns.contains('id')) {
      final userId = remoteRow['user_id'];
      final departmentId = remoteRow['department_id'];
      if (userId != null && departmentId != null) {
        normalized['id'] = UuidUtils.deterministic(
          'user_departments',
          '${userId}_$departmentId',
        );
      }
    }

    // Inject sync bookkeeping columns when they exist locally.
    if (localColumns.contains('sync_status')) {
      normalized['sync_status'] = 'SYNCED';
    }
    if (localColumns.contains('is_synced')) {
      normalized['is_synced'] = 1;
    }

    return normalized;
  }

  /// Returns the set of column names for [table] in the local SQLite database.
  Future<Set<String>> _getLocalColumnNames(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((row) => row['name'] as String).toSet();
  }

  /// Returns true when an existing local row identified by [row] has
  /// `sync_status == 'PENDING'`, meaning it has local changes that have not
  /// yet been pushed to Supabase and must not be overwritten by a pull.
  /// Public for testing.
  Future<bool> localRowIsPending(
    Database db,
    String table,
    Map<String, dynamic> row,
  ) async {
    String where;
    List<Object?> whereArgs;
    if (table == 'role_permissions') {
      where = 'role_id = ? AND permission_code = ?';
      whereArgs = <Object?>[row['role_id'], row['permission_code']];
    } else if (table == 'user_roles') {
      where = 'user_id = ? AND role_id = ?';
      whereArgs = <Object?>[row['user_id'], row['role_id']];
    } else if (row.containsKey('id') && row['id'] != null) {
      where = 'id = ?';
      whereArgs = <Object?>[row['id']];
    } else {
      return false; // Cannot identify the local row; safe to overwrite.
    }

    final existing = await db.query(
      table,
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (existing.isEmpty) return false;
    return existing.first['sync_status'] == 'PENDING';
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
