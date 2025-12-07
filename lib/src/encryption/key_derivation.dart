/// EntiDB Encryption - Key Derivation
///
/// Provides password-based key derivation using PBKDF2.
/// Converts user passwords into cryptographically strong keys.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../exceptions/encryption_exceptions.dart';
import 'encryption_service.dart';

/// Configuration for PBKDF2 key derivation.
///
/// Controls the security parameters of the key derivation function.
/// Higher iteration counts provide more security but slower derivation.
final class KeyDerivationConfig {
  /// Number of PBKDF2 iterations.
  ///
  /// OWASP recommends at least 600,000 iterations for PBKDF2-SHA256.
  /// Higher values provide more resistance to brute-force attacks.
  final int iterations;

  /// Length of the salt in bytes.
  ///
  /// Minimum recommended is 16 bytes (128 bits).
  final int saltLength;

  /// The target key size.
  final AesKeySize keySize;

  /// Creates a key derivation configuration.
  ///
  /// - [iterations]: Number of PBKDF2 iterations (default: 600,000).
  /// - [saltLength]: Salt length in bytes (default: 32).
  /// - [keySize]: Target key size (default: 256 bits).
  const KeyDerivationConfig({
    this.iterations = 600000,
    this.saltLength = 32,
    this.keySize = AesKeySize.bits256,
  });

  /// Default configuration with strong security parameters.
  static const KeyDerivationConfig defaultConfig = KeyDerivationConfig();

  /// Fast configuration for development/testing (NOT for production).
  static const KeyDerivationConfig fast = KeyDerivationConfig(
    iterations: 1000,
    saltLength: 16,
  );
}

/// Result of a key derivation operation.
///
/// Contains both the derived key and the salt used, which must be
/// stored to recreate the same key from the password.
final class DerivedKey {
  /// The derived encryption key.
  final SecretKey secretKey;

  /// The salt used during derivation.
  ///
  /// Must be stored alongside encrypted data to recreate the key.
  final Uint8List salt;

  /// The configuration used for derivation.
  final KeyDerivationConfig config;

  /// Creates a new derived key result.
  const DerivedKey({
    required this.secretKey,
    required this.salt,
    required this.config,
  });

  /// Extracts the raw key bytes.
  Future<Uint8List> extractKeyBytes() async {
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }
}

/// Password-based key derivation service.
///
/// Converts user passwords into cryptographically strong encryption keys
/// using PBKDF2 with SHA-256.
///
/// ## Security Notes
///
/// - Always use a unique random salt for each password
/// - Store the salt alongside the encrypted data
/// - Use sufficient iterations (600,000+ recommended)
/// - Consider using memory-hard functions (Argon2) for higher security
///
/// ## Usage
///
/// ```dart
/// final derivation = KeyDerivationService();
///
/// // Derive a new key from a password
/// final derived = await derivation.deriveKey('user-password');
///
/// // Store the salt with the encrypted data
/// storeSalt(derived.salt);
///
/// // Later, recreate the key with the same salt
/// final key = await derivation.deriveKeyWithSalt(
///   'user-password',
///   storedSalt,
/// );
/// ```
final class KeyDerivationService {
  /// The configuration for key derivation.
  final KeyDerivationConfig config;

  /// The PBKDF2 algorithm instance.
  late final Pbkdf2 _pbkdf2;

  /// Secure random generator for salt generation.
  final Random _random = Random.secure();

  /// Creates a key derivation service with the given configuration.
  KeyDerivationService({this.config = KeyDerivationConfig.defaultConfig}) {
    _pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: config.iterations,
      bits: config.keySize.bits,
    );
  }

  /// Derives a key from a password with a newly generated random salt.
  ///
  /// - [password]: The password to derive a key from.
  ///
  /// Returns a [DerivedKey] containing the key and salt.
  ///
  /// Throws [KeyDerivationException] if derivation fails.
  Future<DerivedKey> deriveKey(String password) async {
    if (password.isEmpty) {
      throw const KeyDerivationException('Password cannot be empty');
    }

    final salt = _generateSalt();
    return deriveKeyWithSalt(password, salt);
  }

  /// Derives a key from a password using a specific salt.
  ///
  /// Use this method to recreate a key that was previously derived.
  ///
  /// - [password]: The password to derive a key from.
  /// - [salt]: The salt to use (must be the same as original derivation).
  ///
  /// Returns a [DerivedKey] containing the key and salt.
  ///
  /// Throws [KeyDerivationException] if derivation fails.
  Future<DerivedKey> deriveKeyWithSalt(String password, Uint8List salt) async {
    if (password.isEmpty) {
      throw const KeyDerivationException('Password cannot be empty');
    }

    if (salt.isEmpty) {
      throw const KeyDerivationException('Salt cannot be empty');
    }

    try {
      final secretKey = await _pbkdf2.deriveKey(
        secretKey: SecretKey(password.codeUnits),
        nonce: salt,
      );

      return DerivedKey(secretKey: secretKey, salt: salt, config: config);
    } catch (e, stackTrace) {
      throw KeyDerivationException(
        'Key derivation failed: $e',
        cause: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Generates a cryptographically secure random salt.
  Uint8List _generateSalt() {
    final salt = Uint8List(config.saltLength);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }

  /// Validates that a password meets minimum requirements.
  ///
  /// Returns `true` if the password is acceptable.
  /// Override this method to implement custom password policies.
  bool validatePassword(String password) {
    // Minimum 8 characters
    return password.length >= 8;
  }
}
