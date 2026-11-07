import 'package:flutter/material.dart';

import 'package:attendance_app/core/models/role.dart';
import 'package:attendance_app/core/services/permission_service.dart';

/// Editable matrix: rows = roles, columns = permissions.
/// The caller is responsible for persisting changes via the repository.
class PermissionGrantEditor extends StatelessWidget {
  const PermissionGrantEditor({
    super.key,
    required this.roles,
    required this.grantsByRole, // Map<roleId, Set<permissionCode>>
    required this.onToggle, // (roleId, permissionCode) => toggle
  });

  final List<Role> roles;
  final Map<String, Set<String>> grantsByRole; // roleId -> granted codes
  final void Function(String roleId, String permissionCode) onToggle;

  @override
  Widget build(BuildContext context) {
    // Collect all permission codes from the service catalogue.
    final allPermissions = PermissionService.instance.permissions.toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final roleList = roles.toList()..sort((a, b) => a.name.compareTo(b.name));

    if (roleList.isEmpty) {
      return const Center(child: Text('No roles found'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ),
          columns: [
            const DataColumn(
              label: Text(
                'Role',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...allPermissions.map(
              (p) => DataColumn(
                label: Tooltip(
                  message: '${p.module}: ${p.description}',
                  child: Text(
                    p.code,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
          rows: roleList.map((role) {
            final granted = grantsByRole[role.id] ?? <String>{};
            final isInstituteWide = role.isInstituteWide;

            return DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            role.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (role.isCustom) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Custom',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        role.code,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                ...allPermissions.map((perm) {
                  // Institute-wide roles hold all permissions by rule
                  final isEffectivelyGranted =
                      isInstituteWide || granted.contains(perm.code);

                  return DataCell(
                    Switch(
                      value: isEffectivelyGranted,
                      onChanged: isInstituteWide
                          ? null // Cannot uncheck superuser permissions
                          : (value) => onToggle(role.id, perm.code),
                    ),
                  );
                }),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
