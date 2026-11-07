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
/// When the permission is not granted, [fallback] is rendered instead
/// (defaults to an empty [SizedBox.shrink]).
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

  /// Rendered when [hasPermission] returns `false`. Defaults to an empty box.
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
      // If no RBACStore is present in the tree or no user is logged in
      // (e.g. isolated widget tests), permit display.
      return child ?? const SizedBox.shrink();
    }

    final granted = store.hasPermission(permission,
        departmentId: departmentId);
    if (granted) return child ?? const SizedBox.shrink();
    return fallback ??
        _PermissionDeniedPlaceholder(permission: permission);
  }
}

/// Subtle placeholder rendered in place of a guarded control the user may not
/// access. Kept intentionally low-key so it never leaks sensitive information.
class _PermissionDeniedPlaceholder extends StatelessWidget {
  const _PermissionDeniedPlaceholder({required this.permission});

  final String permission;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints.tightFor(height: 36),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.25),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'No permission: $permission',
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}
