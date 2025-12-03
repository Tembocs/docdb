import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// General database exception for top-level DocDB operations.
///
/// Thrown when database operations fail at the DocDB level,
/// such as opening/closing the database, managing collections,
/// or configuration errors.
@immutable
class DatabaseException extends DocDBException {
  /// Creates a new [DatabaseException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DatabaseException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when the database cannot be opened.
///
/// This exception indicates that the database file or directory
/// could not be accessed or created.
@immutable
class DatabaseOpenException extends DatabaseException {
  /// The path to the database.
  final String? path;

  /// Creates a new [DatabaseOpenException].
  DatabaseOpenException({this.path, Object? cause, StackTrace? stackTrace})
    : super(
        'Failed to open database${path != null ? ' at "$path"' : ''}',
        cause: cause,
        stackTrace: stackTrace,
      );
}

/// Thrown when the database is not open but an operation requires it.
@immutable
class DatabaseNotOpenException extends DatabaseException {
  /// Creates a new [DatabaseNotOpenException].
  const DatabaseNotOpenException()
    : super('Database is not open. Call open() first.');
}

/// Thrown when the database has been disposed but is still accessed.
@immutable
class DatabaseDisposedException extends DatabaseException {
  /// Creates a new [DatabaseDisposedException].
  const DatabaseDisposedException()
    : super('Database has been disposed and cannot be used.');
}

/// Thrown when a collection operation fails.
///
/// This exception indicates that a collection could not be created,
/// accessed, or dropped.
@immutable
class CollectionOperationException extends DatabaseException {
  /// The name of the collection.
  final String collectionName;

  /// Creates a new [CollectionOperationException].
  CollectionOperationException({
    required this.collectionName,
    required String operation,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
         'Failed to $operation collection "$collectionName"',
         cause: cause,
         stackTrace: stackTrace,
       );
}

/// Thrown when a collection type mismatch occurs.
///
/// This exception indicates that a collection was requested with
/// a different type than it was originally created with.
@immutable
class CollectionTypeMismatchException extends DatabaseException {
  /// The name of the collection.
  final String collectionName;

  /// The expected type.
  final Type expectedType;

  /// The actual type.
  final Type actualType;

  /// Creates a new [CollectionTypeMismatchException].
  CollectionTypeMismatchException({
    required this.collectionName,
    required this.expectedType,
    required this.actualType,
  }) : super(
         'Collection "$collectionName" exists with type $expectedType, '
         'cannot reopen as type $actualType',
       );
}
