import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Dashboard overview page driven entirely by real database data.
class DashboardContent extends StatefulWidget {
  const DashboardContent({super.key});

  @override
  State<DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<DashboardContent> {
  // Async computed dashboard data.
  int _lateCount = 0;
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
    final weekly = await store.weeklyStats();
    final dist = await store.monthlyDistribution();
    final recent = await store.recentActivity();

    if (!mounted) return;
    setState(() {
      _lateCount = late;
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

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Today's summary
              Text(
                'Today\'s Overview',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Stat Cards
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
                    label: 'Total Teachers',
                    value: '${store.teacherCount}',
                    color: Colors.teal,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.class_rounded,
                    label: 'Total Classes',
                    value: '${store.classCount}',
                    color: Colors.deepPurple,
                    theme: theme,
                  ),
                  _buildStatCard(
                    icon: Icons.schedule_rounded,
                    label: 'Late Today',
                    value: '$_lateCount',
                    color: Colors.orange,
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
    required Color color,
    required ThemeData theme,
  }) {
    return SizedBox(
      width: 170,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
                BarChartRodData(toY: present, color: Colors.green, width: 14, borderRadius: BorderRadius.circular(4)),
                BarChartRodData(toY: absent, color: Colors.red.shade300, width: 14, borderRadius: BorderRadius.circular(4)),
              ],
            );
          }),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
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
      height: 200,
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
                        title: '${(e.value / total * 100).round()}%',
                        color: colorMap[e.key] ?? Colors.grey,
                        radius: 42,
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
            backgroundColor: _statusColor(record.status).withValues(alpha: 0.15),
            child: Icon(
              _statusIcon(record.status),
              size: 18,
              color: _statusColor(record.status),
            ),
          ),
          title: Text(
            record.studentName ?? 'Student #${record.studentId}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
