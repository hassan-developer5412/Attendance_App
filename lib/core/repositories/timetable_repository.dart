import 'package:sqflite/sqflite.dart';

import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Thrown when a timetable slot cannot be created or updated because the
/// teacher, class, or room is already booked for the same day and period.
class TimetableConflictException implements Exception {
  final String message;
  const TimetableConflictException(this.message);
  @override
  String toString() => 'TimetableConflictException: $message';
}

/// Persists `timetable_slots` to SQLite and queues Supabase sync records.
///
/// Before inserting or updating, validates that the requested day+period is
/// not already booked for the same teacher, class, or room (case-insensitive
/// room comparison).
class TimetableRepository {
  TimetableRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _dbHelper;

  /// Throws [PermissionDeniedException] unless the current user can manage
  /// timetables. Fail-closed: unauthenticated or suspended users are denied.
  void _requireTimetableManage() {
    if (!PermissionService.instance.hasPermission(
          PermissionCodes.timetableManage,
        )) {
      throw PermissionDeniedException(PermissionCodes.timetableManage);
    }
  }

  /// Returns all non-deleted timetable slots.
  Future<List<TimetableSlot>> getAll() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'timetable_slots',
      where: 'is_deleted = 0',
      orderBy: 'day_of_week ASC, period_slot ASC',
    );
    return rows.map(TimetableSlot.fromMap).toList();
  }

  /// Returns the slot with [id], or null when not found / deleted.
  Future<TimetableSlot?> getById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'timetable_slots',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TimetableSlot.fromMap(rows.first);
  }

  /// Returns all non-deleted slots for a given class.
  Future<List<TimetableSlot>> getByClass(String classId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'timetable_slots',
      where: 'class_id = ? AND is_deleted = 0',
      whereArgs: [classId],
      orderBy: 'day_of_week ASC, period_slot ASC',
    );
    return rows.map(TimetableSlot.fromMap).toList();
  }

  /// Returns all non-deleted slots for a given teacher.
  Future<List<TimetableSlot>> getByTeacher(String teacherId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'timetable_slots',
      where: 'teacher_id = ? AND is_deleted = 0',
      whereArgs: [teacherId],
      orderBy: 'day_of_week ASC, period_slot ASC',
    );
    return rows.map(TimetableSlot.fromMap).toList();
  }

  /// Inserts [slot] after validating there is no conflict with an existing
  /// booking for the same day + period on teacher, class, or room.
  Future<TimetableSlot> insert(TimetableSlot slot) async {
    _requireTimetableManage();
    final db = await _dbHelper.database;
    await _assertNoConflict(db, slot, excludeId: null);
    await db.insert('timetable_slots', slot.toMap());
    SyncService.instance.schedulePush(
      'timetable_slots',
      idColumn: 'id',
      idValue: slot.id,
    );
    return slot;
  }

  /// Updates [slot] after validating there is no conflict with an existing
  /// booking for the same day + period on teacher, class, or room.
  Future<void> update(TimetableSlot slot) async {
    _requireTimetableManage();
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    final updated = slot.copyWith(updatedAt: now);
    await _assertNoConflict(db, updated, excludeId: slot.id);
    await db.update(
      'timetable_slots',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [slot.id],
    );
    SyncService.instance.schedulePush(
      'timetable_slots',
      idColumn: 'id',
      idValue: slot.id,
    );
  }

  /// Soft-deletes the slot with [id] and queues a Supabase sync record.
  Future<void> softDelete(String id) async {
    _requireTimetableManage();
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'timetable_slots',
      {
        'is_deleted': 1,
        'updated_at': now,
        'sync_status': 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    SyncService.instance.schedulePush(
      'timetable_slots',
      idColumn: 'id',
      idValue: id,
    );
  }

  /// Returns all slots pending sync to Supabase.
  Future<List<TimetableSlot>> getPendingSync() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'timetable_slots',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(TimetableSlot.fromMap).toList();
  }

  /// Ensures no non-deleted slot already occupies the same `day_of_week` and
  /// `period_slot` for the same `teacher_id`, `class_id`, or `room_name`
  /// (case-insensitive). Excludes [excludeId] when editing an existing slot.
  Future<void> _assertNoConflict(
    Database db,
    TimetableSlot slot, {
    String? excludeId,
  }) async {
    final where = '''
      day_of_week = ?
      AND period_slot = ?
      AND is_deleted = 0
      ${excludeId == null ? '' : 'AND id != ?'}
    ''';
    final whereArgs = <Object?>[
      slot.dayOfWeek,
      slot.periodSlot,
      ?excludeId,
    ];
    final rows = await db.query(
      'timetable_slots',
      where: where,
      whereArgs: whereArgs,
    );
    final normalizedNewRoom = slot.roomName.toLowerCase();
    for (final row in rows) {
      final existingRoom = (row['room_name'] as String).toLowerCase();
      if (row['teacher_id'].toString() == slot.teacherId) {
        throw TimetableConflictException(
          'Teacher is already booked for ${slot.dayName} period ${slot.periodSlot}.',
        );
      }
      if (row['class_id'].toString() == slot.classId) {
        throw TimetableConflictException(
          'Class is already scheduled for ${slot.dayName} period ${slot.periodSlot}.',
        );
      }
      if (existingRoom == normalizedNewRoom) {
        throw TimetableConflictException(
          'Room "${slot.roomName}" is already booked for ${slot.dayName} period ${slot.periodSlot}.',
        );
      }
    }
  }
}