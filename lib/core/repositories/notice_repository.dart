import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Local SQLite persistence for [Notice] rows, following the same pattern as
/// [LabInventoryRepository].
///
/// Every mutation schedules an outbound Supabase push via
/// [SyncService.schedulePush] so changes propagate to the cloud once the
/// device is online.
class NoticeRepository {
  NoticeRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  // ---------------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------------

  /// Returns all non-deleted notices sorted pinned-first, then newest-first.
  Future<List<Notice>> getAll({bool includeDeleted = false}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'notices',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'is_pinned DESC, created_at DESC',
    );
    return rows.map(Notice.fromMap).toList();
  }

  /// Returns the notice with [id], or `null` when not found / deleted.
  Future<Notice?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'notices',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Notice.fromMap(rows.first);
  }

  /// Returns non-deleted notices visible to [role] (or to everyone when [role]
  /// is null) and optionally scoped to [departmentId].
  ///
  /// A notice is visible to a role when its `target_role` is null, `'all'`, or
  /// matches [role]. When [departmentId] is provided only notices with a
  /// matching `department_id` or no department restriction are returned.
  Future<List<Notice>> getForUser({
    String? role,
    String? departmentId,
  }) async {
    final db = await _dbHelper.database;

    // Build a dynamic WHERE clause.
    final conditions = <String>['is_deleted = 0'];
    final args = <Object?>[];

    if (role != null && role.isNotEmpty) {
      conditions.add(
        "(target_role IS NULL OR target_role = 'all' OR target_role = ?)",
      );
      args.add(role);
    }

    if (departmentId != null && departmentId.isNotEmpty) {
      conditions.add(
        '(department_id IS NULL OR department_id = ?)',
      );
      args.add(departmentId);
    }

    final rows = await db.query(
      'notices',
      where: conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'is_pinned DESC, created_at DESC',
    );
    return rows.map(Notice.fromMap).toList();
  }

  /// Returns all PENDING (unsynced) notices; used by the sync engine.
  Future<List<Notice>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'notices',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Notice.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // WRITE
  // ---------------------------------------------------------------------------

  /// Inserts [notice] into SQLite and queues a Supabase push.
  Future<Notice> insert(Notice notice) async {
    final db = await _dbHelper.database;
    await db.insert('notices', notice.toMap());
    SyncService.instance.schedulePush(
      'notices',
      idColumn: 'id',
      idValue: notice.id,
    );
    return notice;
  }

  /// Updates [notice] in SQLite (stamping a fresh `updated_at`) and queues a
  /// Supabase push.
  Future<void> update(Notice notice) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = notice.copyWith(updatedAt: now);
    await db.update(
      'notices',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [notice.id],
    );
    SyncService.instance.schedulePush(
      'notices',
      idColumn: 'id',
      idValue: notice.id,
    );
  }

  /// Soft-deletes the notice with [id] and queues a Supabase push.
  Future<void> softDelete(String id) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'notices',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'notices',
      idColumn: 'id',
      idValue: id,
    );
  }
}
