/// EntiDB Encryption - AES-GCM Encryption Service
///
/// Provides AES-GCM authenticated encryption using the cryptography package.
/// This implementation ensures both confidentiality and integrity of data.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import '../exceptions/encryption_exceptions.dart';
import 'encryption_service.dart';

/// AES-GCM encryption service implementation.
///
/// This class provides authenticated encryption using AES in GCM mode.
/// It automatically generates a random 12-byte IV (nonce) for each
/// encryption operation to ensure security.
///
/// ## Security Features
///
/// - **Authenticated Encryption**: GCM mode provides both confidentiality
///   and integrity, detecting any tampering with the ciphertext.
/// - **Random IV**: A new random IV is generated for each encryption,
///   preventing IV reuse attacks.
/// - **AAD Support**: Additional Authenticated Data can be included to
///   bind the ciphertext to a specific context.
///
/// ## Key Sizes
///
/// Supports AES-128, AES-192, and AES-256:
/// - 16 bytes (128 bits): AES-128-GCM
/// - 24 bytes (192 bits): AES-192-GCM
/// - 32 bytes (256 bits): AES-256-GCM
///
/// ## Usage
///
/// ```dart
/// // Create with a 256-bit key
/// final key = SecretKey(myKeyBytes);
/// final service = AesGcmEncryptionService(secretKey: key);
///
/// // Encrypt data
/// final result = await service.encrypt(plaintext);
/// final stored = result.combined; // IV + ciphertext
///
/// // Decrypt data
/// final decrypted = await service.decryptCombined(stored);
///
/// // Clean up when done
/// service.destroy();
/// ```
final class AesGcmEncryptionService implements EncryptionService {
  /// The secret key for encryption/decryption.
  SecretKey? _secretKey;

  /// The key size.
  final AesKeySize _keySize;

  /// Whether the service has been destroyed.
  bool _isDestroyed = false;

  /// Creates an AES-GCM encryption service with the given secret key.
  ///
  /// - [secretKey]: The secret key for encryption/decryption. Must be
  ///   16, 24, or 32 bytes for AES-128, AES-192, or AES-256 respectively.
  /// - [keySize]: The key size. Must match the actual key length.
  ///
  /// Throws [InvalidKeyException] if the key size is invalid.
  AesGcmEncryptionService._({
    required SecretKey secretKey,
    required AesKeySize keySize,
  }) : _secretKey = secretKey,
       _keySize = keySize;

  /// Creates an AES-GCM encryption service from raw key bytes.
  ///
  /// - [keyBytes]: The raw key bytes. Must be 16, 24, or 32 bytes.
  ///
  /// Throws [InvalidKeyException] if the key size is invalid.
  factory AesGcmEncryptionService.fromBytes(Uint8List keyBytes) {
    final keySize = _validateKeyBytes(keyBytes);
    return AesGcmEncryptionService._(
      secretKey: SecretKey(keyBytes),
      keySize: keySize,
    );
  }

  /// Creates an AES-GCM encryption service asynchronously from a SecretKey.
  ///
  /// - [secretKey]: The secret key for encryption/decryption.
  ///
  /// Throws [InvalidKeyException] if the key size is invalid.
  static Future<AesGcmEncryptionService> create(SecretKey secretKey) async {
    final bytes = await secretKey.extractBytes();
    final keySize = _validateKeyBytes(Uint8List.fromList(bytes));
    return AesGcmEncryptionService._(secretKey: secretKey, keySize: keySize);
  }

  /// Validates key bytes and returns the key size.
  static AesKeySize _validateKeyBytes(Uint8List keyBytes) {
    final length = keyBytes.length;
    if (!AesKeySize.supportedBytes.contains(length)) {
      throw InvalidKeyException.unsupportedSize(
        actual: length * 8,
        supported: AesKeySize.supportedBits,
      );
    }
    return AesKeySize.fromBytes(length);
  }

  /// Gets the appropriate AES-GCM cipher for the key size.
  AesGcm _getCipher() {
    return switch (_keySize) {
      AesKeySize.bits128 => AesGcm.with128bits(),
      AesKeySize.bits192 => AesGcm.with192bits(),
      AesKeySize.bits256 => AesGcm.with256bits(),
    };
  }

  /// Ensures the service is not destroyed and is ready for use.
  void _ensureNotDestroyed() {
    if (_isDestroyed) {
      throw const EncryptionNotInitializedException();
    }
  }

  @override
  bool get isEnabled => true;

  @override
  AesKeySize get keySize => _keySize;

  @override
  Future<EncryptionResult> encrypt(
    Uint8List plaintext, {
    Uint8List? aad,
  }) async {
    _ensureNotDestroyed();

    try {
      final cipher = _getCipher();
      final secretBox = await cipher.encrypt(
        plaintext,
        secretKey: _secretKey!,
        aad: aad ?? const <int>[],
      );

      // SecretBox contains: nonce + ciphertext + mac
      // We return nonce as IV and ciphertext + mac as ciphertext
      return EncryptionResult(
        iv: Uint8List.fromList(secretBox.nonce),
        ciphertext: Uint8List.fromList(
          secretBox.cipherText + secretBox.mac.bytes,
        ),
      );
    } catch (e, stackTrace) {
      if (e is EncryptionException) rethrow;
      throw EncryptionFailedException(
        'Encryption failed: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Uint8List> decrypt(
    Uint8List ciphertext, {
    required Uint8List iv,
    Uint8List? aad,
  }) async {
    _ensureNotDestroyed();

    // GCM tag is 16 bytes (128 bits)
    const tagLength = 16;

    if (ciphertext.length < tagLength) {
      throw const DecryptionException(
        'Ciphertext too short: must include authentication tag',
      );
    }

    try {
      final cipher = _getCipher();

      // Split ciphertext and MAC
      final actualCiphertext = ciphertext.sublist(
        0,
        ciphertext.length - tagLength,
      );
      final mac = Mac(ciphertext.sublist(ciphertext.length - tagLength));

      final secretBox = SecretBox(actualCiphertext, nonce: iv, mac: mac);

      final decrypted = await cipher.decrypt(
        secretBox,
        secretKey: _secretKey!,
        aad: aad ?? const <int>[],
      );

      return Uint8List.fromList(decrypted);
    } on SecretBoxAuthenticationError catch (e, stackTrace) {
      throw AuthenticationFailedException(cause: e, stackTrace: stackTrace);
    } catch (e, stackTrace) {
      if (e is EncryptionException) rethrow;
      throw DecryptionException(
        'Decryption failed: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Uint8List> decryptCombined(
    Uint8List combined, {
    Uint8List? aad,
    int ivLength = 12,
  }) async {
    if (combined.length <= ivLength) {
      throw DecryptionException(
        'Data too short: must be longer than IV length ($ivLength bytes)',
      );
    }

    final iv = Uint8List.sublistView(combined, 0, ivLength);
    final ciphertext = Uint8List.sublistView(combined, ivLength);

    return decrypt(ciphertext, iv: iv, aad: aad);
  }

  @override
  Future<String> encryptString(String plaintext, {Uint8List? aad}) async {
    final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
    final result = await encrypt(plaintextBytes, aad: aad);
    return base64Encode(result.combined);
  }

  @override
  Future<String> decryptString(String ciphertext, {Uint8List? aad}) async {
    final combined = base64Decode(ciphertext);
    final decrypted = await decryptCombined(
      Uint8List.fromList(combined),
      aad: aad,
    );
    return utf8.decode(decrypted);
  }

  @override
  void destroy() {
    _isDestroyed = true;
    _secretKey = null;
  }

  /// Whether this service has been destroyed.
  @visibleForTesting
  bool get isDestroyed => _isDestroyed;
}
