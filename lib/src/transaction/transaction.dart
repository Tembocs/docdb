// lib/src/transaction/transaction.dart
//
// Barrel file for the transaction module.
// Provides ACID transaction support for entity storage operations.

/// Transaction support for DocDB.
///
/// This module provides comprehensive transaction management for atomic
/// operations on entity storage. Transactions ensure that multiple
/// operations either all succeed or all fail, maintaining data consistency.
///
/// ## Core Components
///
/// - [Transaction]: The main transaction class for atomic operations.
/// - [TransactionManager]: Manages transaction lifecycle for a storage.
/// - [TransactionOperation]: Represents a single operation in a transaction.
/// - [TransactionStatus]: The current state of a transaction.
/// - [OperationType]: Types of operations (insert, update, delete, upsert).
/// - [IsolationLevel]: Transaction isolation levels.
///
/// ## Usage Example
///
/// ### Using Transaction directly:
///
/// ```dart
/// final txn = await Transaction.create(storage);
///
/// txn.insert('user-1', {'name': 'Alice', 'email': 'alice@example.com'});
/// txn.update('user-2', {'name': 'Bob Updated'});
/// txn.delete('user-3');
///
/// await txn.commit(); // All operations succeed or all are rolled back
/// ```
///
/// ### Using TransactionManager:
///
/// ```dart
/// final manager = TransactionManager<User>(userStorage);
///
/// final txn = await manager.beginTransaction();
/// txn.insert('user-1', userData);
/// await manager.commit();
/// ```
///
/// ### Using runInTransaction helper:
///
/// ```dart
/// final result = await manager.runInTransaction((txn) async {
///   txn.insert('product-1', productData);
///   txn.update('product-2', updatedData);
///   return 'success';
/// });
/// ```
///
/// ### Using transactionScope function:
///
/// ```dart
/// await transactionScope(storage, (txn) async {
///   txn.insert('doc-1', docData);
///   // Automatically committed on success, rolled back on error
/// });
/// ```
///
/// ## Isolation Levels
///
/// The module supports standard database isolation levels:
///
/// - [IsolationLevel.readUncommitted]: Allows dirty reads.
/// - [IsolationLevel.readCommitted]: Only reads committed data (default).
/// - [IsolationLevel.repeatableRead]: Consistent reads throughout transaction.
/// - [IsolationLevel.serializable]: Full isolation, no anomalies.
///
/// ## Error Handling
///
/// All transaction errors are wrapped in [TransactionException]:
///
/// ```dart
/// try {
///   await txn.commit();
/// } on TransactionException catch (e) {
///   print('Transaction failed: ${e.message}');
///   // Transaction is automatically rolled back on commit failure
/// }
/// ```
library;

export 'isolation_level.dart';
export 'operation_types.dart';
export 'transaction_impl.dart';
export 'transaction_manager.dart';
export 'transaction_operation.dart';
export 'transaction_status.dart';
