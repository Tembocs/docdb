/// DocDB Storage - Binary Serialization Module
///
/// Provides CBOR-based binary serialization with optional encryption support.
/// This module serves as the serialization layer for all storage implementations.
///
/// ## Features
///
/// - CBOR (RFC 8949) binary encoding for compact, efficient storage
/// - Optional AES-GCM encryption for data-at-rest security
/// - Support for all Dart types including DateTime and binary data
/// - Streaming-friendly design for large documents
///
/// ## Data Format
///
/// ### Unencrypted
/// ```
/// ┌────────────────────────────────────────────────────────┐
/// │ Magic (2)  │ Version (1) │ Flags (1) │ CBOR Data (var) │
/// └────────────────────────────────────────────────────────┘
/// ```
///
/// ### Encrypted
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │ Magic (2) │ Version (1) │ Flags (1) │ IV (12) │ Ciphertext (var) │
/// └─────────────────────────────────────────────────────────────────┘
/// ```
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:meta/meta.dart';

import '../encryption/encryption_service.dart';
import '../encryption/no_encryption_service.dart';
import '../exceptions/storage_exceptions.dart';

/// Magic number for serialized data (0x44 0x42 = "DB").
const int _serializationMagic = 0x4442;

/// Current serialization format version.
const int _serializationVersion = 1;

/// Serialization flags.
abstract final class SerializationFlags {
  /// No special flags.
  static const int none = 0x00;

  /// Data is encrypted.
  static const int encrypted = 0x01;

  /// Data is compressed (reserved for future use).
  static const int compressed = 0x02;
}

/// Header size for serialized data.
const int _headerSize = 4; // magic (2) + version (1) + flags (1)

/// IV size for AES-GCM encryption.
const int _ivSize = 12;

/// Configuration for the serialization service.
@immutable
class SerializationConfig {
  /// The encryption service to use (null for no encryption).
  final EncryptionService? encryptionService;

  /// Whether to enable encryption.
  bool get encryptionEnabled =>
      encryptionService != null && encryptionService!.isEnabled;

  /// Creates a new serialization configuration.
  const SerializationConfig({this.encryptionService});

  /// Default configuration (no encryption).
  static const SerializationConfig defaults = SerializationConfig();

  /// Creates a configuration with encryption.
  factory SerializationConfig.encrypted(EncryptionService service) {
    return SerializationConfig(encryptionService: service);
  }

  /// Creates a configuration without encryption (explicit).
  factory SerializationConfig.unencrypted() {
    return const SerializationConfig(encryptionService: NoEncryptionService());
  }
}

/// Binary serialization service using CBOR with optional encryption.
///
/// This service provides the core serialization functionality for all
/// storage implementations in DocDB.
///
/// ## Usage
///
/// ```dart
/// // Without encryption
/// final serializer = BinarySerializer();
/// final bytes = await serializer.serialize({'name': 'Alice', 'age': 30});
/// final data = await serializer.deserialize(bytes);
///
/// // With encryption
/// final key = await deriveKey(password, salt);
/// final encryptedSerializer = BinarySerializer(
///   config: SerializationConfig.encrypted(
///     AesGcmEncryptionService.fromBytes(key),
///   ),
/// );
/// final encrypted = await encryptedSerializer.serialize(data);
/// ```
class BinarySerializer {
  /// The serialization configuration.
  final SerializationConfig config;

  /// Creates a new binary serializer.
  BinarySerializer({this.config = SerializationConfig.defaults});

  /// Whether encryption is enabled.
  bool get encryptionEnabled => config.encryptionEnabled;

  /// Serializes a Map to binary format.
  ///
  /// The data is first encoded to CBOR, then optionally encrypted.
  ///
  /// - [data]: The map to serialize.
  /// - [aad]: Optional additional authenticated data for encryption.
  ///
  /// Returns the serialized bytes.
  ///
  /// Throws [SerializationException] if serialization fails.
  Future<Uint8List> serialize(
    Map<String, dynamic> data, {
    Uint8List? aad,
  }) async {
    try {
      // Convert to CBOR
      final cborValue = _mapToCbor(data);
      final cborBytes = Uint8List.fromList(cbor.encode(cborValue));

      if (config.encryptionEnabled) {
        return await _serializeEncrypted(cborBytes, aad: aad);
      } else {
        return _serializeUnencrypted(cborBytes);
      }
    } catch (e, st) {
      if (e is StorageException) rethrow;
      throw SerializationException(
        'Failed to serialize data: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Deserializes binary data to a Map.
  ///
  /// - [bytes]: The serialized bytes.
  /// - [aad]: Optional additional authenticated data (must match encryption).
  ///
  /// Returns the deserialized map.
  ///
  /// Throws [SerializationException] if deserialization fails.
  /// Throws [AuthenticationFailedException] if decryption authentication fails.
  Future<Map<String, dynamic>> deserialize(
    Uint8List bytes, {
    Uint8List? aad,
  }) async {
    try {
      if (bytes.length < _headerSize) {
        throw const SerializationException('Data too short: missing header');
      }

      // Read and validate header
      final magic = (bytes[0] << 8) | bytes[1];
      if (magic != _serializationMagic) {
        throw SerializationException(
          'Invalid magic number: expected 0x${_serializationMagic.toRadixString(16)}, '
          'got 0x${magic.toRadixString(16)}',
        );
      }

      final version = bytes[2];
      if (version > _serializationVersion) {
        throw SerializationException(
          'Unsupported format version: $version (max: $_serializationVersion)',
        );
      }

      final flags = bytes[3];
      final isEncrypted = (flags & SerializationFlags.encrypted) != 0;

      Uint8List cborBytes;

      if (isEncrypted) {
        cborBytes = await _deserializeEncrypted(bytes, aad: aad);
      } else {
        cborBytes = _deserializeUnencrypted(bytes);
      }

      // Decode CBOR
      final cborValue = cbor.decode(cborBytes);
      return _cborToMap(cborValue);
    } catch (e, st) {
      if (e is StorageException) rethrow;
      throw SerializationException(
        'Failed to deserialize data: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Serializes without encryption.
  Uint8List _serializeUnencrypted(Uint8List cborBytes) {
    final result = Uint8List(_headerSize + cborBytes.length);

    // Write header
    result[0] = (_serializationMagic >> 8) & 0xFF;
    result[1] = _serializationMagic & 0xFF;
    result[2] = _serializationVersion;
    result[3] = SerializationFlags.none;

    // Write CBOR data
    result.setRange(_headerSize, result.length, cborBytes);

    return result;
  }

  /// Serializes with encryption.
  Future<Uint8List> _serializeEncrypted(
    Uint8List cborBytes, {
    Uint8List? aad,
  }) async {
    final encryptionResult = await config.encryptionService!.encrypt(
      cborBytes,
      aad: aad,
    );

    final result = Uint8List(
      _headerSize + _ivSize + encryptionResult.ciphertext.length,
    );

    // Write header
    result[0] = (_serializationMagic >> 8) & 0xFF;
    result[1] = _serializationMagic & 0xFF;
    result[2] = _serializationVersion;
    result[3] = SerializationFlags.encrypted;

    // Write IV
    result.setRange(_headerSize, _headerSize + _ivSize, encryptionResult.iv);

    // Write ciphertext
    result.setRange(
      _headerSize + _ivSize,
      result.length,
      encryptionResult.ciphertext,
    );

    return result;
  }

  /// Deserializes unencrypted data.
  Uint8List _deserializeUnencrypted(Uint8List bytes) {
    return Uint8List.sublistView(bytes, _headerSize);
  }

  /// Deserializes encrypted data.
  Future<Uint8List> _deserializeEncrypted(
    Uint8List bytes, {
    Uint8List? aad,
  }) async {
    if (config.encryptionService == null) {
      throw const SerializationException(
        'Data is encrypted but no encryption service configured',
      );
    }

    if (bytes.length < _headerSize + _ivSize) {
      throw const SerializationException(
        'Encrypted data too short: missing IV',
      );
    }

    final iv = Uint8List.sublistView(bytes, _headerSize, _headerSize + _ivSize);
    final ciphertext = Uint8List.sublistView(bytes, _headerSize + _ivSize);

    return await config.encryptionService!.decrypt(
      ciphertext,
      iv: iv,
      aad: aad,
    );
  }

  /// Converts a Dart Map to CBOR value.
  CborValue _mapToCbor(Map<String, dynamic> map) {
    final cborMap = <CborValue, CborValue>{};

    for (final entry in map.entries) {
      cborMap[CborString(entry.key)] = _valueToCbor(entry.value);
    }

    return CborMap(cborMap);
  }

  /// Converts a Dart value to CBOR value.
  CborValue _valueToCbor(dynamic value) {
    return switch (value) {
      null => const CborNull(),
      bool b => CborBool(b),
      int i => CborInt(BigInt.from(i)),
      double d => CborFloat(d),
      String s => CborString(s),
      // Store DateTime as CBOR epoch datetime
      DateTime dt => CborDateTimeInt(dt),
      Uint8List bytes => CborBytes(bytes),
      List list => CborList(list.map(_valueToCbor).toList()),
      Map<String, dynamic> map => _mapToCbor(map),
      _ => CborString(value.toString()),
    };
  }

  /// Converts a CBOR value to Dart Map.
  Map<String, dynamic> _cborToMap(CborValue value) {
    if (value is! CborMap) {
      throw const SerializationException('Expected CBOR map at root');
    }

    final result = <String, dynamic>{};

    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! CborString) {
        throw const SerializationException('Map keys must be strings');
      }
      result[key.toString()] = _cborToValue(entry.value);
    }

    return result;
  }

  /// Converts a CBOR value to Dart value.
  dynamic _cborToValue(CborValue value) {
    // Handle DateTime types first (they extend CborInt/CborFloat)
    if (value is CborDateTimeInt) {
      return value.toDateTime();
    }
    if (value is CborDateTimeFloat) {
      return value.toDateTime();
    }

    return switch (value) {
      CborNull() => null,
      CborBool b => b.value,
      CborSmallInt i => i.value,
      CborInt i => i.toInt(),
      CborFloat f => f.value,
      CborString s => s.toString(),
      CborBytes b => Uint8List.fromList(b.bytes),
      CborList l => l.map(_cborToValue).toList(),
      CborMap m => _cborToMap(m),
      _ => value.toString(),
    };
  }
}

/// Exception for serialization errors.
class SerializationException extends StorageException {
  /// Creates a serialization exception.
  const SerializationException(super.message, {super.cause, super.stackTrace});
}
