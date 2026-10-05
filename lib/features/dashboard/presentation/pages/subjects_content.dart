import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Page that lists subjects for a given class and lets the user add or remove them.
class SubjectsContent extends StatefulWidget {
  const SubjectsContent({super.key, required this.schoolClass});

  final SchoolClass schoolClass;

  @override
  State<SubjectsContent> createState() => _SubjectsContentState();
}

class _SubjectsContentState extends State<SubjectsContent> {
  Future<void> _showAddSubjectDialog(InstituteStore store) async {
    final result = await showDialog<_AddSubjectResult>(
      context: context,
      builder: (ctx) => _AddSubjectDialog(
        teachers: store.teachers,
        defaultYear: widget.schoolClass.currentYear,
      ),
    );

    if (result == null || !mounted) return;

    await store.addSubject(
      name: result.name,
      code: result.code,
      teacherName: result.teacherName,
      classId: widget.schoolClass.id,
      departmentId: widget.schoolClass.departmentId,
      academicSessionId: widget.schoolClass.academicSessionId,
      year: result.year.isNotEmpty
          ? result.year
          : widget.schoolClass.currentYear,
      subjectType: result.subjectType,
      contactHours: result.contactHours,
      teacherId: result.teacherId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Subject "${result.name}" added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(InstituteStore store, Subject subject) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subject'),
        content: Text(
          'Remove "${subject.name} (${subject.code})" from ${widget.schoolClass.displayName}?',
        ),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true && mounted) {
      await store.deleteSubject(subject.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${subject.name} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final subjects = store.subjectsForClass(widget.schoolClass.id);
    final dept = store.departmentById(widget.schoolClass.departmentId);
    final session =
        store.academicSessionById(widget.schoolClass.academicSessionId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.schoolClass.displayName} — Subjects',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSubjectDialog(store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Subject'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Class info header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primaryContainer,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.class_rounded,
                        color: colorScheme.onPrimaryContainer,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.schoolClass.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${widget.schoolClass.room} • ${subjects.length} ${subjects.length == 1 ? 'subject' : 'subjects'}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (dept != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    dept.code,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              if (session != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    session.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
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
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Subjects for ${widget.schoolClass.currentYear.isNotEmpty ? widget.schoolClass.currentYear : "All Years"}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${subjects.length} ${subjects.length == 1 ? "Subject" : "Subjects"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: subjects.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.menu_book_outlined,
                              size: 64,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No subjects yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the button below to add a subject',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: subjects.length,
                        itemBuilder: (context, index) {
                          final subject = subjects[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    colorScheme.secondaryContainer,
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      subject.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      subject.subjectType.label,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      subject.code,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    Text('• ${subject.teacherName}'),
                                    if (subject.contactHours > 0)
                                      Text(
                                          '• ${subject.contactHours.toStringAsFixed(1)} hrs/wk'),
                                    if (subject.year.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          subject.year,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete subject',
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: colorScheme.error,
                                ),
                                onPressed: () =>
                                    _confirmDelete(store, subject),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Subject Dialog
// ---------------------------------------------------------------------------

class _AddSubjectResult {
  const _AddSubjectResult({
    required this.name,
    required this.code,
    required this.teacherName,
    required this.year,
    required this.subjectType,
    required this.contactHours,
    this.teacherId,
  });

  final String name;
  final String code;
  final String teacherName;
  final String year;
  final SubjectType subjectType;
  final double contactHours;
  final int? teacherId;
}

class _AddSubjectDialog extends StatefulWidget {
  const _AddSubjectDialog({
    required this.teachers,
    this.defaultYear = '1st Year',
  });

  final List<Teacher> teachers;
  final String defaultYear;

  @override
  State<_AddSubjectDialog> createState() => _AddSubjectDialogState();
}

class _AddSubjectDialogState extends State<_AddSubjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _hoursController;
  late String _selectedYear;
  SubjectType _selectedType = SubjectType.theory;
  Teacher? _selectedTeacher;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _codeController = TextEditingController();
    _hoursController = TextEditingController(text: '3.0');
    _selectedYear = widget.defaultYear.isNotEmpty
        ? widget.defaultYear
        : AcademicYears.defaultValue;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final hours = double.tryParse(_hoursController.text.trim()) ?? 0.0;
    Navigator.of(context).pop(
      _AddSubjectResult(
        name: _nameController.text.trim(),
        code: _codeController.text.trim(),
        teacherName: _selectedTeacher?.name ?? 'Unassigned',
        year: _selectedYear,
        subjectType: _selectedType,
        contactHours: hours,
        teacherId: _selectedTeacher?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subject'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Subject name',
                    hintText: 'e.g. Programming Concepts',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _codeController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Subject code',
                          hintText: 'e.g. CIT-101',
                          prefixIcon: Icon(Icons.code_rounded),
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _hoursController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Contact Hrs',
                          hintText: '3.0',
                          prefixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SubjectType>(
                        initialValue: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'Subject Type',
                          prefixIcon: Icon(Icons.category_rounded),
                        ),
                        items: SubjectType.values
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.label),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedType = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
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
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Teacher>(
                  initialValue: _selectedTeacher,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Teacher',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<Teacher>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...widget.teachers.map(
                      (teacher) => DropdownMenuItem<Teacher>(
                        value: teacher,
                        child: Text('${teacher.name} (${teacher.designation})'),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _selectedTeacher = value),
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
          child: const Text('Add'),
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
