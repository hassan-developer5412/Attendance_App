import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

/// Student roster with admin add, promote/move, and delete actions.
/// Displays academic context: Department, Academic Session, Class Name, and Current Year (e.g. CIT-3rd Year).
class StudentsContent extends StatefulWidget {
  const StudentsContent({super.key});

  @override
  State<StudentsContent> createState() => _StudentsContentState();
}

class _StudentsContentState extends State<StudentsContent> {
  String _searchQuery = '';
  int? _filterClassId;
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
    var list = store.students;

    if (_filterClassId != null) {
      list = list.where((s) => s.classId == _filterClassId).toList();
    }

    if (_searchQuery.trim().isEmpty) return list;
    final query = _searchQuery.toLowerCase().trim();
    return list
        .where(
          (student) =>
              student.name.toLowerCase().contains(query) ||
              student.rollNumber.toLowerCase().contains(query) ||
              (student.registrationNo ?? '').toLowerCase().contains(query) ||
              (student.fatherName.toLowerCase().contains(query)) ||
              store.classLabel(student.classId).toLowerCase().contains(query) ||
              student.currentYear.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _confirmDelete(InstituteStore store, Student student) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete student'),
        content: Text(
          'Remove ${student.name} (${student.rollNumber}) from the student roster?',
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
          content: Text('Please add a class first, then enroll students in it.'),
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
      registrationNo: result.registrationNo,
      fatherName: result.fatherName,
      departmentId: result.departmentId,
      academicSessionId: result.academicSessionId,
      currentYear: result.currentYear,
      status: result.status,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Student added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showPromoteDialog(InstituteStore store, Student student) async {
    final result = await showDialog<PromoteStudentResult>(
      context: context,
      builder: (ctx) => PromoteStudentDialog(
        student: student,
        classes: store.classes,
        sessions: store.academicSessions,
      ),
    );

    if (result == null || !mounted) return;

    await store.promoteOrMoveStudent(
      studentId: student.id,
      newClassId: result.newClassId,
      newYear: result.newYear,
      newAcademicSessionId: result.newAcademicSessionId,
      newDepartmentId: result.newDepartmentId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${student.name} advanced to ${result.newYear} (${store.classLabel(result.newClassId)})',
        ),
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
            const SizedBox(height: 14),

            // Search and Class Filter Row
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
                    decoration: InputDecoration(
                      hintText:
                          'Search by name, roll number, registration, or year...',
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
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _filterClassId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Class',
                      prefixIcon: Icon(Icons.class_outlined),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Classes'),
                      ),
                      ...store.classes.map(
                        (c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(
                            c.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _filterClassId = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

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
                        final cls = store.classById(student.classId);
                        final dept = store.departmentById(student.departmentId ??
                            cls?.departmentId);
                        final session = store.academicSessionById(
                            student.academicSessionId ??
                                cls?.academicSessionId);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      colorScheme.primaryContainer,
                                  child: Text(
                                    student.initials,
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              student.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
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
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Roll: ${student.rollNumber}${student.registrationNo != null ? ' • Reg: ${student.registrationNo}' : ''}${student.fatherName.isNotEmpty ? ' • S/O: ${student.fatherName}' : ''}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          Text(
                                            cls?.displayName ??
                                                store.classLabel(student.classId),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                          if (session != null)
                                            Text(
                                              '• Session: ${session.name}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Promote / Change Year',
                                  icon: Icon(
                                    Icons.upgrade_rounded,
                                    color: colorScheme.primary,
                                  ),
                                  onPressed: () =>
                                      _showPromoteDialog(store, student),
                                ),
                                IconButton(
                                  tooltip: 'Delete student',
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: colorScheme.error,
                                  ),
                                  onPressed: () =>
                                      _confirmDelete(store, student),
                                ),
                              ],
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
