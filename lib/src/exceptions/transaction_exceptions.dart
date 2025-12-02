import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for transaction-related errors.
///
/// Thrown when transaction operations fail, such as commit failures,
/// rollback errors, or isolation violations.
@immutable
class TransactionException extends DocDBException {
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
