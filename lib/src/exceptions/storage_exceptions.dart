import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for storage-related errors.
///
/// Thrown when low-level storage operations fail, such as file I/O
/// errors, permission issues, or disk space problems.
@immutable
class StorageException extends DocDBException {
  /// Creates a new [StorageException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when attempting to insert a document with an existing ID.
///
/// This exception indicates a constraint violation where a document
/// with the same ID already exists in the collection.
@immutable
class DocumentAlreadyExistsException extends StorageException {
  /// Creates a new [DocumentAlreadyExistsException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DocumentAlreadyExistsException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
