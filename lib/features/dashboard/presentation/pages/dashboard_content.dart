import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Dashboard overview page driven entirely by real database data and academic hierarchy stats.
class DashboardContent extends StatefulWidget {
  const DashboardContent({super.key});

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDashboardData());
  }

  Future<void> _loadDashboardData() async {
    final store = context.read<AttendanceStore>();
    final late = await store.todayLateCount();
    final overview = await store.todayOverview();
    final weekly = await store.weeklyStats();
    final dist = await store.monthlyDistribution();
    final recent = await store.recentActivity();

    if (!mounted) return;
    setState(() {
      _lateCount = late;
      _todayOverview = overview;
      _weeklyStats = weekly;
      _distribution = dist;
      _recentActivity = recent;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final currentSession = store.currentAcademicSession;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
            ],
          ),
        ),
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
