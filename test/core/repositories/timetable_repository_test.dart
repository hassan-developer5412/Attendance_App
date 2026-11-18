import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';

void main() {
  late Database db;
  late DatabaseHelper dbHelper;
  late TimetableRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    dbHelper = DatabaseHelper.forTesting(db);
    repository = TimetableRepository(dbHelper: dbHelper);
  });

  tearDown(() async {
    await db.close();
  });

  group('TimetableRepository Conflict Detection', () {
    test('insert saves slot when there is no conflict', () async {
      final slot = TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 1, // Monday
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      final inserted = await repository.insert(slot);
      expect(inserted.id, 'slot_1');

      final loaded = await repository.getById('slot_1');
      expect(loaded, isNotNull);
      expect(loaded!.roomName, 'Room 101');
    });

    test('insert throws TimetableConflictException when teacher is already booked', () async {
      await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      ));

      // Attempt booking same teacher on Monday Period 1 for different class & room
      final conflictingSlot = TimetableSlot(
        id: 'slot_2',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_2',
        subjectId: 'sub_physics',
        teacherId: 'teacher_t1',
        roomName: 'Room 102',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      expect(
        () => repository.insert(conflictingSlot),
        throwsA(isA<TimetableConflictException>().having(
          (e) => e.message,
          'message',
          contains('Teacher is already booked for Monday period 1'),
        )),
      );
    });

    test('insert throws TimetableConflictException when class is already booked', () async {
      await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      ));

      // Attempt booking same class on Monday Period 1 with different teacher & room
      final conflictingSlot = TimetableSlot(
        id: 'slot_2',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_chemistry',
        teacherId: 'teacher_t2',
        roomName: 'Room 105',
        dayOfWeek: 1,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      );

      expect(
        () => repository.insert(conflictingSlot),
        throwsA(isA<TimetableConflictException>().having(
          (e) => e.message,
          'message',
          contains('Class is already scheduled for Monday period 1'),
        )),
      );
    });

    test('insert throws TimetableConflictException when room is already booked (case-insensitive)', () async {
      await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Lab A',
        dayOfWeek: 2, // Tuesday
        periodSlot: 3,
        startTime: '11:00',
        endTime: '11:50',
      ));

      // Attempt booking same room with different casing ('lab a') on Tuesday Period 3
      final conflictingSlot = TimetableSlot(
        id: 'slot_2',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_lt_1',
        subjectId: 'sub_leather',
        teacherId: 'teacher_t2',
        roomName: 'LAB A',
        dayOfWeek: 2,
        periodSlot: 3,
        startTime: '11:00',
        endTime: '11:50',
      );

      expect(
        () => repository.insert(conflictingSlot),
        throwsA(isA<TimetableConflictException>().having(
          (e) => e.message,
          'message',
          contains('Room "LAB A" is already booked for Tuesday period 3'),
        )),
      );
    });

    test('update allows editing self without self-conflict', () async {
      final slot = await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 3, // Wednesday
        periodSlot: 2,
        startTime: '10:00',
        endTime: '10:50',
      ));

      final updated = slot.copyWith(roomName: 'Room 101-B');
      await repository.update(updated);

      final reloaded = await repository.getById('slot_1');
      expect(reloaded?.roomName, 'Room 101-B');
    });

    test('update throws TimetableConflictException when moving to another booked slot', () async {
      await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 4, // Thursday
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      ));

      final slot2 = await repository.insert(TimetableSlot(
        id: 'slot_2',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_2',
        subjectId: 'sub_physics',
        teacherId: 'teacher_t2',
        roomName: 'Room 102',
        dayOfWeek: 4,
        periodSlot: 2,
        startTime: '10:00',
        endTime: '10:50',
      ));

      final movingToRoomConflict = slot2.copyWith(
        periodSlot: 1,
        roomName: 'Room 101',
      );

      expect(
        () => repository.update(movingToRoomConflict),
        throwsA(isA<TimetableConflictException>()),
      );
    });

    test('softDelete frees up the time slot for future bookings', () async {
      final slot = await repository.insert(TimetableSlot(
        id: 'slot_1',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 5, // Friday
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      ));

      await repository.softDelete(slot.id);

      final newSlot = await repository.insert(TimetableSlot(
        id: 'slot_2',
        instituteId: AppConstants.defaultInstituteId,
        classId: 'class_cit_1',
        subjectId: 'sub_math',
        teacherId: 'teacher_t1',
        roomName: 'Room 101',
        dayOfWeek: 5,
        periodSlot: 1,
        startTime: '09:00',
        endTime: '09:50',
      ));

      expect(newSlot.id, 'slot_2');
      final all = await repository.getAll();
      expect(all.length, 1);
      expect(all.first.id, 'slot_2');
    });
  });
}
