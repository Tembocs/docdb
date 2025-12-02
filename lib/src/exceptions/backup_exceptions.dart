import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for backup and restore operations.
///
/// Thrown when backup creation, restoration, or related file
/// operations fail.
@immutable
class BackupException extends DocDBException {
  /// Creates a new [BackupException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when a user backup file cannot be found.
///
/// This exception indicates that the specified backup file for user
/// data does not exist at the expected location.
@immutable
class UserBackupFileNotFoundException extends BackupException {
  /// Creates a new [UserBackupFileNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UserBackupFileNotFoundException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a data backup file cannot be found.
///
/// This exception indicates that the specified backup file for
/// application data does not exist at the expected location.
@immutable
class DataBackupFileNotFoundException extends BackupException {
  /// Creates a new [DataBackupFileNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DataBackupFileNotFoundException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when data backup creation fails.
///
/// This exception indicates that the system was unable to create
/// a backup of the application data, possibly due to I/O errors
/// or insufficient permissions.
@immutable
class DataBackupCreationException extends BackupException {
  /// Creates a new [DataBackupCreationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DataBackupCreationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when data backup restoration fails.
///
/// This exception indicates that the system was unable to restore
/// application data from a backup file, possibly due to corruption
/// or incompatible format.
@immutable
class DataBackupRestorationException extends BackupException {
  /// Creates a new [DataBackupRestorationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DataBackupRestorationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when user backup creation fails.
///
/// This exception indicates that the system was unable to create
/// a backup of the user authentication data, possibly due to I/O
/// errors or insufficient permissions.
@immutable
class UserBackupCreationException extends BackupException {
  /// Creates a new [UserBackupCreationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UserBackupCreationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when user backup restoration fails.
///
/// This exception indicates that the system was unable to restore
/// user authentication data from a backup file, possibly due to
/// corruption or incompatible format.
@immutable
class UserBackupRestorationException extends BackupException {
  /// Creates a new [UserBackupRestorationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const UserBackupRestorationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
