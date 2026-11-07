import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/user_store.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';
import 'package:attendance_app/core/widgets/themed_dropdown.dart';

/// Screen for managing system users, staff allocations, and account security.
/// Accessible ONLY by Admin and HOD roles.
class UserManagementContent extends StatefulWidget {
  const UserManagementContent({super.key});

  @override
  State<UserManagementContent> createState() => _UserManagementContentState();
}

class _UserManagementContentState extends State<UserManagementContent> {
  String _searchQuery = '';
  UserRole? _selectedRoleFilter;
  bool? _selectedSuspensionFilter; // null = all, false = active, true = suspended

  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserStore>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isUserAuthorized(AuthStore authStore, RBACStore rbacStore) {
    final role = authStore.currentUserRole;
    if (role == UserRole.admin ||
        role == UserRole.principal ||
        role == UserRole.vicePrincipal ||
        role == UserRole.hod) {
      return true;
    }
    return rbacStore.hasPermission(PermissionCodes.userView) ||
        rbacStore.hasPermission(PermissionCodes.userCreate);
  }

  bool _isAdmin(AuthStore authStore, RBACStore rbacStore) {
    final role = authStore.currentUserRole;
    return role == UserRole.admin ||
        role == UserRole.principal ||
        role == UserRole.vicePrincipal ||
        rbacStore.currentUserRoles.any((r) => r.isInstituteWide || r.code == 'admin');
  }

  List<User> _filteredUsers(List<User> users) {
    return users.where((user) {
      if (_selectedRoleFilter != null && user.role != _selectedRoleFilter) {
        return false;
      }
      if (_selectedSuspensionFilter != null &&
          user.isSuspended != _selectedSuspensionFilter) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      return user.displayName.toLowerCase().contains(q) ||
          user.username.toLowerCase().contains(q) ||
          (user.rollNo ?? '').toLowerCase().contains(q) ||
          (user.employeeId ?? '').toLowerCase().contains(q) ||
          user.email.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _showCreateUserDialog(
    BuildContext context, {
    required bool isAdmin,
  }) async {
    final instituteStore = context.read<InstituteStore>();
    final userStore = context.read<UserStore>();

    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController();
    final displayNameController = TextEditingController();
    final rollNoController = TextEditingController();
    final employeeIdController = TextEditingController();
    final passwordController = TextEditingController(text: 'Welcome@123');
    final emailController = TextEditingController();

    UserRole selectedRole = isAdmin ? UserRole.teacher : UserRole.student;
    String? selectedDeptId;
    String? selectedClassId;
    bool obscurePassword = true;

    final departments = instituteStore.activeDepartments;
    final classes = instituteStore.classes;

    if (departments.isNotEmpty) {
      selectedDeptId = departments.first.id;
    }
    if (classes.isNotEmpty) {
      selectedClassId = classes.first.id;
    }

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isStudent = selectedRole == UserRole.student;
            final isTeacherOrStaff = selectedRole == UserRole.teacher ||
                selectedRole == UserRole.hod ||
                selectedRole == UserRole.admin;

            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.person_add_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create User Account'),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role selection
                        Text(
                          'Account Role',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 6),
                        AppDropdownButtonFormField<UserRole>(
                          initialValue: selectedRole,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.badge_rounded),
                          ),
                          items: [
                            if (isAdmin) ...[
                              const DropdownMenuItem(
                                value: UserRole.admin,
                                child: Text('Administrator (Full Institute Access)'),
                              ),
                              const DropdownMenuItem(
                                value: UserRole.hod,
                                child: Text('Head of Department (HOD)'),
                              ),
                            ],
                            const DropdownMenuItem(
                              value: UserRole.teacher,
                              child: Text('Teacher / Faculty Member'),
                            ),
                            const DropdownMenuItem(
                              value: UserRole.student,
                              child: Text('Student'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedRole = val);
                            }
                          },
                        ),
                        const SizedBox(height: 14),

                        // Username & Display Name Row
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: usernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Username *',
                                  hintText: 'e.g. cit_teacher1 or 24cit01',
                                  prefixIcon: Icon(Icons.alternate_email_rounded),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Username is required'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: displayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Full Name *',
                                  hintText: 'e.g. Engr. Ahmad Khan',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                                validator: (v) => (v == null || v.trim().isEmpty)
                                    ? 'Full name is required'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Roll No or Employee ID based on role
                        if (isStudent) ...[
                          TextFormField(
                            controller: rollNoController,
                            decoration: const InputDecoration(
                              labelText: 'Roll Number *',
                              hintText: 'e.g. 2024-CIT-01',
                              prefixIcon: Icon(Icons.pin_rounded),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Roll number is required for students'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          AppDropdownButtonFormField<String>(
                            initialValue: selectedClassId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Enrolled Class *',
                              prefixIcon: Icon(Icons.class_outlined),
                            ),
                            items: classes
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.displayName),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setDialogState(() => selectedClassId = val),
                          ),
                          const SizedBox(height: 14),
                        ],

                        if (isTeacherOrStaff) ...[
                          TextFormField(
                            controller: employeeIdController,
                            decoration: const InputDecoration(
                              labelText: 'Employee ID / Faculty Code',
                              hintText: 'e.g. FAC-CIT-01',
                              prefixIcon: Icon(Icons.work_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AppDropdownButtonFormField<String>(
                            initialValue: selectedDeptId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Assigned Department',
                              prefixIcon: Icon(Icons.apartment_rounded),
                            ),
                            items: departments
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text('${d.code} — ${d.name}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setDialogState(() => selectedDeptId = val),
                          ),
                          const SizedBox(height: 14),
                          if (selectedRole == UserRole.teacher) ...[
                            AppDropdownButtonFormField<String?>(
                              initialValue: selectedClassId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Primary Class Assignment (Optional)',
                                prefixIcon: Icon(Icons.class_outlined),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('None (General Faculty)'),
                                ),
                                ...classes.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.displayName),
                                  ),
                                ),
                              ],
                              onChanged: (val) =>
                                  setDialogState(() => selectedClassId = val),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ],

                        // Initial Password
                        TextFormField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Initial Password *',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                              onPressed: () {
                                setDialogState(
                                    () => obscurePassword = !obscurePassword);
                              },
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? 'Password must be at least 6 characters'
                              : null,
                        ),
                        const SizedBox(height: 12),

                        // Security notice container
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: Colors.blue.shade800, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'This account will be flagged with a default password. The user will be required to change it on their first login.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      await userStore.createUser(
                        username: usernameController.text.trim(),
                        displayName: displayNameController.text.trim(),
                        password: passwordController.text,
                        role: selectedRole,
                        rollNo: rollNoController.text.trim(),
                        employeeId: employeeIdController.text.trim(),
                        departmentId: selectedDeptId,
                        classId: selectedClassId,
                        email: emailController.text.trim(),
                        isDefaultPassword: true,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Error creating account: $e'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Create Account'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User account created successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAssignRoleDialog(BuildContext context, User user) async {
    final userStore = context.read<UserStore>();
    UserRole selectedRole = user.role;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Assign Role: ${user.displayName}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select new role for @${user.username}:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  AppDropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.security_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.admin,
                        child: Text('Administrator (admin)'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.hod,
                        child: Text('Head of Department (hod)'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.teacher,
                        child: Text('Teacher (teacher)'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.student,
                        child: Text('Student (student)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedRole = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await userStore.updateUserRole(user.id, selectedRole);
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error updating role: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Update Role'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Role updated to ${selectedRole.value} for ${user.displayName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAssignTeacherDialog(BuildContext context, User user) async {
    final instituteStore = context.read<InstituteStore>();
    final userStore = context.read<UserStore>();

    final departments = instituteStore.activeDepartments;
    final classes = instituteStore.classes;

    String? selectedDeptId;
    String? selectedClassId;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('Assign Teacher: ${user.displayName}'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assign department and primary class for @${user.username}:',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    AppDropdownButtonFormField<String?>(
                      initialValue: selectedDeptId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        prefixIcon: Icon(Icons.apartment_rounded),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Select Department'),
                        ),
                        ...departments.map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text('${d.code} — ${d.name}'),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedDeptId = val),
                    ),
                    const SizedBox(height: 14),
                    AppDropdownButtonFormField<String?>(
                      initialValue: selectedClassId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Primary Class',
                        prefixIcon: Icon(Icons.class_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('None (General Faculty)'),
                        ),
                        ...classes.map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.displayName),
                          ),
                        ),
                      ],
                      onChanged: (val) =>
                          setDialogState(() => selectedClassId = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    try {
                      await userStore.assignTeacher(
                        userId: user.id,
                        departmentId: selectedDeptId,
                        classId: selectedClassId,
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error assigning teacher: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Save Assignments'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Staff assignments updated for ${user.displayName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmToggleSuspension(BuildContext context, User user) async {
    final userStore = context.read<UserStore>();
    final isSuspending = !user.isSuspended;
    final reasonController = TextEditingController(
      text: isSuspending ? 'Administrative hold / Disciplinary action' : '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSuspending ? 'Suspend Account' : 'Reactivate Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSuspending
                  ? 'Are you sure you want to suspend @${user.username} (${user.displayName})? Suspended users cannot log in.'
                  : 'Reactivate @${user.username} (${user.displayName})? The user will immediately regain access to the portal.',
            ),
            if (isSuspending) ...[
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Suspension Reason',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: isSuspending ? Colors.red.shade700 : Colors.green.shade700,
            ),
            child: Text(isSuspending ? 'Suspend' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await userStore.toggleSuspension(
          user.id,
          suspend: isSuspending,
          reason: isSuspending ? reasonController.text.trim() : null,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSuspending
                  ? 'Account @${user.username} suspended.'
                  : 'Account @${user.username} reactivated.',
            ),
            backgroundColor: isSuspending ? Colors.orange.shade800 : Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.principal:
      case UserRole.vicePrincipal:
        return Colors.purple;
      case UserRole.hod:
        return Colors.blue;
      case UserRole.teacher:
        return Colors.teal;
      case UserRole.student:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final authStore = context.watch<AuthStore>();
    final rbacStore = context.watch<RBACStore>();
    final userStore = context.watch<UserStore>();

    final isAuthorized = _isUserAuthorized(authStore, rbacStore);
    final isAdmin = _isAdmin(authStore, rbacStore);

    if (!isAuthorized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Access Restricted',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This screen is accessible ONLY by Institute Administrators and Heads of Department (HOD).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final users = _filteredUsers(userStore.users);
    final totalCount = userStore.users.length;
    final activeCount = userStore.users.where((u) => !u.isSuspended).length;
    final suspendedCount = userStore.users.where((u) => u.isSuspended).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User & Staff Management',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage credentials, assign roles & departments, and enforce account security',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                PermissionGuard(
                  permission: PermissionCodes.userCreate,
                  fallback: FilledButton.icon(
                    onPressed: () =>
                        _showCreateUserDialog(context, isAdmin: isAdmin),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Create User'),
                  ),
                  child: FilledButton.icon(
                    onPressed: () =>
                        _showCreateUserDialog(context, isAdmin: isAdmin),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('Create User'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Summary metrics cards
            Row(
              children: [
                Expanded(
                  child: _metricCard(
                    theme,
                    colorScheme,
                    label: 'Total Accounts',
                    count: totalCount,
                    icon: Icons.people_alt_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    theme,
                    colorScheme,
                    label: 'Active Users',
                    count: activeCount,
                    icon: Icons.check_circle_outline_rounded,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    theme,
                    colorScheme,
                    label: 'Suspended',
                    count: suspendedCount,
                    icon: Icons.block_rounded,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search & Filter controls
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText:
                          'Search by name, username, roll number, or employee ID...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: AppDropdownButtonFormField<UserRole?>(
                    initialValue: _selectedRoleFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Role Filter',
                      prefixIcon: Icon(Icons.filter_list_rounded),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Roles')),
                      DropdownMenuItem(
                          value: UserRole.admin, child: Text('Admins')),
                      DropdownMenuItem(value: UserRole.hod, child: Text('HODs')),
                      DropdownMenuItem(
                          value: UserRole.teacher, child: Text('Teachers')),
                      DropdownMenuItem(
                          value: UserRole.student, child: Text('Students')),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedRoleFilter = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: AppDropdownButtonFormField<bool?>(
                    initialValue: _selectedSuspensionFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.toggle_on_rounded),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Statuses')),
                      DropdownMenuItem(
                          value: false, child: Text('Active Only')),
                      DropdownMenuItem(
                          value: true, child: Text('Suspended Only')),
                    ],
                    onChanged: (val) =>
                        setState(() => _selectedSuspensionFilter = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // User Accounts Table / List
            Expanded(
              child: userStore.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : users.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_search_rounded,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text(
                                'No matching users found.',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: users.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final roleColor = _roleColor(user.role);

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: user.isSuspended
                                      ? Colors.red.withValues(alpha: 0.4)
                                      : colorScheme.outlineVariant,
                                ),
                              ),
                              color: user.isSuspended
                                  ? Colors.red.withValues(alpha: 0.04)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    // Avatar with role badge
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          roleColor.withValues(alpha: 0.2),
                                      child: Text(
                                        user.displayName.isNotEmpty
                                            ? user.displayName[0].toUpperCase()
                                            : user.username[0].toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: roleColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // User details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                user.displayName.isNotEmpty
                                                    ? user.displayName
                                                    : user.username,
                                                style: theme.textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '@${user.username}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: roleColor
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  user.role.value.toUpperCase(),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: roleColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 12,
                                            children: [
                                              if (user.rollNo != null &&
                                                  user.rollNo!.isNotEmpty)
                                                Text(
                                                  'Roll: ${user.rollNo}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              if (user.employeeId != null &&
                                                  user.employeeId!.isNotEmpty)
                                                Text(
                                                  'Emp ID: ${user.employeeId}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              if (user.email.isNotEmpty)
                                                Text(
                                                  user.email,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              if (user.isDefaultPassword)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Default Password',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Colors.amber.shade900,
                                                    ),
                                                  ),
                                                ),
                                              if (user.isSuspended)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Suspended${user.suspendedReason != null ? ': ${user.suspendedReason}' : ''}',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.red.shade900,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Action buttons (Admin only actions guarded)
                                    if (isAdmin) ...[
                                      // Assign Role
                                      IconButton(
                                        icon: const Icon(Icons.security_rounded),
                                        tooltip: 'Assign / Change Role',
                                        onPressed: () => _showAssignRoleDialog(
                                          context,
                                          user,
                                        ),
                                      ),
                                      // If teacher or HOD: assign department / class
                                      if (user.role == UserRole.teacher ||
                                          user.role == UserRole.hod)
                                        IconButton(
                                          icon: const Icon(
                                              Icons.assignment_ind_rounded),
                                          tooltip:
                                              'Assign Department & Primary Class',
                                          onPressed: () =>
                                              _showAssignTeacherDialog(
                                            context,
                                            user,
                                          ),
                                        ),
                                      // Toggle Suspension
                                      IconButton(
                                        icon: Icon(
                                          user.isSuspended
                                              ? Icons.lock_open_rounded
                                              : Icons.block_rounded,
                                          color: user.isSuspended
                                              ? Colors.green
                                              : Colors.red,
                                        ),
                                        tooltip: user.isSuspended
                                            ? 'Reactivate Account'
                                            : 'Suspend Account',
                                        onPressed: () =>
                                            _confirmToggleSuspension(
                                          context,
                                          user,
                                        ),
                                      ),
                                    ],
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

  Widget _metricCard(
    ThemeData theme,
    ColorScheme colorScheme, {
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
