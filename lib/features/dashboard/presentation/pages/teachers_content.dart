import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

/// Staff directory for teachers with admin add and delete actions.
class TeachersContent extends StatefulWidget {
  const TeachersContent({super.key});

  @override
  State<TeachersContent> createState() => _TeachersContentState();
}

class _TeachersContentState extends State<TeachersContent> {
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

  List<Teacher> _filtered(InstituteStore store) {
    if (_searchQuery.trim().isEmpty) return store.teachers;
    final query = _searchQuery.toLowerCase().trim();
    return store.teachers
        .where(
          (teacher) =>
              teacher.name.toLowerCase().contains(query) ||
              teacher.subject.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _confirmDelete(InstituteStore store, Teacher teacher) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete teacher'),
        content: Text('Remove ${teacher.name} from the staff directory?'),
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
      await store.deleteTeacher(teacher.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${teacher.name} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddDialog(InstituteStore store) async {
    final result = await showDialog<AddTeacherResult>(
      context: context,
      builder: (ctx) => AddTeacherDialog(
        subjects: store.subjectsSortedByAssignment,
      ),
    );

    if (result == null || !mounted) return;

    await store.addTeacher(
      name: result.name,
      email: result.email,
      username: result.username,
      password: result.password,
      subjectIds: result.subjectIds,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teacher added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Returns the IDs of subjects currently assigned to a given teacher.
  Set<int> _assignedSubjectIds(InstituteStore store, Teacher teacher) {
    return store.subjects
        .where((s) => s.teacherName == teacher.name)
        .map((s) => s.id)
        .toSet();
  }

  Future<void> _showEditDialog(InstituteStore store, Teacher teacher) async {
    final result = await showDialog<EditTeacherResult>(
      context: context,
      builder: (ctx) => EditTeacherDialog(
        teacher: teacher,
        subjects: store.subjectsSortedByAssignment,
        assignedSubjectIds: _assignedSubjectIds(store, teacher),
      ),
    );

    if (result == null || !mounted) return;

    await store.updateTeacher(
      id: teacher.id,
      name: result.name,
      email: result.email,
      username: result.username,
      password: result.password,
      subjectIds: result.subjectIds,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teacher updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTeacherDetails(
    BuildContext context,
    InstituteStore store,
    Teacher teacher,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    teacher.initials,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  teacher.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  teacher.subject.isEmpty
                      ? 'No subjects assigned'
                      : teacher.subject,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  teacher.isActive ? 'Active Teacher' : 'Inactive Teacher',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: teacher.isActive ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.edit_outlined, color: colorScheme.primary),
                  title: const Text('Edit teacher'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditDialog(store, teacher);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                  title: const Text('Delete teacher'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _confirmDelete(store, teacher);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final teachers = _filtered(store);

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
                  'Teachers',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${teachers.length} ${teachers.length == 1 ? 'teacher' : 'teachers'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddDialog(store),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add teacher'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search teachers by name or subject...',
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
                        tooltip: 'Clear search',
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
              child: teachers.isEmpty
                  ? Center(
                      child: Text(
                        'No teachers found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: teachers.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (context, index) {
                        final teacher = teachers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                _showTeacherDetails(context, store, teacher),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: colorScheme.primaryContainer,
                                    child: Text(
                                      teacher.initials,
                                      style: theme.textTheme.titleMedium?.copyWith(
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
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                teacher.name,
                                                style: theme.textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: teacher.isActive
                                                    ? Colors.green
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          teacher.subject.isEmpty
                                              ? 'No subjects assigned'
                                              : teacher.subject,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit teacher',
                                    icon: Icon(
                                      Icons.edit_outlined,
                                      color: colorScheme.primary,
                                    ),
                                    onPressed: () =>
                                        _showEditDialog(store, teacher),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete teacher',
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: colorScheme.error,
                                    ),
                                    onPressed: () =>
                                        _confirmDelete(store, teacher),
                                  ),
                                ],
                              ),
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
