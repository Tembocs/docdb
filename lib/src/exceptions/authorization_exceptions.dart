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

/// Thrown when a user lacks the required permission for an operation.
///
/// This exception provides details about which permission was required
/// and optionally which resource was being accessed.
@immutable
class PermissionDeniedException extends AuthorizationException {
  /// The permission that was required.
  final String? requiredPermission;

  /// The resource that was being accessed.
  final String? resource;

  /// Creates a new [PermissionDeniedException].
  ///
  /// - [message]: A descriptive error message.
  /// - [requiredPermission]: The permission that was required.
  /// - [resource]: The resource being accessed.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const PermissionDeniedException(
    super.message, {
    this.requiredPermission,
    this.resource,
    super.cause,
    super.stackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('PermissionDeniedException: $message');
    if (requiredPermission != null) {
      buffer.write(' (required: $requiredPermission)');
    }
    if (resource != null) {
      buffer.write(' on resource: $resource');
    }
    return buffer.toString();
  }
}

/// Thrown when attempting to modify a protected system role.
///
/// System roles have restrictions on what can be modified or deleted.
@immutable
class SystemRoleProtectionException extends AuthorizationException {
  /// The name of the protected role.
  final String roleName;

  /// Creates a new [SystemRoleProtectionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [roleName]: The protected role name.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const SystemRoleProtectionException(
    super.message, {
    required this.roleName,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when circular inheritance is detected in role hierarchy.
///
/// Role inheritance must form a directed acyclic graph (DAG).
@immutable
class CircularInheritanceException extends AuthorizationException {
  /// The roles involved in the circular reference.
  final List<String> involvedRoles;

  /// Creates a new [CircularInheritanceException].
  ///
  /// - [message]: A descriptive error message.
  /// - [involvedRoles]: The roles in the circular chain.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const CircularInheritanceException(
    super.message, {
    this.involvedRoles = const [],
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when role inheritance depth exceeds the configured limit.
///
/// This prevents excessively deep inheritance chains that could
/// cause performance issues.
@immutable
class InheritanceDepthExceededException extends AuthorizationException {
  /// The maximum allowed depth.
  final int maxDepth;

  /// The actual depth encountered.
  final int actualDepth;

  /// Creates a new [InheritanceDepthExceededException].
  ///
  /// - [message]: A descriptive error message.
  /// - [maxDepth]: The configured maximum depth.
  /// - [actualDepth]: The depth that was attempted.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const InheritanceDepthExceededException(
    super.message, {
    required this.maxDepth,
    required this.actualDepth,
    super.cause,
    super.stackTrace,
  });
}
