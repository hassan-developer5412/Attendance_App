import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';

/// Dialog shown when Admin/Principal chooses to create a new custom role.
///
/// After creation the new role is seeded into the [RBACStore] cache so that
/// `hasPermission` immediately reflects the new role’s (empty) grant set.
class CreateCustomRoleDialog extends StatefulWidget {
  final RoleRepository roleRepository;
  final RBACStore rbacStore;

  const CreateCustomRoleDialog({
    required this.roleRepository,
    required this.rbacStore,
    super.key,
  });

  @override
  State<CreateCustomRoleDialog> createState() => _CreateCustomRoleDialogState();
}

class _CreateCustomRoleDialogState extends State<CreateCustomRoleDialog> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Custom Role'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Role name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Role code (unique, lowercase)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final name = _nameController.text.trim();
            final code = _codeController.text.trim().toLowerCase();
            final description = _descriptionController.text.trim();
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);
            final auth = context.read<AuthStore>();

            if (name.isEmpty || code.isEmpty) {
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Name and code are required')),
                );
              }
              return;
            }

            // Check code uniqueness.
            final existing = await widget.roleRepository.getByCode(code);
            if (existing != null) {
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text('A role with code "$code" already exists')),
                );
              }
              return;
            }

            await widget.roleRepository.insert(
              name: name,
              code: code,
              description: description,
              isCustom: true,
              isInstituteWide: false,
            );

            // Refresh RBAC cache so hasPermission reflects the new role.
            final user = auth.currentUser;
            if (user != null) {
              await widget.rbacStore.loadForUser(user.id);
            }

            if (mounted) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Custom role created successfully')),
              );
              navigator.pop(true);
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
