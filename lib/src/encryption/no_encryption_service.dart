/// DocDB Encryption - No-Op Encryption Service
///
/// Provides a pass-through implementation that performs no actual encryption.
/// Useful for development, testing, or when encryption is explicitly disabled.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'encryption_service.dart';

/// A pass-through encryption service that performs no encryption.
///
/// This implementation simply returns data unchanged, allowing the database
/// to operate without encryption overhead when encryption is not required.
///
/// ## Use Cases
///
/// - **Development**: Faster iteration without encryption overhead.
/// - **Testing**: Inspect stored data without decryption.
/// - **Performance**: Maximum throughput when security isn't needed.
/// - **Migration**: Temporarily disable encryption during data migration.
///
/// ## Security Warning
///
/// **This service provides NO security.** Data stored using this service
/// is readable by anyone with access to the storage files. Only use this
/// in environments where data confidentiality is not a concern.
///
/// ## Usage
///
/// ```dart
/// final service = NoEncryptionService();
///
/// // Data passes through unchanged
/// final result = await service.encrypt(plaintext);
/// assert(result.ciphertext == plaintext); // Same data!
/// ```
final class NoEncryptionService implements EncryptionService {
  /// Creates a no-op encryption service.
  const NoEncryptionService();

  @override
  bool get isEnabled => false;

  @override
  AesKeySize? get keySize => null;

  @override
  Future<EncryptionResult> encrypt(
    Uint8List plaintext, {
    Uint8List? aad,
  }) async {
    // Return data unchanged with a dummy IV
    return EncryptionResult(
      ciphertext: plaintext,
      iv: Uint8List(12), // Empty IV
    );
  }

  @override
  Future<Uint8List> decrypt(
    Uint8List ciphertext, {
    required Uint8List iv,
    Uint8List? aad,
  }) async {
    // Return data unchanged
    return ciphertext;
  }

  @override
  Future<Uint8List> decryptCombined(
    Uint8List combined, {
    Uint8List? aad,
    int ivLength = 12,
  }) async {
    // Skip the IV prefix and return the rest
    if (combined.length <= ivLength) {
      return Uint8List(0);
    }
    return Uint8List.sublistView(combined, ivLength);
  }

  @override
  Future<String> encryptString(String plaintext, {Uint8List? aad}) async {
    // Encode with dummy IV prefix for format compatibility
    final plaintextBytes = utf8.encode(plaintext);
    final combined = Uint8List(12 + plaintextBytes.length);
    combined.setRange(12, combined.length, plaintextBytes);
    return base64Encode(combined);
  }

  @override
  Future<String> decryptString(String ciphertext, {Uint8List? aad}) async {
    final combined = base64Decode(ciphertext);
    if (combined.length <= 12) {
      return '';
    }
    return utf8.decode(combined.sublist(12));
  }

  @override
  void destroy() {
    // No-op: nothing to destroy
  }
}
