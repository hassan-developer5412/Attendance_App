library;

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';

/// Thrown by repositories when a data call is attempted without the required
/// permission. Repositories must check `PermissionService.hasPermission` before
/// executing mutating (and, where configured, read) operations.
class PermissionDeniedException implements Exception {
  /// The permission code that was missing.
  final String permissionCode;

  /// The user id that was checked (null when no current user is set).
  final String? userId;

  /// The department id that was checked, when a department-scoped call was made.
  final String? departmentId;

  const PermissionDeniedException(
    this.permissionCode, {
    this.userId,
    this.departmentId,
  });

  @override
  String toString() {
    return 'PermissionDeniedException: $permissionCode '
        '(userId: $userId, departmentId: $departmentId)';
  }
}

/// Role-based access control engine.
///
/// Holds an in-memory copy of permissions, roles, role→permission grants,
/// user→role assignments and user→department scopes, and evaluates
/// [hasPermission]. Grants are loaded from the local database by
/// [RBACStore] on login and kept in sync by the RBAC repositories.
///
/// Authority rules:
///   * Roles marked [Role.isInstituteWide] (Admin, Principal, Vice Principal)
///     have institute-wide admin authority and bypass department scoping.
///   * HOD permissions are restricted to their assigned department by default.
///   * Only Admin or Principal/VP can assign or modify user roles.
///   * A user holds a permission when any of their assigned roles grants it
///     and authority rules are satisfied.
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  // permissions by id
  final Map<String, Permission> _permissions = <String, Permission>{};
  // permissions by code
  final Map<String, Permission> _permissionsByCode = <String, Permission>{};
  // roles by id
  final Map<String, Role> _roles = <String, Role>{};
  // roles by code
  final Map<String, Role> _rolesByCode = <String, Role>{};
  // roleId -> Set<permissionCode>
  final Map<String, Set<String>> _rolePermissions = <String, Set<String>>{};
  // userId -> Set<roleId>
  final Map<String, Set<String>> _userRoles = <String, Set<String>>{};
  // userId -> Set<departmentId>
  final Map<String, Set<String>> _userDepartments = <String, Set<String>>{};

  /// Id of the signed-in user, used when [hasPermission] is called without an
  /// explicit [userId]. Set by [RBACStore] after login; cleared on logout.
  String? currentUserId;

  // -----------------------------------------------------------------------
  // Bulk loaders (used by RBACStore after authentication)
  // -----------------------------------------------------------------------

  /// Replaces the in-memory permission catalogue.
  void loadPermissions(Iterable<Permission> permissions) {
    _permissions.clear();
    _permissionsByCode.clear();
    for (final p in permissions) {
      if (p.isDeleted) continue;
      _permissions[p.id] = p;
      _permissionsByCode[p.code] = p;
    }
  }

  /// Replaces the in-memory role catalogue.
  void loadRoles(Iterable<Role> roles) {
    _roles.clear();
    _rolesByCode.clear();
    for (final r in roles) {
      if (r.isDeleted) continue;
      _roles[r.id] = r;
      _rolesByCode[r.code] = r;
    }
  }

  /// Replaces role→permission grants (roleId -> permission codes).
  void loadRolePermissions(Map<String, Iterable<String>> grants) {
    _rolePermissions.clear();
    for (final entry in grants.entries) {
      _rolePermissions[entry.key] = Set<String>.from(entry.value);
    }
  }

  /// Sets the roles assigned to [userId].
  void setUserRoles(String userId, Iterable<String> roleIds) {
    _userRoles[userId] = Set<String>.from(roleIds);
  }

  /// Sets the departments [userId] is scoped to (department-scoped roles).
  void setUserDepartments(String userId, Iterable<String> departmentIds) {
    _userDepartments[userId] = Set<String>.from(departmentIds);
  }

  /// Clears all cached grants and the current user. Call on logout.
  void reset() {
    _permissions.clear();
    _permissionsByCode.clear();
    _roles.clear();
    _rolesByCode.clear();
    _rolePermissions.clear();
    _userRoles.clear();
    _userDepartments.clear();
    currentUserId = null;
  }

  // -----------------------------------------------------------------------
  // Incremental grant mutations (kept in sync with repository writes)
  // -----------------------------------------------------------------------

  void _ensureRole(String roleId) =>
      _rolePermissions.putIfAbsent(roleId, () => <String>{});

  /// Grants [permissionCode] to [roleId] (in-memory; persist via repository).
  void grantPermissionToRole(String roleId, String permissionCode) {
    _ensureRole(roleId);
    _rolePermissions[roleId]!.add(permissionCode);
  }

  /// Revokes [permissionCode] from [roleId] (in-memory; persist via repository).
  void revokePermissionFromRole(String roleId, String permissionCode) {
    _rolePermissions[roleId]?.remove(permissionCode);
  }

  /// Assigns [roleId] to [userId] (in-memory; persist via repository).
  void assignRoleToUser(String userId, String roleId) {
    _userRoles.putIfAbsent(userId, () => <String>{}).add(roleId);
  }

  /// Revokes [roleId] from [userId] (in-memory; persist via repository).
  void revokeRoleFromUser(String userId, String roleId) {
    _userRoles[userId]?.remove(roleId);
  }

  // -----------------------------------------------------------------------
  // Evaluation
  // -----------------------------------------------------------------------

  /// Returns `true` when the user holds [permissionCode].
  ///
  /// Authority rules:
  ///   * Principal/Vice Principal & Admin have institute-wide admin authority
  ///     and bypass department scoping.
  ///   * HOD permissions are restricted to their assigned department by default.
  ///   * When [userId] is omitted, [currentUserId] is used.
  bool hasPermission(
    String permissionCode, {
    String? userId,
    String? departmentId,
  }) {
    final uid = userId ?? currentUserId;
    if (uid == null) return false;

    final roleIds = _userRoles[uid];
    if (roleIds == null || roleIds.isEmpty) return false;

    for (final roleId in roleIds) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      if (role == null || role.isDeleted) continue;

      // 1. Institute-wide admin authority (Admin, Principal, Vice Principal):
      //    Holds institute-wide authority across all departments and modules.
      if (role.isInstituteWide || Role.isCodeInstituteWide(role.code)) {
        return true;
      }

      // 2. Check if this role grants the requested permission code.
      final codes = _rolePermissions[roleId] ?? _rolePermissions[role.id];
      if (codes == null || !codes.contains(permissionCode)) continue;

      // 3. Department scoping for HOD:
      //    HOD permissions are restricted to their assigned department by default.
      if (role.code == 'hod') {
        if (departmentId != null) {
          final depts = _userDepartments[uid];
          if (depts != null && depts.contains(departmentId)) {
            return true;
          }
          // Wrong department for HOD; check other roles if any.
          continue;
        } else {
          // Without specific department constraint, HOD holds the permission.
          return true;
        }
      }

      // 4. Other non-institute-wide roles (Teacher, Student, Parent, etc.)
      return true;
    }

    return false;
  }

  /// Returns whether the user has role-management authority (Admin, Principal, or Vice Principal).
  bool canManageRoles({String? userId}) {
    final uid = userId ?? currentUserId;
    if (uid == null) return false;

    final roleIds = _userRoles[uid];
    if (roleIds == null || roleIds.isEmpty) return false;

    for (final roleId in roleIds) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      if (role == null || role.isDeleted) continue;
      if (role.isInstituteWide ||
          role.code == 'admin' ||
          role.code == 'principal' ||
          role.code == 'vice_principal') {
        return true;
      }
    }
    return false;
  }

  /// The union of permission codes held by [userId]'s roles. Coarse-grained:
  /// suitable for UI show/hide decisions. Use [hasPermission] for
  /// department-accurate enforcement.
  Set<String> permissionsForUser(String? userId) {
    final uid = userId ?? currentUserId;
    if (uid == null) return <String>{};

    final roleIds = _userRoles[uid];
    if (roleIds == null || roleIds.isEmpty) return <String>{};

    for (final roleId in roleIds) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      if (role != null &&
          !role.isDeleted &&
          (role.isInstituteWide || Role.isCodeInstituteWide(role.code))) {
        // Institute-wide admin holds all registered permissions.
        return _permissionsByCode.keys.toSet();
      }
    }

    final codes = <String>{};
    for (final roleId in roleIds) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      if (role == null || role.isDeleted) continue;
      final roleCodes = _rolePermissions[roleId] ?? _rolePermissions[role.id];
      if (roleCodes != null) codes.addAll(roleCodes);
    }
    return codes;
  }

  /// Role ids currently assigned to [userId] (or current user).
  Set<String> roleIdsForUser(String? userId) {
    final uid = userId ?? currentUserId;
    return _userRoles[uid] ?? <String>{};
  }

  /// Department ids [userId] (or current user) is scoped to.
  Set<String> departmentIdsForUser(String? userId) {
    final uid = userId ?? currentUserId;
    return _userDepartments[uid] ?? <String>{};
  }

  /// Roles currently in the catalogue (non-deleted).
  Iterable<Role> get roles => _roles.values.where((r) => !r.isDeleted);

  /// Permissions currently in the catalogue (non-deleted).
  Iterable<Permission> get permissions =>
      _permissionsByCode.values.where((p) => !p.isDeleted);

  Permission? permissionByCode(String code) => _permissionsByCode[code];
  Role? roleById(String id) => _roles[id];
  Role? roleByCode(String code) => _rolesByCode[code];
}
