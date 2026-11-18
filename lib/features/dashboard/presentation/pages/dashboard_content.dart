import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/notice_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/notice_form_dialog.dart';

/// Dashboard overview page driven entirely by real database data and academic hierarchy stats.
class DashboardContent extends StatefulWidget {
  const DashboardContent({
    super.key,
    this.onNavigateToAttendance,
  });

  final void Function({
    required String classId,
    required String subjectId,
    int? periodSlot,
  })? onNavigateToAttendance;

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  // Async computed dashboard data.
  int _lateCount = 0;
  Map<String, dynamic> _todayOverview = {};
  List<Map<String, int>> _weeklyStats = [];
  Map<AttendanceStatus, int> _distribution = {};
  List<AttendanceRecord> _recentActivity = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardData());
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final store = context.read<AttendanceStore>();

      // 2. Add 10-second timeout to database calls loading from SQLite immediately
      final late = await store
          .todayLateCount()
          .timeout(const Duration(seconds: 10));
      final overview = await store
          .todayOverview()
          .timeout(const Duration(seconds: 10));
      final weekly = await store
          .weeklyStats()
          .timeout(const Duration(seconds: 10));
      final dist = await store
          .monthlyDistribution()
          .timeout(const Duration(seconds: 10));
      final recent = await store
          .recentActivity()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _lateCount = late;
        _todayOverview = overview;
        _weeklyStats = weekly;
        _distribution = dist;
        _recentActivity = recent;
      });

      // 3. Run SyncService in the background without blocking the UI
      if (SupabaseConfig.isReady) {
        unawaited(SyncService.instance.pullAll().catchError((e) {
          debugPrint('DashboardContent background sync pull failed: $e');
        }));
      }
    } catch (e, stack) {
      debugPrint('DashboardContent._loadDashboardData error: $e\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load dashboard data: $e';
        });
      }
    } finally {
      // 1. isLoading is ALWAYS set to false in finally block
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final currentSession = store.currentAcademicSession;
    final authStore = context.watch<AuthStore>();
    final currentUser = authStore.currentUser;
    TimetableStore? timetableStore;
    try {
      timetableStore = Provider.of<TimetableStore>(context, listen: true);
    } catch (_) {
      timetableStore = null;
    }

    Teacher? currentTeacher;
    if (currentUser != null) {
      for (final t in store.teachers) {
        if (!t.isDeleted && t.isActive) {
          if (t.userId != null && t.userId == currentUser.id) {
            currentTeacher = t;
            break;
          }
        }
      }
    }
    final nextSlot = currentTeacher != null && timetableStore != null
        ? timetableStore.getCurrentOrNextSlotForTeacher(currentTeacher.id)
        : null;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 4. Showing an error message with a 'Retry' button if loading fails
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load dashboard',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadDashboardData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final todayTotal = (_todayOverview['total'] as int?) ?? 0;
    final todayPresent = (_todayOverview['present'] as int?) ?? 0;
    final todayRate = (_todayOverview['rate'] as num?)?.toDouble() ?? 0.0;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Academic Session & Institute Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.surfaceContainerHighest,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.primary,
                      child: const Icon(
                        Icons.account_balance_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Govt. Institute of Leather Technology (GILT)',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                currentSession != null
                                    ? 'Academic Session: ${currentSession.name} (Active)'
                                    : 'Academic Session: 2024-2027',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Teacher Next Class Banner
              if (currentTeacher != null && nextSlot != null) ...[
                _buildNextClassBanner(
                  context: context,
                  slot: nextSlot,
                  instituteStore: store,
                  theme: theme,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 18),
              ],

              // Today's summary label
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Overview',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: _loadDashboardData,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh data',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Comprehensive Stat Cards Grid
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildStatCard(
                    icon: Icons.groups_rounded,
                    label: 'Total Students',
                    value: '${store.studentCount}',
                    color: Colors.blue,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.school_rounded,
                    label: 'Faculty Members',
                    value: '${store.teacherCount}',
                    color: Colors.teal,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.apartment_rounded,
                    label: 'Active Departments',
                    value: '${store.activeDepartmentCount}',
                    color: Colors.indigo,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.class_rounded,
                    label: 'Registered Classes',
                    value: '${store.classCount}',
                    color: Colors.deepPurple,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.menu_book_rounded,
                    label: 'Total Subjects',
                    value: '${store.subjectCount}',
                    color: Colors.brown,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Today\'s Attendance',
                    value: todayTotal > 0
                        ? '${todayRate.toStringAsFixed(1)}%'
                        : '0%',
                    subtitle: todayTotal > 0
                        ? '$todayPresent of $todayTotal marked'
                        : 'No records today',
                    color: todayRate >= 75 ? Colors.green : Colors.orange,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.schedule_rounded,
                    label: 'Late Today',
                    value: '$_lateCount',
                    color: Colors.amber.shade800,
                    theme: theme,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Weekly Bar Chart
              Text(
                'Weekly Attendance',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildWeeklyChart(colorScheme),
              const SizedBox(height: 28),

              // Monthly Pie Chart
              Text(
                'Monthly Distribution',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildPieChart(theme, colorScheme),
              const SizedBox(height: 28),

              // Recent Activity
              Text(
                'Recent Activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildRecentActivity(theme, colorScheme),
              const SizedBox(height: 28),

              // Notice Board & Circulars
              _buildNoticeBoardSection(theme, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Notice Board Section
  // ---------------------------------------------------------------------------

  Widget _buildNoticeBoardSection(ThemeData theme, ColorScheme colorScheme) {
    AuthStore? authStore;
    try {
      authStore = Provider.of<AuthStore>(context, listen: false);
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Institute Notice Board & Circulars',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            PermissionGuard(
              permission: PermissionCodes.noticeManage,
              fallback: const SizedBox.shrink(),
              child: FilledButton.icon(
                onPressed: () => _onPublishNotice(authStore),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Publish Notice'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Notice list via Consumer
        Consumer<NoticeStore>(
          builder: (ctx, noticeStore, _) {
            final allNotices = noticeStore.notices;
            final pinned = allNotices.where((n) => n.isPinned).toList();
            final rest = allNotices.where((n) => !n.isPinned).toList();
            final display = [...pinned, ...rest].take(5).toList();

            if (display.isEmpty) {
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No notices published yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: display.map((notice) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildNoticeCard(
                      notice, theme, colorScheme, noticeStore, authStore),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoticeCard(
    Notice notice,
    ThemeData theme,
    ColorScheme colorScheme,
    NoticeStore noticeStore,
    AuthStore? authStore,
  ) {
    final canManage =
        authStore?.hasPermission(PermissionCodes.noticeManage) ?? false;
    final dateStr = DateFormat('d MMM yyyy').format(notice.createdAt.toLocal());
    final publisher = notice.publishedByName ?? 'Admin';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: notice.isPinned
              ? theme.colorScheme.primary.withValues(alpha: 0.4)
              : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showNoticeDetailDialog(context, notice, theme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pin icon
              if (notice.isPinned) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$publisher • $dateStr',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit notice',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _onEditNotice(notice, noticeStore, authStore),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Delete notice',
                  color: theme.colorScheme.error,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _onDeleteNotice(notice, noticeStore),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showNoticeDetailDialog(
      BuildContext context, Notice notice, ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
                const SizedBox(height: 8),
                Text(
                  'Published by ${notice.publishedByName ?? "Admin"} on '
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
        );
      },
    );
  }

  Future<void> _onPublishNotice(AuthStore? authStore) async {
    final result = await NoticeFormDialog.showPublishDialog(context);
    if (result == null || !mounted) return;

    final noticeStore = Provider.of<NoticeStore>(context, listen: false);
    final user = authStore?.currentUser;
    final store = Provider.of<InstituteStore>(context, listen: false);

    await noticeStore.addNotice(
      instituteId: SupabaseConfig.instituteId.isNotEmpty
          ? SupabaseConfig.instituteId
          : AppConstants.defaultInstituteId,
      title: result.title,
      body: result.body,
      publishedBy: user?.id ?? 'unknown',
      publishedByName: user?.displayName,
      targetRole: result.targetRole,
      departmentId: result.departmentId,
      attachmentUrl: result.attachmentUrl,
      isPinned: result.isPinned,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notice published successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // Silence unused variable warning.
    store;
  }

  Future<void> _onEditNotice(
      Notice notice, NoticeStore noticeStore, AuthStore? authStore) async {
    final result =
        await NoticeFormDialog.showPublishDialog(context, existing: notice);
    if (result == null || !mounted) return;

    final updated = notice.copyWith(
      title: result.title,
      body: result.body,
      targetRole: result.targetRole,
      departmentId: result.departmentId,
      attachmentUrl: result.attachmentUrl,
      isPinned: result.isPinned,
      updatedAt: DateTime.now().toUtc(),
    );

    await noticeStore.updateNotice(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notice updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onDeleteNotice(Notice notice, NoticeStore noticeStore) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notice'),
        content:
            Text('Are you sure you want to delete "${notice.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await noticeStore.deleteNotice(notice.id);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notice deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildNextClassBanner({
    required BuildContext context,
    required TimetableSlot slot,
    required InstituteStore instituteStore,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final classModel = instituteStore.classById(slot.classId);
    final className =
        classModel?.displayName ?? instituteStore.classLabel(slot.classId);
    final subject = instituteStore.subjectById(slot.subjectId);
    final subjectName = subject != null
        ? '${subject.name} (${subject.code})'
        : slot.subjectId;
    final badgeColor = slot.isLab ? colorScheme.tertiary : colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;

          final contentColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: badgeColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      slot.isLab ? 'LAB SESSION' : 'THEORY CLASS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Period ${slot.periodSlot}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Your next class is $className — ${slot.roomName} at ${slot.formattedStartTime}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subjectName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

          final markAttendanceBtn = FilledButton.icon(
            key: const ValueKey('banner_mark_attendance_button'),
            onPressed: () {
              widget.onNavigateToAttendance?.call(
                classId: slot.classId,
                subjectId: slot.subjectId,
                periodSlot: slot.periodSlot,
              );
            },
            icon: const Icon(Icons.fingerprint_rounded, size: 20),
            label: const Text('Mark Attendance'),
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.schedule_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: contentColumn),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: markAttendanceBtn,
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: contentColumn),
              const SizedBox(width: 16),
              markAttendanceBtn,
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    required Color color,
    required ThemeData theme,
  }) {
    return SizedBox(
      width: 165,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(ColorScheme colorScheme) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

    // Check if there's any data.
    final hasData = _weeklyStats.any(
      (s) => (s['present'] ?? 0) > 0 || (s['absent'] ?? 0) > 0,
    );

    if (!hasData) {
      return _emptyChartPlaceholder('No attendance data for this week');
    }

    double maxY = 0;
    for (final s in _weeklyStats) {
      final total = (s['present'] ?? 0) + (s['absent'] ?? 0);
      if (total > maxY) maxY = total.toDouble();
    }
    maxY = maxY == 0 ? 10 : (maxY * 1.2);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barGroups: List.generate(_weeklyStats.length, (i) {
            final present = (_weeklyStats[i]['present'] ?? 0).toDouble();
            final absent = (_weeklyStats[i]['absent'] ?? 0).toDouble();
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: present,
                  color: Colors.green,
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
                BarChartRodData(
                  toY: absent,
                  color: Colors.red.shade300,
                  width: 14,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= days.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(days[idx], style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
        ),
      ),
    );
  }

  Widget _buildPieChart(ThemeData theme, ColorScheme colorScheme) {
    final total = _distribution.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return _emptyChartPlaceholder('No attendance data for this month');
    }

    final colorMap = {
      AttendanceStatus.present: Colors.green,
      AttendanceStatus.late: Colors.orange,
      AttendanceStatus.absent: Colors.red,
      AttendanceStatus.leave: Colors.blue,
    };

    return SizedBox(
      height: 180,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: _distribution.entries
                    .where((e) => e.value > 0)
                    .map(
                      (e) => PieChartSectionData(
                        value: e.value.toDouble(),
                        title: '${(e.value / total * 100).toInt()}%',
                        color: colorMap[e.key],
                        radius: 40,
                        titleStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _distribution.entries
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorMap[e.key],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${e.key.label}: ${e.value}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(ThemeData theme, ColorScheme colorScheme) {
    if (_recentActivity.isEmpty) {
      return _emptyChartPlaceholder('No recent activity');
    }

    return Column(
      children: _recentActivity.map((record) {
        return ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor:
                _statusColor(record.status).withValues(alpha: 0.15),
            child: Icon(
              _statusIcon(record.status),
              size: 18,
              color: _statusColor(record.status),
            ),
          ),
          title: Text(
            record.studentName ?? 'Student #${record.studentId}',
            style:
                theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${record.status.label} on ${DateFormat('d MMM yyyy').format(record.date)}',
            style: theme.textTheme.bodySmall,
          ),
          dense: true,
        );
      }).toList(),
    );
  }

  Widget _emptyChartPlaceholder(String message) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static Color _statusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green;
      case AttendanceStatus.late:
        return Colors.orange;
      case AttendanceStatus.absent:
        return Colors.red;
      case AttendanceStatus.leave:
        return Colors.blue;
    }
  }

  static IconData _statusIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle_outline_rounded;
      case AttendanceStatus.late:
        return Icons.schedule_rounded;
      case AttendanceStatus.absent:
        return Icons.cancel_outlined;
      case AttendanceStatus.leave:
        return Icons.event_busy_outlined;
    }
  }
}
