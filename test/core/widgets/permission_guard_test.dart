import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/permission.dart';
import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';

/// Widget-level tests for [PermissionGuard].
void main() {
  late RBACStore rbac;

  setUp(() {
    // Reset the global service and create fresh stores.
    PermissionService.instance.reset();
    rbac = RBACStore();
  });

  group('PermissionGuard shows child when permission granted', () {
    testWidgets('granted permission reveals child', (WidgetTester tester) async {
      // Arrange: assign a role with student.view to the current user.
      final studentRole = Role(
        id: 'r1',
        name: 'Student',
        code: 'student',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([studentRole]);
      PermissionService.instance.grantPermissionToRole(studentRole.id, PermissionCodes.studentView);
      PermissionService.instance.assignRoleToUser('u1', studentRole.id);
      PermissionService.instance.currentUserId = 'u1';

      // Build the widget under test.
      await tester.pumpWidget(
        ChangeNotifierProvider<RBACStore>.value(
          value: rbac,
          child: MaterialApp(
            home: Scaffold(
              body: PermissionGuard(
                permission: PermissionCodes.studentView,
                child: const Icon(Icons.person, size: 48, color: Colors.green),
              ),
            ),
          ),
        ),
      );

      // Assert: the green person icon is present (granted).
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.textContaining('No permission'), findsNothing);
    });
  });

  group('PermissionGuard hides child when permission revoked', () {
    testWidgets('not granted shows fallback placeholder', (WidgetTester tester) async {
      PermissionService.instance.currentUserId = 'u2';

      await tester.pumpWidget(
        ChangeNotifierProvider<RBACStore>.value(
          value: rbac,
          child: MaterialApp(
            home: Scaffold(
              body: PermissionGuard(
                permission: PermissionCodes.studentCreate,
                fallback: const Text('Add student'),
                child: const Icon(Icons.person, size: 48, color: Colors.green),
              ),
            ),
          ),
        ),
      );

      // Assert: the fallback text is shown, the icon is hidden.
      expect(find.text('Add student'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
    });
  });

  group('department-scoped HOD', () {
    testWidgets('HOD with matching departmentId shows child', (WidgetTester tester) async {
      final hodRole = Role(
        id: 'r2',
        name: 'HOD',
        code: 'hod',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([hodRole]);
      PermissionService.instance.grantPermissionToRole(hodRole.id, PermissionCodes.studentView);
      PermissionService.instance.assignRoleToUser('u3', hodRole.id);
      PermissionService.instance.setUserDepartments('u3', <String>{'d1'});
      PermissionService.instance.currentUserId = 'u3';

      await tester.pumpWidget(
        ChangeNotifierProvider<RBACStore>.value(
          value: rbac,
          child: MaterialApp(
            home: Scaffold(
              body: PermissionGuard(
                permission: PermissionCodes.studentView,
                departmentId: 'd1',
                child: const Icon(Icons.person, size: 48, color: Colors.green),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('HOD with non-matching departmentId hides child', (WidgetTester tester) async {
      final hodRole = Role(
        id: 'r3',
        name: 'HOD',
        code: 'hod',
        isInstituteWide: false,
      );
      PermissionService.instance.loadRoles([hodRole]);
      PermissionService.instance.grantPermissionToRole(hodRole.id, PermissionCodes.studentView);
      PermissionService.instance.assignRoleToUser('u4', hodRole.id);
      PermissionService.instance.setUserDepartments('u4', <String>{'d1'});
      PermissionService.instance.currentUserId = 'u4';

      await tester.pumpWidget(
        ChangeNotifierProvider<RBACStore>.value(
          value: rbac,
          child: MaterialApp(
            home: Scaffold(
              body: PermissionGuard(
                permission: PermissionCodes.studentView,
                departmentId: 'd2', // wrong department
                child: const Icon(Icons.person, size: 48, color: Colors.green),
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsNothing);
      expect(find.textContaining('No permission'), findsOneWidget);
    });
  });
}
