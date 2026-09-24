import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

/// Student roster with admin add and delete actions.
class StudentsContent extends StatefulWidget {
  const StudentsContent({super.key});

  @override
  State<StudentsContent> createState() => _StudentsContentState();
}

class _StudentsContentState extends State<StudentsContent> {
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Student> _filtered(InstituteStore store) {
    if (_searchQuery.trim().isEmpty) return store.students;
    final query = _searchQuery.toLowerCase().trim();
    return store.students
        .where(
          (student) =>
              student.name.toLowerCase().contains(query) ||
              student.rollNumber.toLowerCase().contains(query) ||
              store.classLabel(student.classId).toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _confirmDelete(InstituteStore store, Student student) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete student'),
        content: Text('Remove ${student.name} from the student roster?'),
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
      await store.deleteStudent(student.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${student.name} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddDialog(InstituteStore store) async {
    if (store.classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a class first, then enroll students in it.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final result = await showDialog<AddStudentResult>(
      context: context,
      builder: (ctx) => AddStudentDialog(classes: store.classes),
    );

    if (result == null || !mounted) return;

    await store.addStudent(
      name: result.name,
      rollNumber: result.rollNumber,
      classId: result.classId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Student added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final students = _filtered(store);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Students',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${students.length} ${students.length == 1 ? 'student' : 'students'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddDialog(store),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add student'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search students by name, roll number, or class...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: colorScheme.onSurfaceVariant,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: students.isEmpty
                  ? Center(
                      child: Text(
                        'No students found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: students.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                student.initials,
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              student.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${student.rollNumber} • ${store.classLabel(student.classId)}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete student',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: colorScheme.error,
                              ),
                              onPressed: () => _confirmDelete(store, student),
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
}
