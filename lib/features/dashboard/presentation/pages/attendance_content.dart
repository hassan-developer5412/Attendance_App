import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/attendance_record.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Attendance page that loads real records from the database.
///
/// Allows the admin to view and mark attendance for each student on a
/// selected date.
class AttendanceContent extends StatefulWidget {
  const AttendanceContent({super.key});

  @override
  State<AttendanceContent> createState() => _AttendanceContentState();
}

class _AttendanceContentState extends State<AttendanceContent> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Load attendance for today after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await context.read<AttendanceStore>().loadForDate(_selectedDate);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  Future<void> _markAttendance(int studentId, AttendanceStatus status) async {
    final store = context.read<AttendanceStore>();
    DateTime? checkIn;
    if (status == AttendanceStatus.present || status == AttendanceStatus.late) {
      checkIn = DateTime.now();
    }
    await store.markAttendance(
      studentId: studentId,
      date: _selectedDate,
      status: status,
      checkInTime: checkIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final attendanceStore = context.watch<AttendanceStore>();
    final records = attendanceStore.records;

    // Build a map from studentId -> AttendanceRecord for quick lookup.
    final Map<int, AttendanceRecord> recordMap = {
      for (final r in records) r.studentId: r,
    };

    final students = store.students;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Attendance',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Mark and view daily student attendance',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Date Picker
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('EEEE, d MMMM yyyy').format(_selectedDate),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_drop_down_rounded, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Summary Row
            if (records.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _statusChip('Present', records.where((r) => r.status == AttendanceStatus.present).length, Colors.green),
                    _statusChip('Late', records.where((r) => r.status == AttendanceStatus.late).length, Colors.orange),
                    _statusChip('Absent', records.where((r) => r.status == AttendanceStatus.absent).length, Colors.red),
                    _statusChip('Leave', records.where((r) => r.status == AttendanceStatus.leave).length, Colors.blue),
                  ],
                ),
              ),

            // Student List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : students.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_outline_rounded, size: 48, color: colorScheme.onSurfaceVariant),
                              const SizedBox(height: 12),
                              Text(
                                'No students enrolled',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add students in the Students page first.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: students.length,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemBuilder: (ctx, index) {
                            final student = students[index];
                            final record = recordMap[student.id];
                            final status = record?.status;
                            final checkIn = record?.checkInTime;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: colorScheme.primaryContainer,
                                      child: Text(
                                        student.initials,
                                        style: TextStyle(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            student.name,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${student.rollNumber} • ${store.classLabel(student.classId)}',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          if (checkIn != null)
                                            Text(
                                              'In: ${DateFormat('hh:mm a').format(checkIn)}',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Status chip
                                    if (status != null) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          status.label,
                                          style: TextStyle(
                                            color: _statusColor(status),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    // Mark attendance dropdown
                                    PopupMenuButton<AttendanceStatus>(
                                      tooltip: 'Mark attendance',
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      onSelected: (newStatus) =>
                                          _markAttendance(student.id, newStatus),
                                      itemBuilder: (_) => AttendanceStatus.values
                                          .map(
                                            (s) => PopupMenuItem(
                                              value: s,
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    _statusIcon(s),
                                                    size: 18,
                                                    color: _statusColor(s),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(s.label),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
        child: null,
      ),
      label: Text('$label: $count'),
      visualDensity: VisualDensity.compact,
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
