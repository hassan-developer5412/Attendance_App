import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/config/supabase_config.dart';
import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/services/sync_service.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/attendance_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/classes_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/dashboard_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/lab_inventory_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/leave_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/reports_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/settings_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/students_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/teachers_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/timetable_content.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/sync_status_pill.dart';
import 'package:attendance_app/features/parent_view/presentation/parent_view_content.dart';
import 'package:attendance_app/features/rbac/presentation/role_management_screen.dart';
import 'package:attendance_app/features/student_view/presentation/student_self_view_content.dart';
import 'package:attendance_app/features/users/presentation/user_management_content.dart';

/// Responsive dashboard shell with permission-driven navigation and role-aware routing.
/// Visible navigation items are derived purely from [RBACStore.hasPermission].
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  /// Returns the permitted menu IDs for a given role according to RBAC layout policies.
  /// Retained for backward compatibility and test access.
  static List<String> getMenuIdsForRole(UserRole role) {
    if (role == UserRole.student) {
      return const ['schedule', 'my_attendance'];
    }
    if (role == UserRole.teacher) {
      return const [
        'dashboard',
        'attendance',
        'timetable',
        'classes',
        'students',
        'leave',
      ];
    }
    if (role == UserRole.hod) {
      return const [
        'dashboard',
        'attendance',
        'timetable',
        'classes',
        'teachers',
        'students',
        'user_management',
        'leave',
        'reports',
        'lab_inventory',
      ];
    }
    return const [
      'dashboard',
      'attendance',
      'timetable',
      'classes',
      'teachers',
      'students',
      'user_management',
      'leave',
      'reports',
      'institute',
      'settings',
      'lab_inventory',
    ];
  }

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  static const double _kBreakpoint = 768;
  static const double _kSidebarWidth = 270;

  /// Staff dashboard permissions that distinguish administrative operations from student/parent self-service.
  static const List<String> _staffDashboardPermissions = [
    PermissionCodes.attendanceMark,
    PermissionCodes.attendanceEdit,
    PermissionCodes.attendanceDelete,
    PermissionCodes.studentView,
    PermissionCodes.studentCreate,
    PermissionCodes.studentEdit,
    PermissionCodes.studentDelete,
    PermissionCodes.teacherView,
    PermissionCodes.teacherCreate,
    PermissionCodes.teacherEdit,
    PermissionCodes.teacherDelete,
    PermissionCodes.classManage,
    PermissionCodes.userView,
    PermissionCodes.userCreate,
    PermissionCodes.userEdit,
    PermissionCodes.userDelete,
    PermissionCodes.userManageRoles,
    PermissionCodes.reportView,
    PermissionCodes.settingManage,
    PermissionCodes.labView,
    PermissionCodes.labManage,
    PermissionCodes.leaveApprove,
    PermissionCodes.feeView,
    PermissionCodes.feeManage,
    PermissionCodes.timetableManage,
    PermissionCodes.noticeManage,
  ];

  int _selectedIndex = 0;
  String? _preselectedClassId;
  String? _preselectedSubjectId;
  int? _preselectedPeriodSlot;

  bool _holdsStudentRole(AuthStore authStore, RBACStore rbacStore) {
    return authStore.currentUserRole == UserRole.student ||
        rbacStore.currentUserRoles.any((r) => r.code == 'student');
  }

  bool _holdsParentRole(AuthStore authStore, RBACStore rbacStore) {
    return authStore.currentUserRole == UserRole.parent ||
        rbacStore.currentUserRoles.any((r) => r.code == 'parent');
  }

  bool _hasStaffDashboardPermissions(RBACStore rbacStore) {
    return rbacStore.hasAnyPermission(_staffDashboardPermissions);
  }

  void _navigateToAttendance({
    required String classId,
    required String subjectId,
    int? periodSlot,
  }) {
    final rbacStore = context.read<RBACStore>();
    final activeItems = _getActiveItems(rbacStore);
    final idx = activeItems.indexWhere((item) => item.id == 'attendance');
    if (idx != -1) {
      setState(() {
        _preselectedClassId = classId;
        _preselectedSubjectId = subjectId;
        _preselectedPeriodSlot = periodSlot;
        _selectedIndex = idx;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Runs SyncService in the background without blocking the UI
    if (SupabaseConfig.isReady) {
      unawaited(SyncService.instance.pullAll().catchError((e) {
        debugPrint('DashboardShell background sync failed: $e');
      }));
    }
  }

  /// Master catalogue of navigation items, each guarded by RBAC permissions.
  List<_MenuItem> _getAllMenuItems() {
    return [
      _MenuItem(
        id: 'dashboard',
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        permission: PermissionCodes.dashboardView,
        builder: () => DashboardContent(
          onNavigateToAttendance: _navigateToAttendance,
        ),
      ),
      _MenuItem(
        id: 'attendance',
        icon: Icons.fingerprint_rounded,
        label: 'Attendance',
        permission: PermissionCodes.attendanceView,
        builder: () => AttendanceContent(
          initialClassId: _preselectedClassId,
          initialSubjectId: _preselectedSubjectId,
          initialPeriodSlot: _preselectedPeriodSlot,
        ),
      ),
      _MenuItem(
        id: 'timetable',
        icon: Icons.calendar_month_rounded,
        label: 'Timetable',
        permission: PermissionCodes.timetableView,
        builder: () => const TimetableContent(),
      ),
      _MenuItem(
        id: 'classes',
        icon: Icons.class_rounded,
        label: 'Classes',
        permission: PermissionCodes.classManage,
        builder: () => const ClassesContent(),
      ),
      _MenuItem(
        id: 'teachers',
        icon: Icons.school_rounded,
        label: 'Teachers',
        permission: PermissionCodes.teacherView,
        builder: () => const TeachersContent(),
      ),
      _MenuItem(
        id: 'students',
        icon: Icons.groups_rounded,
        label: 'Students',
        permission: PermissionCodes.studentView,
        builder: () => const StudentsContent(),
      ),
      _MenuItem(
        id: 'user_management',
        icon: Icons.manage_accounts_rounded,
        label: 'User & Staff Management',
        permissionCheck: (rbac) =>
            rbac.hasPermission(PermissionCodes.userView) ||
            rbac.hasPermission(PermissionCodes.userCreate),
        builder: () => const UserManagementContent(),
      ),
      _MenuItem(
        id: 'role_management',
        icon: Icons.admin_panel_settings_rounded,
        label: 'Role Permissions',
        permission: PermissionCodes.userManageRoles,
        builder: () => const RoleManagementScreen(),
      ),
      _MenuItem(
        id: 'leave',
        icon: Icons.event_busy_rounded,
        label: 'Leave Management',
        permission: PermissionCodes.leaveView,
        builder: () => const LeaveContent(),
      ),
      _MenuItem(
        id: 'reports',
        icon: Icons.bar_chart_rounded,
        label: 'Reports',
        permission: PermissionCodes.reportView,
        builder: () => const ReportsContent(),
      ),
      _MenuItem(
        id: 'settings',
        icon: Icons.settings_rounded,
        label: 'Settings',
        permission: PermissionCodes.settingManage,
        builder: () => const SettingsContent(),
      ),
      _MenuItem(
        id: 'lab_inventory',
        icon: Icons.inventory_2_rounded,
        label: 'Lab Inventory',
        permission: PermissionCodes.labView,
        builder: () => const LabInventoryContent(),
      ),
    ];
  }

  /// Visible navigation items derived purely from RBAC permissions.
  List<_MenuItem> _getActiveItems(RBACStore rbacStore) {
    if (!rbacStore.isAuthenticated) {
      return const [];
    }
    return _getAllMenuItems().where((item) => item.isPermitted(rbacStore)).toList();
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
        await context
            .read<AuthStore>()
            .logout()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Logout failed in DashboardShell: $e');
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildNoModulesView(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_person_rounded,
              size: 56,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Accessible Modules',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your account does not have permission to access any administrative modules.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Sidebar content (shared between permanent sidebar and Drawer)
  // -----------------------------------------------------------------------
  Widget _buildSidebarContent({
    required bool isDrawer,
    required List<_MenuItem> items,
    required int safeIndex,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStore = context.watch<AuthStore>();
    final rbacStore = context.watch<RBACStore>();
    final displayName = authStore.currentUser?.displayName ?? 'User';
    final roleName = rbacStore.currentUserRoles.isNotEmpty
        ? rbacStore.currentUserRoles.first.name
        : (authStore.currentUser?.role.name ?? 'user');

    return Column(
      children: [
        // Brand Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'School & Institute',
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
        const Divider(height: 1),

        // User Profile Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primary,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      roleName.toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Menu Items
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No accessible modules',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = safeIndex == index;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                              if (items[index].id != 'attendance') {
                                _preselectedClassId = null;
                                _preselectedSubjectId = null;
                                _preselectedPeriodSlot = null;
                              }
                            });
                            if (isDrawer) Navigator.of(context).pop();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: 22,
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Logout Button
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: Icon(Icons.logout_rounded, size: 20, color: colorScheme.error),
              label: Text(
                'Logout',
                style: TextStyle(color: colorScheme.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authStore = context.watch<AuthStore>();
    final rbacStore = context.watch<RBACStore>();

    // Direct routing for authenticated users holding student or parent roles without staff permissions.
    final holdsStudent = _holdsStudentRole(authStore, rbacStore);
    final holdsParent = _holdsParentRole(authStore, rbacStore);

    if ((holdsStudent || holdsParent) && !_hasStaffDashboardPermissions(rbacStore)) {
      if (holdsParent) {
        return const ParentViewContent();
      }
      return const StudentSelfViewContent();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeItems = _getActiveItems(rbacStore);
    final safeIndex = activeItems.isEmpty
        ? 0
        : _selectedIndex.clamp(0, activeItems.length - 1);

    final currentItem = activeItems.isNotEmpty ? activeItems[safeIndex] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kBreakpoint;

        if (isWide) {
          // Desktop / Tablet layout
          return Scaffold(
            body: Row(
              children: [
                // Permanent Sidebar
                Container(
                  width: _kSidebarWidth,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      right: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    child: _buildSidebarContent(
                      isDrawer: false,
                      items: activeItems,
                      safeIndex: safeIndex,
                    ),
                  ),
                ),
                // Main Content Area
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(
                        currentItem?.label ?? 'Dashboard',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      centerTitle: false,
                      elevation: 0,
                      scrolledUnderElevation: 1,
                      actions: const [SyncStatusPill()],
                    ),
                    body: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: KeyedSubtree(
                        key: ValueKey(
                          '${currentItem?.id ?? 'default'}_${_preselectedClassId ?? ''}_${_preselectedSubjectId ?? ''}',
                        ),
                        child: currentItem != null
                            ? currentItem.builder()
                            : _buildNoModulesView(theme, colorScheme),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Mobile drawer layout
        return Scaffold(
          appBar: AppBar(
            title: Text(
              currentItem?.label ?? 'Dashboard',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
            actions: const [SyncStatusPill()],
          ),
          drawer: SizedBox(
            width: _kSidebarWidth,
            child: Drawer(
              child: SafeArea(
                child: _buildSidebarContent(
                  isDrawer: true,
                  items: activeItems,
                  safeIndex: safeIndex,
                ),
              ),
            ),
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(
                '${currentItem?.id ?? 'default'}_${_preselectedClassId ?? ''}_${_preselectedSubjectId ?? ''}',
              ),
              child: currentItem != null
                  ? currentItem.builder()
                  : _buildNoModulesView(theme, colorScheme),
            ),
          ),
        );
      },
    );
  }
}

/// Menu item descriptor with dynamic widget builder and RBAC permission checks.
class _MenuItem {
  const _MenuItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.builder,
    this.permission,
    this.permissionCheck,
  });

  final String id;
  final IconData icon;
  final String label;
  final Widget Function() builder;
  final String? permission;
  final bool Function(RBACStore rbacStore)? permissionCheck;

  bool isPermitted(RBACStore rbacStore) {
    if (permissionCheck != null) {
      return permissionCheck!(rbacStore);
    }
    if (permission != null) {
      return rbacStore.hasPermission(permission!);
    }
    return true;
  }
}
