import 'package:meta/meta.dart';

/// Base exception class for all EntiDB exceptions.
///
/// This abstract class provides a common interface for all exceptions thrown
/// by the EntiDB library. It supports:
/// - A descriptive [message] explaining the error
/// - An optional [cause] for exception chaining
/// - An optional [stackTrace] for debugging
///
/// All domain-specific exceptions (e.g., [AuthenticationException],
/// [StorageException]) extend this class, enabling uniform error handling.
///
/// Example usage:
/// ```dart
/// try {
///   await collection.insert(document);
/// } on EntiDBException catch (e) {
///   print('EntiDB error: ${e.message}');
///   if (e.cause != null) {
///     print('Caused by: ${e.cause}');
///   }
/// }
/// ```
@immutable
abstract class EntiDBException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The underlying cause of this exception, if any.
  ///
  /// Use this for exception chaining when wrapping lower-level errors.
  final Object? cause;

  /// The stack trace at the point where the exception was thrown.
  final StackTrace? stackTrace;

  /// Creates a new [EntiDBException].
  ///
  /// - [message]: A descriptive error message (required).
  /// - [cause]: The underlying exception that caused this error (optional).
  /// - [stackTrace]: The stack trace for debugging (optional).
  const EntiDBException(this.message, {this.cause, this.stackTrace});

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}
