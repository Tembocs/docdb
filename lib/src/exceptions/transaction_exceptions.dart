import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for transaction-related errors.
///
/// Thrown when transaction operations fail, such as commit failures,
/// rollback errors, or isolation violations.
@immutable
class TransactionException extends EntiDBException {
  /// Creates a new [TransactionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const TransactionException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when concurrent modifications conflict.
///
/// This exception indicates that two or more transactions attempted
/// to modify the same data simultaneously, violating isolation
/// guarantees.
@immutable
class ConcurrencyException extends TransactionException {
  /// Creates a new [ConcurrencyException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const ConcurrencyException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when a serializable transaction detects a conflict on commit.
///
/// This exception indicates that an entity read by this transaction was
/// modified by another transaction between the time this transaction
/// started and when it tried to commit. This is a serialization failure.
///
/// ## Handling
///
/// When this exception is thrown, the application should typically:
/// 1. Roll back any application state associated with the transaction
/// 2. Retry the entire transaction from the beginning
///
/// ## Example
///
/// ```dart
/// final maxRetries = 3;
/// for (var attempt = 0; attempt < maxRetries; attempt++) {
///   try {
///     await transactionScope(storage, (txn) async {
///       final entity = await txn.get('entity-1');
///       entity!['count'] = (entity['count'] as int) + 1;
///       txn.update('entity-1', entity);
///     }, isolationLevel: IsolationLevel.serializable);
///     break; // Success
///   } on TransactionConflictException {
///     if (attempt == maxRetries - 1) rethrow;
///     // Retry
///   }
/// }
/// ```
@immutable
class TransactionConflictException extends TransactionException {
  /// The IDs of entities that had conflicts.
  final List<String> conflictingIds;

  /// Creates a new [TransactionConflictException].
  ///
  /// - [message]: A descriptive error message.
  /// - [conflictingIds]: The entity IDs that were in conflict.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const TransactionConflictException(
    super.message, {
    this.conflictingIds = const [],
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    return 'TransactionConflictException: $message '
        '(${conflictingIds.length} conflicting entities)';
  }
}
