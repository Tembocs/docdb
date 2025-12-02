import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for document-related errors.
///
/// Thrown when document operations fail, such as serialization,
/// deserialization, or validation errors.
@immutable
class DocumentException extends DocDBException {
  /// Creates a new [DocumentException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DocumentException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when a document cannot be found by its ID.
///
/// This exception indicates that no document exists with the
/// specified identifier in the collection.
@immutable
class DocumentNotFoundException extends DocumentException {
  /// Creates a new [DocumentNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DocumentNotFoundException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
