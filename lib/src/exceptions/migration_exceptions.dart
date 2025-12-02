import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for migration-related errors.
///
/// Thrown when database schema or data migrations fail, such as
/// version upgrade failures, incompatible migrations, or rollback
/// errors.
@immutable
class MigrationException extends DocDBException {
  /// Creates a new [MigrationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const MigrationException(super.message, {super.cause, super.stackTrace});
}
