/// Transaction operation definitions for DocDB.
///
/// Represents individual operations within a transaction that are
/// queued for execution on commit.
library;

import 'package:meta/meta.dart';

import 'operation_types.dart';

/// An individual operation within a transaction.
///
/// Operations are queued when transaction methods are called (insert,
/// update, delete) and executed atomically when the transaction commits.
///
/// ## Usage
///
/// Operations are typically created through [Transaction] methods rather
/// than instantiated directly:
///
/// ```dart
/// final txn = await Transaction.begin(storage);
/// txn.insert('user-1', {'name': 'Alice'}); // Creates insert operation
/// txn.update('user-2', {'name': 'Bob'});   // Creates update operation
/// await txn.commit(); // Executes all operations
/// ```
///
/// ## Immutability
///
/// Operations are immutable once created. The data map is stored
/// by reference, so callers should not modify it after creating
/// the operation.
@immutable
class TransactionOperation {
  /// The type of operation to perform.
  final OperationType type;

  /// The unique identifier of the target entity.
  ///
  /// Required for all operation types.
  final String entityId;

  /// The entity data for insert/update/upsert operations.
  ///
  /// Must be non-null for [OperationType.insert], [OperationType.update],
  /// and [OperationType.upsert]. Should be null for [OperationType.delete].
  final Map<String, dynamic>? data;

  /// Optional metadata associated with this operation.
  ///
  /// Can be used to store additional context such as timestamps,
  /// user IDs, or operation-specific flags.
  final Map<String, dynamic>? metadata;

  /// Creates a new transaction operation.
  ///
  /// For delete operations, [data] should be null.
  /// For insert/update/upsert operations, [data] is required.
  const TransactionOperation._({
    required this.type,
    required this.entityId,
    this.data,
    this.metadata,
  });

  /// Creates an insert operation.
  ///
  /// - [entityId]: The ID of the entity to insert.
  /// - [data]: The entity data to insert.
  /// - [metadata]: Optional operation metadata.
  factory TransactionOperation.insert(
    String entityId,
    Map<String, dynamic> data, {
    Map<String, dynamic>? metadata,
  }) {
    return TransactionOperation._(
      type: OperationType.insert,
      entityId: entityId,
      data: data,
      metadata: metadata,
    );
  }

  /// Creates an update operation.
  ///
  /// - [entityId]: The ID of the entity to update.
  /// - [data]: The new entity data.
  /// - [metadata]: Optional operation metadata.
  factory TransactionOperation.update(
    String entityId,
    Map<String, dynamic> data, {
    Map<String, dynamic>? metadata,
  }) {
    return TransactionOperation._(
      type: OperationType.update,
      entityId: entityId,
      data: data,
      metadata: metadata,
    );
  }

  /// Creates an upsert operation (insert or update).
  ///
  /// - [entityId]: The ID of the entity to upsert.
  /// - [data]: The entity data.
  /// - [metadata]: Optional operation metadata.
  factory TransactionOperation.upsert(
    String entityId,
    Map<String, dynamic> data, {
    Map<String, dynamic>? metadata,
  }) {
    return TransactionOperation._(
      type: OperationType.upsert,
      entityId: entityId,
      data: data,
      metadata: metadata,
    );
  }

  /// Creates a delete operation.
  ///
  /// - [entityId]: The ID of the entity to delete.
  /// - [metadata]: Optional operation metadata.
  factory TransactionOperation.delete(
    String entityId, {
    Map<String, dynamic>? metadata,
  }) {
    return TransactionOperation._(
      type: OperationType.delete,
      entityId: entityId,
      metadata: metadata,
    );
  }

  /// Whether this operation modifies data (insert, update, upsert).
  bool get isWrite => type != OperationType.delete || type == OperationType.delete;

  /// Whether this operation requires data to be provided.
  bool get requiresData =>
      type == OperationType.insert ||
      type == OperationType.update ||
      type == OperationType.upsert;

  /// Validates that the operation is properly constructed.
  ///
  /// Throws [ArgumentError] if the operation is invalid.
  void validate() {
    if (entityId.isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'Cannot be empty');
    }

    if (requiresData && data == null) {
      throw ArgumentError.notNull('data');
    }
  }

  /// Converts this operation to a map for serialization.
  Map<String, dynamic> toMap() => {
        'type': type.name,
        'entityId': entityId,
        if (data != null) 'data': data,
        if (metadata != null) 'metadata': metadata,
      };

  /// Creates an operation from a serialized map.
  factory TransactionOperation.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String;
    final type = OperationType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => throw ArgumentError.value(typeStr, 'type', 'Unknown operation type'),
    );

    return TransactionOperation._(
      type: type,
      entityId: map['entityId'] as String,
      data: map['data'] as Map<String, dynamic>?,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'TransactionOperation(type: ${type.name}, entityId: $entityId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionOperation &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          entityId == other.entityId;

  @override
  int get hashCode => Object.hash(type, entityId);
}
