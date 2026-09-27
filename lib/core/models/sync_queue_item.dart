import 'dart:convert';
import 'package:attendance_app/core/utils/uuid_utils.dart';

/// Represents an operation type on an entity in the offline sync queue.
enum SyncOperation {
  create('CREATE'),
  update('UPDATE'),
  delete('DELETE');

  const SyncOperation(this.value);
  final String value;

  static SyncOperation fromString(String val) {
    return SyncOperation.values.firstWhere(
      (op) => op.value == val.toUpperCase() || op.name == val.toLowerCase(),
      orElse: () => SyncOperation.create,
    );
  }
}

/// Represents a queued mutation to be synchronized with the backend.
class SyncQueueItem {
  SyncQueueItem({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
    this.lastError,
  })  : id = id ?? UuidUtils.generate(),
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;
  final String entityType; // e.g., 'classes', 'students', 'attendance_records'
  final String entityId;   // Canonical UUID of the record
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedPayload = {};
    if (map['payload'] != null) {
      if (map['payload'] is Map) {
        parsedPayload = Map<String, dynamic>.from(map['payload'] as Map);
      } else if (map['payload'] is String) {
        try {
          parsedPayload = jsonDecode(map['payload'] as String) as Map<String, dynamic>;
        } catch (_) {
          parsedPayload = {};
        }
      }
    }

    return SyncQueueItem(
      id: map['id'].toString(),
      entityType: (map['entity_type'] as String?) ?? '',
      entityId: (map['entity_id'] as String?) ?? '',
      operation: SyncOperation.fromString((map['operation'] as String?) ?? 'CREATE'),
      payload: parsedPayload,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)?.toUtc()
          : null,
      retryCount: (map['retry_count'] as int?) ?? 0,
      lastError: map['last_error'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation.value,
      'payload': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'last_error': lastError,
    };
  }

  SyncQueueItem copyWith({
    String? id,
    String? entityType,
    String? entityId,
    SyncOperation? operation,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    int? retryCount,
    String? lastError,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }
}
