import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

/// Staff directory for teachers with admin add, edit, and delete actions,
/// displaying department affiliation, designation, employee code, and assigned subjects with academic context.
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
              teacher.subject.toLowerCase().contains(query) ||
              teacher.designation.toLowerCase().contains(query) ||
              (teacher.employeeCode ?? '').toLowerCase().contains(query),
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
        departments: store.activeDepartments,
        classes: store.classes,
      ),
    );

    if (result == null || !mounted) return;

    await store.addTeacher(
      name: result.name,
      email: result.email,
      username: result.username,
      password: result.password,
      subjectIds: result.subjectIds,
      departmentId: result.departmentId,
      employeeCode: result.employeeCode,
      designation: result.designation,
      classId: result.classId,
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
        .where((s) => s.teacherId == teacher.id || s.teacherName == teacher.name)
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
        departments: store.activeDepartments,
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
      departmentId: result.departmentId,
      employeeCode: result.employeeCode,
      designation: result.designation,
      classId: result.classId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Teacher profile updated'),
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
    final dept = store.departmentById(teacher.departmentId);
    final assignedSubjects = store.subjectsForTeacher(teacher.id);

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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (dept != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  dept.code,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              teacher.designation,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (teacher.employeeCode != null &&
                                teacher.employeeCode!.isNotEmpty) ...[
                              Text(
                                ' • #${teacher.employeeCode}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Contact / Account Info
                  _infoRow(Icons.email_outlined, 'Email', teacher.email),
                  _infoRow(
                      Icons.alternate_email_rounded, 'Username', teacher.username),
                  if (dept != null)
                    _infoRow(Icons.apartment_rounded, 'Department',
                        '${dept.code} — ${dept.name}'),

                  const SizedBox(height: 16),
                  Text(
                    'Assigned Subjects (${assignedSubjects.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (assignedSubjects.isEmpty)
                    Text(
                      'No subjects currently assigned to this faculty member.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...assignedSubjects.map((sub) {
                      final cls = store.classById(sub.classId);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.book_outlined,
                                  size: 18, color: colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${sub.name} (${sub.code})',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      '${cls?.displayName ?? 'Class'} • ${sub.subjectType.label} • ${sub.contactHoursPerWeek.toStringAsFixed(1)} hrs/wk',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 16),
                  const Divider(),
                  ListTile(
                    leading:
                        Icon(Icons.edit_outlined, color: colorScheme.primary),
                    title: const Text('Edit teacher profile'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditDialog(store, teacher);
                    },
                  ),
                  ListTile(
                    leading:
                        Icon(Icons.delete_outline_rounded, color: colorScheme.error),
                    title: const Text('Delete teacher'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _confirmDelete(store, teacher);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
                  'Faculty Directory',
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
                hintText:
                    'Search teachers by name, subject, designation, or code...',
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
                        final dept = store.departmentById(teacher.departmentId);
                        final assignedSubs =
                            store.subjectsForTeacher(teacher.id);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
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
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: Text(
                                      teacher.initials,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color: colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                teacher.name,
                                                style: theme
                                                    .textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (dept != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .secondaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  dept.code,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme
                                                        .onSecondaryContainer,
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(width: 6),
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
                                          '${teacher.designation}${teacher.employeeCode != null && teacher.employeeCode!.isNotEmpty ? ' • Code: ${teacher.employeeCode}' : ''}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          assignedSubs.isEmpty
                                              ? 'No subjects assigned'
                                              : assignedSubs
                                                  .map((s) =>
                                                      '${s.name} (${store.classLabel(s.classId)})')
                                                  .join(', '),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.primary,
                                            fontSize: 11,
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
