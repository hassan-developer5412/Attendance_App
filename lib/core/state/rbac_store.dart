import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/repositories/permission_repository.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/repositories/user_role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Cached RBAC grants for the signed-in user.
///
/// Loaded from the local database by [loadForUser] after a successful login
/// and kept in sync by the RBAC repositories. Exposed to the widget layer
/// (e.g. [PermissionGuard]) via `provider`.
///
/// Example:
/// ```dart
/// Consumer<RBACStore>(
///   builder: (context, store, _) => PermissionGuard(
///     permission: PermissionCodes.studentCreate,
///     child: const AddStudentButton(),
///   ),
/// )
/// ```
class RBACStore extends ChangeNotifier {
  RBACStore({
    RoleRepository? roleRepository,
    UserRoleRepository? userRoleRepository,
    PermissionRepository? permissionRepository,
  })  : _roleRepository = roleRepository ?? RoleRepository(),
        _userRoleRepository = userRoleRepository ?? UserRoleRepository(),
        _permissionRepository = permissionRepository ?? PermissionRepository();

  final RoleRepository _roleRepository;
  final UserRoleRepository _userRoleRepository;
  final PermissionRepository _permissionRepository;

  String? _currentUserId;
  List<Role> _currentUserRoles = const [];
  List<String> _currentUserDepartmentIds = const [];

  /// Id of the signed-in user whose grants are cached, or `null`.
  String? get currentUserId =>
      _currentUserId ?? PermissionService.instance.currentUserId;

  /// Union of permission codes held by the current user's roles. Coarse-grained
  /// — suitable for UI show/hide. Use [hasPermission] for department-accurate
  /// enforcement.
  Set<String> get currentUserPermissions =>
      PermissionService.instance.permissionsForUser(currentUserId);

  /// Roles currently assigned to the signed-in user.
  List<Role> get currentUserRoles => List.unmodifiable(_currentUserRoles);

  /// Departments the signed-in user is scoped to (department-scoped roles such
  /// as HOD).
  List<String> get currentUserDepartmentIds =>
      List.unmodifiable(_currentUserDepartmentIds);

  /// All non-deleted roles in the catalogue.
  List<Role> get roles => PermissionService.instance.roles.toList();

  /// All non-deleted permissions in the catalogue.
  List<Permission> get permissions =>
      PermissionService.instance.permissions.toList();

  /// Whether a user's grants are currently loaded.
  bool get isAuthenticated => currentUserId != null;

  /// Loads the roles, department scopes and permission grants for [userId]
  /// into the [PermissionService] cache and notifies listeners.
  Future<void> loadForUser(String userId) async {
    _currentUserId = userId;
    PermissionService.instance.currentUserId = userId;

    // Load the full role + permission catalogues once.
    final roles = await _roleRepository.getAll();
    final permissions = await _permissionRepository.getAll();
    PermissionService.instance.loadRoles(roles);
    PermissionService.instance.loadPermissions(permissions);

    // Role → permission grants.
    final roleGrants = <String, Set<String>>{};
    for (final role in roles) {
      roleGrants[role.id] =
          await _roleRepository.getPermissionCodesForRole(role.id);
    }
    PermissionService.instance.loadRolePermissions(roleGrants);

    // User → role assignments.
    final assignments = await _userRoleRepository.getAssignmentsForUser(userId);
    final roleIds = assignments
        .where((a) => !a.isDeleted)
        .map((a) => a.roleId)
        .toSet();
    PermissionService.instance.setUserRoles(userId, roleIds);
    _currentUserRoles = roles.where((r) => roleIds.contains(r.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // User → department scopes.
    final depts = await _userRoleRepository.getDepartmentsForUser(userId);
    PermissionService.instance.setUserDepartments(userId, depts);
    _currentUserDepartmentIds = depts.toList()..sort();

    notifyListeners();
  }

  /// Re-loads grants for the current user. No-op when no user is loaded.
  Future<void> refresh() async {
    if (_currentUserId != null) await loadForUser(_currentUserId!);
  }

  /// Clears cached grants. Call on logout.
  void clear() {
    _currentUserId = null;
    PermissionService.instance.currentUserId = null;
    _currentUserRoles = const [];
    _currentUserDepartmentIds = const [];
    PermissionService.instance.reset();
    notifyListeners();
  }

  /// Returns `true` when the current user holds [permission].
  ///
  /// When [departmentId] is supplied, department-scoped roles (e.g. HOD) are
  /// only satisfied if the current user is assigned to that department.
  bool hasPermission(String permission, {String? departmentId}) {
    return PermissionService.instance.hasPermission(
      permission,
      userId: _currentUserId,
      departmentId: departmentId,
    );
  }

  /// Returns `true` when the current user holds *all* of [permissions].
  bool hasAllPermissions(Iterable<String> permissions, {String? departmentId}) {
    return permissions.every(
      (p) => hasPermission(p, departmentId: departmentId),
    );
  }

  /// Returns `true` when the current user holds *any* of [permissions].
  bool hasAnyPermission(Iterable<String> permissions, {String? departmentId}) {
    return permissions.any(
      (p) => hasPermission(p, departmentId: departmentId),
    );
  }
}
