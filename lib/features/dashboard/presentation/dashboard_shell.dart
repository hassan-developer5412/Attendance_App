import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/features/auth/presentation/login_screen.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/attendance_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/dashboard_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/classes_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/leave_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/reports_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/settings_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/students_content.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/teachers_content.dart';

/// Responsive dashboard shell with a left-side navigation menu and a
/// right-side content area. On screens wider than [_kBreakpoint], the
/// sidebar is permanently visible. On narrower screens it collapses to
/// a hamburger-opened [Drawer].
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  static const double _kBreakpoint = 768;
  static const double _kSidebarWidth = 270;

  int _selectedIndex = 0;

  // Menu definitions
  static const _menuItems = <_MenuItem>[
    _MenuItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _MenuItem(icon: Icons.fingerprint_rounded, label: 'Attendance'),
    _MenuItem(icon: Icons.class_rounded, label: 'Classes'),
    _MenuItem(icon: Icons.school_rounded, label: 'Teachers'),
    _MenuItem(icon: Icons.groups_rounded, label: 'Students'),
    _MenuItem(icon: Icons.event_busy_rounded, label: 'Leave Management'),
    _MenuItem(icon: Icons.bar_chart_rounded, label: 'Reports'),
    _MenuItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardContent();
      case 1:
        return const AttendanceContent();
      case 2:
        return const ClassesContent();
      case 3:
        return const TeachersContent();
      case 4:
        return const StudentsContent();
      case 5:
        return const LeaveContent();
      case 6:
        return const ReportsContent();
      case 7:
        return const SettingsContent();
      default:
        return const DashboardContent();
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
      await context.read<AuthStore>().logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // -----------------------------------------------------------------------
  // Sidebar content (shared between permanent sidebar and Drawer)
  // -----------------------------------------------------------------------
  Widget _buildSidebarContent({required bool isDrawer}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStore = context.watch<AuthStore>();
    final displayName = authStore.currentUser?.displayName ?? 'User';
    final role = authStore.currentUser?.role.name ?? 'admin';

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
                      role[0].toUpperCase() + role.substring(1),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),

        // Menu Items
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            itemCount: _menuItems.length,
            itemBuilder: (context, index) {
              final item = _menuItems[index];
              final isSelected = _selectedIndex == index;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedIndex = index);
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
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kBreakpoint;

        if (isWide) {
          // ----- Desktop / Tablet: permanent sidebar -----
          return Scaffold(
            body: Row(
              children: [
                // Left Sidebar
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
                  child: SafeArea(child: _buildSidebarContent(isDrawer: false)),
                ),
                // Right Content
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(
                        _menuItems[_selectedIndex].label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      centerTitle: false,
                      elevation: 0,
                      scrolledUnderElevation: 1,
                    ),
                    body: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: KeyedSubtree(
                        key: ValueKey(_selectedIndex),
                        child: _buildPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ----- Mobile: hamburger drawer -----
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _menuItems[_selectedIndex].label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          drawer: SizedBox(
            width: _kSidebarWidth,
            child: Drawer(
              child: SafeArea(child: _buildSidebarContent(isDrawer: true)),
            ),
          ),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_selectedIndex),
              child: _buildPage(),
            ),
          ),
        );
      },
    );
  }
}

/// Simple data class for menu items.
class _MenuItem {
  const _MenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}
