import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for query-related errors.
///
/// Thrown when query parsing, optimization, or execution fails,
/// such as invalid query syntax or unsupported operations.
@immutable
class QueryException extends EntiDBException {
  /// Creates a new [QueryException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const QueryException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when a user cannot be found by username or ID.
///
/// This exception indicates that no user exists with the
/// specified identifier in the user storage.
@immutable
class UserNotFoundException extends QueryException {
  /// Creates a new [UserNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UserNotFoundException(super.message, {super.cause, super.stackTrace});
}
