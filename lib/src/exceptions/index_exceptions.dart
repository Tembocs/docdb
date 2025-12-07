import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for index-related errors.
///
/// Thrown when index operations fail, such as creation, lookup,
/// or maintenance operations.
@immutable
class IndexException extends EntiDBException {
  /// Creates a new [IndexException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const IndexException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when an index is not found on a specified field.
///
/// This exception indicates that the requested index does not
/// exist for the given field in the collection.
@immutable
class IndexNotFoundException extends IndexException {
  /// Creates a new [IndexNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const IndexNotFoundException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when an unsupported index type is requested.
///
/// This exception indicates that the specified index type
/// (e.g., 'fulltext', 'geo') is not supported by the system.
@immutable
class UnsupportedIndexTypeException extends IndexException {
  /// Creates a new [UnsupportedIndexTypeException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UnsupportedIndexTypeException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when attempting to create an index that already exists.
///
/// This exception indicates a constraint violation where an index
/// on the specified field already exists in the collection.
@immutable
class IndexAlreadyExistsException extends IndexException {
  /// Creates a new [IndexAlreadyExistsException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const IndexAlreadyExistsException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
