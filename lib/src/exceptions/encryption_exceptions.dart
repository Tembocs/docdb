import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Thrown when data encryption fails.
///
/// This exception indicates that the encryption service was unable
/// to encrypt the provided data, possibly due to invalid key,
/// algorithm failure, or data format issues.
@immutable
class EncryptionException extends DocDBException {
  /// Creates a new [EncryptionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const EncryptionException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when data decryption fails.
///
/// This exception indicates that the encryption service was unable
/// to decrypt the provided data, possibly due to incorrect key,
/// corrupted ciphertext, or authentication tag mismatch.
@immutable
class DecryptionException extends DocDBException {
  /// Creates a new [DecryptionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DecryptionException(super.message, {super.cause, super.stackTrace});
}
