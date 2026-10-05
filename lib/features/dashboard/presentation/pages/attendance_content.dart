import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/attendance_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Subject-based Attendance page following the strict academic hierarchy:
/// Department → Academic Session → Class → Year → Subject → Date → Student List → Mark Attendance.
/// Includes dual tabs: "Mark Attendance" and "Session History".
class AttendanceContent extends StatefulWidget {
  const AttendanceContent({super.key});

  @override
  State<AttendanceContent> createState() => _AttendanceContentState();
}

class _AttendanceContentState extends State<AttendanceContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Selection Chain State
  String? _selectedDepartmentId;
  String? _selectedSessionId;
  int? _selectedClassId;
  String _selectedYear = AcademicYears.firstYear;
  int? _selectedSubjectId;
  DateTime _selectedDate = DateTime.now();

  final TextEditingController _remarksController = TextEditingController();
  bool _isLoadingRoster = false;
  bool _isSaving = false;

  // History Tab Filter State
  int? _historySubjectId;
  bool _isLoadingHistory = false;
  List<Map<String, dynamic>> _historySessions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultSelections());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _initDefaultSelections() {
    final instituteStore = context.read<InstituteStore>();

    // 1. Department
    final depts = instituteStore.activeDepartments;
    if (depts.isNotEmpty && _selectedDepartmentId == null) {
      _selectedDepartmentId = depts.first.id;
    }

    // 2. Academic Session
    final sessions = instituteStore.academicSessions;
    if (sessions.isNotEmpty && _selectedSessionId == null) {
      _selectedSessionId =
          instituteStore.currentAcademicSession?.id ?? sessions.first.id;
    }

    // 3. Class
    _syncClassesAndSubjects();
  }

  void _syncClassesAndSubjects() {
    final instituteStore = context.read<InstituteStore>();
    final availableClasses = instituteStore.classesForContext(
      departmentId: _selectedDepartmentId,
      academicSessionId: _selectedSessionId,
    );

    if (availableClasses.isNotEmpty) {
      if (_selectedClassId == null ||
          !availableClasses.any((c) => c.id == _selectedClassId)) {
        _selectedClassId = availableClasses.first.id;
        _selectedYear = availableClasses.first.currentYear.isNotEmpty
            ? availableClasses.first.currentYear
            : AcademicYears.firstYear;
      }
    } else {
      _selectedClassId = null;
    }

    _syncSubjects();
  }

  void _syncSubjects() {
    final instituteStore = context.read<InstituteStore>();
    if (_selectedClassId != null) {
      final availableSubjects = instituteStore.subjectsForClassAndYear(
        _selectedClassId!,
        _selectedYear,
      );

      if (availableSubjects.isNotEmpty) {
        if (_selectedSubjectId == null ||
            !availableSubjects.any((s) => s.id == _selectedSubjectId)) {
          _selectedSubjectId = availableSubjects.first.id;
        }
      } else {
        // Fallback to any subject in the class if year-specific is empty
        final classSubjects = instituteStore.subjectsForClass(_selectedClassId!);
        if (classSubjects.isNotEmpty) {
          _selectedSubjectId = classSubjects.first.id;
        } else {
          _selectedSubjectId = null;
        }
      }
    } else {
      _selectedSubjectId = null;
    }

    if (mounted) setState(() {});
    if (_selectedSubjectId != null) {
      _loadAttendanceRoster();
    }
  }

  List<Student> _getTargetStudents() {
    final instituteStore = context.read<InstituteStore>();
    if (_selectedClassId == null) return [];

    var students = instituteStore.studentsForClassAndYear(
      _selectedClassId!,
      _selectedYear,
    );
    if (students.isEmpty) {
      students = instituteStore.studentsForClass(_selectedClassId!);
    }
    return students;
  }

  Future<void> _loadAttendanceRoster() async {
    if (_selectedClassId == null ||
        _selectedSubjectId == null ||
        _selectedDepartmentId == null ||
        _selectedSessionId == null) {
      return;
    }

    final instituteStore = context.read<InstituteStore>();
    final attendanceStore = context.read<AttendanceStore>();
    final students = _getTargetStudents();
    final subject = instituteStore.subjectById(_selectedSubjectId);

    setState(() => _isLoadingRoster = true);

    await attendanceStore.loadSubjectAttendance(
      departmentId: _selectedDepartmentId!,
      academicSessionId: _selectedSessionId!,
      classId: _selectedClassId!,
      year: _selectedYear,
      subjectId: _selectedSubjectId!,
      date: _selectedDate,
      students: students,
      subjectCode: subject?.code ?? '',
    );

    _remarksController.text = attendanceStore.sessionRemarks;

    if (mounted) {
      setState(() => _isLoadingRoster = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadAttendanceRoster();
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedClassId == null ||
        _selectedSubjectId == null ||
        _selectedDepartmentId == null ||
        _selectedSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all academic levels first')),
      );
      return;
    }

    final instituteStore = context.read<InstituteStore>();
    final attendanceStore = context.read<AttendanceStore>();
    final students = _getTargetStudents();
    final subject = instituteStore.subjectById(_selectedSubjectId);

    setState(() => _isSaving = true);

    try {
      await attendanceStore.saveSubjectAttendance(
        departmentId: _selectedDepartmentId!,
        academicSessionId: _selectedSessionId!,
        classId: _selectedClassId!,
        year: _selectedYear,
        subjectId: _selectedSubjectId!,
        date: _selectedDate,
        students: students,
        subjectCode: subject?.code ?? '',
        teacherId: subject?.teacherId?.toString(),
        remarks: _remarksController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance recorded for ${subject?.name ?? 'Subject'} on ${DateFormat('d MMM yyyy').format(_selectedDate)}',
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving attendance: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _loadHistory(int subjectId) async {
    setState(() {
      _historySubjectId = subjectId;
      _isLoadingHistory = true;
    });

    final attendanceStore = context.read<AttendanceStore>();
    final sessions = await attendanceStore.getSubjectSessionHistory(subjectId);

    if (mounted) {
      setState(() {
        _historySessions = sessions;
        _isLoadingHistory = false;
      });
    }
  }

  void _editSessionFromHistory(Map<String, dynamic> session) {
    setState(() {
      if (session['departmentId'] != null) {
        _selectedDepartmentId = session['departmentId'] as String;
      }
      if (session['academicSessionId'] != null) {
        _selectedSessionId = session['academicSessionId'] as String;
      }
      if (session['classId'] != null) {
        _selectedClassId = session['classId'] as int;
      }
      if (session['year'] != null && (session['year'] as String).isNotEmpty) {
        _selectedYear = session['year'] as String;
      }
      if (_historySubjectId != null) {
        _selectedSubjectId = _historySubjectId;
      }
      if (session['sessionDate'] != null) {
        _selectedDate = DateTime.tryParse(session['sessionDate'] as String) ??
            DateTime.now();
      }
      _remarksController.text = (session['remarks'] as String?) ?? '';
    });

    _tabController.animateTo(0);
    _loadAttendanceRoster();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Tab Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Subject Attendance',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Department → Session → Class → Year → Subject',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (_tabController.index == 0)
                      FilledButton.icon(
                        key: const Key('saveAttendanceHeaderButton'),
                        onPressed: _isSaving ? null : _saveAttendance,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: Text(_isSaving ? 'Saving...' : 'Save Attendance'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  onTap: (index) {
                    setState(() {});
                    if (index == 1 &&
                        _selectedSubjectId != null &&
                        _historySubjectId != _selectedSubjectId) {
                      _loadHistory(_selectedSubjectId!);
                    }
                  },
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.assignment_turned_in_outlined),
                      text: 'Mark Attendance',
                    ),
                    Tab(
                      icon: Icon(Icons.history_rounded),
                      text: 'Session History',
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
                _buildMarkAttendanceTab(theme, colorScheme),
                _buildHistoryTab(theme, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Mark Attendance
  // ---------------------------------------------------------------------------

  Widget _buildMarkAttendanceTab(ThemeData theme, ColorScheme colorScheme) {
    final instituteStore = context.watch<InstituteStore>();
    final attendanceStore = context.watch<AttendanceStore>();

    final departments = instituteStore.activeDepartments;
    final sessions = instituteStore.academicSessions;
    final availableClasses = instituteStore.classesForContext(
      departmentId: _selectedDepartmentId,
      academicSessionId: _selectedSessionId,
    );
    final availableSubjects = _selectedClassId != null
        ? instituteStore.subjectsForClassAndYear(_selectedClassId!, _selectedYear)
        : <Subject>[];

    final students = _getTargetStudents();
    final draftStatuses = attendanceStore.draftStatuses;

    final presentCount = draftStatuses.values
        .where((s) => s == AttendanceStatus.present)
        .length;
    final lateCount =
        draftStatuses.values.where((s) => s == AttendanceStatus.late).length;
    final absentCount =
        draftStatuses.values.where((s) => s == AttendanceStatus.absent).length;
    final leaveCount =
        draftStatuses.values.where((s) => s == AttendanceStatus.leave).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Cascading Academic Selector Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Academic Hierarchy',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 1: Department & Session
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('dept_$_selectedDepartmentId'),
                          initialValue: _selectedDepartmentId,
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
                              _selectedDepartmentId = val;
                              _syncClassesAndSubjects();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('sess_$_selectedSessionId'),
                          initialValue: _selectedSessionId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Academic Session',
                            prefixIcon: Icon(Icons.date_range_rounded),
                            isDense: true,
                          ),
                          items: sessions
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    s.isCurrent ? '${s.name} (Current)' : s.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedSessionId = val;
                              _syncClassesAndSubjects();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Class & Year
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('cls_$_selectedClassId'),
                          initialValue: _selectedClassId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                            prefixIcon: Icon(Icons.class_outlined),
                            isDense: true,
                          ),
                          items: availableClasses
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(
                                    '${c.displayName} (Sec: ${c.section})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedClassId = val;
                              final cls = availableClasses
                                  .where((c) => c.id == val)
                                  .firstOrNull;
                              if (cls != null && cls.currentYear.isNotEmpty) {
                                _selectedYear = cls.currentYear;
                              }
                              _syncSubjects();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('yr_$_selectedYear'),
                          initialValue: _selectedYear,
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
                              setState(() {
                                _selectedYear = val;
                                _syncSubjects();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 3: Subject & Date
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('sub_$_selectedSubjectId'),
                          initialValue: _selectedSubjectId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            prefixIcon: Icon(Icons.menu_book_rounded),
                            isDense: true,
                          ),
                          items: (availableSubjects.isNotEmpty
                                  ? availableSubjects
                                  : (_selectedClassId != null
                                      ? instituteStore
                                          .subjectsForClass(_selectedClassId!)
                                      : <Subject>[]))
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    '${s.name} (${s.code}) [${s.subjectType.label}]',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() => _selectedSubjectId = val);
                            _loadAttendanceRoster();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Session Date',
                              prefixIcon: Icon(Icons.calendar_today_rounded),
                              isDense: true,
                            ),
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(_selectedDate),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Warning / helper if no subject is configured
          if (_selectedSubjectId == null)
            Card(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedClassId == null
                            ? 'Please select a Class to view and mark attendance.'
                            : 'No subjects configured for this class and year. Please add subjects in the Subjects tab.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Status Summary & Fast Action Buttons
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            _statusChip('Total', students.length, colorScheme.primary),
                            _statusChip('Present', presentCount, Colors.green),
                            _statusChip('Late', lateCount, Colors.orange),
                            _statusChip('Absent', absentCount, Colors.red),
                            _statusChip('Leave', leaveCount, Colors.blue),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  attendanceStore.markAll(AttendanceStatus.present),
                              icon: const Icon(Icons.check_circle_outline,
                                  color: Colors.green, size: 18),
                              label: const Text('All Present'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  attendanceStore.markAll(AttendanceStatus.absent),
                              icon: const Icon(Icons.cancel_outlined,
                                  color: Colors.red, size: 18),
                              label: const Text('All Absent'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    // Topic Covered / Remarks field
                    TextField(
                      controller: _remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Topic Covered / Session Remarks (Optional)',
                        hintText: 'e.g. Chapter 3: Leather Tanning Processes',
                        prefixIcon: Icon(Icons.edit_note_rounded),
                        isDense: true,
                      ),
                      onChanged: (val) => attendanceStore.updateRemarks(val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Previously saved session notice
            if (attendanceStore.isPreviouslySaved)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded,
                        color: Colors.green.shade800, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Session records exist for this date. Modifying status and saving will update attendance.',
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Student Roster
            if (_isLoadingRoster)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (students.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 48, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No students found in $_selectedYear',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enroll students in this Class & Year to mark subject attendance.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: students.length,
                itemBuilder: (ctx, index) {
                  final student = students[index];
                  final currentStatus = attendanceStore.getStatus(student.id);

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: _statusColor(currentStatus).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: colorScheme.primaryContainer,
                            child: Text(
                              student.initials,
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
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
                                  'Roll: ${student.rollNumber}${student.registrationNo != null ? ' • Reg: ${student.registrationNo}' : ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Compact Status Selector Buttons
                          _buildStatusToggle(
                            student.id,
                            currentStatus,
                            attendanceStore,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusToggle(
    int studentId,
    AttendanceStatus currentStatus,
    AttendanceStore attendanceStore,
  ) {
    return SegmentedButton<AttendanceStatus>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: AttendanceStatus.present,
          label: Text('P', style: TextStyle(fontWeight: FontWeight.bold)),
          tooltip: 'Present',
        ),
        ButtonSegment(
          value: AttendanceStatus.late,
          label: Text('L', style: TextStyle(fontWeight: FontWeight.bold)),
          tooltip: 'Late',
        ),
        ButtonSegment(
          value: AttendanceStatus.absent,
          label: Text('A', style: TextStyle(fontWeight: FontWeight.bold)),
          tooltip: 'Absent',
        ),
        ButtonSegment(
          value: AttendanceStatus.leave,
          label: Text('LV', style: TextStyle(fontWeight: FontWeight.bold)),
          tooltip: 'Leave',
        ),
      ],
      selected: {currentStatus},
      onSelectionChanged: (newSelection) {
        if (newSelection.isNotEmpty) {
          attendanceStore.setStatus(studentId, newSelection.first);
        }
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _statusColor(currentStatus).withValues(alpha: 0.2);
          }
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _statusColor(currentStatus);
          }
          return null;
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Session History
  // ---------------------------------------------------------------------------

  Widget _buildHistoryTab(ThemeData theme, ColorScheme colorScheme) {
    final instituteStore = context.watch<InstituteStore>();

    final classes = instituteStore.classes;
    final subjects = _selectedClassId != null
        ? instituteStore.subjectsForClass(_selectedClassId!)
        : instituteStore.subjects;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Bar
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('hist_cls_$_selectedClassId'),
                      initialValue: _selectedClassId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Class',
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
                          _selectedClassId = val;
                          final clsSubs = instituteStore.subjectsForClass(val!);
                          if (clsSubs.isNotEmpty) {
                            _historySubjectId = clsSubs.first.id;
                            _loadHistory(_historySubjectId!);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('hist_sub_${_historySubjectId ?? _selectedSubjectId}'),
                      initialValue: _historySubjectId ?? _selectedSubjectId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        prefixIcon: Icon(Icons.menu_book_rounded),
                        isDense: true,
                      ),
                      items: subjects
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
                          _loadHistory(val);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // History Content
          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_historySessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded,
                        size: 48, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'No past sessions recorded for this subject.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mark and save attendance in the Mark Attendance tab to build session history.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _historySessions.length,
              itemBuilder: (ctx, index) {
                final session = _historySessions[index];
                final dateStr = session['sessionDate'] as String? ?? '';
                final parsedDate = DateTime.tryParse(dateStr);
                final formattedDate = parsedDate != null
                    ? DateFormat('EEEE, d MMMM yyyy').format(parsedDate)
                    : dateStr;
                final rate = (session['attendanceRate'] as num?)?.toDouble() ?? 0.0;
                final total = session['totalMarked'] ?? 0;
                final present = session['presentCount'] ?? 0;
                final late = session['lateCount'] ?? 0;
                final absent = session['absentCount'] ?? 0;
                final leave = session['leaveCount'] ?? 0;
                final remarks = session['remarks'] as String? ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.event_note_rounded,
                                    size: 20, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  formattedDate,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (rate >= 75
                                        ? Colors.green
                                        : (rate >= 50
                                            ? Colors.orange
                                            : Colors.red))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${rate.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: rate >= 75
                                      ? Colors.green.shade800
                                      : (rate >= 50
                                          ? Colors.orange.shade800
                                          : Colors.red.shade800),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          children: [
                            Text('Total: $total',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('Present: $present',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.green)),
                            Text('Late: $late',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.orange)),
                            Text('Absent: $absent',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.red)),
                            Text('Leave: $leave',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.blue)),
                          ],
                        ),
                        if (remarks.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Remarks / Topic: $remarks',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _editSessionFromHistory(session),
                            icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                            label: const Text('Edit / Load Session'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
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
  // Helper Widgets
  // ---------------------------------------------------------------------------

  Widget _statusChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 5,
      ),
      label: Text('$label: $count', style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
}
