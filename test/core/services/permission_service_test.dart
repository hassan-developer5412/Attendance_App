import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Unit tests for [PermissionService.hasPermission].
///
/// Covers the core logic: institute-wide authority (Admin / Principal / VP),
/// department scoping for HOD, and permission absence when no user is logged in.
void main() {
  late PermissionService service;

  setUp(() {
    service = PermissionService.instance;
    // Reset state between tests.
    service.reset();
  });

  group('institute-wide authority', () {
    test('Admin holds every permission regardless of department', () {
      // Arrange: assign admin role and set institute-wide grants.
      final adminRole = Role(
        id: 'r1',
        name: 'Administrator',
        code: 'admin',
        isInstituteWide: true,
      );
      service.loadRoles([adminRole]);
      service.grantPermissionToRole(adminRole.id, PermissionCodes.studentCreate);
      service.grantPermissionToRole(adminRole.id, PermissionCodes.feeManage);
      service.assignRoleToUser('u1', adminRole.id);

      // Act / Assert
      expect(service.hasPermission(PermissionCodes.studentCreate, userId: 'u1'), isTrue);
      expect(service.hasPermission(PermissionCodes.feeManage, userId: 'u1'), isTrue);
      expect(service.hasPermission(PermissionCodes.dashboardView, userId: 'u1'), isTrue);
    });

    test('Vice Principal holds institute-wide permissions', () {
      final vpRole = Role(
        id: 'r2',
        name: 'Vice Principal',
        code: 'vice_principal',
        isInstituteWide: true,
      );
      service.loadRoles([vpRole]);
      service.grantPermissionToRole(vpRole.id, PermissionCodes.teacherView);
      service.assignRoleToUser('u2', vpRole.id);

      expect(service.hasPermission(PermissionCodes.teacherView, userId: 'u2'), isTrue);
      expect(service.hasPermission(PermissionCodes.attendanceMark, userId: 'u2'), isTrue);
    });
  });

  group('department scoping for HOD', () {
    test('HOD only sees permissions when user is assigned to the department', () {
      final hodRole = Role(
        id: 'r3',
        name: 'Head of Department',
        code: 'hod',
        isInstituteWide: false,
      );
      service.loadRoles([hodRole]);
      service.grantPermissionToRole(hodRole.id, PermissionCodes.studentView);
      service.assignRoleToUser('u3', hodRole.id);
      // User is scoped to department 'd1'.
      service.setUserDepartments('u3', <String>{'d1'});

      // Without a department constraint the role holds the permission.
      expect(service.hasPermission(PermissionCodes.studentView, userId: 'u3'), isTrue);

      // With a matching department constraint it still holds.
      expect(service.hasPermission(PermissionCodes.studentView, userId: 'u3', departmentId: 'd1'), isTrue);

      // With a non-matching department constraint it does NOT hold.
      expect(service.hasPermission(PermissionCodes.studentView, userId: 'u3', departmentId: 'd2'), isFalse);
    });

    test('Teacher is not department-scoped (no departmentId needed)', () {
      final teacherRole = Role(
        id: 'r4',
        name: 'Teacher',
        code: 'teacher',
        isInstituteWide: false,
      );
      service.loadRoles([teacherRole]);
      service.grantPermissionToRole(teacherRole.id, PermissionCodes.attendanceMark);
      service.assignRoleToUser('u4', teacherRole.id);

      // Teachers are not department-scoped: the permission holds without a departmentId.
      expect(service.hasPermission(PermissionCodes.attendanceMark, userId: 'u4'), isTrue);
      // Passing a random departmentId should not break it.
      expect(service.hasPermission(PermissionCodes.attendanceMark, userId: 'u4', departmentId: 'unused'), isTrue);
    });
  });

  group('no current user', () {
    test('returns false when no user is logged in', () {
      expect(service.hasPermission(PermissionCodes.studentCreate), isFalse);
    });
  });
}
