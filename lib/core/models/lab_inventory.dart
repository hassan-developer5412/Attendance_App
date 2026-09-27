import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Lab Inventory model for tracking laboratory equipment, chemicals, raw materials, and machinery parts.
class LabInventory {
  LabInventory({
    String? id,
    required this.itemName,
    required this.departmentId,
    required this.category,
    required this.currentStock,
    required this.unit,
    required this.reorderLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.isDeleted = false,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  final String itemName;
  final String departmentId;
  final InventoryCategory category;
  final double currentStock;
  final String unit;
  final double reorderLevel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final bool isDeleted;

  factory LabInventory.fromMap(Map<String, dynamic> map) {
    return LabInventory(
      id: map['id'].toString(),
      itemName: map['item_name'] as String,
      departmentId: map['department_id'].toString(),
      category: InventoryCategory.fromString(map['category'] as String),
      currentStock: (map['current_stock'] as num).toDouble(),
      unit: (map['unit'] as String?) ?? 'pcs',
      reorderLevel: (map['reorder_level'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)?.toUtc()
          : null,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'item_name': itemName,
      'department_id': departmentId,
      'category': category.code,
      'current_stock': currentStock,
      'unit': unit,
      'reorder_level': reorderLevel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  Map<String, dynamic> toServerJson() {
    return {
      'id': id,
      'item_name': itemName,
      'department_id': departmentId,
      'category': category.code,
      'current_stock': currentStock,
      'unit': unit,
      'reorder_level': reorderLevel,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus.value,
      'is_deleted': isDeleted,
    };
  }

  LabInventory copyWith({
    String? id,
    String? itemName,
    String? departmentId,
    InventoryCategory? category,
    double? currentStock,
    String? unit,
    double? reorderLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    bool? isDeleted,
  }) {
    return LabInventory(
      id: id ?? this.id,
      itemName: itemName ?? this.itemName,
      departmentId: departmentId ?? this.departmentId,
      category: category ?? this.category,
      currentStock: currentStock ?? this.currentStock,
      unit: unit ?? this.unit,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
