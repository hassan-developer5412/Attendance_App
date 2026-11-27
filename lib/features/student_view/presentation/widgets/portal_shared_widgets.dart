import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';

/// Threshold below which subject or overall attendance triggers a warning badge.
const double kMinAttendanceThreshold = 75.0;

/// Aggregated attendance statistics for a single subject.
class SubjectAttendanceSummary {
  const SubjectAttendanceSummary({
    required this.subjectName,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.leaveCount,
    required this.totalCount,
  });

  final String subjectName;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final int leaveCount;
  final int totalCount;

  int get attendedCount => presentCount + lateCount;

  double get percentage =>
      totalCount > 0 ? (attendedCount / totalCount) * 100.0 : 0.0;

  bool get isBelowThreshold =>
      totalCount > 0 && percentage < kMinAttendanceThreshold;
}

/// Computes subject-wise attendance summaries from raw detailed log rows.
///
/// Each row is expected to contain `subject_name` and `status`.
List<SubjectAttendanceSummary> computeSubjectAttendance(
  List<Map<String, dynamic>> logs,
) {
  final grouped = <String, List<String>>{};
  for (final row in logs) {
    final subject = (row['subject_name'] as String?)?.trim();
    final key = (subject != null && subject.isNotEmpty) ? subject : 'General';
    final status = (row['status'] as String? ?? '').toLowerCase();
    grouped.putIfAbsent(key, () => <String>[]).add(status);
  }

  final summaries = <SubjectAttendanceSummary>[];
  for (final entry in grouped.entries) {
    int present = 0;
    int late = 0;
    int absent = 0;
    int leave = 0;
    for (final s in entry.value) {
      if (s == 'present') {
        present++;
      } else if (s == 'late') {
        late++;
      } else if (s == 'absent') {
        absent++;
      } else if (s == 'leave') {
        leave++;
      }
    }
    summaries.add(
      SubjectAttendanceSummary(
        subjectName: entry.key,
        presentCount: present,
        lateCount: late,
        absentCount: absent,
        leaveCount: leave,
        totalCount: entry.value.length,
      ),
    );
  }

  summaries.sort((a, b) => a.subjectName.compareTo(b.subjectName));
  return summaries;
}

/// Wraps [child] with [PermissionGuard] when RBAC is active in the widget tree.
///
/// When [RBACStore] is authenticated (or [PermissionService.instance.currentUserId]
/// is set), enforces [permission] strictly via [PermissionGuard] and renders
/// [PortalPermissionDeniedView] on denial.
Widget guardPortalSection(
  BuildContext context, {
  required String permission,
  required String sectionName,
  required Widget child,
}) {
  RBACStore? rbacStore;
  try {
    rbacStore = Provider.of<RBACStore>(context, listen: true);
  } catch (_) {
    rbacStore = null;
  }

  final rbacActive = (rbacStore != null && rbacStore.isAuthenticated) ||
      PermissionService.instance.currentUserId != null;

  if (!rbacActive) {
    return child;
  }

  return PermissionGuard(
    permission: permission,
    fallback: PortalPermissionDeniedView(sectionName: sectionName),
    child: child,
  );
}

/// Shown when a user's active RBAC roles lack permission for a portal section.
class PortalPermissionDeniedView extends StatelessWidget {
  const PortalPermissionDeniedView({
    super.key,
    required this.sectionName,
  });

  final String sectionName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 52,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              '$sectionName Restricted',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your account does not currently have permission to view $sectionName.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable empty/unlinked state card for portal sections.
class PortalEmptyStateCard extends StatelessWidget {
  const PortalEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 44,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the student/child identity card (name, roll number, class, department).
class PortalStudentInfoCard extends StatelessWidget {
  const PortalStudentInfoCard({
    super.key,
    required this.displayName,
    this.student,
    this.studentClass,
    this.department,
    this.roleLabel,
  });

  final String displayName;
  final Student? student;
  final SchoolClass? studentClass;
  final Department? department;
  final String? roleLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (roleLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            roleLabel!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (student?.rollNumber.isNotEmpty == true)
                    Text(
                      'Roll No: ${student!.rollNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (studentClass != null)
                    Text(
                      'Class: ${studentClass!.displayName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (department != null)
                    Text(
                      'Department: ${department!.name}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only weekly class & lab timetable view filtered by [classId].
class PortalWeeklyTimetableSection extends StatelessWidget {
  const PortalWeeklyTimetableSection({
    super.key,
    required this.classId,
    required this.isLinked,
    this.unlinkedMessage =
        'No class is linked to this account yet. Timetable will appear once linked.',
  });

  final String? classId;
  final bool isLinked;
  final String unlinkedMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isLinked || classId == null || classId!.isEmpty) {
      return PortalEmptyStateCard(
        icon: Icons.link_off_rounded,
        title: 'Class Not Linked',
        message: unlinkedMessage,
      );
    }

    TimetableStore? timetableStore;
    try {
      timetableStore = Provider.of<TimetableStore>(context, listen: true);
    } catch (_) {
      timetableStore = null;
    }

    if (timetableStore == null) {
      return const PortalEmptyStateCard(
        icon: Icons.schedule_outlined,
        title: 'Timetable Unavailable',
        message: 'Timetable service is currently unavailable offline.',
      );
    }

    InstituteStore? instituteStore;
    try {
      instituteStore = Provider.of<InstituteStore>(context, listen: true);
    } catch (_) {
      instituteStore = null;
    }

    final slots = timetableStore.slotsForClass(classId!);
    if (slots.isEmpty) {
      return const PortalEmptyStateCard(
        icon: Icons.event_note_outlined,
        title: 'No Timetable Scheduled',
        message: 'No weekly class or lab slots have been published for this class yet.',
      );
    }

    // Group slots by dayOfWeek (1 = Monday .. 6 = Saturday)
    final grouped = <int, List<TimetableSlot>>{};
    for (final slot in slots) {
      grouped.putIfAbsent(slot.dayOfWeek, () => <TimetableSlot>[]).add(slot);
    }
    final sortedDays = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedDays.map((day) {
        final daySlots = grouped[day]!;
        final dayName = daySlots.first.dayName;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 15,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...daySlots.map((slot) {
                final subject = instituteStore?.subjectById(slot.subjectId);
                final teacher = instituteStore?.teachers
                    .where((t) => t.id == slot.teacherId)
                    .firstOrNull;
                final subjectLabel = subject != null
                    ? '${subject.name} (${subject.code})'
                    : slot.subjectId;
                final teacherLabel = teacher?.name;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: slot.isLab
                          ? colorScheme.tertiary.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: slot.isLab
                          ? colorScheme.tertiaryContainer
                          : colorScheme.primaryContainer,
                      child: Icon(
                        slot.isLab
                            ? Icons.science_rounded
                            : Icons.menu_book_rounded,
                        size: 20,
                        color: slot.isLab
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      subjectLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      [
                        '${slot.formattedStartTime} – ${slot.formattedEndTime}',
                        'Room: ${slot.roomName}',
                        if (teacherLabel != null && teacherLabel.isNotEmpty)
                          teacherLabel,
                      ].join(' • '),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: slot.isLab
                            ? colorScheme.tertiaryContainer
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        slot.isLab ? 'Lab' : 'Theory',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: slot.isLab
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Shared attendance summary, subject-wise breakdown (<75% warning badge),
/// and detailed attendance history view.
class PortalAttendanceView extends StatelessWidget {
  const PortalAttendanceView({
    super.key,
    required this.logs,
    required this.isLinked,
    this.unlinkedMessage =
        'Account is not linked to a student record. Attendance data will appear once linked.',
    this.onRefresh,
  });

  final List<Map<String, dynamic>> logs;
  final bool isLinked;
  final String unlinkedMessage;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isLinked && logs.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PortalEmptyStateCard(
          icon: Icons.link_off_rounded,
          title: 'Student Record Not Linked',
          message: unlinkedMessage,
        ),
      );
    }

    final presentCount = logs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'present')
        .length;
    final lateCount = logs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'late')
        .length;
    final absentCount = logs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'absent')
        .length;
    final leaveCount = logs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'leave')
        .length;
    final total = logs.length;
    final overallPct =
        total > 0 ? ((presentCount + lateCount) / total * 100.0) : null;
    final rateLabel =
        overallPct != null ? '${overallPct.toStringAsFixed(1)}%' : '--%';
    final isOverallLow =
        overallPct != null && overallPct < kMinAttendanceThreshold;

    final subjectSummaries = computeSubjectAttendance(logs);

    final content = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall Attendance Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall Attendance',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isOverallLow) ...[
                            const SizedBox(height: 4),
                            const _LowAttendanceBadge(),
                          ],
                        ],
                      ),
                      Text(
                        rateLabel,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: overallPct == null
                              ? colorScheme.onSurfaceVariant
                              : isOverallLow
                                  ? Colors.red
                                  : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem('Present', presentCount, Colors.green),
                      _statItem('Late', lateCount, Colors.orange),
                      _statItem('Absent', absentCount, Colors.red),
                      _statItem('Leave', leaveCount, Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Subject-wise Attendance Breakdown
          Text(
            'Subject-wise Attendance',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (subjectSummaries.isEmpty)
            const PortalEmptyStateCard(
              icon: Icons.bar_chart_rounded,
              title: 'No Subject Attendance Yet',
              message:
                  'Subject-wise percentages will appear here once attendance sessions are recorded or synced.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: subjectSummaries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final item = subjectSummaries[idx];
                final pctText = '${item.percentage.toStringAsFixed(1)}%';
                final barColor =
                    item.isBelowThreshold ? Colors.red : Colors.green;

                return Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: item.isBelowThreshold
                          ? Colors.red.withValues(alpha: 0.4)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.subjectName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (item.isBelowThreshold) ...[
                              const _LowAttendanceBadge(),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              pctText,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: barColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (item.percentage / 100.0).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Attended ${item.attendedCount} of ${item.totalCount} sessions'
                          ' • Absent: ${item.absentCount}'
                          '${item.leaveCount > 0 ? ' • Leave: ${item.leaveCount}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 20),
          Text(
            'Attendance History',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (logs.isEmpty)
            const PortalEmptyStateCard(
              icon: Icons.event_note_outlined,
              title: 'No Attendance Records',
              message: 'No attendance records found yet.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final row = logs[idx];
                final statusStr =
                    (row['status'] as String? ?? 'present').toUpperCase();
                final date = row['session_date'] ?? row['date'] ?? '';
                final subject = row['subject_name'] ?? 'Class Session';
                Color statusColor = Colors.green;
                if (statusStr == 'LATE') statusColor = Colors.orange;
                if (statusStr == 'ABSENT') statusColor = Colors.red;
                if (statusStr == 'LEAVE') statusColor = Colors.blue;

                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      child: Icon(Icons.event, color: statusColor, size: 20),
                    ),
                    title: Text(
                      subject.toString(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('Date: $date'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusStr,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );

    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh!, child: content);
    }
    return content;
  }

  Widget _statItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _LowAttendanceBadge extends StatelessWidget {
  const _LowAttendanceBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 13,
            color: Colors.red,
          ),
          SizedBox(width: 4),
          Text(
            'Below 75%',
            style: TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only Notice Board & Circulars view for Student and Parent portals.
class PortalNoticesView extends StatelessWidget {
  const PortalNoticesView({
    super.key,
    required this.audienceRole,
    this.departmentId,
    this.onRefresh,
  });

  /// Audience role filter (`'student'` or `'parent'`), or `null` for managers.
  final String? audienceRole;
  final String? departmentId;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    NoticeStore? noticeStore;
    try {
      noticeStore = Provider.of<NoticeStore>(context, listen: true);
    } catch (_) {
      noticeStore = null;
    }

    if (noticeStore == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: PortalEmptyStateCard(
          icon: Icons.campaign_outlined,
          title: 'Notice Board Unavailable',
          message: 'Notice board is currently unavailable offline.',
        ),
      );
    }

    final filtered = noticeStore.noticesForUser(
      role: audienceRole,
      departmentId: departmentId,
    );

    final pinned = filtered.where((n) => n.isPinned).toList();
    final unpinned = filtered.where((n) => !n.isPinned).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.campaign_outlined,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No notices for you right now.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Check back later for institute announcements and circulars.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final list = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinned.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Pinned',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...pinned.map((n) => _buildNoticeCard(
                  context,
                  n,
                  theme,
                  colorScheme,
                  isPinnedSection: true,
                )),
            const SizedBox(height: 20),
          ],
          if (unpinned.isNotEmpty) ...[
            Text(
              'Recent Announcements',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...unpinned.map((n) => _buildNoticeCard(
                  context,
                  n,
                  theme,
                  colorScheme,
                  isPinnedSection: false,
                )),
          ],
        ],
      ),
    );

    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh!, child: list);
    }
    return list;
  }

  Widget _buildNoticeCard(
    BuildContext context,
    Notice notice,
    ThemeData theme,
    ColorScheme colorScheme, {
    required bool isPinnedSection,
  }) {
    final dateStr = DateFormat('d MMM yyyy').format(notice.createdAt.toLocal());
    final publisher = notice.publishedByName ?? 'Admin';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: isPinnedSection ? 2 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isPinnedSection
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
            width: isPinnedSection ? 1.5 : 1,
          ),
        ),
        color: isPinnedSection
            ? colorScheme.primaryContainer.withValues(alpha: 0.15)
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showNoticeDetail(context, notice, theme),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPinnedSection) ...[
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 2),
                        child: Icon(
                          Icons.push_pin_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        notice.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        dateStr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  notice.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      publisher,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    if (notice.attachmentUrl != null &&
                        notice.attachmentUrl!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.attachment_rounded,
                        size: 12,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Attachment',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'Tap to read more →',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNoticeDetail(BuildContext context, Notice notice, ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          notice.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notice.body, style: theme.textTheme.bodyMedium),
              if (notice.attachmentUrl != null &&
                  notice.attachmentUrl!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.attachment_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        notice.attachmentUrl!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'By ${notice.publishedByName ?? "Admin"} · '
                '${DateFormat("d MMM yyyy").format(notice.createdAt.toLocal())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Shared read-only leave request card showing status badge, date range,
/// supporting attachment pill, and teacher/admin remarks.
class PortalLeaveRequestCard extends StatelessWidget {
  const PortalLeaveRequestCard({
    super.key,
    required this.item,
  });

  final LeaveRequest item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = item.status.color;
    final diff = item.endDate.difference(item.startDate).inDays + 1;
    final durationText = diff <= 1 ? '1 day' : '$diff days';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          item.leaveType,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.status == LeaveStatus.approved
                            ? Icons.check_circle_rounded
                            : item.status == LeaveStatus.rejected
                                ? Icons.cancel_rounded
                                : Icons.hourglass_top_rounded,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.status.displayName,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.date_range_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  item.dateRange,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '• $durationText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (item.reason.isNotEmpty)
              Text(
                item.reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            if (item.attachmentUrl != null &&
                item.attachmentUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildAttachmentPill(item.attachmentUrl!, colorScheme, theme),
            ],
            const Divider(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item.remarks != null && item.remarks!.isNotEmpty
                    ? (item.status == LeaveStatus.approved
                        ? Colors.green.withValues(alpha: 0.08)
                        : item.status == LeaveStatus.rejected
                            ? Colors.red.withValues(alpha: 0.08)
                            : colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4))
                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: item.remarks != null && item.remarks!.isNotEmpty
                      ? (item.status == LeaveStatus.approved
                          ? Colors.green.withValues(alpha: 0.3)
                          : item.status == LeaveStatus.rejected
                              ? Colors.red.withValues(alpha: 0.3)
                              : colorScheme.outlineVariant)
                      : colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 15,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Teacher / Admin Remarks',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.remarks != null && item.remarks!.trim().isNotEmpty
                        ? item.remarks!
                        : (item.status == LeaveStatus.pending
                            ? 'Awaiting review and remarks from faculty or administration.'
                            : 'No remarks recorded.'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle:
                          item.remarks == null || item.remarks!.trim().isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                      color:
                          item.remarks != null && item.remarks!.trim().isNotEmpty
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPill(
    String url,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    final isOfflineQueued = url.startsWith('offline_queued://');
    final displayName = isOfflineQueued
        ? url.replaceFirst('offline_queued://', '').split('/').last
        : url.split('/').last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOfflineQueued
                ? Icons.cloud_queue_rounded
                : Icons.attachment_rounded,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isOfflineQueued
                  ? 'Queued Attachment: $displayName'
                  : 'Medical / Supporting Document: $displayName',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isOfflineQueued) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Offline Queued',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
