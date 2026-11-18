import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/state/timetable_store.dart';

class _FakeTimetableRepository extends TimetableRepository {
  _FakeTimetableRepository() : super();

  final List<TimetableSlot> _data = [];

  @override
  Future<List<TimetableSlot>> getAll() async {
    return _data.where((s) => !s.isDeleted).toList();
  }

  @override
  Future<TimetableSlot> insert(TimetableSlot slot) async {
    _data.add(slot);
    return slot;
  }

  @override
  Future<void> update(TimetableSlot slot) async {
    final idx = _data.indexWhere((s) => s.id == slot.id);
    if (idx >= 0) _data[idx] = slot;
  }

  @override
  Future<void> softDelete(String id) async {
    final idx = _data.indexWhere((s) => s.id == id);
    if (idx >= 0) _data[idx] = _data[idx].copyWith(isDeleted: true);
  }
}

void main() {
  late _FakeTimetableRepository fakeRepo;
  late TimetableStore store;

  setUp(() async {
    fakeRepo = _FakeTimetableRepository();
    store = TimetableStore(repository: fakeRepo);
    await store.init();
  });

  group('TimetableStore - getCurrentOrNextSlotForTeacher', () {
    test('returns null when teacher has no slots', () {
      final slot = store.getCurrentOrNextSlotForTeacher(
        'teacher_1',
        now: DateTime(2026, 11, 18, 10, 0), // Wednesday 10:00 AM
      );
      expect(slot, isNull);
    });

    test('returns active running slot today when end_time > current time', () async {
      // Wednesday is weekday 3. Slot from 09:00 to 09:50.
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's1',
        teacherId: 'teacher_1',
        roomName: 'Room 4',
        dayOfWeek: 3,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      // Wednesday at 09:30 (class currently in progress)
      final slot = store.getCurrentOrNextSlotForTeacher(
        'teacher_1',
        now: DateTime(2026, 11, 18, 9, 30), // Wednesday 9:30 AM
      );

      expect(slot, isNotNull);
      expect(slot!.periodSlot, 1);
      expect(slot.roomName, 'Room 4');
    });

    test('returns upcoming slot today when first slot has already ended', () async {
      // Slot 1: Wednesday 09:00 to 09:50
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's1',
        teacherId: 'teacher_1',
        roomName: 'Room 4',
        dayOfWeek: 3,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      // Slot 2: Wednesday 11:00 to 11:50
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c2',
        subjectId: 's2',
        teacherId: 'teacher_1',
        roomName: 'Lab 2',
        dayOfWeek: 3,
        periodSlot: 3,
        startTime: '11:00',
        endTime: '11:50',
        isLab: true,
      );

      // Wednesday at 10:15 (slot 1 ended, slot 2 upcoming)
      final slot = store.getCurrentOrNextSlotForTeacher(
        'teacher_1',
        now: DateTime(2026, 11, 18, 10, 15),
      );

      expect(slot, isNotNull);
      expect(slot!.periodSlot, 3);
      expect(slot.roomName, 'Lab 2');
      expect(slot.isLab, isTrue);
    });

    test('falls back to earliest slot on the next scheduled weekday when today classes ended', () async {
      // Slot on Wednesday 09:00-09:50
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's1',
        teacherId: 'teacher_1',
        roomName: 'Room 4',
        dayOfWeek: 3, // Wednesday
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      // Slot on Friday 10:00-10:50 (Period 2)
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's2',
        teacherId: 'teacher_1',
        roomName: 'Room 10',
        dayOfWeek: 5, // Friday
        periodSlot: 2,
        startTime: '10:00',
        endTime: '10:50',
      );

      // Wednesday at 17:00 (5:00 PM) - today's classes ended. Next scheduled day is Friday!
      final slot = store.getCurrentOrNextSlotForTeacher(
        'teacher_1',
        now: DateTime(2026, 11, 18, 17, 0),
      );

      expect(slot, isNotNull);
      expect(slot!.dayOfWeek, 5); // Friday
      expect(slot.periodSlot, 2);
      expect(slot.roomName, 'Room 10');
    });

    test('wraps across weekend to Monday when now is Saturday evening', () async {
      // Slot on Monday 09:00
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's1',
        teacherId: 'teacher_1',
        roomName: 'Room 1',
        dayOfWeek: 1, // Monday
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      // Saturday at 20:00 (8:00 PM) - Saturday is 2026-11-21
      final slot = store.getCurrentOrNextSlotForTeacher(
        'teacher_1',
        now: DateTime(2026, 11, 21, 20, 0),
      );

      expect(slot, isNotNull);
      expect(slot!.dayOfWeek, 1); // Monday
      expect(slot.roomName, 'Room 1');
    });
  });

  group('TimetableStore - CRUD and Query Filters', () {
    test('addSlot, updateSlot, deleteSlot update in-memory slots', () async {
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c_alpha',
        subjectId: 's_alpha',
        teacherId: 't_alpha',
        roomName: 'Room 101',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      expect(store.slots.length, 1);
      final first = store.slots.first;

      await store.updateSlot(first.copyWith(roomName: 'Room 102'));
      expect(store.slots.first.roomName, 'Room 102');

      await store.deleteSlot(first.id);
      expect(store.slots, isEmpty);
    });

    test('slotsForClass and slotsForTeacher filter and sort properly', () async {
      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's1',
        teacherId: 't1',
        roomName: 'R1',
        dayOfWeek: 2,
        periodSlot: 2,
        startTime: '10:00',
        endTime: '10:50',
      );

      await store.addSlot(
        instituteId: AppConstants.defaultInstituteId,
        classId: 'c1',
        subjectId: 's2',
        teacherId: 't2',
        roomName: 'R2',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      final class1Slots = store.slotsForClass('c1');
      expect(class1Slots.length, 2);
      expect(class1Slots[0].dayOfWeek, 1);
      expect(class1Slots[1].dayOfWeek, 2);

      final t1Slots = store.slotsForTeacher('t1');
      expect(t1Slots.length, 1);
      expect(t1Slots.first.roomName, 'R1');
    });
  });
}
