import 'package:flutter/material.dart';

import 'package:attendance_app/core/models/institute_models.dart';

class AddClassResult {
  const AddClassResult({
    required this.name,
    required this.section,
    required this.room,
  });

  final String name;
  final String section;
  final String room;
}

class AddTeacherResult {
  const AddTeacherResult({
    required this.name,
    required this.email,
    required this.username,
    required this.password,
    required this.subjectIds,
  });

  final String name;
  final String email;
  final String username;
  final String password;
  final List<int> subjectIds;
}

class EditTeacherResult {
  const EditTeacherResult({
    required this.name,
    required this.email,
    required this.username,
    required this.password,
    required this.subjectIds,
  });

  final String name;
  final String email;
  final String username;
  final String password;
  final List<int> subjectIds;
}

class AddStudentResult {
  const AddStudentResult({
    required this.name,
    required this.rollNumber,
    required this.classId,
  });

  final String name;
  final String rollNumber;
  final int classId;
}

/// Dialog that owns its text controllers until the route is fully removed.
class AddClassDialog extends StatefulWidget {
  const AddClassDialog({super.key});

  @override
  State<AddClassDialog> createState() => _AddClassDialogState();
}

class _AddClassDialogState extends State<AddClassDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _sectionController;
  late final TextEditingController _roomController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _sectionController = TextEditingController();
    _roomController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sectionController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddClassResult(
        name: _nameController.text,
        section: _sectionController.text,
        room: _roomController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add class'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('classNameField'),
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Class name',
                    hintText: 'e.g. Grade 8',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('classSectionField'),
                  controller: _sectionController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    hintText: 'e.g. A or Science',
                    prefixIcon: Icon(Icons.segment_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
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
  const AddTeacherDialog({super.key, required this.subjects});

  /// All subjects sorted with unassigned first.
  final List<Subject> subjects;

  @override
  State<AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  final Set<int> _selectedSubjectIds = {};
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
        width: 460,
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
                TextFormField(
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
                const SizedBox(height: 12),
                TextFormField(
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
                    constraints: const BoxConstraints(maxHeight: 200),
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
  });

  final Teacher teacher;

  /// All subjects sorted with unassigned first.
  final List<Subject> subjects;

  /// IDs of subjects currently assigned to this teacher.
  final Set<int> assignedSubjectIds;

  @override
  State<EditTeacherDialog> createState() => _EditTeacherDialogState();
}

class _EditTeacherDialogState extends State<EditTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final Set<int> _selectedSubjectIds;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.teacher.name);
    _emailController = TextEditingController(text: widget.teacher.email);
    _usernameController = TextEditingController(text: widget.teacher.username);
    _passwordController = TextEditingController(text: widget.teacher.password);
    _selectedSubjectIds = Set<int>.from(widget.assignedSubjectIds);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
        width: 460,
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
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'e.g. teacher01',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
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
                    constraints: const BoxConstraints(maxHeight: 200),
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
  late int _classId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _rollController = TextEditingController();
    _classId = widget.classes.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddStudentResult(
        name: _nameController.text,
        rollNumber: _rollController.text,
        classId: _classId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add student'),
      content: SizedBox(
        width: 420,
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
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('studentClassField'),
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Class'),
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

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }
  return null;
}
