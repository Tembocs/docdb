// lib/src/transaction/transaction_manager.dart

import 'dart:async';

import 'package:docdb/src/entity/entity.dart';
import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/logger/docdb_logger.dart';
import 'package:docdb/src/storage/storage.dart';
import 'package:docdb/src/utils/constants.dart';

import 'isolation_level.dart';
import 'transaction_impl.dart';
import 'transaction_status.dart';

/// Manages the lifecycle of transactions for a specific entity type.
///
/// The [TransactionManager] ensures that only one transaction is active at a time
/// for a given storage backend. It provides methods to begin, commit, and rollback
/// transactions, as well as query the current transaction state.
///
/// This class is generic over the entity type [T], allowing type-safe transaction
/// management for different entity types.
///
/// ## Usage Example
///
/// ```dart
/// final manager = TransactionManager<Product>(productStorage);
///
/// // Begin a transaction
/// final transaction = await manager.beginTransaction();
///
/// try {
///   // Perform operations within the transaction
///   await transaction.insert(newProduct);
///   await transaction.update(existingProduct);
///
///   // Commit changes
///   await manager.commit();
/// } catch (e) {
///   // Rollback on error
///   await manager.rollback();
///   rethrow;
/// }
/// ```
///
/// ## Thread Safety
///
/// The transaction manager tracks a single active transaction. Attempting to begin
/// a new transaction while one is already active will throw a [TransactionException].
///
/// ## Isolation Levels
///
/// The manager supports different isolation levels when beginning transactions,
/// allowing control over read visibility and write conflict behavior.
class TransactionManager<T extends Entity> {
  /// The storage backend this manager operates on.
  final Storage<T> _storage;

  /// The currently active transaction, if any.
  Transaction<T>? _currentTransaction;

  /// Logger for transaction management operations.
  final DocDBLogger _logger = DocDBLogger(LoggerNameConstants.transaction);

  /// Creates a new transaction manager for the given storage.
  ///
  /// The [storage] parameter specifies the storage backend that transactions
  /// will operate on.
  TransactionManager(this._storage);

  /// The storage backend this manager operates on.
  Storage<T> get storage => _storage;

  /// Begins a new transaction with the specified isolation level.
  ///
  /// Creates and returns a new [Transaction] that can be used to perform
  /// atomic operations on the storage. Only one transaction can be active
  /// at a time.
  ///
  /// ## Parameters
  ///
  /// - [isolationLevel]: The isolation level for the transaction. Defaults to
  ///   [IsolationLevel.readCommitted].
  ///
  /// ## Returns
  ///
  /// A [Transaction] instance representing the new transaction.
  ///
  /// ## Throws
  ///
  /// - [TransactionException]: If a transaction is already active.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final transaction = await manager.beginTransaction(
  ///   isolationLevel: IsolationLevel.serializable,
  /// );
  /// ```
  Future<Transaction<T>> beginTransaction({
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
  }) async {
    if (_currentTransaction != null && _currentTransaction!.isActive) {
      const message =
          'Another transaction is currently active. Please commit or rollback before starting a new one.';
      _logger.error(message);
      throw TransactionException(message);
    }

    _currentTransaction = await Transaction.create(
      _storage,
      isolationLevel: isolationLevel,
    );
    _logger.debug('Transaction ${_currentTransaction!.id} started');
    return _currentTransaction!;
  }

  /// Commits the current transaction, persisting all changes.
  ///
  /// All operations queued in the current transaction will be applied to
  /// the storage atomically. After a successful commit, the transaction
  /// is cleared and a new transaction can be started.
  ///
  /// ## Throws
  ///
  /// - [TransactionException]: If no active transaction exists.
  /// - [TransactionException]: If the commit operation fails.
  ///
  /// ## Example
  ///
  /// ```dart
  /// await manager.beginTransaction();
  /// // ... perform operations ...
  /// await manager.commit();
  /// ```
  Future<void> commit() async {
    if (_currentTransaction == null || !_currentTransaction!.isActive) {
      const message =
          'No active transaction to commit. Please begin a transaction first.';
      _logger.error(message);
      throw TransactionException(message);
    }

    final transactionId = _currentTransaction!.id;
    await _currentTransaction!.commit();
    _currentTransaction = null;
    _logger.debug('Transaction $transactionId committed');
  }

  /// Rolls back the current transaction, discarding all changes.
  ///
  /// All operations queued in the current transaction will be discarded,
  /// and the storage will remain unchanged. After a rollback, the transaction
  /// is cleared and a new transaction can be started.
  ///
  /// ## Throws
  ///
  /// - [TransactionException]: If no active transaction exists.
  /// - [TransactionException]: If the rollback operation fails.
  ///
  /// ## Example
  ///
  /// ```dart
  /// await manager.beginTransaction();
  /// // ... perform operations ...
  /// await manager.rollback(); // Discard all changes
  /// ```
  Future<void> rollback() async {
    if (_currentTransaction == null || !_currentTransaction!.isActive) {
      const message =
          'No active transaction to rollback. Please begin a transaction first.';
      _logger.error(message);
      throw TransactionException(message);
    }

    final transactionId = _currentTransaction!.id;
    await _currentTransaction!.rollback();
    _currentTransaction = null;
    _logger.debug('Transaction $transactionId rolled back');
  }

  /// Retrieves the current active transaction, if any.
  ///
  /// Returns `null` if no transaction is currently active.
  Transaction<T>? get currentTransaction => _currentTransaction;

  /// Whether a transaction is currently active.
  bool get hasActiveTransaction =>
      _currentTransaction != null && _currentTransaction!.isActive;

  /// The status of the current transaction, or `null` if no transaction exists.
  TransactionStatus? get currentStatus => _currentTransaction?.status;

  /// Resets the transaction manager, clearing any active transactions.
  ///
  /// **Warning**: This forcefully clears the transaction reference without
  /// committing or rolling back. Use with caution, primarily for cleanup
  /// or testing purposes.
  ///
  /// For normal operations, prefer using [commit] or [rollback] to properly
  /// end a transaction.
  void reset() {
    if (_currentTransaction != null) {
      _logger.warning(
        'Force-resetting transaction manager. Transaction ${_currentTransaction!.id} discarded.',
      );
    }
    _currentTransaction = null;
  }

  /// Disposes of the transaction manager and any active transaction.
  ///
  /// If a transaction is active, it will be rolled back before disposal.
  /// After calling this method, the manager should not be used.
  Future<void> dispose() async {
    if (_currentTransaction != null && _currentTransaction!.isActive) {
      _logger.warning(
        'Disposing transaction manager with active transaction. Rolling back...',
      );
      await _currentTransaction!.rollback();
    }
    _currentTransaction = null;
    _logger.debug('Transaction manager disposed');
  }

  /// Executes a function within a transaction, automatically handling commit/rollback.
  ///
  /// This is a convenience method that wraps the transaction lifecycle:
  /// 1. Begins a new transaction
  /// 2. Executes the provided function
  /// 3. Commits on success or rolls back on error
  ///
  /// ## Parameters
  ///
  /// - [action]: The function to execute within the transaction. Receives the
  ///   transaction as a parameter.
  /// - [isolationLevel]: The isolation level for the transaction.
  ///
  /// ## Returns
  ///
  /// The result of the action function.
  ///
  /// ## Throws
  ///
  /// - Any exception thrown by the action function. The transaction will be
  ///   rolled back before rethrowing.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final result = await manager.runInTransaction((tx) async {
  ///   await tx.insert(product1);
  ///   await tx.insert(product2);
  ///   return await tx.getAll();
  /// });
  /// ```
  Future<R> runInTransaction<R>(
    Future<R> Function(Transaction<T> transaction) action, {
    IsolationLevel isolationLevel = IsolationLevel.readCommitted,
  }) async {
    final transaction = await beginTransaction(isolationLevel: isolationLevel);

    try {
      final result = await action(transaction);
      await commit();
      return result;
    } catch (e) {
      await rollback();
      rethrow;
    }
  }
}
