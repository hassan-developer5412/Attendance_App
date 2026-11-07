import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/repositories/student_repository.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/widgets/themed_dropdown.dart';

/// Restricted Self-View content for students.
/// Strictly displays their own class schedule and personal attendance records.
class StudentSelfViewContent extends StatefulWidget {
  final int initialTab;

  const StudentSelfViewContent({
    super.key,
    this.initialTab = 0,
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
  List<Map<String, dynamic>> _subjectSummaries = [];
  List<Map<String, dynamic>> _detailedLogs = [];
  String? _selectedSubjectFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStudentData());
  }

  @override
  void didUpdateWidget(covariant StudentSelfViewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabController.animateTo(widget.initialTab.clamp(0, 1));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentData() async {
    setState(() => _isLoading = true);

    final authStore = context.read<AuthStore>();
    final instituteStore = context.read<InstituteStore>();
    final attendanceStore = context.read<AttendanceStore>();

    final user = authStore.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Look up student by roll_no or username
    final studentRepo = StudentRepository();
    final lookupRoll = user.rollNo ?? user.username;
    Student? student = await studentRepo.getByRollNumber(lookupRoll);

    // If not found by roll number, try searching by user ID or name in loaded students
    if (student == null) {
      final match = instituteStore.students.where((s) =>
          s.rollNumber.toLowerCase() == lookupRoll.toLowerCase() ||
          s.name.toLowerCase() == user.displayName.toLowerCase());
      if (match.isNotEmpty) {
        student = match.first;
      }
    }

    if (student != null) {
      _student = student;
      _studentClass = instituteStore.classById(student.classId);
      _department = instituteStore.departmentById(student.departmentId);

      _enrolledSubjects = instituteStore.subjectsForClassAndYear(
        student.classId,
        student.currentYear,
      );
      if (_enrolledSubjects.isEmpty) {
        _enrolledSubjects = instituteStore.subjectsForClass(student.classId);
      }

      // Load attendance summaries & detailed logs
      _subjectSummaries =
          await attendanceStore.getStudentAttendanceBySubject(student.id);
      _detailedLogs =
          await attendanceStore.getDetailedAttendanceForStudent(student.id);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStore = context.watch<AuthStore>();
    final user = authStore.currentUser;

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading student academic record...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Student Profile Header Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      (user?.displayName.isNotEmpty == true
                              ? user!.displayName[0]
                              : 'S')
                          .toUpperCase(),
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
                            Text(
                              user?.displayName ?? 'Student',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'STUDENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          children: [
                            Text(
                              'Roll: ${user?.rollNo ?? _student?.rollNumber ?? 'N/A'}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            if (_studentClass != null)
                              Text(
                                'Class: ${_studentClass!.displayName}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (_department != null)
                              Text(
                                'Dept: ${_department!.code}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (_studentClass?.room.isNotEmpty == true)
                              Text(
                                'Room: ${_studentClass!.room}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.schedule_rounded),
                    text: 'Class Schedule & Subjects',
                  ),
                  Tab(
                    icon: Icon(Icons.fact_check_rounded),
                    text: 'My Attendance Record',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildScheduleTab(theme, colorScheme),
              _buildAttendanceTab(theme, colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Class Schedule & Subjects
  // ---------------------------------------------------------------------------

  Widget _buildScheduleTab(ThemeData theme, ColorScheme colorScheme) {
    if (_enrolledSubjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 56, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No subjects scheduled yet for this class.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your department administration will assign subjects to this class roster.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enrolled Course Modules (${_enrolledSubjects.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_studentClass != null)
                Chip(
                  label: Text(
                    'Year: ${_student?.currentYear ?? _studentClass!.currentYear}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _enrolledSubjects.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final sub = _enrolledSubjects[index];

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          sub.subjectType == SubjectType.practical
                              ? Icons.science_rounded
                              : Icons.book_rounded,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    sub.name,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    sub.code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_outline_rounded,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      sub.teacherName.isNotEmpty
                                          ? sub.teacherName
                                          : 'Instructor Assigned',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.category_outlined,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      sub.subjectType.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time_rounded,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${sub.contactHoursPerWeek.toStringAsFixed(1)} hrs/wk',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
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
  // Tab 2: My Attendance Record
  // ---------------------------------------------------------------------------

  Widget _buildAttendanceTab(ThemeData theme, ColorScheme colorScheme) {
    int totalHeld = 0;
    int totalAttended = 0;
    int totalPresent = 0;
    int totalLate = 0;
    int totalAbsent = 0;
    int totalLeave = 0;

    for (final s in _subjectSummaries) {
      totalHeld += (s['totalSessions'] as int?) ?? 0;
      totalAttended += (s['attendedCount'] as int?) ?? 0;
      totalPresent += (s['presentCount'] as int?) ?? 0;
      totalLate += (s['lateCount'] as int?) ?? 0;
      totalAbsent += (s['absentCount'] as int?) ?? 0;
      totalLeave += (s['leaveCount'] as int?) ?? 0;
    }

    final double overallRate =
        totalHeld > 0 ? (totalAttended / totalHeld * 100) : 100.0;
    final bool isShortage = totalHeld > 0 && overallRate < 75.0;

    final filteredLogs = _selectedSubjectFilter == null
        ? _detailedLogs
        : _detailedLogs
            .where((l) => l['subject_id'] == _selectedSubjectFilter)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Attendance Rate Overview Banner
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: isShortage
                    ? Colors.red.withValues(alpha: 0.5)
                    : Colors.green.withValues(alpha: 0.5),
              ),
            ),
            color: isShortage
                ? Colors.red.withValues(alpha: 0.05)
                : Colors.green.withValues(alpha: 0.05),
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isShortage
                                ? '⚠️ Shortage Warning: Minimum 75% required for examination eligibility'
                                : '✅ Satisfactory: Eligible for examination appearance',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isShortage
                                  ? Colors.red.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isShortage ? Colors.red : Colors.green)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${overallRate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isShortage
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (overallRate / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: colorScheme.outlineVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isShortage ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem('Total Sessions', totalHeld.toString(),
                          colorScheme.primary),
                      _statItem('Present', totalPresent.toString(), Colors.green),
                      _statItem('Late', totalLate.toString(), Colors.orange),
                      _statItem('Absent', totalAbsent.toString(), Colors.red),
                      _statItem('Leave', totalLeave.toString(), Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Subject-wise Breakdown
          Text(
            'Subject Attendance Breakdown',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (_subjectSummaries.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No subject attendance recorded yet.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _subjectSummaries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = _subjectSummaries[index];
                final rate = (item['attendanceRate'] as num?)?.toDouble() ?? 0.0;
                final attended = item['attendedCount'] ?? 0;
                final total = item['totalSessions'] ?? 0;
                final subShortage = total > 0 && rate < 75.0;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['subjectName']} (${item['subjectCode']})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$attended of $total sessions attended • P:${item['presentCount']} L:${item['lateCount']} A:${item['absentCount']} LV:${item['leaveCount']}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (subShortage ? Colors.red : Colors.green)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '${rate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: subShortage
                                  ? Colors.red.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 20),

          // Daily Attendance History Log
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Attendance Activity',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_enrolledSubjects.isNotEmpty)
                SizedBox(
                  width: 180,
                  child: AppDropdownButtonFormField<String?>(
                    initialValue: _selectedSubjectFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Subjects', style: TextStyle(fontSize: 12)),
                      ),
                      ..._enrolledSubjects.map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.code,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedSubjectFilter = val),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (filteredLogs.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No attendance logs recorded for the selected filter.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredLogs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final log = filteredLogs[index];
                final dateStr = log['date'] as String? ?? '';
                final parsedDate = DateTime.tryParse(dateStr);
                final formattedDate = parsedDate != null
                    ? DateFormat('EEE, d MMM yyyy').format(parsedDate)
                    : dateStr;
                final statusStr = log['status'] as String? ?? 'present';
                final status = AttendanceStatus.fromString(statusStr);
                final subjectName = log['subject_name'] ?? log['subject_code'] ?? 'Class Gathering';
                final remarks = log['session_remarks'] as String? ?? '';

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.event_available_rounded,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subjectName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                formattedDate +
                                    (remarks.isNotEmpty ? ' • $remarks' : ''),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusChip(status),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _statusChip(AttendanceStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case AttendanceStatus.present:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = 'Present';
        break;
      case AttendanceStatus.late:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'Late';
        break;
      case AttendanceStatus.absent:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        label = 'Absent';
        break;
      case AttendanceStatus.leave:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        label = 'Leave';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}
