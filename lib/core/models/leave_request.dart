import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    this.id,
    required this.requesterName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.status = LeaveStatus.pending,
  });

  final int? id;
  final String requesterName;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  LeaveStatus status;

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
    return LeaveRequest(
      id: map['id'] as int?,
      requesterName: map['requester_name'] as String,
      leaveType: map['leave_type'] as String,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: DateTime.parse(map['end_date'] as String),
      reason: map['reason'] as String,
      status: LeaveStatus.fromString(map['status'] as String),
    );
  }

  /// Converts to a database row map for insert/update.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'requester_name': requesterName,
      'leave_type': leaveType,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'reason': reason,
      'status': status.value,
    };
  }
}
