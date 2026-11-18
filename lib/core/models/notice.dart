import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Institute Notice Board & Circulars model.
///
/// A notice is scoped to an [instituteId] and may optionally target a specific
/// [targetRole] (e.g. `'all'`, `'teacher'`, `'student'`) and/or a single
/// [departmentId]. Notices can be pinned, soft-deleted, and replicated to the
/// Supabase backend via the standard sync pipeline.
class Notice {
  Notice({
    String? id,
    required this.instituteId,
    required this.title,
    required this.body,
    this.targetRole,
    this.departmentId,
    this.attachmentUrl,
    this.isPinned = false,
    required this.publishedBy,
    this.publishedByName,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
    this.isSynced = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String instituteId;
  final String title;
  final String body;

  /// Optional role filter: `'all'`, `'teacher'`, `'student'`, etc.
  /// `null` or `'all'` means the notice is visible to everyone.
  final String? targetRole;

  /// Optional FK to `departments.id`. Null means institute-wide.
  final String? departmentId;

  /// Optional URL to an attached file (PDF, image, …).
  final String? attachmentUrl;

  /// Whether this notice is pinned to the top of the board.
  final bool isPinned;

  /// User id of the person who published this notice.
  final String publishedBy;

  /// Display name of the publisher (denormalized for offline read).
  final String? publishedByName;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;
  final bool isSynced;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  factory Notice.fromMap(Map<String, dynamic> map) {
    return Notice(
      id: map['id'].toString(),
      instituteId: map['institute_id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      targetRole: map['target_role'] as String?,
      departmentId: map['department_id'] as String?,
      attachmentUrl: map['attachment_url'] as String?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      publishedBy: map['published_by'] as String,
      publishedByName: map['published_by_name'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      isSynced: (map['is_synced'] as int? ?? 0) == 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Serializes all fields for local SQLite persistence.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'institute_id': instituteId,
      'title': title,
      'body': body,
      'target_role': targetRole,
      'department_id': departmentId,
      'attachment_url': attachmentUrl,
      'is_pinned': isPinned ? 1 : 0,
      'published_by': publishedBy,
      'published_by_name': publishedByName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  /// Supabase replication payload: JSON-native types, no local bookkeeping
  /// columns (`sync_status`, `is_synced`). `institute_id` is included so the
  /// backend can enforce row-level tenant isolation.
  Map<String, dynamic> toSupabaseJson() {
    return {
      'id': id,
      'institute_id': instituteId,
      'title': title,
      'body': body,
      'target_role': targetRole,
      'department_id': departmentId,
      'attachment_url': attachmentUrl,
      'is_pinned': isPinned,
      'published_by': publishedBy,
      'published_by_name': publishedByName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_deleted': isDeleted,
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  Notice copyWith({
    String? id,
    String? instituteId,
    String? title,
    String? body,
    // Use an Object? sentinel so callers can explicitly pass `null` to clear
    // nullable fields (targetRole, departmentId, attachmentUrl,
    // publishedByName).
    Object? targetRole = _sentinel,
    Object? departmentId = _sentinel,
    Object? attachmentUrl = _sentinel,
    bool? isPinned,
    String? publishedBy,
    Object? publishedByName = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
    bool? isSynced,
  }) {
    return Notice(
      id: id ?? this.id,
      instituteId: instituteId ?? this.instituteId,
      title: title ?? this.title,
      body: body ?? this.body,
      targetRole:
          targetRole == _sentinel ? this.targetRole : targetRole as String?,
      departmentId: departmentId == _sentinel
          ? this.departmentId
          : departmentId as String?,
      attachmentUrl: attachmentUrl == _sentinel
          ? this.attachmentUrl
          : attachmentUrl as String?,
      isPinned: isPinned ?? this.isPinned,
      publishedBy: publishedBy ?? this.publishedBy,
      publishedByName: publishedByName == _sentinel
          ? this.publishedByName
          : publishedByName as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  String toString() =>
      'Notice(id: $id, title: $title, targetRole: $targetRole, '
      'isPinned: $isPinned, isDeleted: $isDeleted)';
}

/// Private sentinel used by [Notice.copyWith] to distinguish "not provided"
/// from an explicit `null` for nullable fields.
const Object _sentinel = Object();
