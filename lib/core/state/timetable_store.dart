import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';

/// Manages class & lab timetable slots backed by [TimetableRepository].
///
/// Every mutation delegates to the repository, which queues a Supabase sync
/// record via [SyncService.schedulePush] (see `timetable_repository.dart`),
/// so changes sync to the cloud once the device is back online.
class TimetableStore extends ChangeNotifier {
  TimetableStore({TimetableRepository? repository})
      : _repository = repository ?? TimetableRepository();

  final TimetableRepository _repository;

  final List<TimetableSlot> _slots = [];

  /// All non-deleted timetable slots, ordered by day then period.
  List<TimetableSlot> get slots => List.unmodifiable(_slots);

  /// Non-deleted slots for the given class, ordered by day then period.
  List<TimetableSlot> slotsForClass(String classId) {
    return _slots
        .where((slot) => !slot.isDeleted && slot.classId == classId)
        .toList()
      ..sort((a, b) {
        final dayCmp = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (dayCmp != 0) return dayCmp;
        return a.periodSlot.compareTo(b.periodSlot);
      });
  }

  /// Non-deleted slots for the given teacher, ordered by day then period.
  List<TimetableSlot> slotsForTeacher(String teacherId) {
    return _slots
        .where((slot) => !slot.isDeleted && slot.teacherId == teacherId)
        .toList()
      ..sort((a, b) {
        final dayCmp = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (dayCmp != 0) return dayCmp;
        return a.periodSlot.compareTo(b.periodSlot);
      });
  }

  /// Returns the slot with [id], or null when it is not loaded.
  TimetableSlot? slotById(String id) {
    if (id.isEmpty) return null;
    try {
      return _slots.where((slot) => slot.id == id).first;
    } on StateError {
      return null;
    }
  }

  /// Loads all non-deleted timetable slots from the local database.
  Future<void> init() async {
    final loaded = await _repository.getAll();
    _slots
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// Creates a new timetable slot.
  ///
  /// Throws [TimetableConflictException] when the teacher, class, or room is
  /// already booked for the same day+period.
  Future<void> addSlot({
    required String instituteId,
    String? academicSessionId,
    required String classId,
    required String subjectId,
    required String teacherId,
    required String roomName,
    required int dayOfWeek,
    required int periodSlot,
    required String startTime,
    required String endTime,
    bool isLab = false,
  }) async {
    final slot = TimetableSlot(
      instituteId: instituteId,
      academicSessionId: academicSessionId,
      classId: classId,
      subjectId: subjectId,
      teacherId: teacherId,
      roomName: roomName,
      dayOfWeek: dayOfWeek,
      periodSlot: periodSlot,
      startTime: startTime,
      endTime: endTime,
      isLab: isLab,
    );
    await _repository.insert(slot);
    _slots.insert(0, slot);
    notifyListeners();
  }

  /// Updates an existing timetable slot.
  ///
  /// Throws [TimetableConflictException] when the change would conflict with
  /// another booking for the same day+period.
  Future<void> updateSlot(TimetableSlot updated) async {
    await _repository.update(updated);
    final idx = _slots.indexWhere((slot) => slot.id == updated.id);
    if (idx >= 0) {
      _slots[idx] = updated;
      notifyListeners();
    }
  }

  /// Soft-deletes the slot with [id].
  Future<void> deleteSlot(String id) async {
    await _repository.softDelete(id);
    _slots.removeWhere((slot) => slot.id == id);
    notifyListeners();
  }

  /// Returns the currently running or earliest upcoming timetable slot for
  /// [teacherId] today, or the next scheduled weekday slot if today's classes
  /// have ended.
  ///
  /// Uses `dayOfWeek == now.weekday` (1 = Monday … 6 = Saturday) and compares
  /// `end_time` against the current `HH:mm`. If no slot is found today,
  /// falls back to the earliest slot on the next scheduled weekday.
  TimetableSlot? getCurrentOrNextSlotForTeacher(
    String teacherId, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final currentDay = current.weekday;
    final currentTime = '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}';

    // Candidate slots for this teacher, sorted by day then period.
    final candidates = slotsForTeacher(teacherId);

    // 1. Slots today that are currently running or have not yet started
    //    (end_time > current time).
    final todaySlots = candidates.where((slot) {
      if (slot.dayOfWeek != currentDay) return false;
      return slot.endTime.compareTo(currentTime) > 0;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

    if (todaySlots.isNotEmpty) {
      return todaySlots.first;
    }

    // 2. Fallback: earliest slot on the next scheduled weekday.
    //    Search forward from tomorrow through the coming week.
    final weekdays = <int>{1, 2, 3, 4, 5, 6}; // Monday–Saturday
    for (int offset = 1; offset <= 7; offset++) {
      final weekday = ((currentDay - 1 + offset) % 7) + 1;
      if (!weekdays.contains(weekday)) continue;
      final daySlots = candidates
          .where((slot) => slot.dayOfWeek == weekday)
          .toList()
          ..sort((a, b) => a.periodSlot.compareTo(b.periodSlot));
      if (daySlots.isNotEmpty) {
        return daySlots.first;
      }
    }

    return null;
  }
}