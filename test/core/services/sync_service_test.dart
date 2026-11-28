import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/database_helper.dart';
import 'package:attendance_app/core/database/migrations/fresh_database_creator.dart';
import 'package:attendance_app/core/models/attendance_session.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/sync_queue_item.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/attendance_session_repository.dart';
import 'package:attendance_app/core/repositories/lab_inventory_repository.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/repositories/notice_repository.dart';
import 'package:attendance_app/core/repositories/sync_queue_repository.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/services/sync_service.dart';

void main() {
  late Database db;
  late DatabaseHelper dbHelper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await FreshDatabaseCreator.createAndSeed(db);
    DatabaseHelper.setTestDatabase(db);
    dbHelper = DatabaseHelper.forTesting(db);
  });

  tearDown(() async {
    PermissionService.instance.reset();
    DatabaseHelper.setTestDatabase(null);
    await db.close();
  });

  group('normalizeRemoteRowForSqlite - newer schema tables', () {
    test('notices: converts bools, handles missing optional columns & null timestamps', () async {
      final remoteRow = <String, dynamic>{
        'id': 'notice-1',
        'institute_id': 'inst-1',
        'title': 'Exam Schedule',
        'body': 'Finals start Monday.',
        'is_pinned': true,
        'published_by': 'user-admin',
        'is_deleted': false,
        'created_at': null,
        'updated_at': null,
        'supabase_only_col': 'ignored',
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'notices',
        remoteRow,
      );

      expect(normalized, isNotNull);
      expect(normalized!.containsKey('supabase_only_col'), isFalse);
      expect(normalized['is_pinned'], 1);
      expect(normalized['is_deleted'], 0);
      expect(normalized['created_at'], isA<String>());
      expect(normalized['updated_at'], isA<String>());
      expect(normalized['sync_status'], 'SYNCED');
      expect(normalized['is_synced'], 1);

      await db.insert(
        'notices',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('notices', where: 'id = ?', whereArgs: ['notice-1']);
      expect(rows.length, 1);
      expect(rows.first['is_pinned'], 1);
      expect(rows.first['target_role'], isNull);
    });

    test('notices: defaults null is_pinned and is_deleted to 0', () async {
      final remoteRow = <String, dynamic>{
        'id': 'notice-2',
        'title': 'Holiday',
        'body': 'Campus closed.',
        'is_pinned': null,
        'is_deleted': null,
        'published_by': 'user-admin',
        'updated_at': '2026-05-01T10:00:00Z',
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'notices',
        remoteRow,
      );

      expect(normalized!['is_pinned'], 0);
      expect(normalized['is_deleted'], 0);
      expect(normalized['institute_id'], AppConstants.defaultInstituteId);
      expect(normalized['created_at'], '2026-05-01T10:00:00Z');

      await db.insert(
        'notices',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('notices', where: 'id = ?', whereArgs: ['notice-2']);
      expect(rows.length, 1);
    });

    test('timetable_slots: converts is_lab and is_deleted bools and handles missing optional columns', () async {
      final remoteRow = <String, dynamic>{
        'id': 'slot-1',
        'institute_id': 'inst-1',
        'class_id': 'class-1',
        'subject_id': 'sub-1',
        'teacher_id': 'teacher-1',
        'room_name': 'Lab A',
        'day_of_week': 2,
        'period_slot': 3,
        'start_time': '10:30',
        'end_time': '11:30',
        'is_lab': true,
        'is_deleted': false,
        'created_at': null,
        'updated_at': '2026-05-01T08:00:00Z',
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'timetable_slots',
        remoteRow,
      );

      expect(normalized!['is_lab'], 1);
      expect(normalized['is_deleted'], 0);
      expect(normalized['created_at'], '2026-05-01T08:00:00Z');
      expect(normalized['sync_status'], 'SYNCED');
      expect(normalized['is_synced'], 1);

      await db.insert(
        'timetable_slots',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('timetable_slots', where: 'id = ?', whereArgs: ['slot-1']);
      expect(rows.length, 1);
      expect(rows.first['is_lab'], 1);
      expect(rows.first['academic_session_id'], isNull);
    });

    test('leave_requests: handles nullable columns, null status/timestamps, and bools cleanly', () async {
      final remoteRow = <String, dynamic>{
        'id': 'leave-1',
        'requester_name': 'Alice Smith',
        'leave_type': 'Sick',
        'start_date': '2026-05-10T00:00:00Z',
        'end_date': '2026-05-11T00:00:00Z',
        'reason': 'Fever',
        'status': null,
        'is_deleted': false,
        'created_at': null,
        'updated_at': null,
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'leave_requests',
        remoteRow,
      );

      expect(normalized!['status'], 'pending');
      expect(normalized['is_deleted'], 0);
      expect(normalized['institute_id'], AppConstants.defaultInstituteId);
      expect(normalized['created_at'], isA<String>());
      expect(normalized['updated_at'], isA<String>());
      expect(normalized['sync_status'], 'SYNCED');
      expect(normalized['is_synced'], 1);

      await db.insert(
        'leave_requests',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('leave_requests', where: 'id = ?', whereArgs: ['leave-1']);
      expect(rows.length, 1);
      expect(rows.first['status'], 'pending');
      expect(rows.first['student_id'], isNull);
      expect(rows.first['remarks'], isNull);
      expect(rows.first['attachment_url'], isNull);
    });

    test('attendance_sessions: converts null nullable-FKs from Supabase to SQLite defaults', () async {
      final remoteRow = <String, dynamic>{
        'id': 'sess-1',
        'subject_code': 'CS101',
        'department_id': null,
        'faculty_id': null,
        'session_date': '2026-05-10',
        'academic_session_id': null,
        'class_id': null,
        'year': null,
        'subject_id': null,
        'remarks': null,
        'is_deleted': false,
        'created_at': null,
        'updated_at': '2026-05-10T09:00:00Z',
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'attendance_sessions',
        remoteRow,
      );

      expect(normalized!['department_id'], '');
      expect(normalized['faculty_id'], '');
      expect(normalized['academic_session_id'], '');
      expect(normalized['year'], '');
      expect(normalized['remarks'], '');
      expect(normalized['is_deleted'], 0);

      await db.insert(
        'attendance_sessions',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('attendance_sessions', where: 'id = ?', whereArgs: ['sess-1']);
      expect(rows.length, 1);
    });

    test('lab_inventory: applies defaults for missing/null stock, unit, and reorder_level', () async {
      final remoteRow = <String, dynamic>{
        'id': 'lab-1',
        'item_name': 'Oscilloscope',
        'department_id': 'dept-ece',
        'category': 'equipment',
        'current_stock': null,
        'unit': null,
        'reorder_level': null,
        'is_deleted': false,
        'created_at': null,
        'updated_at': '2026-05-10T09:00:00Z',
      };

      final normalized = await SyncService.instance.normalizeRemoteRowForSqlite(
        db,
        'lab_inventory',
        remoteRow,
      );

      expect(normalized!['current_stock'], 0.0);
      expect(normalized['unit'], 'pcs');
      expect(normalized['reorder_level'], 0.0);
      expect(normalized['is_deleted'], 0);

      await db.insert(
        'lab_inventory',
        normalized,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final rows = await db.query('lab_inventory', where: 'id = ?', whereArgs: ['lab-1']);
      expect(rows.length, 1);
    });
  });

  group('Pending-row conflict protection & soft-delete replication', () {
    test('notices: PENDING local row is preserved on remote upsert and remote soft-delete', () async {
      await db.insert('notices', {
        'id': 'notice-pending',
        'institute_id': AppConstants.defaultInstituteId,
        'title': 'Local Draft',
        'body': 'Local body',
        'is_pinned': 1,
        'published_by': 'u1',
        'created_at': '2026-05-01T00:00:00Z',
        'updated_at': '2026-05-01T00:00:00Z',
        'is_deleted': 0,
        'sync_status': 'PENDING',
        'is_synced': 0,
      });

      expect(
        await SyncService.instance.localRowIsPending(
          db,
          'notices',
          {'id': 'notice-pending'},
        ),
        isTrue,
      );

      // Remote upsert should NOT overwrite local PENDING row.
      await SyncService.instance.applyRemoteRow(db, 'notices', {
        'id': 'notice-pending',
        'institute_id': AppConstants.defaultInstituteId,
        'title': 'Remote Overwrite',
        'body': 'Remote body',
        'is_pinned': false,
        'published_by': 'u1',
        'created_at': '2026-05-01T00:00:00Z',
        'updated_at': '2026-05-02T00:00:00Z',
        'is_deleted': false,
      });

      var rows = await db.query('notices', where: 'id = ?', whereArgs: ['notice-pending']);
      expect(rows.length, 1);
      expect(rows.first['title'], 'Local Draft');
      expect(rows.first['sync_status'], 'PENDING');

      // Remote soft-delete should ALSO NOT delete local PENDING row.
      await SyncService.instance.applyRemoteRow(db, 'notices', {
        'id': 'notice-pending',
        'is_deleted': true,
      });

      rows = await db.query('notices', where: 'id = ?', whereArgs: ['notice-pending']);
      expect(rows.length, 1);
      expect(rows.first['title'], 'Local Draft');
    });

    test('notices: SYNCED local row is deleted when remote is_deleted == true', () async {
      await db.insert('notices', {
        'id': 'notice-synced',
        'institute_id': AppConstants.defaultInstituteId,
        'title': 'Old Notice',
        'body': 'Old body',
        'is_pinned': 0,
        'published_by': 'u1',
        'created_at': '2026-05-01T00:00:00Z',
        'updated_at': '2026-05-01T00:00:00Z',
        'is_deleted': 0,
        'sync_status': 'SYNCED',
        'is_synced': 1,
      });

      await SyncService.instance.applyRemoteRow(db, 'notices', {
        'id': 'notice-synced',
        'is_deleted': true,
      });

      final rows = await db.query('notices', where: 'id = ?', whereArgs: ['notice-synced']);
      expect(rows, isEmpty);
    });

    test('timetable_slots: PENDING local row is preserved on remote upsert and remote soft-delete', () async {
      await db.insert('timetable_slots', {
        'id': 'slot-pending',
        'institute_id': AppConstants.defaultInstituteId,
        'class_id': 'c1',
        'subject_id': 's1',
        'teacher_id': 't1',
        'room_name': 'Local Room',
        'day_of_week': 1,
        'period_slot': 1,
        'start_time': '09:00',
        'end_time': '10:00',
        'is_lab': 0,
        'created_at': '2026-05-01T00:00:00Z',
        'updated_at': '2026-05-01T00:00:00Z',
        'is_deleted': 0,
        'sync_status': 'PENDING',
        'is_synced': 0,
      });

      expect(
        await SyncService.instance.localRowIsPending(
          db,
          'timetable_slots',
          {'id': 'slot-pending'},
        ),
        isTrue,
      );

      await SyncService.instance.applyRemoteRow(db, 'timetable_slots', {
        'id': 'slot-pending',
        'institute_id': AppConstants.defaultInstituteId,
        'class_id': 'c1',
        'subject_id': 's1',
        'teacher_id': 't1',
        'room_name': 'Remote Room',
        'day_of_week': 1,
        'period_slot': 1,
        'start_time': '09:00',
        'end_time': '10:00',
        'is_lab': true,
        'is_deleted': false,
        'updated_at': '2026-05-02T00:00:00Z',
      });

      var rows = await db.query('timetable_slots', where: 'id = ?', whereArgs: ['slot-pending']);
      expect(rows.first['room_name'], 'Local Room');
      expect(rows.first['sync_status'], 'PENDING');

      await SyncService.instance.applyRemoteRow(db, 'timetable_slots', {
        'id': 'slot-pending',
        'is_deleted': true,
      });

      rows = await db.query('timetable_slots', where: 'id = ?', whereArgs: ['slot-pending']);
      expect(rows.length, 1);
    });

    test('leave_requests: PENDING local row is preserved on remote upsert and remote soft-delete', () async {
      await db.insert('leave_requests', {
        'id': 'leave-pending',
        'requester_name': 'Local Requester',
        'leave_type': 'Casual',
        'start_date': '2026-05-01T00:00:00Z',
        'end_date': '2026-05-02T00:00:00Z',
        'reason': 'Local reason',
        'status': 'pending',
        'created_at': '2026-05-01T00:00:00Z',
        'updated_at': '2026-05-01T00:00:00Z',
        'sync_status': 'PENDING',
        'is_deleted': 0,
        'institute_id': AppConstants.defaultInstituteId,
        'is_synced': 0,
      });

      expect(
        await SyncService.instance.localRowIsPending(
          db,
          'leave_requests',
          {'id': 'leave-pending'},
        ),
        isTrue,
      );

      await SyncService.instance.applyRemoteRow(db, 'leave_requests', {
        'id': 'leave-pending',
        'requester_name': 'Remote Requester',
        'leave_type': 'Casual',
        'start_date': '2026-05-01T00:00:00Z',
        'end_date': '2026-05-02T00:00:00Z',
        'reason': 'Remote reason',
        'status': 'approved',
        'is_deleted': false,
        'updated_at': '2026-05-02T00:00:00Z',
      });

      var rows = await db.query('leave_requests', where: 'id = ?', whereArgs: ['leave-pending']);
      expect(rows.first['status'], 'pending');
      expect(rows.first['reason'], 'Local reason');

      await SyncService.instance.applyRemoteRow(db, 'leave_requests', {
        'id': 'leave-pending',
        'is_deleted': true,
      });

      rows = await db.query('leave_requests', where: 'id = ?', whereArgs: ['leave-pending']);
      expect(rows.length, 1);
    });
  });

  group('Repository mutations enqueue valid SyncQueueItem payloads', () {
    test('insert, update, and softDelete across all 5 newer repositories enqueue valid SyncQueueItems', () async {
      final queueRepo = SyncQueueRepository(dbHelper: dbHelper);
      final noticeRepo = NoticeRepository(dbHelper: dbHelper);
      final timetableRepo = TimetableRepository(dbHelper: dbHelper);
      final sessionRepo = AttendanceSessionRepository(dbHelper: dbHelper);
      final leaveRepo = LeaveRepository(dbHelper: dbHelper);
      final labRepo = LabInventoryRepository(dbHelper: dbHelper);

      PermissionService.instance.reset();
      PermissionService.instance.loadRoles([
        Role(
          id: 'role-admin',
          code: 'admin',
          name: 'Admin',
          isInstituteWide: true,
        ),
      ]);
      PermissionService.instance.loadRolePermissions({
        'role-admin': [
          PermissionCodes.noticeManage,
          PermissionCodes.timetableManage,
          PermissionCodes.attendanceMark,
          PermissionCodes.attendanceEdit,
          PermissionCodes.attendanceDelete,
          PermissionCodes.leaveView,
          PermissionCodes.leaveApprove,
          PermissionCodes.labManage,
        ],
      });
      PermissionService.instance.setUserRoles('admin-1', ['role-admin']);
      PermissionService.instance.currentUserId = 'admin-1';

      // 1. Notices: insert -> update (from SYNCED) -> softDelete
        final notice = Notice(
          id: 'n-queue-1',
          instituteId: AppConstants.defaultInstituteId,
          title: 'Notice 1',
          body: 'Body 1',
          isPinned: true,
          publishedBy: 'u1',
        );
        await noticeRepo.insert(notice);
        await SyncService.instance.enqueueUnsyncedRows();

        var pending = await queueRepo.getPendingItems();
        final nCreate = pending.firstWhere((e) => e.entityType == 'notices' && e.entityId == 'n-queue-1');
        expect(nCreate.operation, SyncOperation.update);
        expect(nCreate.payload['is_pinned'], true);
        expect(nCreate.payload['is_deleted'], false);
        expect(nCreate.payload.containsKey('sync_status'), isFalse);

        await queueRepo.clear();
        await db.update('notices', {'sync_status': 'SYNCED', 'is_synced': 1}, where: 'id = ?', whereArgs: ['n-queue-1']);

        await noticeRepo.update(notice.copyWith(
          title: 'Notice 1 Updated',
          syncStatus: SyncStatus.synced,
          isSynced: true,
        ));
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final nUpdate = pending.firstWhere((e) => e.entityType == 'notices' && e.entityId == 'n-queue-1');
        expect(nUpdate.operation, SyncOperation.update);
        expect(nUpdate.payload['title'], 'Notice 1 Updated');

        await queueRepo.clear();
        await noticeRepo.softDelete('n-queue-1');
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final nDelete = pending.firstWhere((e) => e.entityType == 'notices' && e.entityId == 'n-queue-1');
        expect(nDelete.operation, SyncOperation.delete);
        expect(nDelete.payload['is_deleted'], true);

        // 2. Timetable slots: insert -> update -> softDelete
        await queueRepo.clear();
        final slot = TimetableSlot(
          id: 'tt-queue-1',
          instituteId: AppConstants.defaultInstituteId,
          classId: 'c1',
          subjectId: 's1',
          teacherId: 't1',
          roomName: 'R1',
          dayOfWeek: 1,
          periodSlot: 1,
          startTime: '09:00',
          endTime: '10:00',
          isLab: true,
        );
        await timetableRepo.insert(slot);
        await timetableRepo.update(slot.copyWith(roomName: 'R2', syncStatus: SyncStatus.synced, isSynced: true));
        await timetableRepo.softDelete('tt-queue-1');
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final ttItem = pending.firstWhere((e) => e.entityType == 'timetable_slots' && e.entityId == 'tt-queue-1');
        expect(ttItem.operation, SyncOperation.delete);
        expect(ttItem.payload['room_name'], 'R2');
        expect(ttItem.payload['is_lab'], true);
        expect(ttItem.payload['is_deleted'], true);

        // 3. Attendance sessions: insert -> update -> softDelete
        await queueRepo.clear();
        final session = AttendanceSession(
          id: 'as-queue-1',
          subjectCode: 'CS101',
          departmentId: '',
          facultyId: '',
          sessionDate: '2026-05-10',
        );
        await sessionRepo.insert(session);
        await sessionRepo.update(session.copyWith(remarks: 'Updated', syncStatus: SyncStatus.synced));
        await sessionRepo.softDelete('as-queue-1');
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final asItem = pending.firstWhere((e) => e.entityType == 'attendance_sessions' && e.entityId == 'as-queue-1');
        expect(asItem.operation, SyncOperation.delete);
        expect(asItem.payload['remarks'], 'Updated');
        expect(asItem.payload['is_deleted'], true);

        // 4. Leave requests: insert -> updateStatus -> softDelete
        await queueRepo.clear();
        final leave = LeaveRequest(
          id: 'lr-queue-1',
          requesterName: 'Bob',
          leaveType: 'Sick',
          startDate: DateTime.utc(2026, 5, 10),
          endDate: DateTime.utc(2026, 5, 11),
          reason: 'Cold',
          studentId: 'stu-1',
        );
        await leaveRepo.insert(leave, requestingUserId: 'stu-1');
        await leaveRepo.updateStatus('lr-queue-1', LeaveStatus.approved, remarks: 'OK', requestingUserId: 'admin-1');
        await leaveRepo.softDelete('lr-queue-1', requestingUserId: 'stu-1');
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final lrItem = pending.firstWhere((e) => e.entityType == 'leave_requests' && e.entityId == 'lr-queue-1');
        expect(lrItem.operation, SyncOperation.delete);
        expect(lrItem.payload['status'], 'approved');
        expect(lrItem.payload['remarks'], 'OK');
        expect(lrItem.payload['is_deleted'], true);

        // 5. Lab inventory: insert -> update -> softDelete
        await queueRepo.clear();
        final lab = LabInventory(
          id: 'lab-queue-1',
          itemName: 'Multimeter',
          departmentId: 'dept-1',
          category: InventoryCategory.hardwareEquipment,
          currentStock: 5,
          unit: 'pcs',
          reorderLevel: 2,
        );
        await labRepo.insert(lab);
        await labRepo.update(lab.copyWith(currentStock: 4, syncStatus: SyncStatus.synced));
        await labRepo.softDelete('lab-queue-1');
        await SyncService.instance.enqueueUnsyncedRows();
        pending = await queueRepo.getPendingItems();
        final labItem = pending.firstWhere((e) => e.entityType == 'lab_inventory' && e.entityId == 'lab-queue-1');
        expect(labItem.operation, SyncOperation.delete);
        expect(labItem.payload['current_stock'], 4.0);
        expect(labItem.payload['is_deleted'], true);
    });
  });
}
