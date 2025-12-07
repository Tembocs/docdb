// lib/src/transaction/transaction_impl.dart

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../entity/entity.dart';
import '../exceptions/exceptions.dart';
import '../logger/logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'isolation_level.dart';
import 'operation_types.dart';
import 'transaction_operation.dart';
import 'transaction_status.dart';

/// UUID generator for transaction IDs.
const _uuid = Uuid();

/// A transaction for atomic entity operations.
///
/// Transactions allow multiple operations to be grouped together and
/// executed atomically. Either all operations succeed, or all are
/// rolled back.
///
/// ## Usage
///
/// ```dart
/// final txn = await Transaction.create(storage);
///
/// try {
///   txn.insert('user-1', {'name': 'Alice', 'age': 30});
///   txn.update('user-2', {'name': 'Bob', 'age': 25});
///   txn.delete('user-3');
///
///   await txn.commit();
/// } catch (e) {
///   await txn.rollback();
///   rethrow;
/// }
/// ```
///
/// ## Lifecycle
///
/// ```
/// ─── create() ───► [active] ─── commit() ───► [committed]
///                       │
///                       └─── rollback() ───► [rolledBack]
/// ```
///
/// ## Isolation Levels
///
/// The transaction supports different isolation levels to control
/// read visibility and write conflict behavior:
///
/// - [IsolationLevel.readUncommitted]: Allows reading uncommitted changes.
/// - [IsolationLevel.readCommitted]: Only reads committed changes.
/// - [IsolationLevel.repeatableRead]: Consistent reads throughout transaction.
/// - [IsolationLevel.serializable]: Full isolation, transactions execute serially.
///
/// ## Thread Safety
///
/// Transactions are not thread-safe. Each transaction should be used
/// from a single isolate. For concurrent operations, use separate
/// transactions with proper coordination.
class Transaction<T extends Entity> {
  /// Unique identifier for this transaction.
  final String _id;

  /// The storage backend for this transaction.
  final Storage<T> _storage;

  /// The isolation level for this transaction.
  final IsolationLevel _isolationLevel;

  /// Logger for transaction operations.
  final EntiDBLogger _logger;

  /// The current status of this transaction.
  TransactionStatus _status;

  /// Snapshot of storage state when transaction began.
  ///
  /// Used for rollback in case of failure.
  final Map<String, Map<String, dynamic>> _snapshot;

  /// Queued operations to execute on commit.
  final List<TransactionOperation> _operations = [];

  /// Entities read during this transaction (for serializable isolation).
  ///
  /// Used for conflict detection when isolation level is [IsolationLevel.serializable].
  final Set<String> _readSet = {};

  /// Timestamp when the transaction was created/started.
  final DateTime _createdAt;

  /// Timestamp when the transaction was completed (commit/rollback).
  DateTime? _completedAt;

  /// Private constructor - use [create] factory method.
  Transaction._({
    required String id,
    required Storage<T> storage,
    required IsolationLevel isolationLevel,
    required Map<String, Map<String, dynamic>> snapshot,
  }) : _id = id,
       _storage = storage,
       _isolationLevel = isolationLevel,
       _snapshot = snapshot,
       _status = TransactionStatus.active,
       _createdAt = DateTime.now(),
       _logger = EntiDBLogger(LoggerNameConstants.transaction);

  /// Creates and starts a new transaction for the given storage.
  ///
  /// Takes a snapshot of the current storage state for potential rollback.
  /// The transaction is created in [TransactionStatus.active] state and
  /// is ready to accept operations.
  ///
  /// ## Parameters
  ///
  /// - [storage]: The storage backend to perform operations on.
  /// - [isolationLevel]: The isolation level for the transaction.
  ///   Defaults to [IsolationLevel.readCommitted].
  ///
  /// ## Throws
  ///
  /// - [TransactionException]: If storage is not open or snapshot fails.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final txn = await Transaction.create(
  ///   storage,
  ///   isolationLevel: IsolationLevel.serializable,
  /// );
  /// ```
  static Future<Transaction<T>> create<T extends Entity>(
    Storage<T> storage, {
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
  }) async {
    if (!storage.isOpen) {
      throw TransactionException(
        'Cannot create transaction: storage is not open.',
      );
    }

    final logger = EntiDBLogger(LoggerNameConstants.transaction);

    try {
      // Take snapshot for rollback
      final snapshot = await storage.getAll();
      final id = _uuid.v4();

      logger.info(
        'Transaction $id created with ${snapshot.length} entities in snapshot. '
        'Isolation level: ${isolationLevel.name}',
      );

      return Transaction._(
        id: id,
        storage: storage,
        isolationLevel: isolationLevel,
        snapshot: snapshot,
      );
    } catch (e, stackTrace) {
      logger.error('Failed to create transaction', e, stackTrace);
      throw TransactionException('Failed to create transaction: $e', cause: e);
    }
  }

  /// The unique identifier for this transaction.
  String get id => _id;

  /// The isolation level for this transaction.
  IsolationLevel get isolationLevel => _isolationLevel;

  /// The current status of this transaction.
  TransactionStatus get status => _status;

  /// Whether the transaction is active and accepting operations.
  bool get isActive => _status == TransactionStatus.active;

  /// Whether the transaction has been committed.
  bool get isCommitted => _status == TransactionStatus.committed;

  /// Whether the transaction has been rolled back.
  bool get isRolledBack => _status == TransactionStatus.rolledBack;

  /// Whether the transaction has completed (committed or rolled back).
  bool get isCompleted =>
      _status == TransactionStatus.committed ||
      _status == TransactionStatus.rolledBack ||
      _status == TransactionStatus.failed;

  /// The number of pending operations.
  int get operationCount => _operations.length;

  /// Unmodifiable list of pending operations.
  List<TransactionOperation> get operations => List.unmodifiable(_operations);

  /// When this transaction was created.
  DateTime get createdAt => _createdAt;

  /// When this transaction completed, or null if not yet completed.
  DateTime? get completedAt => _completedAt;

  /// Duration since transaction was created.
  ///
  /// Useful for monitoring transaction lifespan and detecting
  /// long-running transactions.
  Duration get age => DateTime.now().difference(_createdAt);

  /// Queues an insert operation.
  ///
  /// - [entityId]: The unique identifier for the new entity.
  /// - [data]: The entity data to insert.
  ///
  /// Throws [TransactionException] if transaction is not active.
  void insert(String entityId, Map<String, dynamic> data) {
    _ensureActive();
    final operation = TransactionOperation.insert(entityId, data);
    operation.validate();
    _operations.add(operation);
    _logger.debug('Transaction $_id: Queued insert for entity: $entityId');
  }

  /// Queues an update operation.
  ///
  /// - [entityId]: The ID of the entity to update.
  /// - [data]: The new entity data.
  ///
  /// Throws [TransactionException] if transaction is not active.
  void update(String entityId, Map<String, dynamic> data) {
    _ensureActive();
    final operation = TransactionOperation.update(entityId, data);
    operation.validate();
    _operations.add(operation);
    _logger.debug('Transaction $_id: Queued update for entity: $entityId');
  }

  /// Queues an upsert operation.
  ///
  /// - [entityId]: The ID of the entity to upsert.
  /// - [data]: The entity data.
  ///
  /// Throws [TransactionException] if transaction is not active.
  void upsert(String entityId, Map<String, dynamic> data) {
    _ensureActive();
    final operation = TransactionOperation.upsert(entityId, data);
    operation.validate();
    _operations.add(operation);
    _logger.debug('Transaction $_id: Queued upsert for entity: $entityId');
  }

  /// Queues a delete operation.
  ///
  /// - [entityId]: The ID of the entity to delete.
  ///
  /// Throws [TransactionException] if transaction is not active.
  void delete(String entityId) {
    _ensureActive();
    final operation = TransactionOperation.delete(entityId);
    operation.validate();
    _operations.add(operation);
    _logger.debug('Transaction $_id: Queued delete for entity: $entityId');
  }

  /// Reads an entity within the transaction context.
  ///
  /// The read behavior depends on the isolation level:
  /// - [IsolationLevel.readUncommitted]: Reads latest storage state (may include
  ///   uncommitted changes from other transactions in concurrent scenarios).
  /// - [IsolationLevel.readCommitted]: Reads current committed storage state.
  /// - [IsolationLevel.repeatableRead]: Reads from snapshot taken at transaction
  ///   start, with pending operations from this transaction applied.
  /// - [IsolationLevel.serializable]: Same as repeatableRead, with conflict
  ///   detection on commit.
  ///
  /// - [entityId]: The ID of the entity to read.
  ///
  /// Returns the entity data, or null if not found.
  ///
  /// Throws [TransactionException] if transaction is not active.
  Future<Map<String, dynamic>?> get(String entityId) async {
    _ensureActive();
    try {
      return _getWithIsolation(entityId);
    } catch (e) {
      _logger.error('Transaction $_id: Failed to read entity $entityId', e);
      throw TransactionException(
        'Failed to read entity $entityId: $e',
        cause: e,
      );
    }
  }

  /// Internal method to get entity respecting isolation level.
  Future<Map<String, dynamic>?> _getWithIsolation(String entityId) async {
    // Track reads for serializable conflict detection
    if (_isolationLevel == IsolationLevel.serializable) {
      _readSet.add(entityId);
    }

    switch (_isolationLevel) {
      case IsolationLevel.readUncommitted:
      case IsolationLevel.readCommitted:
        // Read from current storage state
        return await _storage.get(entityId);

      case IsolationLevel.repeatableRead:
      case IsolationLevel.serializable:
        // Read from snapshot with pending operations applied
        return _getFromSnapshotWithPendingOps(entityId);
    }
  }

  /// Gets entity from snapshot with pending operations applied.
  ///
  /// This provides a consistent view: the snapshot from transaction start
  /// plus any modifications made within this transaction.
  Map<String, dynamic>? _getFromSnapshotWithPendingOps(String entityId) {
    // Start with the snapshot value
    Map<String, dynamic>? result = _snapshot[entityId];
    bool deleted = false;

    // Apply pending operations for this entity
    for (final op in _operations) {
      if (op.entityId != entityId) continue;

      switch (op.type) {
        case OperationType.insert:
        case OperationType.update:
        case OperationType.upsert:
          result = Map<String, dynamic>.from(op.data!);
          deleted = false;
        case OperationType.delete:
          result = null;
          deleted = true;
      }
    }

    return deleted ? null : result;
  }

  /// Reads all entities within the transaction context.
  ///
  /// The read behavior depends on the isolation level:
  /// - [IsolationLevel.readUncommitted]: Reads latest storage state.
  /// - [IsolationLevel.readCommitted]: Reads current committed storage state.
  /// - [IsolationLevel.repeatableRead]: Reads from snapshot with pending
  ///   operations from this transaction applied.
  /// - [IsolationLevel.serializable]: Same as repeatableRead.
  ///
  /// Returns a map of entity IDs to their data.
  ///
  /// Throws [TransactionException] if transaction is not active.
  Future<Map<String, Map<String, dynamic>>> getAll() async {
    _ensureActive();
    try {
      return _getAllWithIsolation();
    } catch (e) {
      _logger.error('Transaction $_id: Failed to read all entities', e);
      throw TransactionException('Failed to read all entities: $e', cause: e);
    }
  }

  /// Internal method to get all entities respecting isolation level.
  Future<Map<String, Map<String, dynamic>>> _getAllWithIsolation() async {
    switch (_isolationLevel) {
      case IsolationLevel.readUncommitted:
      case IsolationLevel.readCommitted:
        // Read from current storage state
        final result = await _storage.getAll();
        // Track all reads for serializable (though this is called after switch check)
        return result;

      case IsolationLevel.repeatableRead:
      case IsolationLevel.serializable:
        // Read from snapshot with pending operations applied
        final result = _getAllFromSnapshotWithPendingOps();
        // Track all entity IDs for serializable conflict detection
        if (_isolationLevel == IsolationLevel.serializable) {
          _readSet.addAll(result.keys);
          _readSet.addAll(_snapshot.keys);
        }
        return result;
    }
  }

  /// Gets all entities from snapshot with pending operations applied.
  Map<String, Map<String, dynamic>> _getAllFromSnapshotWithPendingOps() {
    // Start with a deep copy of the snapshot
    final result = <String, Map<String, dynamic>>{};
    for (final entry in _snapshot.entries) {
      result[entry.key] = Map<String, dynamic>.from(entry.value);
    }

    // Apply all pending operations
    for (final op in _operations) {
      switch (op.type) {
        case OperationType.insert:
        case OperationType.update:
        case OperationType.upsert:
          result[op.entityId] = Map<String, dynamic>.from(op.data!);
        case OperationType.delete:
          result.remove(op.entityId);
      }
    }

    return result;
  }

  /// Checks if an entity exists within the transaction context.
  ///
  /// The read behavior depends on the isolation level:
  /// - [IsolationLevel.readUncommitted] / [IsolationLevel.readCommitted]:
  ///   Checks current storage state.
  /// - [IsolationLevel.repeatableRead] / [IsolationLevel.serializable]:
  ///   Checks snapshot with pending operations applied.
  ///
  /// - [entityId]: The ID of the entity to check.
  ///
  /// Returns true if the entity exists, false otherwise.
  ///
  /// Throws [TransactionException] if transaction is not active.
  Future<bool> exists(String entityId) async {
    _ensureActive();
    try {
      return _existsWithIsolation(entityId);
    } catch (e) {
      _logger.error(
        'Transaction $_id: Failed to check existence of entity $entityId',
        e,
      );
      throw TransactionException(
        'Failed to check existence of entity $entityId: $e',
        cause: e,
      );
    }
  }

  /// Internal method to check existence respecting isolation level.
  Future<bool> _existsWithIsolation(String entityId) async {
    // Track reads for serializable conflict detection
    if (_isolationLevel == IsolationLevel.serializable) {
      _readSet.add(entityId);
    }

    switch (_isolationLevel) {
      case IsolationLevel.readUncommitted:
      case IsolationLevel.readCommitted:
        return await _storage.exists(entityId);

      case IsolationLevel.repeatableRead:
      case IsolationLevel.serializable:
        return _getFromSnapshotWithPendingOps(entityId) != null;
    }
  }

  /// Commits the transaction, executing all queued operations.
  ///
  /// Operations are executed in the order they were queued. If any
  /// operation fails, the transaction is rolled back automatically.
  ///
  /// For [IsolationLevel.serializable], conflict detection is performed
  /// before executing operations. If any entity read during this transaction
  /// was modified by another transaction since our snapshot was taken,
  /// a [TransactionConflictException] is thrown.
  ///
  /// Throws [TransactionException] if:
  /// - Transaction is not active
  /// - Any operation fails
  /// - Rollback fails after operation failure
  ///
  /// Throws [TransactionConflictException] if:
  /// - Serializable isolation level detects a conflict
  Future<void> commit() async {
    _ensureActive();

    if (_operations.isEmpty) {
      _status = TransactionStatus.committed;
      _completedAt = DateTime.now();
      _logger.info('Transaction $_id committed (no operations).');
      return;
    }

    _logger.info(
      'Transaction $_id: Committing with ${_operations.length} operations...',
    );

    try {
      // For serializable isolation, check for conflicts before committing
      if (_isolationLevel == IsolationLevel.serializable) {
        await _checkForConflicts();
      }

      await _executeOperations();
      _status = TransactionStatus.committed;
      _completedAt = DateTime.now();
      _logger.info('Transaction $_id committed successfully.');
    } on TransactionConflictException {
      // Don't wrap conflict exceptions - they're already the right type
      _status = TransactionStatus.rolledBack;
      _completedAt = DateTime.now();
      _logger.info(
        'Transaction $_id rolled back due to serializable conflict.',
      );
      rethrow;
    } catch (e, stackTrace) {
      _logger.error(
        'Transaction $_id: Commit failed, attempting rollback...',
        e,
        stackTrace,
      );

      try {
        await _restoreSnapshot();
        _status = TransactionStatus.rolledBack;
        _completedAt = DateTime.now();
        _logger.info('Transaction $_id rolled back after commit failure.');
      } catch (rollbackError, rollbackStack) {
        _status = TransactionStatus.failed;
        _completedAt = DateTime.now();
        _logger.error(
          'Transaction $_id: Rollback failed! Database may be inconsistent.',
          rollbackError,
          rollbackStack,
        );
        throw TransactionException(
          'Transaction failed: $e. Rollback also failed: $rollbackError. '
          'Database may be in inconsistent state.',
          cause: e,
        );
      }

      throw TransactionException(
        'Transaction failed and was rolled back: $e',
        cause: e,
      );
    }
  }

  /// Checks for serializable conflicts.
  ///
  /// Compares the current storage state with the snapshot for all entities
  /// in the read set. If any entity has changed, throws a conflict exception.
  Future<void> _checkForConflicts() async {
    if (_readSet.isEmpty) return;

    final conflicts = <String>[];

    for (final entityId in _readSet) {
      final snapshotValue = _snapshot[entityId];
      final currentValue = await _storage.get(entityId);

      // Check if the entity was modified since snapshot
      if (!_mapsAreEqual(snapshotValue, currentValue)) {
        conflicts.add(entityId);
      }
    }

    if (conflicts.isNotEmpty) {
      throw TransactionConflictException(
        'Serializable conflict detected: ${conflicts.length} entity(s) were '
        'modified by another transaction. Conflicting entities: '
        '${conflicts.take(5).join(", ")}${conflicts.length > 5 ? "..." : ""}',
        conflictingIds: conflicts,
      );
    }
  }

  /// Compares two entity maps for equality.
  bool _mapsAreEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final aValue = a[key];
      final bValue = b[key];

      if (aValue is Map && bValue is Map) {
        if (!_mapsAreEqual(
          aValue.cast<String, dynamic>(),
          bValue.cast<String, dynamic>(),
        )) {
          return false;
        }
      } else if (aValue is List && bValue is List) {
        if (!_listsAreEqual(aValue, bValue)) {
          return false;
        }
      } else if (aValue != bValue) {
        return false;
      }
    }

    return true;
  }

  /// Compares two lists for equality.
  bool _listsAreEqual(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] is Map && b[i] is Map) {
        if (!_mapsAreEqual(
          (a[i] as Map).cast<String, dynamic>(),
          (b[i] as Map).cast<String, dynamic>(),
        )) {
          return false;
        }
      } else if (a[i] is List && b[i] is List) {
        if (!_listsAreEqual(a[i], b[i])) {
          return false;
        }
      } else if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Rolls back the transaction, discarding all queued operations.
  ///
  /// Clears the operation queue without executing. The storage state
  /// remains unchanged from when the transaction was created.
  ///
  /// Throws [TransactionException] if:
  /// - Transaction is not active
  /// - Rollback fails
  Future<void> rollback() async {
    _ensureActive();

    _logger.info(
      'Transaction $_id: Rolling back with ${_operations.length} pending operations...',
    );

    try {
      // Clear operations without executing
      _operations.clear();
      _status = TransactionStatus.rolledBack;
      _completedAt = DateTime.now();
      _logger.info('Transaction $_id rolled back successfully.');
    } catch (e, stackTrace) {
      _status = TransactionStatus.failed;
      _completedAt = DateTime.now();
      _logger.error('Transaction $_id: Rollback failed', e, stackTrace);
      throw TransactionException('Rollback failed: $e', cause: e);
    }
  }

  /// Disposes of the transaction.
  ///
  /// If the transaction is still active, it will be rolled back.
  /// After disposal, the transaction should not be used.
  Future<void> dispose() async {
    if (isActive) {
      _logger.warning(
        'Transaction $_id: Disposing active transaction, rolling back...',
      );
      await rollback();
    }
    _operations.clear();
  }

  /// Executes all queued operations on the storage.
  Future<void> _executeOperations() async {
    for (int i = 0; i < _operations.length; i++) {
      final operation = _operations[i];
      try {
        await _executeOperation(operation);
      } catch (e) {
        _logger.error(
          'Transaction $_id: Operation ${i + 1}/${_operations.length} failed: '
          '${operation.type.name} on ${operation.entityId}',
          e,
        );
        rethrow;
      }
    }
  }

  /// Executes a single operation on the storage.
  Future<void> _executeOperation(TransactionOperation operation) async {
    switch (operation.type) {
      case OperationType.insert:
        await _storage.insert(operation.entityId, operation.data!);
      case OperationType.update:
        await _storage.update(operation.entityId, operation.data!);
      case OperationType.upsert:
        await _storage.upsert(operation.entityId, operation.data!);
      case OperationType.delete:
        await _storage.delete(operation.entityId);
    }
  }

  /// Restores storage to the snapshot state.
  Future<void> _restoreSnapshot() async {
    _logger.debug(
      'Transaction $_id: Restoring snapshot with ${_snapshot.length} entities...',
    );

    // Delete all current entities
    await _storage.deleteAll();

    // Restore from snapshot
    if (_snapshot.isNotEmpty) {
      await _storage.insertMany(_snapshot);
    }
  }

  /// Ensures the transaction is in active state.
  void _ensureActive() {
    if (_status != TransactionStatus.active) {
      throw TransactionException(
        'Cannot perform operation: transaction $_id is $_status.',
      );
    }
  }

  @override
  String toString() {
    return 'Transaction<$T>('
        'id: $_id, '
        'status: $_status, '
        'operations: ${_operations.length}, '
        'isolationLevel: ${_isolationLevel.name}'
        ')';
  }
}

/// Extension for creating transactions from storage.
extension TransactionExtension<T extends Entity> on Storage<T> {
  /// Creates and starts a new transaction for this storage.
  ///
  /// This is a convenience method that calls [Transaction.create].
  ///
  /// ## Parameters
  ///
  /// - [isolationLevel]: The isolation level for the transaction.
  ///   Defaults to [IsolationLevel.readCommitted].
  ///
  /// ## Example
  ///
  /// ```dart
  /// final txn = await storage.beginTransaction();
  /// ```
  Future<Transaction<T>> beginTransaction({
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
  }) async {
    return Transaction.create<T>(this, isolationLevel: isolationLevel);
  }
}

/// A simple transaction scope for automatic commit/rollback.
///
/// Ensures the transaction is properly committed or rolled back
/// even if an exception occurs.
///
/// ## Usage
///
/// ```dart
/// await transactionScope(storage, (txn) async {
///   txn.insert('user-1', {'name': 'Alice'});
///   txn.update('user-2', {'name': 'Bob'});
///   // Automatically committed if no exception
/// });
/// ```
///
/// ## Parameters
///
/// - [storage]: The storage to create the transaction on.
/// - [action]: The function to execute within the transaction.
/// - [isolationLevel]: The isolation level for the transaction.
///
/// ## Returns
///
/// The result of the action function.
///
/// ## Throws
///
/// Any exception thrown by the action function. The transaction will be
/// rolled back before rethrowing.
@experimental
Future<R> transactionScope<T extends Entity, R>(
  Storage<T> storage,
  FutureOr<R> Function(Transaction<T> txn) action, {
  IsolationLevel isolationLevel = IsolationLevel.readCommitted,
}) async {
  final txn = await storage.beginTransaction(isolationLevel: isolationLevel);

  try {
    final result = await action(txn);
    await txn.commit();
    return result;
  } catch (e) {
    if (txn.isActive) {
      await txn.rollback();
    }
    rethrow;
  }
}
