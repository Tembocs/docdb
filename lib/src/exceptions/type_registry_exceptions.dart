import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for type registry errors.
///
/// Thrown when type registration or lookup operations fail, such as
/// duplicate type registration, missing serializers, or type
/// resolution errors.
@immutable
class TypeRegistryException extends DocDBException {
  /// Creates a new [TypeRegistryException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const TypeRegistryException(super.message, {super.cause, super.stackTrace});
}
