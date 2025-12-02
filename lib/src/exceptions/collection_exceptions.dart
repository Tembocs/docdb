import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for collection-related errors.
///
/// Thrown when collection operations fail, such as creating,
/// accessing, or modifying collections.
@immutable
class CollectionException extends DocDBException {
  /// Creates a new [CollectionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const CollectionException(super.message, {super.cause, super.stackTrace});
}
