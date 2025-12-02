import 'package:meta/meta.dart';

import 'docdb_exception.dart';

/// Base exception for encryption-related errors.
///
/// This is the parent class for all encryption exceptions, providing
/// a common type for catching any encryption-related error.
@immutable
class EncryptionException extends DocDBException {
  /// Creates a new [EncryptionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const EncryptionException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when data encryption fails.
///
/// This exception indicates that the encryption service was unable
/// to encrypt the provided data, possibly due to invalid input,
/// algorithm failure, or internal errors.
@immutable
class EncryptionFailedException extends EncryptionException {
  /// Creates a new [EncryptionFailedException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const EncryptionFailedException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Thrown when data decryption fails.
///
/// This exception indicates that the encryption service was unable
/// to decrypt the provided data, possibly due to incorrect key,
/// corrupted ciphertext, or internal errors.
@immutable
class DecryptionException extends EncryptionException {
  /// Creates a new [DecryptionException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const DecryptionException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when authentication verification fails during decryption.
///
/// This exception indicates that the GCM authentication tag did not match,
/// which typically means the ciphertext was tampered with, the wrong key
/// was used, or the associated data (AAD) doesn't match.
///
/// **Security Note**: This is a critical security exception. Do not expose
/// detailed information about why authentication failed to prevent
/// oracle attacks.
@immutable
class AuthenticationFailedException extends DecryptionException {
  /// Creates a new [AuthenticationFailedException].
  ///
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const AuthenticationFailedException({Object? cause, StackTrace? stackTrace})
    : super(
        'Authentication failed: data may have been tampered with or wrong key used',
        cause: cause,
        stackTrace: stackTrace,
      );
}

/// Thrown when an invalid encryption key is provided.
///
/// This exception indicates that the key doesn't meet the requirements
/// for the encryption algorithm, such as incorrect length or format.
@immutable
class InvalidKeyException extends EncryptionException {
  /// The expected key length in bits.
  final int? expectedBits;

  /// The actual key length in bits.
  final int? actualBits;

  /// Creates a new [InvalidKeyException].
  ///
  /// - [message]: A descriptive error message.
  /// - [expectedBits]: The expected key length in bits.
  /// - [actualBits]: The actual key length in bits.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const InvalidKeyException(
    super.message, {
    this.expectedBits,
    this.actualBits,
    super.cause,
    super.stackTrace,
  });

  /// Creates an [InvalidKeyException] for key size mismatch.
  InvalidKeyException.invalidSize({
    required int expected,
    required int actual,
    Object? cause,
    StackTrace? stackTrace,
  }) : this(
         'Invalid key size: expected $expected bits, got $actual bits',
         expectedBits: expected,
         actualBits: actual,
         cause: cause,
         stackTrace: stackTrace,
       );

  /// Creates an [InvalidKeyException] for unsupported key sizes.
  InvalidKeyException.unsupportedSize({
    required int actual,
    required List<int> supported,
    Object? cause,
    StackTrace? stackTrace,
  }) : this(
         'Unsupported key size: $actual bits. Supported sizes: ${supported.join(", ")} bits',
         actualBits: actual,
         cause: cause,
         stackTrace: stackTrace,
       );
}

/// Thrown when key derivation from a password fails.
///
/// This exception indicates that the key derivation function (KDF)
/// failed to derive a key from the provided password, possibly due
/// to invalid parameters or internal errors.
@immutable
class KeyDerivationException extends EncryptionException {
  /// Creates a new [KeyDerivationException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const KeyDerivationException(super.message, {super.cause, super.stackTrace});
}

/// Thrown when the encryption service is not properly initialized.
///
/// This exception indicates that the encryption service was used
/// before being properly configured with a key or other required
/// parameters.
@immutable
class EncryptionNotInitializedException extends EncryptionException {
  /// Creates a new [EncryptionNotInitializedException].
  const EncryptionNotInitializedException()
    : super('Encryption service is not initialized. Provide a key first.');
}

/// Thrown when an invalid IV (Initialization Vector) is provided.
///
/// This exception indicates that the IV doesn't meet the requirements
/// for the encryption algorithm, such as incorrect length.
@immutable
class InvalidIvException extends EncryptionException {
  /// The expected IV length in bytes.
  final int? expectedBytes;

  /// The actual IV length in bytes.
  final int? actualBytes;

  /// Creates a new [InvalidIvException].
  ///
  /// - [message]: A descriptive error message.
  /// - [expectedBytes]: The expected IV length in bytes.
  /// - [actualBytes]: The actual IV length in bytes.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const InvalidIvException(
    super.message, {
    this.expectedBytes,
    this.actualBytes,
    super.cause,
    super.stackTrace,
  });
}
