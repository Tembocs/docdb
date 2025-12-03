/// Write-Ahead Log (WAL) record definitions.
///
/// Defines the structure and serialization of WAL records used for
/// crash recovery and transaction durability.
library;

import 'dart:typed_data';

import 'package:cbor/cbor.dart';

import '../constants.dart';
import 'wal_constants.dart';

/// A Log Sequence Number (LSN) identifying a position in the WAL.
///
/// LSNs are monotonically increasing and represent the byte offset
/// of a record in the WAL file. They're used for:
/// - Ordering log records
/// - Identifying recovery points
/// - Tracking dirty pages
extension type const Lsn(int value) {
  /// Invalid/null LSN.
  static const Lsn invalid = Lsn(LsnConstants.invalid);

  /// First valid LSN.
  static const Lsn first = Lsn(LsnConstants.first);

  /// Whether this is a valid LSN.
  bool get isValid => value > LsnConstants.invalid;

  /// Returns the next LSN after a record of the given size.
  Lsn advance(int recordSize) => Lsn(value + recordSize);

  /// Comparison operators.
  bool operator <(Lsn other) => value < other.value;
  bool operator <=(Lsn other) => value <= other.value;
  bool operator >(Lsn other) => value > other.value;
  bool operator >=(Lsn other) => value >= other.value;
}

/// A Write-Ahead Log record.
///
/// Each record represents an atomic operation that can be replayed
/// during recovery. Records contain:
/// - Header with type, transaction ID, and LSN
/// - Payload with operation-specific data
/// - Checksum for integrity verification
class WalRecord {
  /// The type of this record.
  final WalRecordType type;

  /// Flags for this record.
  final int flags;

  /// The transaction ID this record belongs to.
  ///
  /// Zero for system records (checkpoints, end-of-log).
  final int transactionId;

  /// The Log Sequence Number of this record.
  final Lsn lsn;

  /// The LSN of the previous record in this transaction.
  ///
  /// Used for rollback to follow the undo chain.
  final Lsn prevLsn;

  /// The payload data.
  final Uint8List payload;

  /// Creates a new WAL record.
  const WalRecord({
    required this.type,
    this.flags = 0,
    required this.transactionId,
    required this.lsn,
    required this.prevLsn,
    required this.payload,
  });

  /// The total size of this record in bytes.
  int get size => WalRecordConstants.headerSize + payload.length;

  /// Whether this record has a continuation.
  bool get hasContinuation => (flags & WalRecordFlags.continuation) != 0;

  /// Whether this is the last record in a sequence.
  bool get isLastInSequence => (flags & WalRecordFlags.lastInSequence) != 0;

  /// Whether this record contains a full page image.
  bool get hasFullPageImage => (flags & WalRecordFlags.fullPageImage) != 0;

  /// Computes the CRC32 checksum for this record.
  int computeChecksum() {
    var crc = ChecksumConstants.crc32Initial;

    // Include type
    crc = _updateCrc(crc, type.value);

    // Include flags
    crc = _updateCrc(crc, flags);

    // Include transaction ID
    for (int i = 0; i < 8; i++) {
      crc = _updateCrc(crc, (transactionId >> (i * 8)) & 0xFF);
    }

    // Include LSN
    for (int i = 0; i < 8; i++) {
      crc = _updateCrc(crc, (lsn.value >> (i * 8)) & 0xFF);
    }

    // Include previous LSN
    for (int i = 0; i < 8; i++) {
      crc = _updateCrc(crc, (prevLsn.value >> (i * 8)) & 0xFF);
    }

    // Include payload length
    for (int i = 0; i < 4; i++) {
      crc = _updateCrc(crc, (payload.length >> (i * 8)) & 0xFF);
    }

    // Include payload
    for (final byte in payload) {
      crc = _updateCrc(crc, byte);
    }

    return crc ^ ChecksumConstants.crc32Initial;
  }

  int _updateCrc(int crc, int byte) {
    crc ^= byte;
    for (var j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ ChecksumConstants.crc32Polynomial;
      } else {
        crc >>= 1;
      }
    }
    return crc;
  }

  /// Serializes this record to bytes.
  Uint8List toBytes() {
    final buffer = Uint8List(size);
    final data = ByteData.sublistView(buffer);

    // Write header
    data.setUint8(WalRecordOffsets.recordType, type.value);
    data.setUint8(WalRecordOffsets.flags, flags);
    data.setInt64(WalRecordOffsets.transactionId, transactionId, Endian.little);
    data.setInt64(WalRecordOffsets.lsn, lsn.value, Endian.little);
    data.setInt64(WalRecordOffsets.prevLsn, prevLsn.value, Endian.little);
    data.setUint32(
      WalRecordOffsets.payloadLength,
      payload.length,
      Endian.little,
    );

    // Compute and write checksum
    final checksum = computeChecksum();
    data.setUint32(WalRecordOffsets.checksum, checksum, Endian.little);

    // Write payload
    buffer.setRange(WalRecordOffsets.payload, size, payload);

    return buffer;
  }

  /// Deserializes a record from bytes.
  ///
  /// Throws [WalCorruptedException] if the checksum doesn't match.
  factory WalRecord.fromBytes(Uint8List buffer) {
    if (buffer.length < WalRecordConstants.headerSize) {
      throw WalCorruptedException('Record too short: ${buffer.length} bytes');
    }

    final data = ByteData.sublistView(buffer);

    final type = WalRecordType.fromValue(
      data.getUint8(WalRecordOffsets.recordType),
    );
    final flags = data.getUint8(WalRecordOffsets.flags);
    final transactionId = data.getInt64(
      WalRecordOffsets.transactionId,
      Endian.little,
    );
    final lsn = Lsn(data.getInt64(WalRecordOffsets.lsn, Endian.little));
    final prevLsn = Lsn(data.getInt64(WalRecordOffsets.prevLsn, Endian.little));
    final payloadLength = data.getUint32(
      WalRecordOffsets.payloadLength,
      Endian.little,
    );
    final storedChecksum = data.getUint32(
      WalRecordOffsets.checksum,
      Endian.little,
    );

    if (buffer.length < WalRecordConstants.headerSize + payloadLength) {
      throw WalCorruptedException(
        'Record payload truncated: expected $payloadLength bytes, '
        'got ${buffer.length - WalRecordConstants.headerSize}',
      );
    }

    final payload = Uint8List.sublistView(
      buffer,
      WalRecordOffsets.payload,
      WalRecordOffsets.payload + payloadLength,
    );

    final record = WalRecord(
      type: type,
      flags: flags,
      transactionId: transactionId,
      lsn: lsn,
      prevLsn: prevLsn,
      payload: payload,
    );

    // Verify checksum
    final computedChecksum = record.computeChecksum();
    if (computedChecksum != storedChecksum) {
      throw WalCorruptedException(
        'Record checksum mismatch at LSN ${lsn.value}: '
        'expected 0x${storedChecksum.toRadixString(16)}, '
        'got 0x${computedChecksum.toRadixString(16)}',
      );
    }

    return record;
  }

  @override
  String toString() {
    return 'WalRecord(type: $type, txn: $transactionId, '
        'lsn: ${lsn.value}, prevLsn: ${prevLsn.value}, '
        'payload: ${payload.length} bytes)';
  }
}

/// Payload for insert/update/delete records.
///
/// Contains the collection name, entity ID, and data.
class DataOperationPayload {
  /// The collection this operation affects.
  final String collectionName;

  /// The entity ID.
  final String entityId;

  /// The data before the operation (null for insert).
  final Map<String, dynamic>? beforeImage;

  /// The data after the operation (null for delete).
  final Map<String, dynamic>? afterImage;

  /// Creates a new data operation payload.
  const DataOperationPayload({
    required this.collectionName,
    required this.entityId,
    this.beforeImage,
    this.afterImage,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    final map = CborMap({
      CborString('collection'): CborString(collectionName),
      CborString('entityId'): CborString(entityId),
      if (beforeImage != null) CborString('before'): _mapToCbor(beforeImage!),
      if (afterImage != null) CborString('after'): _mapToCbor(afterImage!),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  /// Deserializes from CBOR bytes.
  factory DataOperationPayload.fromBytes(Uint8List bytes) {
    final cborValue = cbor.decode(bytes);
    if (cborValue is! CborMap) {
      throw const WalCorruptedException('Invalid payload: expected CBOR map');
    }

    final collection = cborValue[CborString('collection')];
    final entityId = cborValue[CborString('entityId')];
    final before = cborValue[CborString('before')];
    final after = cborValue[CborString('after')];

    return DataOperationPayload(
      collectionName: (collection as CborString).toString(),
      entityId: (entityId as CborString).toString(),
      beforeImage: before != null ? _cborToMap(before) : null,
      afterImage: after != null ? _cborToMap(after) : null,
    );
  }

  /// Creates an insert payload.
  factory DataOperationPayload.insert({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      afterImage: data,
    );
  }

  /// Creates an update payload.
  factory DataOperationPayload.update({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      beforeImage: before,
      afterImage: after,
    );
  }

  /// Creates a delete payload.
  factory DataOperationPayload.delete({
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) {
    return DataOperationPayload(
      collectionName: collectionName,
      entityId: entityId,
      beforeImage: data,
    );
  }
}

/// Payload for checkpoint records.
///
/// Contains the state needed to reconstruct the database at this point.
class CheckpointPayload {
  /// The checkpoint timestamp.
  final DateTime timestamp;

  /// Active transaction IDs at checkpoint time.
  final List<int> activeTransactions;

  /// Dirty page information: pageId -> LSN of oldest unflushed modification.
  final Map<int, int> dirtyPages;

  /// Creates a new checkpoint payload.
  const CheckpointPayload({
    required this.timestamp,
    required this.activeTransactions,
    required this.dirtyPages,
  });

  /// Serializes to CBOR bytes.
  Uint8List toBytes() {
    final map = CborMap({
      CborString('timestamp'): CborDateTimeInt(timestamp),
      CborString('activeTxns'): CborList(
        activeTransactions.map((t) => CborSmallInt(t)).toList(),
      ),
      CborString('dirtyPages'): CborMap({
        for (final entry in dirtyPages.entries)
          CborSmallInt(entry.key): CborSmallInt(entry.value),
      }),
    });
    return Uint8List.fromList(cbor.encode(map));
  }

  /// Deserializes from CBOR bytes.
  factory CheckpointPayload.fromBytes(Uint8List bytes) {
    final cborValue = cbor.decode(bytes);
    if (cborValue is! CborMap) {
      throw const WalCorruptedException(
        'Invalid checkpoint payload: expected CBOR map',
      );
    }

    final timestampValue = cborValue[CborString('timestamp')];
    final activeTxnsValue = cborValue[CborString('activeTxns')];
    final dirtyPagesValue = cborValue[CborString('dirtyPages')];

    DateTime timestamp;
    if (timestampValue is CborDateTimeInt) {
      timestamp = timestampValue.toDateTime();
    } else if (timestampValue is CborSmallInt) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        timestampValue.value * 1000,
      );
    } else {
      throw const WalCorruptedException('Invalid timestamp in checkpoint');
    }

    final activeTransactions = <int>[];
    if (activeTxnsValue is CborList) {
      for (final item in activeTxnsValue) {
        if (item is CborSmallInt) {
          activeTransactions.add(item.value);
        } else if (item is CborInt) {
          activeTransactions.add(item.toInt());
        }
      }
    }

    final dirtyPages = <int, int>{};
    if (dirtyPagesValue is CborMap) {
      for (final entry in dirtyPagesValue.entries) {
        final key = entry.key;
        final value = entry.value;
        int keyInt = 0;
        int valueInt = 0;

        if (key is CborSmallInt) {
          keyInt = key.value;
        } else if (key is CborInt) {
          keyInt = key.toInt();
        }

        if (value is CborSmallInt) {
          valueInt = value.value;
        } else if (value is CborInt) {
          valueInt = value.toInt();
        }

        dirtyPages[keyInt] = valueInt;
      }
    }

    return CheckpointPayload(
      timestamp: timestamp,
      activeTransactions: activeTransactions,
      dirtyPages: dirtyPages,
    );
  }
}

// CBOR conversion helper functions

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
    throw const WalCorruptedException('Expected CBOR map');
  }

  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! CborString) {
      throw const WalCorruptedException('Map keys must be strings');
    }
    result[key.toString()] = _cborToValue(entry.value);
  }
  return result;
}

/// Converts a CBOR value to Dart value.
dynamic _cborToValue(CborValue value) {
  // Handle DateTime types first
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

/// Exception thrown when WAL data is corrupted.
class WalCorruptedException implements Exception {
  /// The error message.
  final String message;

  /// Creates a new WAL corruption exception.
  const WalCorruptedException(this.message);

  @override
  String toString() => 'WalCorruptedException: $message';
}

/// Exception thrown when WAL recovery fails.
class WalRecoveryException implements Exception {
  /// The error message.
  final String message;

  /// The underlying cause.
  final Object? cause;

  /// Creates a new WAL recovery exception.
  const WalRecoveryException(this.message, {this.cause});

  @override
  String toString() {
    if (cause != null) {
      return 'WalRecoveryException: $message (caused by: $cause)';
    }
    return 'WalRecoveryException: $message';
  }
}
