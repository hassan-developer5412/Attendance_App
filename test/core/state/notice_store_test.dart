// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/repositories/notice_repository.dart';
import 'package:attendance_app/core/state/notice_store.dart';

// ---------------------------------------------------------------------------
// Fake repository — no DB, no SyncService calls
// ---------------------------------------------------------------------------

class _FakeNoticeRepository extends NoticeRepository {
  _FakeNoticeRepository() : super();

  final List<Notice> _data = [];

  @override
  Future<List<Notice>> getAll({bool includeDeleted = false}) async {
    if (includeDeleted) return List.from(_data);
    return _data.where((n) => !n.isDeleted).toList();
  }

  @override
  Future<Notice> insert(Notice notice) async {
    _data.add(notice);
    return notice;
  }

  @override
  Future<void> update(Notice notice) async {
    final idx = _data.indexWhere((n) => n.id == notice.id);
    if (idx >= 0) _data[idx] = notice;
  }

  @override
  Future<void> softDelete(String id) async {
    final idx = _data.indexWhere((n) => n.id == id);
    if (idx >= 0) _data[idx] = _data[idx].copyWith(isDeleted: true);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Notice _notice({
  String id = 'n1',
  String title = 'Test Notice',
  String body = 'Body text',
  String? targetRole,
  String? departmentId,
  bool isPinned = false,
  bool isDeleted = false,
}) {
  return Notice(
    id: id,
    instituteId: AppConstants.defaultInstituteId,
    title: title,
    body: body,
    targetRole: targetRole,
    departmentId: departmentId,
    isPinned: isPinned,
    publishedBy: 'user_1',
    publishedByName: 'Admin',
    isDeleted: isDeleted,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('NoticeStore — noticesForUser() filtering', () {
    late _FakeNoticeRepository repo;
    late NoticeStore store;

    setUp(() async {
      repo = _FakeNoticeRepository();
      store = NoticeStore(repository: repo);

      // Seed notices
      await repo.insert(_notice(id: 'all1', targetRole: null));           // null → all
      await repo.insert(_notice(id: 'all2', targetRole: 'all'));          // 'all' → all
      await repo.insert(_notice(id: 'tea1', targetRole: 'teacher'));      // teachers only
      await repo.insert(_notice(id: 'stu1', targetRole: 'student'));      // students only
      await repo.insert(_notice(id: 'dep1', targetRole: null, departmentId: 'dept_cit')); // dept-scoped
      await repo.insert(_notice(id: 'del1', targetRole: null, isDeleted: true)); // soft-deleted

      await store.init();
    });

    test('null targetRole notice is visible to teacher', () {
      final result = store.noticesForUser(role: 'teacher');
      expect(result.any((n) => n.id == 'all1'), isTrue);
    });

    test("'all' targetRole notice is visible to teacher", () {
      final result = store.noticesForUser(role: 'teacher');
      expect(result.any((n) => n.id == 'all2'), isTrue);
    });

    test("'student' targetRole notice is NOT visible to teacher", () {
      final result = store.noticesForUser(role: 'teacher');
      expect(result.any((n) => n.id == 'stu1'), isFalse);
    });

    test("'teacher' targetRole notice is visible to teacher", () {
      final result = store.noticesForUser(role: 'teacher');
      expect(result.any((n) => n.id == 'tea1'), isTrue);
    });

    test("'teacher' targetRole notice is NOT visible to student", () {
      final result = store.noticesForUser(role: 'student');
      expect(result.any((n) => n.id == 'tea1'), isFalse);
    });

    test("'student' targetRole notice IS visible to student", () {
      final result = store.noticesForUser(role: 'student');
      expect(result.any((n) => n.id == 'stu1'), isTrue);
    });

    test('null departmentId notice is visible to any department', () {
      final result =
          store.noticesForUser(role: 'teacher', departmentId: 'dept_lt');
      expect(result.any((n) => n.id == 'all1'), isTrue);
    });

    test('department-specific notice is visible to matching department', () {
      final result =
          store.noticesForUser(role: 'teacher', departmentId: 'dept_cit');
      expect(result.any((n) => n.id == 'dep1'), isTrue);
    });

    test('department-specific notice is NOT visible to other department', () {
      final result =
          store.noticesForUser(role: 'teacher', departmentId: 'dept_lt');
      expect(result.any((n) => n.id == 'dep1'), isFalse);
    });

    test('soft-deleted notice is never returned', () {
      final result = store.noticesForUser();
      expect(result.any((n) => n.id == 'del1'), isFalse);
    });

    test('no-arg call returns all non-deleted notices', () {
      final result = store.noticesForUser();
      // 5 non-deleted notices seeded above
      expect(result.length, equals(5));
    });
  });

  group('NoticeStore — pinnedNotices getter', () {
    late _FakeNoticeRepository repo;
    late NoticeStore store;

    setUp(() async {
      repo = _FakeNoticeRepository();
      store = NoticeStore(repository: repo);

      await repo.insert(_notice(id: 'p1', isPinned: true));
      await repo.insert(_notice(id: 'p2', isPinned: true));
      await repo.insert(_notice(id: 'u1', isPinned: false));
      await repo.insert(_notice(id: 'del', isPinned: true, isDeleted: true));

      await store.init();
    });

    test('pinnedNotices returns only pinned non-deleted', () {
      final pinned = store.pinnedNotices;
      expect(pinned.length, equals(2));
      expect(pinned.any((n) => n.id == 'p1'), isTrue);
      expect(pinned.any((n) => n.id == 'p2'), isTrue);
      expect(pinned.any((n) => n.id == 'del'), isFalse);
    });
  });

  group('NoticeStore — CRUD mutations', () {
    late _FakeNoticeRepository repo;
    late NoticeStore store;

    setUp(() async {
      repo = _FakeNoticeRepository();
      store = NoticeStore(repository: repo);
      await store.init();
    });

    test('addNotice prepends and notifies listeners', () async {
      var notified = false;
      store.addListener(() => notified = true);

      await store.addNotice(
        instituteId: AppConstants.defaultInstituteId,
        title: 'New Notice',
        body: 'Body',
        publishedBy: 'u1',
      );

      expect(notified, isTrue);
      expect(store.notices.length, equals(1));
      expect(store.notices.first.title, equals('New Notice'));
    });

    test('addNotice preserves isPinned flag', () async {
      await store.addNotice(
        instituteId: AppConstants.defaultInstituteId,
        title: 'Pinned',
        body: 'Body',
        publishedBy: 'u1',
        isPinned: true,
      );
      expect(store.notices.first.isPinned, isTrue);
    });

    test('updateNotice replaces in list and notifies', () async {
      await store.addNotice(
        instituteId: AppConstants.defaultInstituteId,
        title: 'Original',
        body: 'Body',
        publishedBy: 'u1',
      );
      final original = store.notices.first;
      final updated = original.copyWith(title: 'Updated');

      var notified = false;
      store.addListener(() => notified = true);

      await store.updateNotice(updated);

      expect(notified, isTrue);
      expect(store.notices.first.title, equals('Updated'));
    });

    test('deleteNotice removes from list and notifies', () async {
      await store.addNotice(
        instituteId: AppConstants.defaultInstituteId,
        title: 'To Delete',
        body: 'Body',
        publishedBy: 'u1',
      );
      final id = store.notices.first.id;

      var notified = false;
      store.addListener(() => notified = true);

      await store.deleteNotice(id);

      expect(notified, isTrue);
      expect(store.notices, isEmpty);
    });

    test('init() loads notices from repository', () async {
      // Add directly to repo (bypassing store)
      await repo.insert(_notice(id: 'direct'));
      await store.init();
      expect(store.notices.any((n) => n.id == 'direct'), isTrue);
    });
  });

  group('NoticeStore — sync normalization', () {
    test('fromMap normalises is_pinned integer to bool', () {
      final map = {
        'id': 'x1',
        'institute_id': AppConstants.defaultInstituteId,
        'title': 'T',
        'body': 'B',
        'target_role': null,
        'department_id': null,
        'attachment_url': null,
        'is_pinned': 1,
        'published_by': 'u',
        'published_by_name': null,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'sync_status': 'PENDING',
        'is_deleted': 0,
        'is_synced': 0,
      };
      final notice = Notice.fromMap(map);
      expect(notice.isPinned, isTrue);
      expect(notice.isDeleted, isFalse);
    });

    test('fromMap normalises is_deleted integer to bool', () {
      final map = {
        'id': 'x2',
        'institute_id': AppConstants.defaultInstituteId,
        'title': 'T',
        'body': 'B',
        'target_role': null,
        'department_id': null,
        'attachment_url': null,
        'is_pinned': 0,
        'published_by': 'u',
        'published_by_name': null,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'sync_status': 'SYNCED',
        'is_deleted': 1,
        'is_synced': 1,
      };
      final notice = Notice.fromMap(map);
      expect(notice.isDeleted, isTrue);
      expect(notice.syncStatus, equals(SyncStatus.synced));
    });

    test('toSupabaseJson converts bool isPinned correctly', () {
      final notice = _notice(id: 'sj1', isPinned: true);
      final json = notice.toSupabaseJson();
      expect(json['is_pinned'], isTrue); // boolean for Supabase
      expect(json['is_deleted'], isFalse);
    });

    test('toMap converts bool isPinned to int for SQLite', () {
      final notice = _notice(id: 'tm1', isPinned: true);
      final map = notice.toMap();
      expect(map['is_pinned'], equals(1));
      expect(map['is_deleted'], equals(0));
    });
  });
}
