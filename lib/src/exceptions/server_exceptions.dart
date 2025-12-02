import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for server-related errors.
///
/// Thrown when server operations fail, such as initialization,
/// connection handling, or shutdown errors.
@immutable
class ServerException extends DocDBException {
  /// Creates a new [ServerException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const ServerException(super.message, {super.cause, super.stackTrace});
}
