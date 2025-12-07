import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for backup and restore operations.
///
/// Thrown when backup creation, restoration, or related file
/// operations fail.
@immutable
class BackupException extends EntiDBException {
  /// Creates a new [BackupException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when backup integrity verification fails.
///
/// This exception indicates that a backup file's checksum does not
/// match the expected value, suggesting data corruption or tampering.
@immutable
class BackupIntegrityException extends BackupException {
  /// The expected checksum value.
  final String? expectedChecksum;

  /// The actual checksum calculated from the backup data.
  final String? actualChecksum;

  /// Creates a new [BackupIntegrityException].
  ///
  /// - [message]: A descriptive error message.
  /// - [expectedChecksum]: The expected checksum value.
  /// - [actualChecksum]: The actual calculated checksum.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupIntegrityException(
    super.message, {
    this.expectedChecksum,
    this.actualChecksum,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when backup decompression fails.
///
/// This exception indicates that a compressed backup file could not
/// be decompressed, possibly due to corruption or invalid format.
@immutable
class BackupDecompressionException extends BackupException {
  /// Creates a new [BackupDecompressionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupDecompressionException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when backup compression fails.
///
/// This exception indicates that data could not be compressed
/// during backup creation, possibly due to memory constraints.
@immutable
class BackupCompressionException extends BackupException {
  /// Creates a new [BackupCompressionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupCompressionException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a backup file has an incompatible version.
///
/// This exception indicates that the backup file was created with
/// a different version of the backup format that cannot be restored.
@immutable
class BackupVersionException extends BackupException {
  /// The version of the backup file.
  final String? backupVersion;

  /// The supported version(s) for restoration.
  final String? supportedVersion;

  /// Creates a new [BackupVersionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [backupVersion]: The version found in the backup.
  /// - [supportedVersion]: The version(s) supported by the system.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupVersionException(
    super.message, {
    this.backupVersion,
    this.supportedVersion,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a backup operation times out.
///
/// This exception indicates that a backup or restore operation
/// exceeded the configured timeout duration.
@immutable
class BackupTimeoutException extends BackupException {
  /// The configured timeout duration.
  final Duration? timeout;

  /// Creates a new [BackupTimeoutException].
  ///
  /// - [message]: A descriptive error message.
  /// - [timeout]: The timeout duration that was exceeded.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupTimeoutException(
    super.message, {
    this.timeout,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a backup quota or limit is exceeded.
///
/// This exception indicates that creating a new backup would exceed
/// configured limits such as maximum backup count or total storage size.
@immutable
class BackupQuotaExceededException extends BackupException {
  /// The current count or size.
  final int? currentValue;

  /// The maximum allowed count or size.
  final int? maxValue;

  /// Creates a new [BackupQuotaExceededException].
  ///
  /// - [message]: A descriptive error message.
  /// - [currentValue]: The current count or size.
  /// - [maxValue]: The maximum allowed value.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupQuotaExceededException(
    super.message, {
    this.currentValue,
    this.maxValue,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a backup file is empty or has no entities.
///
/// This exception indicates that a backup restoration failed because
/// the backup file contains no data to restore.
@immutable
class EmptyBackupException extends BackupException {
  /// Creates a new [EmptyBackupException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const EmptyBackupException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when a backup operation is not supported.
///
/// This exception indicates that the requested backup operation
/// is not supported by the current storage or configuration.
@immutable
class BackupNotSupportedException extends BackupException {
  /// The operation that was attempted.
  final String? operation;

  /// Creates a new [BackupNotSupportedException].
  ///
  /// - [message]: A descriptive error message.
  /// - [operation]: The unsupported operation name.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const BackupNotSupportedException(
    super.message, {
    this.operation,
    super.cause,
    super.stackTrace,
  });
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
