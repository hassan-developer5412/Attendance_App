import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/rbac_store.dart';

void main() {
  late RBACStore store;

  setUp(() {
    PermissionService.instance.reset();
    store = RBACStore();
  });

  group('RBACStore fail-closed checks', () {
    test('unauthenticated store (currentUserId == null) returns false for all permission checks', () {
      expect(store.currentUserId, isNull);
      expect(store.isAuthenticated, isFalse);
      expect(store.isLoaded, isFalse);

      expect(store.hasPermission(PermissionCodes.studentView), isFalse);
      expect(store.hasAnyPermission([PermissionCodes.studentView]), isFalse);
      expect(store.hasAllPermissions([PermissionCodes.studentView]), isFalse);
      expect(store.hasAllPermissions([]), isFalse);
      expect(store.hasAnyPermission([]), isFalse);
      expect(store.currentUserPermissions, isEmpty);
    });

    test('unloaded store returns false for all permission checks', () {
      final role = Role(
        id: 'r1',
        name: 'Admin',
        code: 'admin',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([role]);
      PermissionService.instance.assignRoleToUser('u1', role.id);
      PermissionService.instance.currentUserId = 'u1';

      // Explicitly set store as unloaded
      store.isLoaded = false;
      expect(store.isLoaded, isFalse);

      expect(store.hasPermission(PermissionCodes.studentView), isFalse);
      expect(store.hasAnyPermission([PermissionCodes.studentView]), isFalse);
      expect(store.hasAllPermissions([PermissionCodes.studentView]), isFalse);
    });

    test('suspended user returns false for all permission checks', () {
      final role = Role(
        id: 'r1',
        name: 'Admin',
        code: 'admin',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([role]);
      PermissionService.instance.assignRoleToUser('u1', role.id);
      PermissionService.instance.currentUserId = 'u1';

      expect(store.hasPermission(PermissionCodes.studentView), isTrue);

      // Suspend the user
      store.isSuspended = true;
      expect(store.isSuspended, isTrue);
      expect(store.isAuthenticated, isFalse);

      expect(store.hasPermission(PermissionCodes.studentView), isFalse);
      expect(store.hasAnyPermission([PermissionCodes.studentView]), isFalse);
      expect(store.hasAllPermissions([PermissionCodes.studentView]), isFalse);
      expect(store.currentUserPermissions, isEmpty);
    });

    test('clear() resets store to unauthenticated and unloaded state', () {
      final role = Role(
        id: 'r1',
        name: 'Admin',
        code: 'admin',
        isInstituteWide: true,
      );
      PermissionService.instance.loadRoles([role]);
      PermissionService.instance.assignRoleToUser('u1', role.id);
      PermissionService.instance.currentUserId = 'u1';

      expect(store.hasPermission(PermissionCodes.studentView), isTrue);

      store.clear();

      expect(store.currentUserId, isNull);
      expect(store.isAuthenticated, isFalse);
      expect(store.isLoaded, isFalse);
      expect(store.hasPermission(PermissionCodes.studentView), isFalse);
      expect(store.hasAnyPermission([PermissionCodes.studentView]), isFalse);
      expect(store.hasAllPermissions([PermissionCodes.studentView]), isFalse);
    });
  });
}
