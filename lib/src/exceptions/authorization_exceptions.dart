import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for authorization-related errors.
///
/// Thrown when a user lacks the necessary permissions to perform
/// an operation, such as accessing a resource or executing a command.
@immutable
class AuthorizationException extends DocDBException {
  /// Creates a new [AuthorizationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const AuthorizationException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when an operation references an undefined role.
///
/// This exception indicates that the specified role name does not
/// exist in the role manager's registry.
@immutable
class UndefinedRoleException extends AuthorizationException {
  /// Creates a new [UndefinedRoleException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UndefinedRoleException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when attempting to define a role that already exists.
///
/// This exception indicates a constraint violation where the role
/// name is already registered in the role manager.
@immutable
class RoleAlreadyDefinedException extends AuthorizationException {
  /// Creates a new [RoleAlreadyDefinedException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const RoleAlreadyDefinedException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
