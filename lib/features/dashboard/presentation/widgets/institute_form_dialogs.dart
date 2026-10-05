import 'package:flutter/material.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/database/migrations/migration_helpers.dart';
import 'package:attendance_app/core/models/institute_models.dart';

class AddClassResult {
  const AddClassResult({
    required this.name,
    required this.section,
    required this.room,
    this.departmentId,
    this.academicSessionId,
    this.className,
    this.currentYear = '1st Year',
  });

  final String name;
  final String section;
  final String room;
  final String? departmentId;
  final String? academicSessionId;
  final String? className;
  final String currentYear;
}

class AddTeacherResult {
  const AddTeacherResult({
    required this.name,
    required this.email,
    required this.username,
    required this.password,
    required this.subjectIds,
    this.departmentId,
    this.employeeCode,
    this.designation = 'Instructor',
    this.classId,
  });

  final String name;
  final String email;
  final String username;
  final String password;
  final List<int> subjectIds;
  final String? departmentId;
  final String? employeeCode;
  final String designation;
  final int? classId;
}

class EditTeacherResult {
  const EditTeacherResult({
    required this.name,
    required this.email,
    required this.username,
    required this.password,
    required this.subjectIds,
    this.departmentId,
    this.employeeCode,
    this.designation = 'Instructor',
    this.classId,
  });

  final String name;
  final String email;
  final String username;
  final String password;
  final List<int> subjectIds;
  final String? departmentId;
  final String? employeeCode;
  final String designation;
  final int? classId;
}

class AddStudentResult {
  const AddStudentResult({
    required this.name,
    required this.rollNumber,
    required this.classId,
    this.registrationNo,
    this.fatherName = '',
    this.departmentId,
    this.academicSessionId,
    this.currentYear = '1st Year',
    this.status = 'ACTIVE',
  });

  final String name;
  final String rollNumber;
  final int classId;
  final String? registrationNo;
  final String fatherName;
  final String? departmentId;
  final String? academicSessionId;
  final String currentYear;
  final String status;
}

class PromoteStudentResult {
  const PromoteStudentResult({
    required this.newClassId,
    required this.newYear,
    this.newAcademicSessionId,
    this.newDepartmentId,
  });

  final int newClassId;
  final String newYear;
  final String? newAcademicSessionId;
  final String? newDepartmentId;
}

class AddAcademicSessionResult {
  const AddAcademicSessionResult({
    required this.name,
    required this.startDate,
    required this.endDate,
    this.isCurrent = false,
  });

  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final bool isCurrent;
}

/// Dialog for creating a class in GILT's Class_Name Current_Year structure (e.g. CIT-1st Year).
class AddClassDialog extends StatefulWidget {
  const AddClassDialog({
    super.key,
    this.departments = const [],
    this.sessions = const [],
  });

  final List<Department> departments;
  final List<AcademicSession> sessions;

  @override
  State<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<AddClassDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _programController;
  late final TextEditingController _sectionController;
  late final TextEditingController _roomController;

  String? _selectedDepartmentId;
  String? _selectedSessionId;
  String _selectedYear = AcademicYears.defaultValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _programController = TextEditingController(text: 'CIT');
    _sectionController = TextEditingController();
    _roomController = TextEditingController();

    if (widget.departments.isNotEmpty) {
      _selectedDepartmentId = widget.departments.first.id;
      final deptCode = widget.departments.first.code;
      final deptEnum = AcademicDepartment.fromCode(deptCode);
      if (deptEnum != null && deptEnum.classPrograms.isNotEmpty) {
        _programController.text = deptEnum.classPrograms.first;
      }
    }
    if (widget.sessions.isNotEmpty) {
      final current =
          widget.sessions.where((s) => s.isCurrent).firstOrNull ?? widget.sessions.first;
      _selectedSessionId = current.id;
    }
    _syncDisplayName();
  }

  void _syncDisplayName() {
    final prog = _programController.text.trim();
    if (prog.isNotEmpty) {
      _nameController.text = '$prog-$_selectedYear';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _programController.dispose();
    _sectionController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final prog = _programController.text.trim();
    final finalName =
        _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : '$prog-$_selectedYear';
    
    String effectiveClassName = prog;
    String effectiveYear = _selectedYear;

    if (finalName.contains('-')) {
      final parts = finalName.split('-');
      effectiveClassName = parts[0].trim();
      effectiveYear = parts.sublist(1).join('-').trim();
    } else if (finalName.isNotEmpty && finalName != '$prog-$_selectedYear') {
      effectiveClassName = finalName;
      if (widget.departments.isEmpty) {
        effectiveYear = '';
      }
    }

    Navigator.of(context).pop(
      AddClassResult(
        name: finalName,
        className: effectiveClassName.isNotEmpty ? effectiveClassName : finalName,
        currentYear: effectiveYear,
        departmentId: _selectedDepartmentId,
        academicSessionId: _selectedSessionId,
        section: _sectionController.text,
        room: _roomController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Add class'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.departments.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                    isExpanded: true,
                    items: widget.departments
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
                        final dept = widget.departments.firstWhere((d) => d.id == val);
                        final deptEnum = AcademicDepartment.fromCode(dept.code);
                        if (deptEnum != null && deptEnum.classPrograms.isNotEmpty) {
                          _programController.text = deptEnum.classPrograms.first;
                        } else {
                          _programController.text = dept.code;
                        }
                        _syncDisplayName();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.sessions.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSessionId,
                    decoration: const InputDecoration(
                      labelText: 'Academic Session',
                      prefixIcon: Icon(Icons.date_range_rounded),
                    ),
                    isExpanded: true,
                    items: widget.sessions
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.isCurrent ? '${s.name} (Current Session)' : s.name,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => _selectedSessionId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _programController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Program / Code',
                          hintText: 'e.g. CIT, LT, FW',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        validator: _required,
                        onChanged: (_) => _syncDisplayName(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedYear,
                        decoration: const InputDecoration(
                          labelText: 'Current Year',
                          prefixIcon: Icon(Icons.timeline_rounded),
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
                              _syncDisplayName();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('classNameField'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Display Class Name',
                    hintText: 'e.g. CIT-1st Year',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('classSectionField'),
                        controller: _sectionController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Section',
                          hintText: 'e.g. A or Morning',
                          prefixIcon: Icon(Icons.segment_rounded),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('classRoomField'),
                        controller: _roomController,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Classroom',
                          hintText: 'e.g. Room 12',
                          prefixIcon: Icon(Icons.meeting_room_outlined),
                        ),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Recognized format: ${_programController.text.trim()}-$_selectedYear',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirmAddButton'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class AddTeacherDialog extends StatefulWidget {
  const AddTeacherDialog({
    super.key,
    required this.subjects,
    this.departments = const [],
    this.classes = const [],
  });

  /// All subjects sorted with unassigned first.
  final List<Subject> subjects;
  final List<Department> departments;
  final List<SchoolClass> classes;

  @override
  State<AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _employeeCodeController;
  String _designation = 'Instructor';
  String? _selectedDepartmentId;
  int? _selectedClassId;
  final Set<int> _selectedSubjectIds = {};
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _employeeCodeController = TextEditingController();

    if (widget.departments.isNotEmpty) {
      _selectedDepartmentId = widget.departments.first.id;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _employeeCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddTeacherResult(
        name: _nameController.text,
        email: _emailController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        subjectIds: _selectedSubjectIds.toList(),
        departmentId: _selectedDepartmentId,
        employeeCode: _employeeCodeController.text.trim().isNotEmpty
            ? _employeeCodeController.text.trim()
            : null,
        designation: _designation,
        classId: _selectedClassId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Add teacher'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const Key('teacherNameField'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                if (widget.departments.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                    isExpanded: true,
                    items: widget.departments
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.code} — ${d.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedDepartmentId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _designation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Designation',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Instructor', child: Text('Instructor')),
                          DropdownMenuItem(
                              value: 'Senior Instructor',
                              child: Text('Senior Instructor')),
                          DropdownMenuItem(
                              value: 'Lecturer', child: Text('Lecturer')),
                          DropdownMenuItem(
                              value: 'Head of Department',
                              child: Text('HOD')),
                        ],
                        onChanged: (val) =>
                            setState(() => _designation = val ?? 'Instructor'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _employeeCodeController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Employee Code',
                          hintText: 'e.g. FAC-01',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('teacherEmailField'),
                  controller: _emailController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'e.g. teacher@institute.edu',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('teacherUsernameField'),
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'e.g. teacher01',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('teacherPasswordField'),
                        controller: _passwordController,
                        textInputAction: TextInputAction.next,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Assign subjects',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select the subjects this teacher will teach.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.subjects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No subjects available. Add subjects to classes first.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.subjects.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final subject = widget.subjects[index];
                          final isUnassigned =
                              subject.teacherName == 'Unassigned' ||
                                  subject.teacherName.trim().isEmpty;
                          final isSelected =
                              _selectedSubjectIds.contains(subject.id);
                          return CheckboxListTile(
                            dense: true,
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedSubjectIds.add(subject.id);
                                } else {
                                  _selectedSubjectIds.remove(subject.id);
                                }
                              });
                            },
                            title: Text(
                              '${subject.name} (${subject.code})',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              isUnassigned
                                  ? 'Unassigned'
                                  : 'Assigned to ${subject.teacherName}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isUnassigned
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirmAddButton'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class EditTeacherDialog extends StatefulWidget {
  const EditTeacherDialog({
    super.key,
    required this.teacher,
    required this.subjects,
    required this.assignedSubjectIds,
    this.departments = const [],
  });

  final Teacher teacher;
  final List<Subject> subjects;
  final Set<int> assignedSubjectIds;
  final List<Department> departments;

  @override
  State<EditTeacherDialog> createState() => _EditTeacherDialogState();
}

class _EditTeacherDialogState extends State<EditTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _employeeCodeController;
  late String _designation;
  String? _selectedDepartmentId;
  late final Set<int> _selectedSubjectIds;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teacher.name);
    _emailController = TextEditingController(text: widget.teacher.email);
    _usernameController = TextEditingController(text: widget.teacher.username);
    _passwordController = TextEditingController(text: widget.teacher.password);
    _employeeCodeController =
        TextEditingController(text: widget.teacher.employeeCode ?? '');
    _designation = widget.teacher.designation;
    _selectedDepartmentId = widget.teacher.departmentId;
    _selectedSubjectIds = Set<int>.from(widget.assignedSubjectIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _employeeCodeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      EditTeacherResult(
        name: _nameController.text,
        email: _emailController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        subjectIds: _selectedSubjectIds.toList(),
        departmentId: _selectedDepartmentId,
        employeeCode: _employeeCodeController.text.trim().isNotEmpty
            ? _employeeCodeController.text.trim()
            : null,
        designation: _designation,
        classId: widget.teacher.classId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Edit teacher'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                if (widget.departments.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDepartmentId,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      prefixIcon: Icon(Icons.apartment_rounded),
                    ),
                    isExpanded: true,
                    items: widget.departments
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.code} — ${d.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedDepartmentId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _designation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Designation',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Instructor', child: Text('Instructor')),
                          DropdownMenuItem(
                              value: 'Senior Instructor',
                              child: Text('Senior Instructor')),
                          DropdownMenuItem(
                              value: 'Lecturer', child: Text('Lecturer')),
                          DropdownMenuItem(
                              value: 'Head of Department',
                              child: Text('HOD')),
                        ],
                        onChanged: (val) =>
                            setState(() => _designation = val ?? 'Instructor'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _employeeCodeController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Employee Code',
                          hintText: 'e.g. FAC-01',
                          prefixIcon: Icon(Icons.tag_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'e.g. teacher@institute.edu',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'e.g. teacher01',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passwordController,
                        textInputAction: TextInputAction.next,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Assign subjects',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select the subjects this teacher will teach.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.subjects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No subjects available. Add subjects to classes first.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.subjects.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final subject = widget.subjects[index];
                          final isUnassigned =
                              subject.teacherName == 'Unassigned' ||
                                  subject.teacherName.trim().isEmpty;
                          final isSelected =
                              _selectedSubjectIds.contains(subject.id);
                          return CheckboxListTile(
                            dense: true,
                            value: isSelected,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedSubjectIds.add(subject.id);
                                } else {
                                  _selectedSubjectIds.remove(subject.id);
                                }
                              });
                            },
                            title: Text(
                              '${subject.name} (${subject.code})',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              isUnassigned
                                  ? 'Unassigned'
                                  : 'Assigned to ${subject.teacherName}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isUnassigned
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class AddStudentDialog extends StatefulWidget {
  const AddStudentDialog({super.key, required this.classes});

  final List<SchoolClass> classes;

  @override
  State<AddStudentDialog> createState() => _AddStudentDialogState();
}

class _AddStudentDialogState extends State<AddStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _rollController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _regNoController;
  late int _classId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _rollController = TextEditingController();
    _fatherNameController = TextEditingController();
    _regNoController = TextEditingController();
    _classId = widget.classes.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rollController.dispose();
    _fatherNameController.dispose();
    _regNoController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final selectedClass = widget.classes.firstWhere((c) => c.id == _classId);
    Navigator.of(context).pop(
      AddStudentResult(
        name: _nameController.text,
        rollNumber: _rollController.text,
        classId: _classId,
        fatherName: _fatherNameController.text.trim(),
        registrationNo: _regNoController.text.trim().isNotEmpty
            ? _regNoController.text.trim()
            : null,
        departmentId: selectedClass.departmentId,
        academicSessionId: selectedClass.academicSessionId,
        currentYear: selectedClass.currentYear.isNotEmpty
            ? selectedClass.currentYear
            : AcademicYears.defaultValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add student'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('studentNameField'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fatherNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Father name',
                    prefixIcon: Icon(Icons.family_restroom_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('studentRollField'),
                        controller: _rollController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Roll number',
                          hintText: 'e.g. 09A-21',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _regNoController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Registration No',
                          hintText: 'e.g. REG-09A-21',
                          prefixIcon: Icon(Icons.assignment_ind_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('studentClassField'),
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Class & Year',
                    prefixIcon: Icon(Icons.class_rounded),
                  ),
                  items: widget.classes
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _classId = value;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirmAddButton'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Dialog to promote or move a student to a different class / academic year / session.
class PromoteStudentDialog extends StatefulWidget {
  const PromoteStudentDialog({
    super.key,
    required this.student,
    required this.classes,
    this.sessions = const [],
  });

  final Student student;
  final List<SchoolClass> classes;
  final List<AcademicSession> sessions;

  @override
  State<PromoteStudentDialog> createState() => _PromoteStudentDialogState();
}

class _PromoteStudentDialogState extends State<PromoteStudentDialog> {
  late int _selectedClassId;
  late String _selectedYear;
  String? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.student.classId;
    _selectedYear = widget.student.currentYear;
    _selectedSessionId = widget.student.academicSessionId;

    // Suggest next year if 1st Year or 2nd Year
    if (_selectedYear == '1st Year') {
      _selectedYear = '2nd Year';
    } else if (_selectedYear == '2nd Year') {
      _selectedYear = '3rd Year';
    }
  }

  void _submit() {
    final selectedClass =
        widget.classes.where((c) => c.id == _selectedClassId).firstOrNull;
    Navigator.of(context).pop(
      PromoteStudentResult(
        newClassId: _selectedClassId,
        newYear: _selectedYear,
        newAcademicSessionId: _selectedSessionId ?? selectedClass?.academicSessionId,
        newDepartmentId: selectedClass?.departmentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Promote / Move Student'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move ${widget.student.name} to the next academic year or session without modifying previous attendance records.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _selectedClassId,
              decoration: const InputDecoration(
                labelText: 'Target Class',
                prefixIcon: Icon(Icons.class_rounded),
              ),
              isExpanded: true,
              items: widget.classes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedClassId = val);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedYear,
              decoration: const InputDecoration(
                labelText: 'Academic Year',
                prefixIcon: Icon(Icons.timeline_rounded),
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
                if (val != null) setState(() => _selectedYear = val);
              },
            ),
            if (widget.sessions.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedSessionId,
                decoration: const InputDecoration(
                  labelText: 'Target Academic Session',
                  prefixIcon: Icon(Icons.calendar_today_rounded),
                ),
                isExpanded: true,
                items: widget.sessions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _selectedSessionId = val),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm Move'),
        ),
      ],
    );
  }
}

/// Dialog to add a new academic session (e.g. 2026-27).
class AddAcademicSessionDialog extends StatefulWidget {
  const AddAcademicSessionDialog({super.key});

  @override
  State<AddAcademicSessionDialog> createState() =>
      _AddAcademicSessionDialogState();
}

class _AddAcademicSessionDialogState extends State<AddAcademicSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final DateTime _startDate = DateTime.now();
  final DateTime _endDate = DateTime.now().add(const Duration(days: 365));
  bool _isCurrent = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: MigrationHelpers.currentAcademicSessionName(DateTime.now()),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddAcademicSessionResult(
        name: _nameController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        isCurrent: _isCurrent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Academic Session'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Session Name',
                  hintText: 'e.g. 2026-27',
                  prefixIcon: Icon(Icons.date_range_rounded),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isCurrent,
                title: const Text('Set as Current Active Session'),
                onChanged: (val) => setState(() => _isCurrent = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add Session'),
        ),
      ],
    );
  }
}

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}
