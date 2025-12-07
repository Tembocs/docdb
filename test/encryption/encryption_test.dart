/// EntiDB Encryption Module Tests
///
/// Comprehensive tests for the encryption module including AesGcmEncryptionService,
/// NoEncryptionService, and KeyDerivationService.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'package:entidb/src/encryption/encryption.dart';
import 'package:entidb/src/exceptions/encryption_exceptions.dart';

void main() {
  group('AesKeySize Enum', () {
    test('should have correct byte values', () {
      expect(AesKeySize.bits128.bytes, equals(16));
      expect(AesKeySize.bits192.bytes, equals(24));
      expect(AesKeySize.bits256.bytes, equals(32));
    });

    test('should have correct bit values', () {
      expect(AesKeySize.bits128.bits, equals(128));
      expect(AesKeySize.bits192.bits, equals(192));
      expect(AesKeySize.bits256.bits, equals(256));
    });

    test('should create from byte length', () {
      expect(AesKeySize.fromBytes(16), equals(AesKeySize.bits128));
      expect(AesKeySize.fromBytes(24), equals(AesKeySize.bits192));
      expect(AesKeySize.fromBytes(32), equals(AesKeySize.bits256));
    });

    test('should throw for invalid byte length', () {
      expect(() => AesKeySize.fromBytes(15), throwsArgumentError);
      expect(() => AesKeySize.fromBytes(20), throwsArgumentError);
      expect(() => AesKeySize.fromBytes(64), throwsArgumentError);
    });

    test('should have correct supported sizes', () {
      expect(AesKeySize.supportedBits, equals([128, 192, 256]));
      expect(AesKeySize.supportedBytes, equals([16, 24, 32]));
    });
  });

  group('EncryptionResult', () {
    test('should create with ciphertext and iv', () {
      final ciphertext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final iv = Uint8List.fromList([
        10,
        20,
        30,
        40,
        50,
        60,
        70,
        80,
        90,
        100,
        110,
        120,
      ]);

      final result = EncryptionResult(ciphertext: ciphertext, iv: iv);

      expect(result.ciphertext, equals(ciphertext));
      expect(result.iv, equals(iv));
    });

    test('should combine iv and ciphertext', () {
      final ciphertext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final iv = Uint8List.fromList([
        10,
        20,
        30,
        40,
        50,
        60,
        70,
        80,
        90,
        100,
        110,
        120,
      ]);

      final result = EncryptionResult(ciphertext: ciphertext, iv: iv);
      final combined = result.combined;

      expect(combined.length, equals(iv.length + ciphertext.length));
      expect(combined.sublist(0, iv.length), equals(iv));
      expect(combined.sublist(iv.length), equals(ciphertext));
    });

    test('should parse from combined data', () {
      final iv = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final ciphertext = Uint8List.fromList([100, 101, 102, 103, 104]);
      final combined = Uint8List(iv.length + ciphertext.length);
      combined.setRange(0, iv.length, iv);
      combined.setRange(iv.length, combined.length, ciphertext);

      final result = EncryptionResult.fromCombined(combined);

      expect(result.iv, equals(iv));
      expect(result.ciphertext, equals(ciphertext));
    });

    test('should throw for data shorter than IV length', () {
      final shortData = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(
        () => EncryptionResult.fromCombined(shortData),
        throwsArgumentError,
      );
    });

    test('should handle custom IV length', () {
      final iv = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final ciphertext = Uint8List.fromList([100, 101, 102]);
      final combined = Uint8List(iv.length + ciphertext.length);
      combined.setRange(0, iv.length, iv);
      combined.setRange(iv.length, combined.length, ciphertext);

      final result = EncryptionResult.fromCombined(combined, ivLength: 8);

      expect(result.iv, equals(iv));
      expect(result.ciphertext, equals(ciphertext));
    });
  });

  group('AesGcmEncryptionService', () {
    late AesGcmEncryptionService service128;
    late AesGcmEncryptionService service192;
    late AesGcmEncryptionService service256;

    setUp(() async {
      // Generate keys for each size
      final key128 = Uint8List.fromList(List.generate(16, (i) => i));
      final key192 = Uint8List.fromList(List.generate(24, (i) => i));
      final key256 = Uint8List.fromList(List.generate(32, (i) => i));

      service128 = AesGcmEncryptionService.fromBytes(key128);
      service192 = AesGcmEncryptionService.fromBytes(key192);
      service256 = AesGcmEncryptionService.fromBytes(key256);
    });

    group('Construction', () {
      test('should create from 128-bit key', () {
        final key = Uint8List.fromList(List.generate(16, (i) => i));
        final service = AesGcmEncryptionService.fromBytes(key);

        expect(service.isEnabled, isTrue);
        expect(service.keySize, equals(AesKeySize.bits128));
      });

      test('should create from 192-bit key', () {
        final key = Uint8List.fromList(List.generate(24, (i) => i));
        final service = AesGcmEncryptionService.fromBytes(key);

        expect(service.isEnabled, isTrue);
        expect(service.keySize, equals(AesKeySize.bits192));
      });

      test('should create from 256-bit key', () {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final service = AesGcmEncryptionService.fromBytes(key);

        expect(service.isEnabled, isTrue);
        expect(service.keySize, equals(AesKeySize.bits256));
      });

      test('should throw for invalid key size', () {
        final invalidKey = Uint8List.fromList(List.generate(20, (i) => i));

        expect(
          () => AesGcmEncryptionService.fromBytes(invalidKey),
          throwsA(isA<InvalidKeyException>()),
        );
      });

      test('should create async from SecretKey', () async {
        final secretKey = SecretKey(List.generate(32, (i) => i));
        final service = await AesGcmEncryptionService.create(secretKey);

        expect(service.isEnabled, isTrue);
        expect(service.keySize, equals(AesKeySize.bits256));
      });
    });

    group('Encrypt/Decrypt', () {
      test('should encrypt and decrypt binary data', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Hello, World!'));

        final encrypted = await service256.encrypt(plaintext);
        expect(encrypted.ciphertext, isNot(equals(plaintext)));
        expect(encrypted.iv.length, equals(12)); // GCM uses 12-byte IV

        final decrypted = await service256.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
        );

        expect(decrypted, equals(plaintext));
      });

      test('should encrypt and decrypt empty data', () async {
        final plaintext = Uint8List(0);

        final encrypted = await service256.encrypt(plaintext);
        final decrypted = await service256.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
        );

        expect(decrypted, equals(plaintext));
      });

      test('should encrypt and decrypt large data', () async {
        // 1 MB of data
        final plaintext = Uint8List.fromList(
          List.generate(1024 * 1024, (i) => i % 256),
        );

        final encrypted = await service256.encrypt(plaintext);
        final decrypted = await service256.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
        );

        expect(decrypted, equals(plaintext));
      });

      test('should generate unique IV for each encryption', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Test data'));

        final result1 = await service256.encrypt(plaintext);
        final result2 = await service256.encrypt(plaintext);

        // IVs should be different
        expect(result1.iv, isNot(equals(result2.iv)));
        // Ciphertexts will also be different due to different IVs
        expect(result1.ciphertext, isNot(equals(result2.ciphertext)));
      });

      test('should work with different key sizes', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Test message'));

        for (final service in [service128, service192, service256]) {
          final encrypted = await service.encrypt(plaintext);
          final decrypted = await service.decrypt(
            encrypted.ciphertext,
            iv: encrypted.iv,
          );
          expect(decrypted, equals(plaintext));
        }
      });
    });

    group('Decrypt Combined', () {
      test('should decrypt combined IV + ciphertext', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Combined test'));

        final encrypted = await service256.encrypt(plaintext);
        final combined = encrypted.combined;

        final decrypted = await service256.decryptCombined(combined);

        expect(decrypted, equals(plaintext));
      });

      test('should throw for data shorter than IV', () async {
        final shortData = Uint8List.fromList([1, 2, 3, 4, 5]);

        expect(
          () => service256.decryptCombined(shortData),
          throwsA(isA<DecryptionException>()),
        );
      });
    });

    group('String Encryption', () {
      test('should encrypt and decrypt strings', () async {
        const plaintext = 'Hello, encryption!';

        final encrypted = await service256.encryptString(plaintext);
        expect(encrypted, isNot(equals(plaintext)));
        expect(encrypted, contains(RegExp(r'^[A-Za-z0-9+/=]+$'))); // Base64

        final decrypted = await service256.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });

      test('should handle empty string', () async {
        const plaintext = '';

        final encrypted = await service256.encryptString(plaintext);
        final decrypted = await service256.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });

      test('should handle unicode strings', () async {
        const plaintext = '你好世界 🌍 مرحبا';

        final encrypted = await service256.encryptString(plaintext);
        final decrypted = await service256.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });

      test('should handle long strings', () async {
        final plaintext = 'A' * 10000;

        final encrypted = await service256.encryptString(plaintext);
        final decrypted = await service256.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });
    });

    group('Additional Authenticated Data (AAD)', () {
      test('should encrypt with AAD', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret data'));
        final aad = Uint8List.fromList(utf8.encode('context-info'));

        final encrypted = await service256.encrypt(plaintext, aad: aad);
        final decrypted = await service256.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
          aad: aad,
        );

        expect(decrypted, equals(plaintext));
      });

      test('should fail decryption with wrong AAD', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret data'));
        final aad = Uint8List.fromList(utf8.encode('context-info'));
        final wrongAad = Uint8List.fromList(utf8.encode('wrong-context'));

        final encrypted = await service256.encrypt(plaintext, aad: aad);

        expect(
          () => service256.decrypt(
            encrypted.ciphertext,
            iv: encrypted.iv,
            aad: wrongAad,
          ),
          throwsA(isA<AuthenticationFailedException>()),
        );
      });

      test('should fail decryption when AAD missing', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Secret data'));
        final aad = Uint8List.fromList(utf8.encode('context-info'));

        final encrypted = await service256.encrypt(plaintext, aad: aad);

        // Decrypting without AAD when it was used for encryption should fail
        expect(
          () => service256.decrypt(encrypted.ciphertext, iv: encrypted.iv),
          throwsA(isA<AuthenticationFailedException>()),
        );
      });

      test('should use AAD with string encryption', () async {
        const plaintext = 'Secret string';
        final aad = Uint8List.fromList(utf8.encode('string-context'));

        final encrypted = await service256.encryptString(plaintext, aad: aad);
        final decrypted = await service256.decryptString(encrypted, aad: aad);

        expect(decrypted, equals(plaintext));
      });
    });

    group('Authentication', () {
      test('should detect tampered ciphertext', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Original data'));

        final encrypted = await service256.encrypt(plaintext);

        // Tamper with the ciphertext
        final tampered = Uint8List.fromList(encrypted.ciphertext);
        tampered[0] ^= 0xFF;

        expect(
          () => service256.decrypt(tampered, iv: encrypted.iv),
          throwsA(isA<AuthenticationFailedException>()),
        );
      });

      test('should detect tampered IV', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Original data'));

        final encrypted = await service256.encrypt(plaintext);

        // Tamper with the IV
        final tamperedIv = Uint8List.fromList(encrypted.iv);
        tamperedIv[0] ^= 0xFF;

        expect(
          () => service256.decrypt(encrypted.ciphertext, iv: tamperedIv),
          throwsA(isA<AuthenticationFailedException>()),
        );
      });

      test('should detect truncated ciphertext', () async {
        final plaintext = Uint8List.fromList(utf8.encode('Original data'));

        final encrypted = await service256.encrypt(plaintext);

        // Truncate the ciphertext (remove auth tag)
        final truncated = Uint8List.sublistView(
          encrypted.ciphertext,
          0,
          encrypted.ciphertext.length - 8,
        );

        expect(
          () => service256.decrypt(truncated, iv: encrypted.iv),
          throwsA(isA<AuthenticationFailedException>()),
        );
      });
    });

    group('Destroy', () {
      test('should throw after destruction', () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final tempService = AesGcmEncryptionService.fromBytes(key);

        // Use normally first
        final plaintext = Uint8List.fromList(utf8.encode('Test'));
        await tempService.encrypt(plaintext);

        // Destroy
        tempService.destroy();

        // Should throw after destroy
        expect(
          () => tempService.encrypt(plaintext),
          throwsA(isA<EncryptionNotInitializedException>()),
        );
      });
    });
  });

  group('NoEncryptionService', () {
    late NoEncryptionService service;

    setUp(() {
      service = const NoEncryptionService();
    });

    group('Properties', () {
      test('should report encryption as disabled', () {
        expect(service.isEnabled, isFalse);
      });

      test('should have null key size', () {
        expect(service.keySize, isNull);
      });
    });

    group('Encrypt/Decrypt', () {
      test('should pass through binary data unchanged', () async {
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final encrypted = await service.encrypt(plaintext);
        expect(encrypted.ciphertext, equals(plaintext));

        final decrypted = await service.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
        );
        expect(decrypted, equals(plaintext));
      });

      test('should generate dummy IV', () async {
        final plaintext = Uint8List.fromList([1, 2, 3]);

        final encrypted = await service.encrypt(plaintext);

        expect(encrypted.iv.length, equals(12));
        expect(encrypted.iv, equals(Uint8List(12))); // All zeros
      });

      test('should decrypt combined data', () async {
        final plaintext = Uint8List.fromList([10, 20, 30, 40]);

        final encrypted = await service.encrypt(plaintext);
        final combined = encrypted.combined;

        final decrypted = await service.decryptCombined(combined);

        expect(decrypted, equals(plaintext));
      });
    });

    group('String Encryption', () {
      test('should pass through string data', () async {
        const plaintext = 'Hello, World!';

        final encrypted = await service.encryptString(plaintext);
        final decrypted = await service.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });

      test('should handle empty string', () async {
        const plaintext = '';

        final encrypted = await service.encryptString(plaintext);
        final decrypted = await service.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });

      test('should produce base64 encoded output', () async {
        const plaintext = 'Test';

        final encrypted = await service.encryptString(plaintext);

        // Should be valid base64
        expect(() => base64Decode(encrypted), returnsNormally);
      });
    });

    group('AAD Handling', () {
      test('should ignore AAD', () async {
        final plaintext = Uint8List.fromList([1, 2, 3]);
        final aad = Uint8List.fromList([100, 101, 102]);

        final encrypted = await service.encrypt(plaintext, aad: aad);
        expect(encrypted.ciphertext, equals(plaintext));

        // Should still decrypt with or without AAD
        final decrypted1 = await service.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
          aad: aad,
        );
        final decrypted2 = await service.decrypt(
          encrypted.ciphertext,
          iv: encrypted.iv,
        );

        expect(decrypted1, equals(plaintext));
        expect(decrypted2, equals(plaintext));
      });
    });
  });

  group('KeyDerivationService', () {
    late KeyDerivationService service;

    setUp(() {
      // Use fast config for tests
      service = KeyDerivationService(config: KeyDerivationConfig.fast);
    });

    group('KeyDerivationConfig', () {
      test('should have default config values', () {
        const config = KeyDerivationConfig.defaultConfig;

        expect(config.iterations, equals(600000));
        expect(config.saltLength, equals(32));
        expect(config.keySize, equals(AesKeySize.bits256));
      });

      test('should have fast config values', () {
        const config = KeyDerivationConfig.fast;

        expect(config.iterations, equals(1000));
        expect(config.saltLength, equals(16));
      });

      test('should create custom config', () {
        const config = KeyDerivationConfig(
          iterations: 10000,
          saltLength: 24,
          keySize: AesKeySize.bits128,
        );

        expect(config.iterations, equals(10000));
        expect(config.saltLength, equals(24));
        expect(config.keySize, equals(AesKeySize.bits128));
      });
    });

    group('Key Derivation', () {
      test('should derive key from password', () async {
        const password = 'my-secret-password';

        final derived = await service.deriveKey(password);

        expect(derived.secretKey, isNotNull);
        expect(derived.salt.length, equals(service.config.saltLength));
        expect(derived.config, equals(service.config));
      });

      test('should derive correct key size', () async {
        const password = 'test-password';

        // 128-bit key
        final service128 = KeyDerivationService(
          config: const KeyDerivationConfig(
            iterations: 1000,
            keySize: AesKeySize.bits128,
          ),
        );
        final key128 = await service128.deriveKey(password);
        final bytes128 = await key128.extractKeyBytes();
        expect(bytes128.length, equals(16));

        // 256-bit key
        final service256 = KeyDerivationService(
          config: const KeyDerivationConfig(
            iterations: 1000,
            keySize: AesKeySize.bits256,
          ),
        );
        final key256 = await service256.deriveKey(password);
        final bytes256 = await key256.extractKeyBytes();
        expect(bytes256.length, equals(32));
      });

      test('should generate unique salt each time', () async {
        const password = 'same-password';

        final derived1 = await service.deriveKey(password);
        final derived2 = await service.deriveKey(password);

        expect(derived1.salt, isNot(equals(derived2.salt)));
      });

      test('should throw for empty password', () async {
        expect(
          () => service.deriveKey(''),
          throwsA(isA<KeyDerivationException>()),
        );
      });
    });

    group('Derive with Salt', () {
      test('should derive same key with same salt', () async {
        const password = 'consistent-password';

        final derived1 = await service.deriveKey(password);
        final derived2 = await service.deriveKeyWithSalt(
          password,
          derived1.salt,
        );

        final bytes1 = await derived1.extractKeyBytes();
        final bytes2 = await derived2.extractKeyBytes();

        expect(bytes1, equals(bytes2));
      });

      test('should derive different key with different salt', () async {
        const password = 'same-password';

        final derived1 = await service.deriveKey(password);
        final derived2 = await service.deriveKey(password);

        final bytes1 = await derived1.extractKeyBytes();
        final bytes2 = await derived2.extractKeyBytes();

        expect(bytes1, isNot(equals(bytes2)));
      });

      test('should derive different key for different password', () async {
        const password1 = 'password-one';
        const password2 = 'password-two';

        final derived1 = await service.deriveKey(password1);
        final derived2 = await service.deriveKeyWithSalt(
          password2,
          derived1.salt,
        );

        final bytes1 = await derived1.extractKeyBytes();
        final bytes2 = await derived2.extractKeyBytes();

        expect(bytes1, isNot(equals(bytes2)));
      });
    });

    group('Integration with Encryption', () {
      test('should create encryption service from derived key', () async {
        const password = 'encryption-password';

        final derived = await service.deriveKey(password);
        final keyBytes = await derived.extractKeyBytes();

        final encryptionService = AesGcmEncryptionService.fromBytes(keyBytes);
        expect(encryptionService.isEnabled, isTrue);
      });

      test('should encrypt and decrypt using derived key', () async {
        const password = 'full-cycle-password';
        const plaintext = 'Secret message to encrypt';

        // Derive key and create encryption service
        final derived = await service.deriveKey(password);
        final keyBytes = await derived.extractKeyBytes();
        final encryptionService = AesGcmEncryptionService.fromBytes(keyBytes);

        // Encrypt
        final encrypted = await encryptionService.encryptString(plaintext);

        // Recreate key from password and salt
        final derived2 = await service.deriveKeyWithSalt(
          password,
          derived.salt,
        );
        final keyBytes2 = await derived2.extractKeyBytes();
        final encryptionService2 = AesGcmEncryptionService.fromBytes(keyBytes2);

        // Decrypt
        final decrypted = await encryptionService2.decryptString(encrypted);

        expect(decrypted, equals(plaintext));
      });
    });
  });

  group('EncryptionService Interface', () {
    test('AesGcmEncryptionService should implement EncryptionService', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final service = AesGcmEncryptionService.fromBytes(key);

      expect(service, isA<EncryptionService>());
    });

    test('NoEncryptionService should implement EncryptionService', () {
      const service = NoEncryptionService();

      expect(service, isA<EncryptionService>());
    });
  });
}
