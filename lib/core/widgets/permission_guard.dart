import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/state/rbac_store.dart';

/// Conditionally renders [child] only when the current user holds [permission].
///
/// Rebuilds automatically when the [RBACStore] grants change (e.g. after a role
/// is assigned or a permission grant is edited). Use this to hide UI controls
/// that the user is not authorized to interact with:
///
/// ```dart
/// PermissionGuard(
///   permission: PermissionCodes.studentCreate,
///   child: const AddStudentButton(),
/// )
/// ```
///
/// When the permission is not granted or the user/store is uninitialized,
/// [fallback] is rendered instead (defaults to [const SizedBox.shrink()]).
class PermissionGuard extends StatelessWidget {
  const PermissionGuard({
    super.key,
    required this.permission,
    this.departmentId,
    this.child,
    this.fallback,
  });

  /// The permission code to check (see [PermissionCodes]).
  final String permission;

  /// Optional department id for department-scoped roles (e.g. HOD).
  final String? departmentId;

  /// Rendered when [hasPermission] returns `true`.
  final Widget? child;

  /// Rendered when [hasPermission] returns `false` or the store is uninitialized.
  /// Defaults to [const SizedBox.shrink()].
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    RBACStore? store;
    try {
      store = Provider.of<RBACStore>(context, listen: true);
    } on ProviderNotFoundException {
      store = null;
    }

    if (store == null || !store.isAuthenticated) {
      // Fail closed: unauthorized or uninitialized states never render protected UI.
      return fallback ?? const SizedBox.shrink();
    }

    final granted = store.hasPermission(permission,
        departmentId: departmentId);
    if (granted) return child ?? const SizedBox.shrink();
    return fallback ?? const SizedBox.shrink();
  }
}
