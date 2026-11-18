import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/repositories/notice_repository.dart';

/// Manages the in-memory list of [Notice] rows backed by [NoticeRepository].
///
/// Follows the exact same `ChangeNotifier` pattern used by [LabInventoryStore]
/// and [LeaveStore]. Every mutation delegates persistence and sync scheduling
/// to the repository; this store only maintains the in-memory projection and
/// fires [notifyListeners] so the UI rebuilds.
class NoticeStore extends ChangeNotifier {
  NoticeStore({NoticeRepository? repository})
      : _repository = repository ?? NoticeRepository();

  final NoticeRepository _repository;

  final List<Notice> _notices = [];

  // ---------------------------------------------------------------------------
  // Public read-only projections
  // ---------------------------------------------------------------------------

  /// All non-deleted notices loaded from the local database, pinned-first
  /// then newest-first (mirrors the SQL order-by).
  List<Notice> get notices => List.unmodifiable(_notices);

  /// Only the pinned notices, in creation order descending.
  List<Notice> get pinnedNotices =>
      _notices.where((n) => n.isPinned && !n.isDeleted).toList();

  /// Returns notices visible to [role] and / or [departmentId].
  ///
  /// A notice is included when:
  /// - Its `targetRole` is null, `'all'`, or matches [role] (when [role] is
  ///   provided).
  /// - Its `departmentId` is null or matches [departmentId] (when
  ///   [departmentId] is provided).
  ///
  /// Pass neither argument to receive every loaded (non-deleted) notice.
  List<Notice> noticesForUser({String? role, String? departmentId}) {
    return _notices.where((n) {
      if (n.isDeleted) return false;

      // Role filter: null / 'all' target_role is visible to everyone.
      if (role != null && role.isNotEmpty) {
        final target = n.targetRole;
        final visibleToRole =
            target == null || target == 'all' || target == role;
        if (!visibleToRole) return false;
      }

      // Department filter: null department_id means institute-wide.
      if (departmentId != null && departmentId.isNotEmpty) {
        final dept = n.departmentId;
        if (dept != null && dept != departmentId) return false;
      }

      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads all non-deleted notices from SQLite into memory and notifies
  /// listeners. Called at startup and after every Supabase pull cycle via
  /// [SyncService.onPullCompleted].
  Future<void> init() async {
    final loaded = await _repository.getAll();
    _notices
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Creates a new notice, persists it, and prepends it to the in-memory list.
  ///
  /// The repository queues a Supabase push so the notice is replicated to the
  /// cloud once the device is online.
  Future<void> addNotice({
    required String instituteId,
    required String title,
    required String body,
    required String publishedBy,
    String? publishedByName,
    String? targetRole,
    String? departmentId,
    String? attachmentUrl,
    bool isPinned = false,
  }) async {
    final notice = Notice(
      instituteId: instituteId,
      title: title.trim(),
      body: body.trim(),
      publishedBy: publishedBy,
      publishedByName: publishedByName,
      targetRole: targetRole,
      departmentId: departmentId,
      attachmentUrl: attachmentUrl,
      isPinned: isPinned,
    );
    await _repository.insert(notice);

    // Insert at position 0 so pinned + newest-first ordering is preserved for
    // the common case; a full reload on the next pull cycle corrects any edge
    // cases.
    _notices.insert(0, notice);
    notifyListeners();
  }

  /// Persists changes to [updated] and replaces the in-memory copy.
  Future<void> updateNotice(Notice updated) async {
    await _repository.update(updated);
    final idx = _notices.indexWhere((n) => n.id == updated.id);
    if (idx >= 0) {
      _notices[idx] = updated;
      notifyListeners();
    }
  }

  /// Soft-deletes the notice with [id] and removes it from the in-memory list.
  Future<void> deleteNotice(String id) async {
    await _repository.softDelete(id);
    _notices.removeWhere((n) => n.id == id);
    notifyListeners();
  }
}
