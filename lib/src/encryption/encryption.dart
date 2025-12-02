/// DocDB Encryption Module
///
/// Provides data-at-rest encryption services for the database.
/// Supports AES-GCM authenticated encryption with 128/192/256-bit keys.
///
/// ## Overview
///
/// The encryption module provides:
/// - **AES-GCM encryption**: Authenticated encryption ensuring both
///   confidentiality and integrity
/// - **Password-based keys**: PBKDF2 key derivation from passwords
/// - **AAD support**: Additional Authenticated Data for context binding
/// - **No-op mode**: Pass-through for development/testing
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/encryption/encryption_module.dart';
///
/// // Option 1: Direct key
/// final key = Uint8List(32); // Your 256-bit key
/// final service = AesGcmEncryptionService.fromBytes(key);
///
/// // Option 2: Password-derived key
/// final derivation = KeyDerivationService();
/// final derived = await derivation.deriveKey('user-password');
/// final service = AesGcmEncryptionService(secretKey: derived.secretKey);
///
/// // Encrypt data
/// final result = await service.encrypt(plaintext);
/// final stored = result.combined; // Store this
///
/// // Decrypt data
/// final decrypted = await service.decryptCombined(stored);
///
/// // Clean up
/// service.destroy();
/// ```
///
/// ## Security Recommendations
///
/// 1. **Use 256-bit keys**: Provides the strongest security.
/// 2. **Store salt separately**: For password-derived keys, store the salt
///    in a secure location.
/// 3. **Use AAD when possible**: Bind ciphertext to its context.
/// 4. **Destroy keys when done**: Call `destroy()` to clear key material.
/// 5. **Never reuse IVs**: The service generates random IVs automatically.
///
/// ## Disabling Encryption
///
/// For development or when encryption isn't needed:
///
/// ```dart
/// final service = NoEncryptionService();
/// // Data passes through unchanged
/// ```
library;

export 'aes_gcm_encryption.dart' show AesGcmEncryptionService;
export 'encryption_service.dart'
    show AesKeySize, EncryptionResult, EncryptionService;
export 'key_derivation.dart'
    show DerivedKey, KeyDerivationConfig, KeyDerivationService;
export 'no_encryption_service.dart' show NoEncryptionService;
