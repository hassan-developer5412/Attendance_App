import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/models/user.dart';
import 'package:attendance_app/core/repositories/permission_repository.dart';
import 'package:attendance_app/core/repositories/role_repository.dart';
import 'package:attendance_app/core/repositories/user_repository.dart';
import 'package:attendance_app/core/repositories/user_role_repository.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Cached RBAC grants for the signed-in user.
///
/// Loaded from the local database by [loadForUser] after a successful login
/// and kept in sync by the RBAC repositories. Exposed to the widget layer
/// (e.g. [PermissionGuard]) via `provider`.
///
/// Enforces strict fail-closed checks: if `currentUserId == null`, the user is
/// suspended, or the store is unauthenticated/unloaded, all permission checks
/// ([hasPermission], [hasAnyPermission], [hasAllPermissions]) immediately
/// return `false`.
class RBACStore extends ChangeNotifier {
  RBACStore({
    RoleRepository? roleRepository,
    UserRoleRepository? userRoleRepository,
    PermissionRepository? permissionRepository,
    UserRepository? userRepository,
  })  : _roleRepository = roleRepository ?? RoleRepository(),
        _userRoleRepository = userRoleRepository ?? UserRoleRepository(),
        _permissionRepository = permissionRepository ?? PermissionRepository(),
        _userRepository = userRepository ?? UserRepository();

  final RoleRepository _roleRepository;
  final UserRoleRepository _userRoleRepository;
  final PermissionRepository _permissionRepository;
  final UserRepository _userRepository;

  String? _currentUserId;
  bool _isLoaded = false;
  bool? _overrideIsLoaded;
  bool _isSuspended = false;
  List<Role> _currentUserRoles = const [];
  List<String> _currentUserDepartmentIds = const [];

  /// Id of the signed-in user whose grants are cached, or `null`.
  String? get currentUserId =>
      _currentUserId ?? PermissionService.instance.currentUserId;

  /// Union of permission codes held by the current user's roles. Coarse-grained
  /// — suitable for UI show/hide. Use [hasPermission] for department-accurate
  /// enforcement.
  Set<String> get currentUserPermissions {
    if (currentUserId == null ||
        !isAuthenticated ||
        !isLoaded ||
        isSuspended) {
      return const <String>{};
    }
    return PermissionService.instance.permissionsForUser(currentUserId);
  }

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

  /// Whether a user's session is currently authenticated and active.
  bool get isAuthenticated => currentUserId != null && !isSuspended;

  /// Whether grants are currently loaded for the authenticated user.
  bool get isLoaded =>
      _overrideIsLoaded ??
      (_isLoaded ||
          (_currentUserId != null) ||
          (PermissionService.instance.currentUserId != null));

  set isLoaded(bool value) {
    _overrideIsLoaded = value;
    _isLoaded = value;
    notifyListeners();
  }

  /// Whether the current user is marked as suspended.
  bool get isSuspended =>
      _isSuspended ||
      (currentUserId != null &&
          PermissionService.instance.isUserSuspended(currentUserId!));

  set isSuspended(bool value) {
    _isSuspended = value;
    final uid = currentUserId;
    if (uid != null) {
      PermissionService.instance.setUserSuspended(uid, value);
    }
    notifyListeners();
  }

  /// Loads the roles, department scopes and permission grants for [userId]
  /// into the [PermissionService] cache and notifies listeners.
  Future<void> loadForUser(
    String userId, {
    User? user,
    bool isSuspended = false,
  }) async {
    _currentUserId = userId;
    PermissionService.instance.currentUserId = userId;
    _overrideIsLoaded = false;
    _isLoaded = false;

    // Check user suspension status
    bool userSuspended = isSuspended || (user?.isSuspended ?? false);
    if (!userSuspended) {
      try {
        final dbUser = await _userRepository.getById(userId);
        if (dbUser != null && dbUser.isSuspended) {
          userSuspended = true;
        }
      } catch (_) {
        userSuspended = PermissionService.instance.isUserSuspended(userId);
      }
    }
    _isSuspended = userSuspended;
    PermissionService.instance.setUserSuspended(userId, userSuspended);

    if (userSuspended) {
      _currentUserRoles = const [];
      _currentUserDepartmentIds = const [];
      _isLoaded = true;
      _overrideIsLoaded = null;
      notifyListeners();
      return;
    }

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

    _isLoaded = true;
    _overrideIsLoaded = null;
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
    _isLoaded = false;
    _overrideIsLoaded = null;
    _isSuspended = false;
    PermissionService.instance.reset();
    notifyListeners();
  }

  /// Returns `true` when the current user holds [permission].
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if
  /// `currentUserId == null`, the user is suspended, or the store is
  /// unauthenticated/unloaded.
  ///
  /// When [departmentId] is supplied, department-scoped roles (e.g. HOD, Lab
  /// In-Charge, Assistant and custom department roles) are only satisfied if
  /// the current user is assigned to that department, unless the caller is the
  /// record owner (`ownerUserId != null && ownerUserId == currentUserId`).
  ///
  /// [classId] is accepted for signature compatibility and reserved for future
  /// class-level scoping. When [userId] is supplied it overrides the effective
  /// user id passed through to [PermissionService.hasPermission].
  bool hasPermission(
    String permission, {
    String? userId,
    String? departmentId,
    String? classId,
    String? ownerUserId,
  }) {
    if (currentUserId == null ||
        !isAuthenticated ||
        !isLoaded ||
        isSuspended) {
      return false;
    }
    return PermissionService.instance.hasPermission(
      permission,
      userId: userId ?? currentUserId,
      departmentId: departmentId,
      classId: classId,
      ownerUserId: ownerUserId,
    );
  }

  /// Returns `true` when the current user holds *all* of [permissions].
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if
  /// `currentUserId == null`, the user is suspended, the store is
  /// unauthenticated/unloaded, or [permissions] is empty.
  bool hasAllPermissions(Iterable<String> permissions, {String? departmentId}) {
    if (currentUserId == null ||
        !isAuthenticated ||
        !isLoaded ||
        isSuspended ||
        permissions.isEmpty) {
      return false;
    }
    return permissions.every(
      (p) => hasPermission(p, departmentId: departmentId),
    );
  }

  /// Returns `true` when the current user holds *any* of [permissions].
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if
  /// `currentUserId == null`, the user is suspended, the store is
  /// unauthenticated/unloaded, or [permissions] is empty.
  bool hasAnyPermission(Iterable<String> permissions, {String? departmentId}) {
    if (currentUserId == null ||
        !isAuthenticated ||
        !isLoaded ||
        isSuspended ||
        permissions.isEmpty) {
      return false;
    }
    return permissions.any(
      (p) => hasPermission(p, departmentId: departmentId),
    );
  }
}
