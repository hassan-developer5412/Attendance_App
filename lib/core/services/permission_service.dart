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
///   * Strict fail-closed: unauthenticated users (`currentUserId == null`) and
///     suspended users immediately fail all permission checks.
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
  // Set of suspended user ids
  final Set<String> _suspendedUserIds = <String>{};

  /// Id of the signed-in user, used when permission checks are called without an
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

  /// Sets whether [userId] is suspended.
  void setUserSuspended(String userId, bool isSuspended) {
    if (isSuspended) {
      _suspendedUserIds.add(userId);
    } else {
      _suspendedUserIds.remove(userId);
    }
  }

  /// Returns whether [userId] (or [currentUserId] if omitted) is suspended.
  bool isUserSuspended([String? userId]) {
    final uid = userId ?? currentUserId;
    if (uid == null) return false;
    return _suspendedUserIds.contains(uid);
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
    _suspendedUserIds.clear();
    currentUserId = null;
    _syncBypassActive = false;
  }

  // -----------------------------------------------------------------------
  // Sync bypass (SyncService only)
  // -----------------------------------------------------------------------

  /// `true` only while [SyncService] is applying a remote RBAC pull inside
  /// [withSyncBypass]. While set, RBAC write guards ([canManageRoles]) do not
  /// reject the sync writer: Supabase is the source of truth for RBAC data,
  /// so a teacher/student device may still persist remotely-pulled roles,
  /// permissions and assignments even though the logged-in device user
  /// lacks admin write permissions.
  ///
  /// Normal app code cannot lower the write guards through this API, and the
  /// flag is always reset in a `finally` block, so ordinary writes remain
  /// strictly fail-closed.
  bool _syncBypassActive = false;

  /// Whether a sync-bypass run is currently in progress (read-only).
  bool get isSyncBypassActive => _syncBypassActive;

  /// Runs [action] with the sync-bypass flag held and **always** resets it in
  /// a `finally` block, even if [action] throws. Only [SyncService] may call
  /// this, and only while pulling/upserting remote RBAC tables.
  Future<T> withSyncBypass<T>(Future<T> Function() action) async {
    _syncBypassActive = true;
    try {
      return await action();
    } finally {
      _syncBypassActive = false;
    }
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
  ///   * Department-scoped staff roles (HOD, Lab In-Charge, Assistant and
  ///     custom department roles) are restricted to the user's assigned
  ///     departments when [departmentId] is supplied, unless the caller is the
  ///     record owner (`ownerUserId != null && ownerUserId == effectiveUserId`).
  ///   * When [userId] is omitted, [currentUserId] is used.
  ///   * [classId] is accepted for signature compatibility and reserved for
  ///     future class-level scoping.
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if the
  /// resolved user id is null or the user is marked as suspended.
  bool hasPermission(
    String permissionCode, {
    String? userId,
    String? departmentId,
    String? classId,
    String? ownerUserId,
  }) {
    // Resolve the effective user id. Fail-closed when no user is known.
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid)) return false;

    final roleIds = _userRoles[uid];
    if (roleIds == null || roleIds.isEmpty) return false;

    final userDepartments = _userDepartments[uid] ?? <String>{};

    // Whether any active (non-deleted) assigned role is institute-wide.
    final hasInstituteWideAuthority = roleIds.any((roleId) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      return role != null &&
          !role.isDeleted &&
          (role.isInstituteWide || Role.isCodeInstituteWide(role.code));
    });

    // A user acting on their own record bypasses department scoping.
    final isRecordOwner = ownerUserId != null && ownerUserId == uid;

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

      // 3. Department scoping for non-institute-wide staff roles
      //    (HOD, Lab In-Charge, Assistant and custom department roles).
      //    Enforced only when a department constraint is supplied, the user has
      //    no institute-wide authority, and the caller is not the record owner.
      if (departmentId != null &&
          !hasInstituteWideAuthority &&
          !isRecordOwner &&
          _isDepartmentScopedStaffRole(role)) {
        if (!userDepartments.contains(departmentId)) {
          // Wrong department for this role; check other roles if any.
          continue;
        }
        return true;
      }

      // 4. Other non-institute-wide roles (Teacher, Student, Parent, etc.)
      return true;
    }

    return false;
  }

  /// Throws [PermissionDeniedException] unless the user holds [permissionCode].
  ///
  /// Enforces strict fail-closed checks: unauthenticated (`currentUserId == null`)
  /// and suspended users immediately throw [PermissionDeniedException].
  void requirePermission(
    String permissionCode, {
    String? userId,
    String? departmentId,
    String? classId,
    String? ownerUserId,
  }) {
    final uid = userId ?? currentUserId;
    if (!hasPermission(
      permissionCode,
      userId: uid,
      departmentId: departmentId,
      classId: classId,
      ownerUserId: ownerUserId,
    )) {
      throw PermissionDeniedException(
        permissionCode,
        userId: uid,
        departmentId: departmentId,
      );
    }
  }

  /// Returns `true` when [userId] (or [currentUserId]) is allowed to access
  /// [departmentId].
  ///
  /// Authority rules:
  ///   * Unauthenticated (`currentUserId == null`), suspended users, and users
  ///     with no active roles fail closed (`false`).
  ///   * Institute-wide roles (Admin, Principal, Vice Principal) bypass
  ///     department scoping and return `true`.
  ///   * When [departmentId] is `null` or empty, returns `true` for
  ///     authenticated non-suspended users with an active role.
  ///   * Non-institute-wide users (HOD, Teacher, Lab In-Charge, Assistant,
  ///     custom roles) must have [departmentId] in their assigned departments.
  bool canAccessDepartment(String? departmentId, {String? userId}) {
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid)) return false;

    final roleIds = _userRoles[uid];
    if (roleIds == null || roleIds.isEmpty) return false;

    final hasInstituteWide = roleIds.any((roleId) {
      final role = _roles[roleId] ?? _rolesByCode[roleId];
      return role != null &&
          !role.isDeleted &&
          (role.isInstituteWide || Role.isCodeInstituteWide(role.code));
    });
    if (hasInstituteWide) return true;

    if (departmentId == null || departmentId.isEmpty) return true;

    final userDepartments = _userDepartments[uid] ?? const <String>{};
    return userDepartments.contains(departmentId);
  }

  /// Whether [role] is a department-scoped staff role whose grants are
  /// limited to the user's assigned departments.
  static bool _isDepartmentScopedStaffRole(Role role) {
    return role.code == 'hod' ||
        role.code == 'lab_in_charge' ||
        role.code == 'assistant' ||
        role.isCustom;
  }

  /// Returns `true` when the user holds *all* of [permissions].
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if the
  /// resolved user id is null, the user is suspended, or [permissions] is empty.
  bool hasAllPermissions(
    Iterable<String> permissions, {
    String? userId,
    String? departmentId,
  }) {
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid) || permissions.isEmpty) {
      return false;
    }

    for (final p in permissions) {
      if (!hasPermission(p, userId: uid, departmentId: departmentId)) {
        return false;
      }
    }
    return true;
  }

  /// Returns `true` when the user holds *any* of [permissions].
  ///
  /// Enforces strict fail-closed checks: immediately returns `false` if the
  /// resolved user id is null, the user is suspended, or [permissions] is empty.
  bool hasAnyPermission(
    Iterable<String> permissions, {
    String? userId,
    String? departmentId,
  }) {
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid) || permissions.isEmpty) {
      return false;
    }

    for (final p in permissions) {
      if (hasPermission(p, userId: uid, departmentId: departmentId)) {
        return true;
      }
    }
    return false;
  }

  /// Returns whether the user has role-management authority (Admin, Principal, or Vice Principal).
  bool canManageRoles({String? userId}) {
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid)) return false;

    // Trusted sync writer: remote RBAC pulls are persisted even when the
    // logged-in device user is a teacher or student without admin write
    // permissions — Supabase is the source of truth for RBAC data. Outside of
    // a sync cycle [_syncBypassActive] is false and the fail-closed evaluation
    // below applies.
    if (_syncBypassActive) return true;

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
    if (uid == null || isUserSuspended(uid)) return <String>{};

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
    if (uid == null || isUserSuspended(uid)) return <String>{};
    return _userRoles[uid] ?? <String>{};
  }

  /// Department ids [userId] (or current user) is scoped to.
  Set<String> departmentIdsForUser(String? userId) {
    final uid = userId ?? currentUserId;
    if (uid == null || isUserSuspended(uid)) return <String>{};
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
