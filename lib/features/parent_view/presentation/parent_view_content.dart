import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/repositories/attendance_repository.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/features/auth/presentation/password_change_screen.dart';
import 'package:attendance_app/features/student_view/presentation/widgets/portal_shared_widgets.dart';

/// Read-only self-service portal for parents to monitor their linked child's:
/// 1. Weekly Class & Lab Timetable via [TimetableStore] (filtered by child's `classId`)
/// 2. Subject-wise & overall attendance percentages (with <75% warning badge)
/// 3. Leave application status and teacher/admin remarks (read-only)
/// 4. Institute Notice Board & Circulars via [NoticeStore] (institute-wide + child's department)
///
/// All sections enforce RBAC via [PermissionGuard] / [PermissionService.instance]
/// and render graceful empty states when offline or unlinked.
class ParentViewContent extends StatefulWidget {
  final int initialTab;
  final String? studentId;

  const ParentViewContent({
    super.key,
    this.initialTab = 0,
    this.studentId,
  });

  @override
  State<ParentViewContent> createState() => _ParentViewContentState();
}

class _ParentViewContentState extends State<ParentViewContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  Student? _student;
  SchoolClass? _studentClass;
  Department? _department;
  List<Map<String, dynamic>> _detailedAttendanceLogs = [];

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
  void didUpdateWidget(covariant ParentViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabController.animateTo(widget.initialTab.clamp(0, 3));
    }
    if (widget.studentId != oldWidget.studentId) {
      _loadAllData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (_student == null && _resolvedStudentId.isEmpty && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      AuthStore? authStore;
      InstituteStore? instituteStore;
      AttendanceStore? attendanceStore;
      LeaveStore? leaveStore;
      TimetableStore? timetableStore;
      NoticeStore? noticeStore;

      try {
        authStore = Provider.of<AuthStore>(context, listen: false);
      } catch (_) {}
      try {
        instituteStore = Provider.of<InstituteStore>(context, listen: false);
      } catch (_) {}
      try {
        attendanceStore = Provider.of<AttendanceStore>(context, listen: false);
      } catch (_) {}
      try {
        leaveStore = Provider.of<LeaveStore>(context, listen: false);
      } catch (_) {}
      try {
        timetableStore = Provider.of<TimetableStore>(context, listen: false);
      } catch (_) {}
      try {
        noticeStore = Provider.of<NoticeStore>(context, listen: false);
      } catch (_) {}

      final user = authStore?.currentUser;
      final studentRepo = StudentRepository();

      // 1. Resolve linked child record
      Student? student;
      if (widget.studentId != null && widget.studentId!.isNotEmpty) {
        try {
          student = await studentRepo.getById(widget.studentId!).timeout(
                const Duration(milliseconds: 500),
                onTimeout: () => null,
              );
        } catch (_) {}
        if (student == null && instituteStore != null) {
          student = instituteStore.students
              .where((s) => s.id == widget.studentId)
              .firstOrNull;
        }
      }

      if (student == null && user != null) {
        final lookupRoll = user.rollNo;
        if (lookupRoll != null && lookupRoll.isNotEmpty) {
          try {
            student = await studentRepo.getByRollNumber(lookupRoll).timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () => null,
                );
          } catch (_) {}
          if (student == null && instituteStore != null) {
            student = instituteStore.students
                .where(
                  (s) => s.rollNumber.toLowerCase() == lookupRoll.toLowerCase(),
                )
                .firstOrNull;
          }
        }
      }

      _student = student;
      _resolvedStudentId = student?.id ?? widget.studentId ?? '';
      _resolvedStudentName = student?.name ?? '';

      // 2. Resolve class & department for child
      if (student != null && instituteStore != null) {
        _studentClass = instituteStore.classById(student.classId);
        _department = instituteStore.departmentById(student.departmentId);
      } else {
        _studentClass = null;
        _department = null;
      }

      // 3. Ensure TimetableStore & NoticeStore are initialized if empty
      if (timetableStore != null && timetableStore.slots.isEmpty) {
        try {
          await timetableStore.init().timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {},
              );
        } catch (_) {}
      }
      if (noticeStore != null && noticeStore.notices.isEmpty) {
        try {
          await noticeStore.init().timeout(
                const Duration(milliseconds: 500),
                onTimeout: () {},
              );
        } catch (_) {}
      }

      // 4. Resolve Attendance Logs for linked child
      if (_resolvedStudentId.isNotEmpty) {
        if (attendanceStore != null) {
          try {
            _detailedAttendanceLogs = await attendanceStore
                .getDetailedAttendanceForStudent(_resolvedStudentId)
                .timeout(
                  const Duration(milliseconds: 500),
                  onTimeout: () => const [],
                );
          } catch (_) {
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
      } else {
        _detailedAttendanceLogs = [];
      }

      // 5. Resolve Leaves for linked child (read-only)
      if (leaveStore != null && _resolvedStudentId.isNotEmpty) {
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
        debugPrint('Logout failed in ParentViewContent: $e');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  /// Opens the voluntary password-change screen for the logged-in parent.
  Future<void> _showChangePassword() async {
    final authStore = Provider.of<AuthStore>(context, listen: false);
    if (authStore.currentUser == null) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PasswordChangeScreen(isMandatory: false),
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password changed successfully. Please use your new password to sign in.',
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titleSuffix = _resolvedStudentName.isNotEmpty
        ? _resolvedStudentName
        : 'Child Overview';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Parent Portal — $titleSuffix',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Change Password',
            onPressed: _showChangePassword,
          ),
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
            Tab(icon: Icon(Icons.schedule_rounded), text: 'Timetable'),
            Tab(icon: Icon(Icons.fact_check_rounded), text: 'Attendance'),
            Tab(icon: Icon(Icons.event_busy_rounded), text: 'Leaves'),
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
                  Text('Loading parent portal...'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                guardPortalSection(
                  context,
                  permission: PermissionCodes.timetableView,
                  sectionName: 'Timetable',
                  child: _buildTimetableTab(theme, colorScheme),
                ),
                guardPortalSection(
                  context,
                  permission: PermissionCodes.attendanceView,
                  sectionName: 'Attendance',
                  child: PortalAttendanceView(
                    logs: _detailedAttendanceLogs,
                    isLinked: _student != null,
                    unlinkedMessage:
                        'No student profile is linked to this parent account yet. '
                        'Contact administration to link your child\'s record.',
                    onRefresh: _loadAllData,
                  ),
                ),
                guardPortalSection(
                  context,
                  permission: PermissionCodes.leaveView,
                  sectionName: 'Leave Status',
                  child: _buildReadOnlyLeavesTab(theme, colorScheme),
                ),
                guardPortalSection(
                  context,
                  permission: PermissionCodes.noticeView,
                  sectionName: 'Notices',
                  child: PortalNoticesView(
                    audienceRole: PermissionService.instance
                            .hasPermission(PermissionCodes.noticeManage)
                        ? null
                        : 'parent',
                    departmentId: _department?.id ?? _student?.departmentId,
                    onRefresh: _loadAllData,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTimetableTab(ThemeData theme, ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_student != null) ...[
              PortalStudentInfoCard(
                displayName: _resolvedStudentName,
                student: _student,
                studentClass: _studentClass,
                department: _department,
                roleLabel: 'Child',
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'Weekly Class & Lab Timetable',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            PortalWeeklyTimetableSection(
              classId: _student?.classId,
              isLinked: _student != null,
              unlinkedMessage:
                  'No student profile is linked to this parent account yet. '
                  'Your child\'s weekly timetable will appear once linked.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyLeavesTab(ThemeData theme, ColorScheme colorScheme) {
    if (_student == null && _resolvedStudentId.isEmpty) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: PortalEmptyStateCard(
          icon: Icons.link_off_rounded,
          title: 'Child Record Not Linked',
          message:
              'No student profile is linked to this parent account yet. '
              'Leave records will appear once linked.',
        ),
      );
    }

    LeaveStore? leaveStore;
    try {
      leaveStore = Provider.of<LeaveStore>(context, listen: true);
    } catch (_) {
      leaveStore = null;
    }

    final childLeaves = _resolvedStudentId.isNotEmpty
        ? (leaveStore?.requestsForStudent(_resolvedStudentId) ?? [])
        : <LeaveRequest>[];

    final pendingCount =
        childLeaves.where((r) => r.status == LeaveStatus.pending).length;
    final approvedCount =
        childLeaves.where((r) => r.status == LeaveStatus.approved).length;
    final rejectedCount =
        childLeaves.where((r) => r.status == LeaveStatus.rejected).length;

    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Child\'s Leave Applications (Read-Only)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    radius: 5,
                  ),
                  label: Text('Pending: $pendingCount'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.green,
                    radius: 5,
                  ),
                  label: Text('Approved: $approvedCount'),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: const CircleAvatar(
                    backgroundColor: Colors.red,
                    radius: 5,
                  ),
                  label: Text('Rejected: $rejectedCount'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (childLeaves.isEmpty)
              const PortalEmptyStateCard(
                icon: Icons.event_available_rounded,
                title: 'No Leave Requests',
                message: 'No leave applications have been submitted yet.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: childLeaves.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (ctx, index) {
                  return PortalLeaveRequestCard(item: childLeaves[index]);
                },
              ),
          ],
        ),
      ),
    );
  }
}
