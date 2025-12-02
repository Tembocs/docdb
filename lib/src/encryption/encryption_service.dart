/// DocDB Encryption - Encryption Service Interface
///
/// Defines the abstract interface for encryption services. All encryption
/// implementations must implement this interface to ensure consistent
/// behavior across the database.
library;

import 'dart:typed_data';

/// Supported key sizes for AES encryption.
///
/// AES supports three key sizes, each providing different security levels:
/// - 128 bits (16 bytes): Good security, fastest performance
/// - 192 bits (24 bytes): Better security, moderate performance
/// - 256 bits (32 bytes): Best security, slowest performance
enum AesKeySize {
  /// 128-bit key (16 bytes).
  bits128(16, 128),

  /// 192-bit key (24 bytes).
  bits192(24, 192),

  /// 256-bit key (32 bytes).
  bits256(32, 256);

  /// The key size in bytes.
  final int bytes;

  /// The key size in bits.
  final int bits;

  const AesKeySize(this.bytes, this.bits);

  /// Returns the [AesKeySize] for the given byte length.
  ///
  /// Throws [ArgumentError] if the length doesn't match any supported size.
  static AesKeySize fromBytes(int byteLength) {
    return switch (byteLength) {
      16 => AesKeySize.bits128,
      24 => AesKeySize.bits192,
      32 => AesKeySize.bits256,
      _ => throw ArgumentError.value(
        byteLength,
        'byteLength',
        'Invalid key length. Must be 16, 24, or 32 bytes.',
      ),
    };
  }

  /// List of all supported key sizes in bits.
  static const List<int> supportedBits = [128, 192, 256];

  /// List of all supported key sizes in bytes.
  static const List<int> supportedBytes = [16, 24, 32];
}

/// Result of an encryption operation.
///
/// Contains the ciphertext along with the IV (nonce) used for encryption.
/// The IV is required for decryption and must be stored alongside the
/// ciphertext.
final class EncryptionResult {
  /// The encrypted data (ciphertext + authentication tag for GCM).
  final Uint8List ciphertext;

  /// The initialization vector (nonce) used for encryption.
  ///
  /// For AES-GCM, this is typically 12 bytes (96 bits).
  final Uint8List iv;

  /// Creates a new encryption result.
  const EncryptionResult({required this.ciphertext, required this.iv});

  /// Returns the combined IV + ciphertext as a single byte array.
  ///
  /// This is the recommended format for storage, as it keeps the IV
  /// and ciphertext together.
  Uint8List get combined {
    final result = Uint8List(iv.length + ciphertext.length);
    result.setRange(0, iv.length, iv);
    result.setRange(iv.length, result.length, ciphertext);
    return result;
  }

  /// Parses a combined IV + ciphertext byte array.
  ///
  /// - [data]: The combined byte array.
  /// - [ivLength]: The length of the IV in bytes (default: 12 for GCM).
  factory EncryptionResult.fromCombined(Uint8List data, {int ivLength = 12}) {
    if (data.length <= ivLength) {
      throw ArgumentError.value(
        data.length,
        'data',
        'Data too short: must be longer than IV length ($ivLength bytes)',
      );
    }
    return EncryptionResult(
      iv: Uint8List.sublistView(data, 0, ivLength),
      ciphertext: Uint8List.sublistView(data, ivLength),
    );
  }
}

/// Abstract interface for encryption services.
///
/// Implementations of this interface provide data-at-rest encryption
/// for the database. The interface supports both raw binary encryption
/// and convenience methods for string encryption.
///
/// ## Security Contract
///
/// Implementations MUST:
/// - Generate a new random IV for each encryption operation
/// - Use authenticated encryption (e.g., AES-GCM) to detect tampering
/// - Never reuse an IV with the same key
/// - Use constant-time comparison for authentication verification
///
/// ## Usage Example
///
/// ```dart
/// final service = AesGcmEncryptionService(key: secretKey);
///
/// // Encrypt binary data
/// final result = await service.encrypt(plaintext);
/// final stored = result.combined; // IV + ciphertext
///
/// // Decrypt
/// final decrypted = await service.decryptCombined(stored);
///
/// // String convenience methods
/// final encrypted = await service.encryptString('sensitive data');
/// final original = await service.decryptString(encrypted);
/// ```
abstract interface class EncryptionService {
  /// Whether this service actually performs encryption.
  ///
  /// Returns `false` for [NoEncryptionService] implementations.
  bool get isEnabled;

  /// The key size used by this encryption service.
  ///
  /// Returns `null` for services that don't use symmetric keys.
  AesKeySize? get keySize;

  /// Encrypts the given plaintext data.
  ///
  /// - [plaintext]: The data to encrypt.
  /// - [aad]: Optional Additional Authenticated Data. This data is
  ///   authenticated but not encrypted. It must be provided during
  ///   decryption as well.
  ///
  /// Returns an [EncryptionResult] containing the ciphertext and IV.
  ///
  /// Throws [EncryptionFailedException] if encryption fails.
  /// Throws [EncryptionNotInitializedException] if service not ready.
  Future<EncryptionResult> encrypt(Uint8List plaintext, {Uint8List? aad});

  /// Decrypts the given ciphertext.
  ///
  /// - [ciphertext]: The encrypted data (including authentication tag).
  /// - [iv]: The initialization vector used during encryption.
  /// - [aad]: Optional Additional Authenticated Data. Must match the
  ///   AAD provided during encryption.
  ///
  /// Returns the decrypted plaintext.
  ///
  /// Throws [DecryptionException] if decryption fails.
  /// Throws [AuthenticationFailedException] if authentication fails.
  /// Throws [EncryptionNotInitializedException] if service not ready.
  Future<Uint8List> decrypt(
    Uint8List ciphertext, {
    required Uint8List iv,
    Uint8List? aad,
  });

  /// Decrypts data from the combined IV + ciphertext format.
  ///
  /// This is a convenience method for decrypting data stored using
  /// [EncryptionResult.combined].
  ///
  /// - [combined]: The combined IV + ciphertext bytes.
  /// - [aad]: Optional Additional Authenticated Data.
  /// - [ivLength]: The length of the IV in bytes (default: 12).
  ///
  /// Returns the decrypted plaintext.
  ///
  /// Throws [DecryptionException] if decryption fails.
  /// Throws [AuthenticationFailedException] if authentication fails.
  Future<Uint8List> decryptCombined(
    Uint8List combined, {
    Uint8List? aad,
    int ivLength = 12,
  });

  /// Encrypts a string and returns a base64-encoded result.
  ///
  /// The result contains the IV prepended to the ciphertext, encoded
  /// as a base64 string for easy storage.
  ///
  /// - [plaintext]: The string to encrypt.
  /// - [aad]: Optional Additional Authenticated Data.
  ///
  /// Returns a base64-encoded string containing IV + ciphertext.
  ///
  /// Throws [EncryptionFailedException] if encryption fails.
  Future<String> encryptString(String plaintext, {Uint8List? aad});

  /// Decrypts a base64-encoded string.
  ///
  /// - [ciphertext]: The base64-encoded IV + ciphertext.
  /// - [aad]: Optional Additional Authenticated Data.
  ///
  /// Returns the decrypted string.
  ///
  /// Throws [DecryptionException] if decryption fails.
  /// Throws [AuthenticationFailedException] if authentication fails.
  Future<String> decryptString(String ciphertext, {Uint8List? aad});

  /// Securely destroys any key material held by this service.
  ///
  /// After calling this method, the service can no longer be used
  /// for encryption or decryption until a new key is provided.
  ///
  /// Implementations should overwrite key memory with zeros.
  void destroy();
}
