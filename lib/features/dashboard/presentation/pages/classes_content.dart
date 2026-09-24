import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/institute_models.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';
import 'package:attendance_app/features/dashboard/presentation/pages/subjects_content.dart';

/// Admin directory for adding and removing classes.
class ClassesContent extends StatefulWidget {
  const ClassesContent({super.key});

  @override
  State<ClassesContent> createState() => _ClassesContentState();
}

class _ClassesContentState extends State<ClassesContent> {
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

  List<SchoolClass> _filtered(InstituteStore store) {
    final query = _searchQuery.toLowerCase().trim();
    if (query.isEmpty) return store.classes;
    return store.classes
        .where(
          (item) =>
              item.displayName.toLowerCase().contains(query) ||
              item.room.toLowerCase().contains(query),
        )
        .toList();
  }

  Future<void> _confirmDelete(InstituteStore store, SchoolClass item) async {
    final studentCount =
        store.students.where((s) => s.classId == item.id).length;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete class'),
        content: Text(
          studentCount == 0
              ? 'Remove ${item.displayName} from the institute directory?'
              : 'Remove ${item.displayName}? ${studentCount == 1 ? '1 student' : '$studentCount students'} in this class will also be removed.',
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
      await store.deleteClass(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.displayName} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddDialog(InstituteStore store) async {
    final result = await showDialog<AddClassResult>(
      context: context,
      builder: (ctx) => const AddClassDialog(),
    );

    if (result == null || !mounted) return;

    await store.addClass(
      name: result.name,
      section: result.section,
      room: result.room,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Class added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<InstituteStore>();
    final items = _filtered(store);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Classes',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showAddDialog(store),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add class'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${store.classCount} ${store.classCount == 1 ? 'class' : 'classes'} in the institute',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search classes by name or room...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No classes found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final studentCount = store.students
                            .where((s) => s.classId == item.id)
                            .length;
                        final teacherCount = store.teachers
                            .where((t) => t.classId == item.id)
                            .length;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SubjectsContent(
                                    schoolClass: item,
                                  ),
                                ),
                              );
                            },
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.class_rounded,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                            title: Text(
                              item.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${item.room} • $teacherCount teachers • $studentCount students',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Delete class',
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: colorScheme.error,
                                  ),
                                  onPressed: () => _confirmDelete(store, item),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: colorScheme.onSurfaceVariant,
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
