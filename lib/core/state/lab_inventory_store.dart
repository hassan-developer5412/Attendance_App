import 'package:flutter/foundation.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/lab_inventory.dart';
import 'package:attendance_app/core/repositories/lab_inventory_repository.dart';

/// Manages laboratory inventory items backed by [LabInventoryRepository].
///
/// `InstituteStore` already manages seven directory entities, so lab
/// inventory has its own dedicated store following the exact same state
/// pattern (see [InstituteStore] and [LeaveStore]).
///
/// Every mutation delegates to the repository, which queues a Supabase sync
/// record via [SyncService.schedulePush] (see `lab_inventory_repository.dart`),
/// so changes sync to the cloud once the device is back online.
class LabInventoryStore extends ChangeNotifier {
  LabInventoryStore({LabInventoryRepository? repository})
      : _repository = repository ?? LabInventoryRepository();

  final LabInventoryRepository _repository;

  final List<LabInventory> _items = [];

  /// All non-deleted inventory items, most recently added first.
  List<LabInventory> get items => List.unmodifiable(_items);

  /// Items whose current stock is at or below the reorder level.
  List<LabInventory> get lowStockItems {
    final lowStock = _items
        .where((item) => !item.isDeleted && item.currentStock <= item.reorderLevel)
        .toList();
    lowStock.sort((a, b) => a.currentStock.compareTo(b.currentStock));
    return lowStock;
  }

  /// Inventory items for the given department, excluding soft-deleted items.
  List<LabInventory> itemsForDepartment(String departmentId) {
    return _items
        .where(
            (item) => !item.isDeleted && item.departmentId == departmentId)
        .toList();
  }

  int get itemCount => _items.where((item) => !item.isDeleted).length;
  int get lowStockCount => lowStockItems.length;

  /// Returns the item with [id], or null when it is not loaded.
  LabInventory? itemById(String id) {
    if (id.isEmpty) return null;
    try {
      return _items.where((item) => item.id == id).first;
    } on StateError {
      return null;
    }
  }

  /// Loads inventory items from the local database.
  ///
  /// When [departmentId] is provided, only items for that department are
  /// loaded; otherwise all items are loaded.
  Future<void> init({String? departmentId}) async {
    final loaded = departmentId == null || departmentId.isEmpty
        ? await _repository.getAll()
        : await _repository.getByDepartment(departmentId);
    _items
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  /// Creates a new inventory item.
  ///
  /// The repository persists the item to SQLite and queues a Supabase sync
  /// record for the insert.
  Future<void> addLabInventory({
    required String itemName,
    required String departmentId,
    required InventoryCategory category,
    required double currentStock,
    required String unit,
    required double reorderLevel,
  }) async {
    final item = LabInventory(
      itemName: itemName.trim(),
      departmentId: departmentId,
      category: category,
      currentStock: currentStock,
      unit: unit.trim().isNotEmpty ? unit.trim() : 'pcs',
      reorderLevel: reorderLevel,
    );
    await _repository.insert(item);
    _items.insert(0, item);
    notifyListeners();
  }

  /// Updates an existing inventory item.
  ///
  /// The repository persists the change to SQLite and queues a Supabase sync
  /// record for the update.
  Future<void> updateLabInventory(LabInventory updated) async {
    await _repository.update(updated);
    final idx = _items.indexWhere((item) => item.id == updated.id);
    if (idx >= 0) {
      _items[idx] = updated;
      notifyListeners();
    }
  }

  /// Soft-deletes the inventory item with [id].
  ///
  /// The repository marks the row deleted in SQLite and queues a Supabase
  /// sync record for the deletion.
  Future<void> deleteLabInventory(String id) async {
    await _repository.softDelete(id);
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}
