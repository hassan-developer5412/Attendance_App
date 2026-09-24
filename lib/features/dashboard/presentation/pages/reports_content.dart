import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/state/attendance_store.dart';

/// Reports & analytics page driven by real database queries.
class ReportsContent extends StatefulWidget {
  const ReportsContent({super.key});

  @override
  State<ReportsContent> createState() => _ReportsContentState();
}

class _ReportsContentState extends State<ReportsContent> {
  List<Map<String, dynamic>> _monthlyTrend = [];
  List<Map<String, dynamic>> _classComparison = [];
  List<Map<String, dynamic>> _topAttenders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReports());
  }

  Future<void> _loadReports() async {
    final store = context.read<AttendanceStore>();
    final trend = await store.monthlyTrend();
    final comparison = await store.classComparison();
    final top = await store.topAttenders();

    if (!mounted) return;
    setState(() {
      _monthlyTrend = trend;
      _classComparison = comparison;
      _topAttenders = top;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadReports,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reports & Analytics',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Insights from real attendance data',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Monthly Trend Line Chart
              _sectionTitle('Monthly Attendance Trend'),
              const SizedBox(height: 12),
              _buildMonthlyTrendChart(colorScheme),
              const SizedBox(height: 28),

              // Class Comparison Bar Chart
              _sectionTitle('Attendance by Class'),
              const SizedBox(height: 12),
              _buildClassComparisonChart(colorScheme),
              const SizedBox(height: 28),

              // Top Attenders Table
              _sectionTitle('Top Attenders This Month'),
              const SizedBox(height: 12),
              _buildTopAttendersTable(theme, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildMonthlyTrendChart(ColorScheme colorScheme) {
    if (_monthlyTrend.isEmpty || _monthlyTrend.every((m) => (m['rate'] as double) == 0)) {
      return _emptyPlaceholder('No attendance data for the trend chart');
    }

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                _monthlyTrend.length,
                (i) => FlSpot(i.toDouble(), (_monthlyTrend[i]['rate'] as double)),
              ),
              isCurved: true,
              color: colorScheme.primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: colorScheme.primary.withValues(alpha: 0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _monthlyTrend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _monthlyTrend[idx]['month'] as String,
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) {
                  if (value % 25 != 0) return const SizedBox.shrink();
                  return Text(
                    '${value.toInt()}%',
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassComparisonChart(ColorScheme colorScheme) {
    if (_classComparison.isEmpty) {
      return _emptyPlaceholder('No class data available');
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 100,
          barGroups: List.generate(_classComparison.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (_classComparison[i]['rate'] as double),
                  color: colorScheme.primary,
                  width: 22,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
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
                  if (idx < 0 || idx >= _classComparison.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _classComparison[idx]['className'] as String,
                      style: const TextStyle(fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) {
                  if (value % 25 != 0) return const SizedBox.shrink();
                  return Text('${value.toInt()}%', style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (value) => FlLine(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopAttendersTable(ThemeData theme, ColorScheme colorScheme) {
    if (_topAttenders.isEmpty) {
      return _emptyPlaceholder('No student attendance data yet');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columnSpacing: 16,
          columns: const [
            DataColumn(label: Text('Student')),
            DataColumn(label: Text('Class')),
            DataColumn(label: Text('Rate'), numeric: true),
            DataColumn(label: Text('On-Time'), numeric: true),
          ],
          rows: _topAttenders.map((a) {
            return DataRow(cells: [
              DataCell(Text(
                a['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(a['className'] as String)),
              DataCell(Text('${a['rate']}%')),
              DataCell(Text('${a['onTimeRate']}%')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _emptyPlaceholder(String message) {
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
}
