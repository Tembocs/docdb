import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Thrown when document validation against a schema fails.
///
/// This exception indicates that a document does not conform to
/// the expected schema, such as missing required fields, type
/// mismatches, or constraint violations.
@immutable
class SchemaValidationException extends DocDBException {
  /// Creates a new [SchemaValidationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const SchemaValidationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
