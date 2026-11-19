import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/leave_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/widgets/themed_dropdown.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';

/// Self-Service portal for students.
///
/// Provides:
/// 1. Class Schedule & Enrolled Subjects
/// 2. Personal Attendance History & Statistics
/// 3. Self-Service Leave Applications with Supabase Storage attachments & offline queuing
class StudentSelfViewContent extends StatefulWidget {
  final int initialTab;
  final String? studentId;

  const StudentSelfViewContent({
    super.key,
    this.initialTab = 0,
    this.studentId,
  });

  @override
  State<StudentSelfViewContent> createState() => _StudentSelfViewContentState();
}

class _StudentSelfViewContentState extends State<StudentSelfViewContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  Student? _student;
  SchoolClass? _studentClass;
  Department? _department;
  List<Subject> _enrolledSubjects = [];
  List<Map<String, dynamic>> _detailedAttendanceLogs = [];

  // Leave filtering
  String _leaveFilterStatus = 'All';

  // Resolved identity
  String _resolvedStudentId = '';
  String _resolvedStudentName = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllData());
  }

  @override
  void didUpdateWidget(covariant StudentSelfViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabController.animateTo(widget.initialTab.clamp(0, 3));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  LeaveStore? _getLeaveStore() {
    try {
      return Provider.of<LeaveStore>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAllData() async {
    if (_student == null && _resolvedStudentId.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      AuthStore? authStore;
      InstituteStore? instituteStore;
      AttendanceStore? attendanceStore;

      try {
        authStore = Provider.of<AuthStore>(context, listen: false);
      } catch (_) {}
      try {
        instituteStore = Provider.of<InstituteStore>(context, listen: false);
      } catch (_) {}
      try {
        attendanceStore = Provider.of<AttendanceStore>(context, listen: false);
      } catch (_) {}

      final user = authStore?.currentUser;
      final studentRepo = StudentRepository();

      // 1. Resolve Student Record
      Student? student;
      if (widget.studentId != null && widget.studentId!.isNotEmpty) {
        try {
          student = await studentRepo.getById(widget.studentId!).timeout(
                const Duration(milliseconds: 500),
                onTimeout: () => null,
              );
        } catch (_) {}
      }

      if (student == null && user != null) {
        final lookupRoll = user.rollNo ?? user.username;
        if (lookupRoll.isNotEmpty) {
          try {
            student = await studentRepo.getByRollNumber(lookupRoll).timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () => null,
                );
          } catch (_) {}
        }
        if (student == null) {
          try {
            student = await studentRepo.getById(user.id).timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () => null,
                );
          } catch (_) {}
        }
        if (student == null && instituteStore != null) {
          final matches = instituteStore.students.where((s) =>
              s.rollNumber.toLowerCase() == lookupRoll.toLowerCase() ||
              s.name.toLowerCase() == user.displayName.toLowerCase());
          if (matches.isNotEmpty) {
            student = matches.first;
          }
        }
      }

      _student = student;
      _resolvedStudentId = student?.id ?? widget.studentId ?? user?.id ?? 'student_id';
      _resolvedStudentName = student?.name ?? user?.displayName ?? 'Student';

      // 2. Resolve Class and Subjects
      if (student != null && instituteStore != null) {
        _studentClass = instituteStore.classById(student.classId);
        _department = instituteStore.departmentById(student.departmentId);
        _enrolledSubjects = instituteStore.subjectsForClassAndYear(
          student.classId,
          student.currentYear,
        );
        if (_enrolledSubjects.isEmpty) {
          _enrolledSubjects = instituteStore.subjectsForClass(student.classId);
        }
      }

      // 3. Resolve Attendance Logs
      if (attendanceStore != null && _resolvedStudentId.isNotEmpty) {
        try {
          _detailedAttendanceLogs =
              await attendanceStore.getDetailedAttendanceForStudent(_resolvedStudentId).timeout(
                    const Duration(milliseconds: 500),
                    onTimeout: () => const [],
                  );
        } catch (_) {
          // Fallback to AttendanceRepository if AttendanceStore fails
          try {
            _detailedAttendanceLogs = await AttendanceRepository()
                .getDetailedAttendanceForStudent(_resolvedStudentId)
                .timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () => const [],
                );
          } catch (_) {}
        }
      }

      // 4. Resolve Leaves using LeaveStore / LeaveRepository
      final leaveStore = _getLeaveStore();
      if (leaveStore != null) {
        try {
          await leaveStore.loadAll(studentId: _resolvedStudentId).timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {},
              );
        } catch (_) {}
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showApplyLeaveModal() async {
    final result = await showModalBottomSheet<_LeaveApplicationFormData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApplyLeaveBottomSheet(
        studentName: _resolvedStudentName,
        studentId: _resolvedStudentId,
      ),
    );

    if (result == null || !mounted) return;

    // Apply leave through LeaveStore
    final leaveStore = _getLeaveStore();
    if (leaveStore != null) {
      await leaveStore.applyLeave(
        requesterName: result.studentName,
        leaveType: result.leaveType,
        startDate: result.startDate,
        endDate: result.endDate,
        reason: result.reason,
        studentId: result.studentId,
        attachmentUrl: result.attachmentUrl,
      );
    } else {
      // Fallback directly to repository if store is not in scope
      final repo = LeaveRepository();
      await repo.insert(
        LeaveRequest(
          requesterName: result.studentName,
          leaveType: result.leaveType,
          startDate: result.startDate,
          endDate: result.endDate,
          reason: result.reason,
          studentId: result.studentId,
          attachmentUrl: result.attachmentUrl,
        ),
      );
      setState(() {});
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.attachmentUrl != null &&
                    result.attachmentUrl!.startsWith('offline_queued://')
                ? 'Leave request submitted! Document queued for upload once online.'
                : 'Leave request submitted successfully!',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      try {
        final authStore = Provider.of<AuthStore>(context, listen: false);
        await authStore.logout().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Logout failed in StudentSelfViewContent: $e');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Student Portal — ${_resolvedStudentName.isNotEmpty ? _resolvedStudentName : "Self Service"}',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.schedule_rounded), text: 'Schedule'),
            Tab(icon: Icon(Icons.fact_check_rounded), text: 'Attendance'),
            Tab(icon: Icon(Icons.event_busy_rounded), text: 'My Leaves'),
            Tab(icon: Icon(Icons.campaign_rounded), text: 'Notices'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading student portal...'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildScheduleTab(theme, colorScheme),
                _buildAttendanceTab(theme, colorScheme),
                _buildLeavesTab(theme, colorScheme),
                _buildNoticesTab(theme, colorScheme),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 0: Class Schedule
  // ---------------------------------------------------------------------------
  Widget _buildScheduleTab(ThemeData theme, ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStudentInfoCard(theme, colorScheme),
          const SizedBox(height: 20),
          Text(
            'Enrolled Subjects & Classes',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_enrolledSubjects.isEmpty)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No enrolled subjects found for this session.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _enrolledSubjects.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final sub = _enrolledSubjects[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Text(
                        sub.code.isNotEmpty ? sub.code[0] : 'S',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      sub.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${sub.code} • ${sub.subjectType.label}'),
                    trailing: Chip(
                      label: Text(sub.year.isNotEmpty ? sub.year : 'General'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Attendance History
  // ---------------------------------------------------------------------------
  Widget _buildAttendanceTab(ThemeData theme, ColorScheme colorScheme) {
    final presentCount = _detailedAttendanceLogs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'present')
        .length;
    final lateCount = _detailedAttendanceLogs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'late')
        .length;
    final absentCount = _detailedAttendanceLogs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'absent')
        .length;
    final leaveCount = _detailedAttendanceLogs
        .where((l) => (l['status'] as String?)?.toLowerCase() == 'leave')
        .length;
    final total = _detailedAttendanceLogs.length;
    final rate = total > 0 ? ((presentCount + lateCount) / total * 100).toStringAsFixed(1) : '100.0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Overall Attendance',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$rate%',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: double.tryParse(rate)! >= 75 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _attendanceStatItem('Present', presentCount, Colors.green),
                      _attendanceStatItem('Late', lateCount, Colors.orange),
                      _attendanceStatItem('Absent', absentCount, Colors.red),
                      _attendanceStatItem('Leave', leaveCount, Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Attendance History',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_detailedAttendanceLogs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No attendance records found yet.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _detailedAttendanceLogs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, idx) {
                final row = _detailedAttendanceLogs[idx];
                final statusStr = (row['status'] as String? ?? 'present').toUpperCase();
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
                    title: Text(subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Date: $date'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusStr,
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _attendanceStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: My Leaves
  // ---------------------------------------------------------------------------
  Widget _buildLeavesTab(ThemeData theme, ColorScheme colorScheme) {
    LeaveStore? leaveStore;
    try {
      leaveStore = Provider.of<LeaveStore>(context, listen: true);
    } catch (_) {
      leaveStore = null;
    }

    final allItems = leaveStore?.requests ?? [];
    // Ensure records are filtered to the logged-in student's records
    final studentLeaves = allItems.where((r) {
      if (r.studentId != null && r.studentId!.isNotEmpty) {
        return r.studentId == _resolvedStudentId;
      }
      return r.requesterName.toLowerCase() == _resolvedStudentName.toLowerCase();
    }).toList();

    final filtered = studentLeaves.where((r) {
      if (_leaveFilterStatus == 'All') return true;
      return r.status.displayName.toLowerCase() == _leaveFilterStatus.toLowerCase();
    }).toList();

    final pendingCount = studentLeaves.where((r) => r.status == LeaveStatus.pending).length;
    final approvedCount = studentLeaves.where((r) => r.status == LeaveStatus.approved).length;
    final rejectedCount = studentLeaves.where((r) => r.status == LeaveStatus.rejected).length;

    return RefreshIndicator(
      onRefresh: () async {
        if (leaveStore != null) {
          await leaveStore.loadAll(studentId: _resolvedStudentId);
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top action bar
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Leave Applications',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Submit and track your leave status and teacher remarks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showApplyLeaveModal,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Apply for Leave'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stat chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _leaveStatChip('Pending', pendingCount, Colors.orange),
                _leaveStatChip('Approved', approvedCount, Colors.green),
                _leaveStatChip('Rejected', rejectedCount, Colors.red),
              ],
            ),
            const SizedBox(height: 16),

            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Pending', 'Approved', 'Rejected'].map((status) {
                  final isSelected = _leaveFilterStatus == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(status),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() => _leaveFilterStatus = selected ? status : 'All');
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Leaves list
            if (filtered.isEmpty)
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 48,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No leave requests found',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Need time off? Click "Apply for Leave" above to submit an application.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (ctx, index) {
                  return _buildLeaveRequestCard(filtered[index], theme, colorScheme);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveRequestCard(
    LeaveRequest item,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final statusColor = item.status.color;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Type Header
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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

            // Date Range
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
                  '• ${_calculateDuration(item.startDate, item.endDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Reason
            if (item.reason.isNotEmpty)
              Text(
                item.reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),

            // Supporting Attachment
            if (item.attachmentUrl != null && item.attachmentUrl!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildAttachmentPill(item.attachmentUrl!, colorScheme, theme),
            ],

            const Divider(height: 20),

            // Teacher/Admin Remarks Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: item.remarks != null && item.remarks!.isNotEmpty
                    ? (item.status == LeaveStatus.approved
                        ? Colors.green.withValues(alpha: 0.08)
                        : item.status == LeaveStatus.rejected
                            ? Colors.red.withValues(alpha: 0.08)
                            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4))
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
                      fontStyle: item.remarks == null || item.remarks!.trim().isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: item.remarks != null && item.remarks!.trim().isNotEmpty
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

  Widget _buildAttachmentPill(String url, ColorScheme colorScheme, ThemeData theme) {
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
            isOfflineQueued ? Icons.cloud_queue_rounded : Icons.attachment_rounded,
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
                style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leaveStatChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 5),
      label: Text('$label: $count'),
      visualDensity: VisualDensity.compact,
    );
  }

  String _calculateDuration(DateTime start, DateTime end) {
    final diff = end.difference(start).inDays + 1;
    return diff <= 1 ? '1 day' : '$diff days';
  }

  Widget _buildStudentInfoCard(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                _resolvedStudentName.isNotEmpty ? _resolvedStudentName[0].toUpperCase() : 'S',
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
                  Text(
                    _resolvedStudentName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (_student?.rollNumber.isNotEmpty == true)
                    Text(
                      'Roll No: ${_student!.rollNumber}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  if (_studentClass != null)
                    Text(
                      'Class: ${_studentClass!.displayName}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  if (_department != null)
                    Text(
                      'Department: ${_department!.name}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Notice Board & Circulars (read-only student view)
  // ---------------------------------------------------------------------------

  Widget _buildNoticesTab(ThemeData theme, ColorScheme colorScheme) {
    // Try to access NoticeStore — it may not be in the tree in some contexts.
    NoticeStore? noticeStore;
    try {
      noticeStore = Provider.of<NoticeStore>(context, listen: true);
    } catch (_) {}

    if (noticeStore == null) {
      return Center(
        child: Text(
          'Notice board unavailable.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    final filtered = noticeStore.noticesForUser(
      role: 'student',
      departmentId: _department?.id,
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

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pinned Notices ───────────────────────────────────────────
            if (pinned.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.push_pin_rounded,
                      size: 16, color: colorScheme.primary),
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
              ...pinned.map((n) => _buildStudentNoticeCard(
                    n,
                    theme,
                    colorScheme,
                    isPinnedSection: true,
                  )),
              const SizedBox(height: 20),
            ],

            // ── All Notices ──────────────────────────────────────────────
            if (unpinned.isNotEmpty) ...[
              Text(
                'Recent Announcements',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ...unpinned.map((n) => _buildStudentNoticeCard(
                    n,
                    theme,
                    colorScheme,
                    isPinnedSection: false,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentNoticeCard(
    Notice notice,
    ThemeData theme,
    ColorScheme colorScheme, {
    required bool isPinnedSection,
  }) {
    final dateStr =
        DateFormat('d MMM yyyy').format(notice.createdAt.toLocal());
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
          onTap: () => _showStudentNoticeDetail(context, notice, theme),
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
                    // Date chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
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
                // Body preview
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
                    Icon(Icons.person_outline_rounded,
                        size: 12, color: colorScheme.onSurfaceVariant),
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
                      Icon(Icons.attachment_rounded,
                          size: 12, color: colorScheme.primary),
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

  void _showStudentNoticeDetail(
      BuildContext context, Notice notice, ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          notice.title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice.body,
                style: theme.textTheme.bodyMedium,
              ),
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

// ---------------------------------------------------------------------------
// Apply Leave Bottom Sheet / Dialog
// ---------------------------------------------------------------------------

class _LeaveApplicationFormData {
  final String studentName;
  final String studentId;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String? attachmentUrl;

  _LeaveApplicationFormData({
    required this.studentName,
    required this.studentId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    this.attachmentUrl,
  });
}

class _ApplyLeaveBottomSheet extends StatefulWidget {
  final String studentName;
  final String studentId;

  const _ApplyLeaveBottomSheet({
    required this.studentName,
    required this.studentId,
  });

  @override
  State<_ApplyLeaveBottomSheet> createState() => _ApplyLeaveBottomSheetState();
}

class _ApplyLeaveBottomSheetState extends State<_ApplyLeaveBottomSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _reasonController;

  String _leaveType = 'Sick Leave';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  // Attachment state
  String? _attachedFileName;
  Uint8List? _attachedFileBytes;
  bool _isUploadingAttachment = false;

  static const _leaveTypes = [
    'Sick Leave',
    'Medical Leave',
    'Casual Leave',
    'Personal Leave',
    'Emergency Leave',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.studentName);
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  void _selectSampleAttachment(String type) {
    final sanitizedName =
        '${type.toLowerCase().replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    // Simulated medical note / document payload
    final dummyContent =
        'Official Supporting Medical Note for ${widget.studentName} (${widget.studentId})\nDate: ${DateTime.now().toIso8601String()}\nDocument Type: $type';
    final bytes = Uint8List.fromList(utf8.encode(dummyContent));

    setState(() {
      _attachedFileName = sanitizedName;
      _attachedFileBytes = bytes;
    });
  }

  void _clearAttachment() {
    setState(() {
      _attachedFileName = null;
      _attachedFileBytes = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isUploadingAttachment = true);

    String? attachmentUrl;
    if (_attachedFileName != null && _attachedFileBytes != null) {
      try {
        attachmentUrl = await SyncService.instance.uploadAttachment(
          fileName: _attachedFileName!,
          bytes: _attachedFileBytes!,
          contentType: _attachedFileName!.endsWith('.png')
              ? 'image/png'
              : _attachedFileName!.endsWith('.jpg') || _attachedFileName!.endsWith('.jpeg')
                  ? 'image/jpeg'
                  : 'application/pdf',
        );
      } catch (e) {
        // Fallback to queue via sync service if unexpected exception occurs
        final storagePath = 'leaves/${DateTime.now().millisecondsSinceEpoch}_$_attachedFileName';
        await SyncService.instance.queueStorageUpload(
          bucket: 'leave-attachments',
          fileName: _attachedFileName!,
          bytes: _attachedFileBytes!,
        );
        attachmentUrl = 'offline_queued://$storagePath';
      }
    }

    if (!mounted) return;
    setState(() => _isUploadingAttachment = false);

    Navigator.of(context).pop(
      _LeaveApplicationFormData(
        studentName: _nameController.text.trim(),
        studentId: widget.studentId,
        leaveType: _leaveType,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text.trim(),
        attachmentUrl: attachmentUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: mediaQuery.size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        mediaQuery.viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Apply for Leave',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Submit your leave dates, reason, and supporting medical documents',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // Student Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Student Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // Leave Type
              AppDropdownButtonFormField<String>(
                initialValue: _leaveType,
                decoration: const InputDecoration(
                  labelText: 'Leave Type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _leaveTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _leaveType = val);
                },
              ),
              const SizedBox(height: 14),

              // Dates Picker
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: true),
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(DateFormat('d MMM yyyy').format(_startDate)),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('to'),
                  ),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: false),
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(DateFormat('d MMM yyyy').format(_endDate)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Reason
              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for Leave',
                  alignLabelWithHint: true,
                  hintText: 'e.g. Fever and flu, advised complete bed rest by doctor...',
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Please enter a reason' : null,
              ),
              const SizedBox(height: 16),

              // Supporting Document / Attachment
              Text(
                'Supporting Document (Optional)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Attach a doctor note or medical certificate (uploaded to Supabase Storage with offline sync):',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              if (_attachedFileName == null) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.medical_services_outlined, size: 16),
                      label: const Text('Attach Medical Certificate'),
                      onPressed: () => _selectSampleAttachment('Medical Certificate'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.note_add_outlined, size: 16),
                      label: const Text('Attach Doctor Note'),
                      onPressed: () => _selectSampleAttachment('Doctor Note'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.file_present_rounded, size: 16),
                      label: const Text('Attach Prescription'),
                      onPressed: () => _selectSampleAttachment('Prescription'),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.description_rounded, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _attachedFileName!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${_attachedFileBytes?.lengthInBytes ?? 0} bytes • Supabase Storage Ready',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _clearAttachment,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Remove attachment',
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isUploadingAttachment ? null : _submit,
                    icon: _isUploadingAttachment
                        ? const Icon(Icons.hourglass_top_rounded, size: 18)
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(_isUploadingAttachment ? 'Submitting...' : 'Submit Leave Request'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
