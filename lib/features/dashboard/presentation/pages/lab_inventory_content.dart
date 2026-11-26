import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/department.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/lab_inventory_store.dart';
import 'package:attendance_app/core/services/permission_service.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';
import 'package:attendance_app/features/dashboard/presentation/widgets/institute_form_dialogs.dart';

/// Dashboard page for managing laboratory inventory — equipment, chemicals,
/// raw materials, and machinery parts across departments/labs.
///
/// Follows the same state + RBAC pattern as [ClassesContent] and other
/// directory pages. Mutations flow through [LabInventoryStore], which
/// delegates to [LabInventoryRepository] (auto-queuing Supabase sync
/// records via [SyncService.schedulePush]).
class LabInventoryContent extends StatefulWidget {
  const LabInventoryContent({super.key});

  @override
  State<LabInventoryContent> createState() => _LabInventoryContentState();
}

class _LabInventoryContentState extends State<LabInventoryContent> {
  String _searchQuery = '';
  String? _selectedDepartmentId;
  InventoryCategory? _selectedCategory;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Returns inventory items matching the current search and filters.
  List<LabInventory> _filtered(LabInventoryStore store,
      {List<Department>? departments}) {
    final query = _searchQuery.toLowerCase().trim();
    var items = store.items.where((item) => !item.isDeleted).toList();

    if (_selectedDepartmentId != null &&
        _selectedDepartmentId!.isNotEmpty) {
      items = items
          .where((item) => item.departmentId == _selectedDepartmentId)
          .toList();
    }

    if (_selectedCategory != null) {
      items = items.where((item) => item.category == _selectedCategory).toList();
    }

    if (query.isNotEmpty) {
      items = items
          .where((item) =>
              item.itemName.toLowerCase().contains(query) ||
              item.unit.toLowerCase().contains(query))
          .toList();
    }

    // Most recently added first.
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// Whether any item is currently below (or at) its reorder level.
  int _lowStockCount(LabInventoryStore store) =>
      store.lowStockCount;

  Future<void> _confirmDelete(LabInventoryStore store,
      LabInventory item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete inventory item'),
        content: Text(
          'Remove "${item.itemName}" (${item.unit}) from lab inventory?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete == true && mounted) {
      try {
        await store.deleteLabInventory(item.id);
      } on PermissionDeniedException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission denied: ${e.permissionCode}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.itemName} deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddDialog(
      LabInventoryStore store, List<Department> departments) async {
    final result = await showLabInventoryFormDialog(
      context: context,
      departments: departments,
    );

    if (result == null || !mounted) return;

    try {
      await store.addLabInventory(
        itemName: result.itemName,
        departmentId: result.departmentId,
        category: result.category,
        currentStock: result.currentStock,
        unit: result.unit,
        reorderLevel: result.reorderLevel,
      );
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permission denied: ${e.permissionCode}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.itemName} added'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showEditDialog(
      LabInventoryStore store,
      List<Department> departments,
      LabInventory item,
      ) async {
    final result = await showLabInventoryFormDialog(
      context: context,
      departments: departments,
      item: item,
    );

    if (result == null || !mounted) return;

    try {
      await store.updateLabInventory(result.toInventory());
    } on PermissionDeniedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permission denied: ${e.permissionCode}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${result.itemName} updated'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Status badge for an item based on stock vs reorder level.
  Widget _statusBadge(LabInventory item) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLowStock = item.currentStock <= item.reorderLevel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLowStock
            ? colorScheme.errorContainer.withValues(alpha: 0.25)
            : colorScheme.secondaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLowStock ? 'LOW STOCK' : 'OK',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isLowStock
              ? colorScheme.onErrorContainer
              : colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  /// Department label for a given id, falling back to the id itself.
  String _departmentLabel(String? id, List<Department> departments) {
    if (id == null || id.isEmpty) return '—';
    try {
      final dept = departments.firstWhere((d) => d.id == id);
      return '${dept.code} — ${dept.name}';
    } on StateError {
      return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final labStore = context.watch<LabInventoryStore>();
    final instituteStore = context.watch<InstituteStore>();
    final departments = instituteStore.activeDepartments;
    final colorScheme = Theme.of(context).colorScheme;
    final items = _filtered(labStore, departments: departments);
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ------------------------------------------------------------------
        // Header bar: title, search, filters, add button
        // ------------------------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Lab Inventory',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Equipment, chemicals, raw materials, and machinery parts',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Low stock summary chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_rounded,
                        size: 16, color: colorScheme.error),
                    const SizedBox(width: 6),
                    Text(
                      '${_lowStockCount(labStore)} low stock',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PermissionGuard(
                permission: PermissionCodes.labManage,
                child: FilledButton.icon(
                  key: const Key('labInventoryAddButton'),
                  onPressed: () => _showAddDialog(labStore, departments),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Equipment / Item'),
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------------------------
        // Search + filter bar
        // ------------------------------------------------------------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              TextFormField(
                key: const Key('labInventorySearchField'),
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search items…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Department filter
                  if (departments.isNotEmpty)
                    _DepartmentFilterChip(
                      departments: departments,
                      selectedId: _selectedDepartmentId,
                      onChanged: (id) =>
                          setState(() => _selectedDepartmentId = id),
                    ),
                  // Category filter
                  _CategoryFilterChip(
                    selected: _selectedCategory,
                    onChanged: (cat) =>
                        setState(() => _selectedCategory = cat),
                  ),
                  // Clear filters
                  if (_selectedDepartmentId != null || _selectedCategory != null)
                    OutlinedButton(
                      key: const Key('labInventoryClearFilters'),
                      onPressed: () => setState(() {
                        _selectedDepartmentId = null;
                        _selectedCategory = null;
                      }),
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
            ],
          ),
        ),

        // ------------------------------------------------------------------
        // Item list (cards on mobile, table on desktop)
        // ------------------------------------------------------------------
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 56, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        'No lab inventory items',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_searchQuery.isNotEmpty ||
                          _selectedDepartmentId != null ||
                          _selectedCategory != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton(
                            onPressed: () => setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                              _selectedDepartmentId = null;
                              _selectedCategory = null;
                            }),
                            child: const Text('Clear filters'),
                          ),
                        ),
                    ],
                  ),
                )
              : isWide
                  ? _buildTable(labStore, departments, items)
                  : _buildCards(labStore, departments, items),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // Desktop table layout
  // -----------------------------------------------------------------------
  Widget _buildTable(
      LabInventoryStore store, List<Department> departments,
      List<LabInventory> items) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.resolveWith(
                    (_) => colorScheme.surfaceContainerHighest,
                  ),
                  columns: [
                    const DataColumn(label: Text('Item')),
                    DataColumn(
                        label: Text(
                      'Department',
                      overflow: TextOverflow.ellipsis,
                    )),
                    const DataColumn(label: Text('Category')),
                    const DataColumn(label: Text('Stock')),
                    const DataColumn(label: Text('Reorder')),
                    const DataColumn(label: Text('Unit')),
                    const DataColumn(label: Text('Status')),
                    DataColumn(
                      label: Text(
                        'Actions',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  rows: items.map((item) {
                    return DataRow(cells: [
                      DataCell(
                        Text(item.itemName,
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        showEditIcon: false,
                      ),
                      DataCell(Text(
                        _departmentLabel(item.departmentId, departments),
                        overflow: TextOverflow.ellipsis,
                      )),
                      DataCell(Text(item.category.label)),
                      DataCell(Text(item.currentStock.toStringAsFixed(1))),
                      DataCell(Text(item.reorderLevel.toStringAsFixed(1))),
                      DataCell(Text(item.unit)),
                      DataCell(_statusBadge(item)),
                      DataCell(Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PermissionGuard(
                            permission: PermissionCodes.labManage,
                            child: IconButton(
                              key: Key('labInventoryEdit${item.id}'),
                              tooltip: 'Edit',
                              icon: Icon(Icons.edit_rounded,
                                  color: colorScheme.primary),
                              onPressed: () =>
                                  _showEditDialog(store, departments, item),
                            ),
                          ),
                          PermissionGuard(
                            permission: PermissionCodes.labManage,
                            child: IconButton(
                              key: Key('labInventoryDelete${item.id}'),
                              tooltip: 'Delete',
                              icon: Icon(Icons.delete_outline_rounded,
                                  color: colorScheme.error),
                              onPressed: () => _confirmDelete(store, item),
                            ),
                          ),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Mobile card layout
  // -----------------------------------------------------------------------
  Widget _buildCards(
      LabInventoryStore store, List<Department> departments,
      List<LabInventory> items) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      key: const PageStorageKey('labInventoryCards'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        final item = items[index];
        final isLowStock = item.currentStock <= item.reorderLevel;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            key: Key('labInventoryCard${item.id}'),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _categoryIcon(item.category),
                color: colorScheme.primary,
              ),
            ),
            title: Text(item.itemName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.category.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.currentStock.toStringAsFixed(0)} ${item.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: isLowStock
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusBadge(item),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Dept: ${_departmentLabel(item.departmentId, departments)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PermissionGuard(
                  permission: PermissionCodes.labManage,
                  child: IconButton(
                    key: Key('labInventoryEdit${item.id}'),
                    tooltip: 'Edit',
                    icon: Icon(Icons.edit_rounded,
                        color: colorScheme.primary),
                    onPressed: () =>
                        _showEditDialog(store, departments, item),
                  ),
                ),
                PermissionGuard(
                  permission: PermissionCodes.labManage,
                  child: IconButton(
                    key: Key('labInventoryDelete${item.id}'),
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline_rounded,
                        color: colorScheme.error),
                    onPressed: () => _confirmDelete(store, item),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _categoryIcon(InventoryCategory category) {
    switch (category) {
      case InventoryCategory.chemical:
        return Icons.science_rounded;
      case InventoryCategory.rawMaterial:
        return Icons.inventory_rounded;
      case InventoryCategory.machineryPart:
        return Icons.build_rounded;
      case InventoryCategory.hardwareEquipment:
        return Icons.devices_rounded;
    }
  }
}

/// Filter chip for selecting a department.
class _DepartmentFilterChip extends StatelessWidget {
  const _DepartmentFilterChip({
    required this.departments,
    this.selectedId,
    required this.onChanged,
  });

  final List<Department> departments;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = departments.firstWhere(
      (d) => d.id == selectedId,
      orElse: () => Department(
        id: '', name: '', code: '', isActive: false,
      ),
    );
    final isSelected = selectedId != null && selectedId!.isNotEmpty;

    return ChoiceChip(
      label: Text(
        isSelected && selected.id.isNotEmpty
            ? '${selected.code} — ${selected.name}'
            : 'All departments',
      ),
      selected: isSelected,
      onSelected: (_) {
        if (isSelected) {
          onChanged(null);
        }
      },
    );
  }
}

/// Filter chip for selecting an inventory category.
class _CategoryFilterChip extends StatelessWidget {
  const _CategoryFilterChip({
    required this.selected,
    required this.onChanged,
  });

  final InventoryCategory? selected;
  final ValueChanged<InventoryCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected != null;

    return FilterChip(
      label: Text(isSelected ? selected!.label : 'All categories'),
      selected: isSelected,
      onSelected: (_) {
        if (isSelected) {
          onChanged(null);
        }
      },
    );
  }
}