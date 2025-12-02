import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for storage-related errors.
///
/// Thrown when low-level storage operations fail, such as file I/O
/// errors, permission issues, or disk space problems.
@immutable
class StorageException extends DocDBException {
  /// The path to the storage location (file or directory).
  final String? path;

  /// Creates a new [StorageException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the affected storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageException(
    super.message, {
    this.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when attempting to insert a document with an existing ID.
///
/// This exception indicates a constraint violation where a document
/// with the same ID already exists in the collection.
@immutable
class DocumentAlreadyExistsException extends StorageException {
  /// Creates a new [DocumentAlreadyExistsException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the affected storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DocumentAlreadyExistsException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a storage location (file or directory) is not found.
///
/// This exception indicates that the requested storage path does not exist.
@immutable
class StorageNotFoundException extends StorageException {
  /// Creates a new [StorageNotFoundException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the missing storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageNotFoundException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a storage location already exists.
///
/// This exception indicates that the storage path already exists
/// when attempting to create a new one.
@immutable
class StorageAlreadyExistsException extends StorageException {
  /// Creates a new [StorageAlreadyExistsException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the existing storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageAlreadyExistsException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when storage data is corrupted.
///
/// This exception indicates that the stored data has been corrupted
/// and cannot be read or processed correctly.
@immutable
class StorageCorruptedException extends StorageException {
  /// Creates a new [StorageCorruptedException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the corrupted storage.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageCorruptedException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when there is a version mismatch in the storage format.
///
/// This exception indicates that the storage file was created with
/// an incompatible version of the database format.
@immutable
class StorageVersionMismatchException extends StorageException {
  /// The version of the file.
  final int fileVersion;

  /// The supported version.
  final int supportedVersion;

  /// Creates a new [StorageVersionMismatchException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the storage location.
  /// - [fileVersion]: The version of the file.
  /// - [supportedVersion]: The supported version.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageVersionMismatchException(
    super.message, {
    super.path,
    required this.fileVersion,
    required this.supportedVersion,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when a storage operation fails.
///
/// This is a general exception for storage operation failures
/// that don't fit into more specific categories.
@immutable
class StorageOperationException extends StorageException {
  /// Creates a new [StorageOperationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the affected storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageOperationException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when attempting to access a storage that is not open.
///
/// This exception indicates that the storage must be opened
/// before the operation can be performed.
@immutable
class StorageNotOpenException extends StorageException {
  /// Creates a new [StorageNotOpenException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageNotOpenException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when attempting to write to a read-only storage.
///
/// This exception indicates that the storage was opened in read-only
/// mode and cannot be modified.
@immutable
class StorageReadOnlyException extends StorageException {
  /// Creates a new [StorageReadOnlyException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageReadOnlyException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when there is insufficient disk space for a storage operation.
///
/// This exception indicates that the disk is full or there isn't
/// enough space to complete the operation.
@immutable
class StorageOutOfSpaceException extends StorageException {
  /// The required space in bytes.
  final int? requiredBytes;

  /// The available space in bytes.
  final int? availableBytes;

  /// Creates a new [StorageOutOfSpaceException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the storage location.
  /// - [requiredBytes]: The required space in bytes.
  /// - [availableBytes]: The available space in bytes.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StorageOutOfSpaceException(
    super.message, {
    super.path,
    this.requiredBytes,
    this.availableBytes,
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when there is a permission error accessing storage.
///
/// This exception indicates that the process does not have
/// the required permissions to access the storage location.
@immutable
class StoragePermissionException extends StorageException {
  /// Creates a new [StoragePermissionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [path]: The path to the storage location.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const StoragePermissionException(
    super.message, {
    super.path,
    super.cause,
    super.stackTrace,
  });
}
