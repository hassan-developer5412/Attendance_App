import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Status of a leave request.
enum LeaveStatus {
  pending,
  approved,
  rejected;

  String get value => name;

  /// Human-readable display name.
  String get displayName {
    switch (this) {
      case LeaveStatus.pending:
        return 'Pending';
      case LeaveStatus.approved:
        return 'Approved';
      case LeaveStatus.rejected:
        return 'Rejected';
    }
  }

  /// Semantic color for this status.
  Color get color {
    switch (this) {
      case LeaveStatus.pending:
        return Colors.orange;
      case LeaveStatus.approved:
        return Colors.green;
      case LeaveStatus.rejected:
        return Colors.red;
    }
  }

  static LeaveStatus fromString(String value) {
    return LeaveStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => LeaveStatus.pending,
    );
  }
}

/// A leave request submitted by a teacher or staff member.
class LeaveRequest {
  LeaveRequest({
    String? id,
    required this.requesterName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.status = LeaveStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String requesterName;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  LeaveStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  /// Formatted date range string (e.g. '15 Sep - 17 Sep 2026').
  String get dateRange {
    final startFormatted = DateFormat('d MMM').format(startDate);
    final endFormatted = DateFormat('d MMM yyyy').format(endDate);
    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return DateFormat('d MMM yyyy').format(startDate);
    }
    return '$startFormatted - $endFormatted';
  }

  /// Creates a [LeaveRequest] from a database row map.
  factory LeaveRequest.fromMap(Map<String, dynamic> map) {
    // Prefer the canonical UUID; fall back to the legacy integer primary key.
    final rawUuid = map['uuid']?.toString();
    final rawId = map['id']?.toString();
    final canonicalId = (rawUuid != null && rawUuid.isNotEmpty)
        ? rawUuid
        : (rawId ?? '');

    return LeaveRequest(
      id: canonicalId,
      requesterName: (map['requester_name'] as String?) ?? '',
      leaveType: (map['leave_type'] as String?) ?? '',
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      reason: (map['reason'] as String?) ?? '',
      status: LeaveStatus.fromString(map['status'] as String),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  /// Converts to a database row map for insert/update.
  ///
  /// `id` is intentionally omitted: on the legacy `leave_requests` table it is an
  /// `INTEGER PRIMARY KEY AUTOINCREMENT`, so the canonical UUID is written to the
  /// dedicated `uuid` column instead.
  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'requester_name': requesterName,
      'leave_type': leaveType,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'reason': reason,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  /// REST API JSON format
  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'requester_name': requesterName,
      'leave_type': leaveType,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'reason': reason,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  LeaveRequest copyWith({
    String? id,
    String? requesterName,
    String? leaveType,
    DateTime? startDate,
    DateTime? endDate,
    String? reason,
    LeaveStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return LeaveRequest(
      id: id ?? this.id,
      requesterName: requesterName ?? this.requesterName,
      leaveType: leaveType ?? this.leaveType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

