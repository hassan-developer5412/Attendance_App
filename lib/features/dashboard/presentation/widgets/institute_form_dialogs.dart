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
    required this.subject,
    required this.classId,
  });

  final String name;
  final String subject;
  final int? classId;
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
  const AddTeacherDialog({super.key, required this.classes});

  final List<SchoolClass> classes;

  @override
  State<AddTeacherDialog> createState() => _AddTeacherDialogState();
}

class _AddTeacherDialogState extends State<AddTeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late int? _classId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _subjectController = TextEditingController();
    _classId = widget.classes.isEmpty ? null : widget.classes.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      AddTeacherResult(
        name: _nameController.text,
        subject: _subjectController.text,
        classId: _classId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add teacher'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  key: const Key('teacherSubjectField'),
                  controller: _subjectController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g. Mathematics',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('teacherClassField'),
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Assigned class',
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
                  onChanged: (value) => _classId = value,
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
