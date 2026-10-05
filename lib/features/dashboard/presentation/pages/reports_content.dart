import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Comprehensive Reports page offering 4 distinct views:
/// 1. Student Report: Breakdown across all enrolled subjects
/// 2. Subject Report: Hierarchy-driven session logs and subject attendance rate
/// 3. Class/Year Report: Class-level breakdown across all subjects
/// 4. Trends & Charts: Monthly trend line chart, class bar comparison, and top attenders
class ReportsContent extends StatefulWidget {
  const ReportsContent({super.key});

  @override
  State<ReportsContent> createState() => _ReportsContentState();
}

class _ReportsContentState extends State<ReportsContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // General Analytics Data
  List<Map<String, dynamic>> _monthlyTrend = [];
  List<Map<String, dynamic>> _classComparison = [];
  List<Map<String, dynamic>> _topAttenders = [];
  bool _isLoadingAnalytics = true;

  // View 1: Student Report
  int? _selectedStudentId;
  List<Map<String, dynamic>> _studentSubjectRecords = [];
  bool _isLoadingStudentReport = false;

  // View 2: Subject Report
  String? _subjectReportDeptId;
  int? _subjectReportClassId;
  String _subjectReportYear = AcademicYears.firstYear;
  int? _subjectReportSubjectId;
  List<Map<String, dynamic>> _subjectSessionHistory = [];
  bool _isLoadingSubjectReport = false;

  // View 3: Class Report
  int? _classReportClassId;
  List<Map<String, dynamic>> _classSubjectSummary = [];
  bool _isLoadingClassReport = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadGeneralAnalytics();
      _initReportSelections();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initReportSelections() {
    final store = context.read<InstituteStore>();

    // Init Student
    if (store.students.isNotEmpty) {
      _selectedStudentId = store.students.first.id;
      _loadStudentReport(_selectedStudentId!);
    }

    // Init Subject Report Cascades
    if (store.activeDepartments.isNotEmpty) {
      _subjectReportDeptId = store.activeDepartments.first.id;
    }
    if (store.classes.isNotEmpty) {
      _subjectReportClassId = store.classes.first.id;
      _classReportClassId = store.classes.first.id;
      final classSubjects = store.subjectsForClass(_subjectReportClassId!);
      if (classSubjects.isNotEmpty) {
        _subjectReportSubjectId = classSubjects.first.id;
        _loadSubjectReport(_subjectReportSubjectId!);
      }
      _loadClassReport(_classReportClassId!);
    }
  }

  Future<void> _loadGeneralAnalytics() async {
    final store = context.read<AttendanceStore>();
    final trend = await store.monthlyTrend();
    final comparison = await store.classComparison();
    final top = await store.topAttenders();

    if (!mounted) return;
    setState(() {
      _monthlyTrend = trend;
      _classComparison = comparison;
      _topAttenders = top;
      _isLoadingAnalytics = false;
    });
  }

  Future<void> _loadStudentReport(int studentId) async {
    setState(() => _isLoadingStudentReport = true);
    final attendanceStore = context.read<AttendanceStore>();
    final data = await attendanceStore.getStudentAttendanceBySubject(studentId);
    if (!mounted) return;
    setState(() {
      _studentSubjectRecords = data;
      _isLoadingStudentReport = false;
    });
  }

  Future<void> _loadSubjectReport(int subjectId) async {
    setState(() => _isLoadingSubjectReport = true);
    final attendanceStore = context.read<AttendanceStore>();
    final history = await attendanceStore.getSubjectSessionHistory(subjectId);
    if (!mounted) return;
    setState(() {
      _subjectSessionHistory = history;
      _isLoadingSubjectReport = false;
    });
  }

  Future<void> _loadClassReport(int classId) async {
    setState(() => _isLoadingClassReport = true);
    final attendanceStore = context.read<AttendanceStore>();
    final summary =
        await attendanceStore.getSubjectAttendanceSummary(classId: classId);
    if (!mounted) return;
    setState(() {
      _classSubjectSummary = summary;
      _isLoadingClassReport = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reports & Analytics',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Academic attendance reports and institutional insights',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: const [
                    Tab(icon: Icon(Icons.person_outline), text: 'Student Report'),
                    Tab(icon: Icon(Icons.book_outlined), text: 'Subject Report'),
                    Tab(icon: Icon(Icons.class_outlined), text: 'Class Report'),
                    Tab(icon: Icon(Icons.analytics_outlined), text: 'Trends & Charts'),
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
                _buildStudentReportTab(theme, colorScheme),
                _buildSubjectReportTab(theme, colorScheme),
                _buildClassReportTab(theme, colorScheme),
                _buildTrendsTab(theme, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Student Report
  // ---------------------------------------------------------------------------

  Widget _buildStudentReportTab(ThemeData theme, ColorScheme colorScheme) {
    final instituteStore = context.watch<InstituteStore>();
    final students = instituteStore.students;

    if (students.isEmpty) {
      return _emptyPlaceholder('No students enrolled in the system');
    }

    final selectedStudent = students
        .where((s) => s.id == _selectedStudentId)
        .firstOrNull ??
        students.first;

    final studentClass = instituteStore.classById(selectedStudent.classId);
    final studentDept =
        instituteStore.departmentById(selectedStudent.departmentId ?? studentClass?.departmentId);

    // Compute student aggregate
    final totalSessions = _studentSubjectRecords.fold<int>(
        0, (sum, r) => sum + ((r['totalSessions'] as int?) ?? 0));
    final attendedSessions = _studentSubjectRecords.fold<int>(
        0, (sum, r) => sum + ((r['attendedCount'] as int?) ?? 0));
    final overallRate = totalSessions > 0
        ? (attendedSessions / totalSessions * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Selector & Info Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey('rep_stu_${selectedStudent.id}'),
                    initialValue: selectedStudent.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Select Student',
                      prefixIcon: Icon(Icons.person_search_rounded),
                      isDense: true,
                    ),
                    items: students
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.name} (${s.rollNumber}) — ${instituteStore.classLabel(s.classId)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedStudentId = val);
                        _loadStudentReport(val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Text(
                          selectedStudent.initials,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedStudent.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Roll: ${selectedStudent.rollNumber}${selectedStudent.registrationNo != null ? ' • Reg: ${selectedStudent.registrationNo}' : ''}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${studentClass?.displayName ?? 'Unassigned'} • Dept: ${studentDept?.code ?? 'General'} • Year: ${selectedStudent.currentYear}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Overall Rate Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: (overallRate >= 75
                                  ? Colors.green
                                  : (overallRate >= 50
                                      ? Colors.orange
                                      : Colors.red))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${overallRate.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: overallRate >= 75
                                    ? Colors.green.shade800
                                    : (overallRate >= 50
                                        ? Colors.orange.shade800
                                        : Colors.red.shade800),
                              ),
                            ),
                            const Text(
                              'Overall',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Subject Breakdown Table
          Text(
            'Enrolled Subjects Attendance Breakdown',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          if (_isLoadingStudentReport)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_studentSubjectRecords.isEmpty)
            _emptyPlaceholder('No attendance sessions recorded for this student.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingRowColor: WidgetStateProperty.all(
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  columns: const [
                    DataColumn(label: Text('Subject')),
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Total'), numeric: true),
                    DataColumn(label: Text('Attended'), numeric: true),
                    DataColumn(label: Text('Absent'), numeric: true),
                    DataColumn(label: Text('Leave'), numeric: true),
                    DataColumn(label: Text('Rate %'), numeric: true),
                  ],
                  rows: _studentSubjectRecords.map((r) {
                    final rate = (r['attendanceRate'] as num?)?.toDouble() ?? 0.0;
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          r['subjectName'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(r['subjectCode'] as String)),
                        DataCell(Text(r['subjectType'] as String? ?? 'THEORY')),
                        DataCell(Text('${r['totalSessions']}')),
                        DataCell(Text(
                          '${r['attendedCount']}',
                          style: const TextStyle(
                              color: Colors.green, fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(
                          '${r['absentCount']}',
                          style: TextStyle(
                            color: (r['absentCount'] as int? ?? 0) > 0
                                ? Colors.red
                                : null,
                          ),
                        )),
                        DataCell(Text('${r['leaveCount']}')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (rate >= 75
                                      ? Colors.green
                                      : (rate >= 50
                                          ? Colors.orange
                                          : Colors.red))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${rate.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: rate >= 75
                                    ? Colors.green.shade800
                                    : (rate >= 50
                                        ? Colors.orange.shade800
                                        : Colors.red.shade800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Subject Report
  // ---------------------------------------------------------------------------

  Widget _buildSubjectReportTab(ThemeData theme, ColorScheme colorScheme) {
    final instituteStore = context.watch<InstituteStore>();
    final departments = instituteStore.activeDepartments;
    final classes = instituteStore.classesForDepartment(_subjectReportDeptId);
    final subjects = _subjectReportClassId != null
        ? instituteStore.subjectsForClassAndYear(
            _subjectReportClassId!, _subjectReportYear)
        : <Subject>[];

    final currentSubject =
        instituteStore.subjectById(_subjectReportSubjectId);

    // Compute subject aggregates
    final totalSessions = _subjectSessionHistory.length;
    final totalRecords = _subjectSessionHistory.fold<int>(
        0, (sum, s) => sum + ((s['totalMarked'] as int?) ?? 0));
    final totalAttended = _subjectSessionHistory.fold<int>(
        0,
        (sum, s) =>
            sum +
            ((s['presentCount'] as int?) ?? 0) +
            ((s['lateCount'] as int?) ?? 0));
    final overallSubjectRate =
        totalRecords > 0 ? (totalAttended / totalRecords * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cascading filter card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('rep_dept_$_subjectReportDeptId'),
                          initialValue: _subjectReportDeptId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            prefixIcon: Icon(Icons.apartment_rounded),
                            isDense: true,
                          ),
                          items: departments
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${d.code} — ${d.name}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _subjectReportDeptId = val;
                              final deptsCls = instituteStore
                                  .classesForDepartment(val);
                              if (deptsCls.isNotEmpty) {
                                _subjectReportClassId = deptsCls.first.id;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('rep_cls_$_subjectReportClassId'),
                          initialValue: _subjectReportClassId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                            prefixIcon: Icon(Icons.class_outlined),
                            isDense: true,
                          ),
                          items: classes
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    c.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _subjectReportClassId = val;
                              final clsSubs = instituteStore
                                  .subjectsForClass(val!);
                              if (clsSubs.isNotEmpty) {
                                _subjectReportSubjectId = clsSubs.first.id;
                                _loadSubjectReport(clsSubs.first.id);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('rep_yr_$_subjectReportYear'),
                          initialValue: _subjectReportYear,
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            prefixIcon: Icon(Icons.timeline_rounded),
                            isDense: true,
                          ),
                          items: AcademicYears.labels
                              .map(
                                (y) => DropdownMenuItem(
                                  value: y,
                                  child: Text(y),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _subjectReportYear = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('rep_sub_$_subjectReportSubjectId'),
                          initialValue: _subjectReportSubjectId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            prefixIcon: Icon(Icons.menu_book_rounded),
                            isDense: true,
                          ),
                          items: (subjects.isNotEmpty
                                  ? subjects
                                  : (_subjectReportClassId != null
                                      ? instituteStore.subjectsForClass(
                                          _subjectReportClassId!)
                                      : <Subject>[]))
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.name} (${s.code})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _subjectReportSubjectId = val);
                              _loadSubjectReport(val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (currentSubject != null) ...[
            // Subject KPI Cards
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _kpiCard(
                  icon: Icons.event_repeat_rounded,
                  title: 'Total Sessions',
                  value: '$totalSessions',
                  color: Colors.blue,
                  theme: theme,
                ),
                _kpiCard(
                  icon: Icons.people_outline_rounded,
                  title: 'Student Entries',
                  value: '$totalRecords',
                  color: Colors.deepPurple,
                  theme: theme,
                ),
                _kpiCard(
                  icon: Icons.percent_rounded,
                  title: 'Average Attendance',
                  value: '${overallSubjectRate.toStringAsFixed(1)}%',
                  color: overallSubjectRate >= 75 ? Colors.green : Colors.orange,
                  theme: theme,
                ),
                _kpiCard(
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Instructor',
                  value: currentSubject.teacherName,
                  color: Colors.teal,
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Sessions History Table
            Text(
              'Session Records Log',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            if (_isLoadingSubjectReport)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_subjectSessionHistory.isEmpty)
              _emptyPlaceholder('No attendance sessions logged for this subject.')
            else
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 18,
                    headingRowColor: WidgetStateProperty.all(
                      colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Marked'), numeric: true),
                      DataColumn(label: Text('Present'), numeric: true),
                      DataColumn(label: Text('Late'), numeric: true),
                      DataColumn(label: Text('Absent'), numeric: true),
                      DataColumn(label: Text('Leave'), numeric: true),
                      DataColumn(label: Text('Rate %'), numeric: true),
                      DataColumn(label: Text('Topic Covered')),
                    ],
                    rows: _subjectSessionHistory.map((s) {
                      final rate = (s['attendanceRate'] as num?)?.toDouble() ?? 0.0;
                      return DataRow(
                        cells: [
                          DataCell(Text(
                            s['sessionDate'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(Text('${s['totalMarked']}')),
                          DataCell(Text('${s['presentCount']}',
                              style: const TextStyle(color: Colors.green))),
                          DataCell(Text('${s['lateCount']}',
                              style: const TextStyle(color: Colors.orange))),
                          DataCell(Text('${s['absentCount']}',
                              style: const TextStyle(color: Colors.red))),
                          DataCell(Text('${s['leaveCount']}',
                              style: const TextStyle(color: Colors.blue))),
                          DataCell(Text('${rate.toStringAsFixed(1)}%')),
                          DataCell(Text(
                            (s['remarks'] as String?)?.isNotEmpty == true
                                ? s['remarks'] as String
                                : '—',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Class Report
  // ---------------------------------------------------------------------------

  Widget _buildClassReportTab(ThemeData theme, ColorScheme colorScheme) {
    final instituteStore = context.watch<InstituteStore>();
    final classes = instituteStore.classes;

    if (classes.isEmpty) {
      return _emptyPlaceholder('No classes registered');
    }

    final selectedClass = classes
        .where((c) => c.id == _classReportClassId)
        .firstOrNull ??
        classes.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Class Picker
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DropdownButtonFormField<int>(
                key: ValueKey('rep_cls_pick_${selectedClass.id}'),
                initialValue: selectedClass.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select Class & Year',
                  prefixIcon: Icon(Icons.class_rounded),
                  isDense: true,
                ),
                items: classes
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          '${c.displayName} (Sec: ${c.section}, Room: ${c.room})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _classReportClassId = val);
                    _loadClassReport(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Subjects Summary for ${selectedClass.displayName}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          if (_isLoadingClassReport)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_classSubjectSummary.isEmpty)
            _emptyPlaceholder('No subjects or attendance data found for this class.')
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateProperty.all(
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  columns: const [
                    DataColumn(label: Text('Subject')),
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Year')),
                    DataColumn(label: Text('Total Marked'), numeric: true),
                    DataColumn(label: Text('Present'), numeric: true),
                    DataColumn(label: Text('Attendance %'), numeric: true),
                  ],
                  rows: _classSubjectSummary.map((sub) {
                    final pct = (sub['percentage'] as num?)?.toDouble() ?? 0.0;
                    return DataRow(
                      cells: [
                        DataCell(Text(
                          sub['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        )),
                        DataCell(Text(sub['code'] as String)),
                        DataCell(Text(sub['year'] as String? ?? '—')),
                        DataCell(Text('${sub['total']}')),
                        DataCell(Text(
                          '${sub['present']}',
                          style: const TextStyle(color: Colors.green),
                        )),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: (pct >= 75
                                      ? Colors.green
                                      : (pct >= 50
                                          ? Colors.orange
                                          : Colors.red))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: pct >= 75
                                    ? Colors.green.shade800
                                    : (pct >= 50
                                        ? Colors.orange.shade800
                                        : Colors.red.shade800),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Overall Trends & Charts
  // ---------------------------------------------------------------------------

  Widget _buildTrendsTab(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoadingAnalytics) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadGeneralAnalytics,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
    if (_monthlyTrend.isEmpty ||
        _monthlyTrend.every((m) => (m['rate'] as double) == 0)) {
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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  return Text('${value.toInt()}%',
                      style: const TextStyle(fontSize: 10));
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
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

  Widget _kpiCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return SizedBox(
      width: 155,
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
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 8),
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                title,
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
