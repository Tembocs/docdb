import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for authentication-related errors.
///
/// Thrown when authentication operations fail, such as login attempts,
/// token validation, or user registration issues.
@immutable
class AuthenticationException extends EntiDBException {
  /// Creates a new [AuthenticationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const AuthenticationException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when attempting to register a user with an existing username.
///
/// This exception indicates a constraint violation where the requested
/// username is already taken in the user storage.
@immutable
class UserAlreadyExistsException extends AuthenticationException {
  /// Creates a new [UserAlreadyExistsException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UserAlreadyExistsException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when login fails due to invalid credentials.
///
/// This exception is raised when either the username does not exist
/// or the provided password does not match the stored hash.
@immutable
class InvalidUserOrPasswordException extends AuthenticationException {
  /// Creates a new [InvalidUserOrPasswordException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const InvalidUserOrPasswordException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a JWT token is invalid or has expired.
///
/// This exception indicates that the provided authentication token
/// cannot be used, either because it has been tampered with, is
/// malformed, or has exceeded its validity period.
@immutable
class InvalidOrExpiredTokenException extends AuthenticationException {
  /// Creates a new [InvalidOrExpiredTokenException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const InvalidOrExpiredTokenException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when JWT token operations fail.
///
/// This exception covers errors during token generation, parsing,
/// or validation that are not related to expiration.
@immutable
class JWTTokenException extends AuthenticationException {
  /// Creates a new [JWTTokenException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const JWTTokenException(super.message, {super.cause, super.stackTrace});
}
