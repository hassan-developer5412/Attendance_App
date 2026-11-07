import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/features/rbac/presentation/create_custom_role_dialog.dart';
import 'package:attendance_app/features/rbac/presentation/permission_grant_editor.dart';

/// Screen for Admin/Principal to edit role-permission grants and create custom roles.
class RoleManagementScreen extends StatefulWidget {
  final RoleRepository? roleRepository;

  const RoleManagementScreen({super.key, this.roleRepository});

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  late final RoleRepository _roleRepository;
  bool _isLoading = true;
  List<Role> _roles = [];
  Map<String, Set<String>> _grantsByRole = {};

  @override
  void initState() {
    super.initState();
    _roleRepository = widget.roleRepository ?? RoleRepository();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final roles = await _roleRepository.getAll();
      final grants = <String, Set<String>>{};
      for (final role in roles) {
        grants[role.id] =
            await _roleRepository.getPermissionCodesForRole(role.id);
      }
      if (mounted) {
        setState(() {
          _roles = roles;
          _grantsByRole = grants;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load roles: $e')),
        );
      }
    }
  }

  Future<void> _handleToggle(String roleId, String permissionCode) async {
    final currentSet = _grantsByRole[roleId] ?? <String>{};
    final isGranted = currentSet.contains(permissionCode);

    final auth = context.read<AuthStore>();
    final rbac = context.read<RBACStore>();

    try {
      if (isGranted) {
        await _roleRepository.revokePermission(roleId, permissionCode);
        currentSet.remove(permissionCode);
      } else {
        await _roleRepository.grantPermission(roleId, permissionCode);
        currentSet.add(permissionCode);
      }

      if (mounted) {
        setState(() {
          _grantsByRole[roleId] = Set<String>.from(currentSet);
        });
      }

      // Synchronize RBAC store for current user
      if (auth.currentUser != null) {
        await rbac.loadForUser(auth.currentUser!.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update permission: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RBACStore>();
    final canManage = rbac.hasPermission(PermissionCodes.userManageRoles) ||
        PermissionService.instance.canManageRoles();

    if (!canManage) {
      return Scaffold(
        appBar: AppBar(title: const Text('Access Denied')),
        body: const Center(
          child: Text(
            'Unauthorized: only Admin/Principal/VP may manage roles.',
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Role & Permission Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create custom role',
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (_) => CreateCustomRoleDialog(
                  roleRepository: _roleRepository,
                  rbacStore: rbac,
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : PermissionGrantEditor(
              roles: _roles,
              grantsByRole: _grantsByRole,
              onToggle: _handleToggle,
            ),
    );
  }
}
