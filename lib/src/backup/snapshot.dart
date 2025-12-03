/// DocDB Backup - Snapshot
///
/// Represents a point-in-time snapshot of storage state for backup
/// and restore operations with integrity verification.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../entity/entity.dart';

/// Represents a point-in-time snapshot of storage data.
///
/// A snapshot captures the complete state of an entity storage at a specific
/// moment, including all entity data and metadata needed for restoration.
/// Snapshots support integrity verification through checksums.
///
/// ## Creating Snapshots
///
/// ```dart
/// // From entity data
/// final entities = await storage.getAll();
/// final snapshot = Snapshot.fromEntities(
///   entities: entities,
///   version: '2.0.0',
///   description: 'Pre-migration backup',
/// );
///
/// // Verify integrity
/// if (!snapshot.verifyIntegrity()) {
///   throw BackupCorruptionException('Snapshot failed integrity check');
/// }
/// ```
///
/// ## Serialization
///
/// Snapshots can be serialized to bytes for file storage:
///
/// ```dart
/// final bytes = snapshot.toBytes();
/// await File('backup.snap').writeAsBytes(bytes);
///
/// // Later, restore from file
/// final loaded = Snapshot.fromBytes(await File('backup.snap').readAsBytes());
/// ```
///
/// ## Compression
///
/// Enable compression for large datasets to reduce storage size:
///
/// ```dart
/// final compressed = Snapshot.fromEntities(
///   entities: largeDataset,
///   compressed: true,
/// );
/// ```
final class Snapshot implements Entity {
  /// Unique identifier for this snapshot.
  @override
  final String? id;

  /// Timestamp when the snapshot was created.
  final DateTime timestamp;

  /// The binary data of the snapshot.
  ///
  /// Contains serialized entity data in JSON format, optionally compressed.
  final Uint8List data;

  /// SHA-256 checksum of the data for integrity verification.
  final String checksum;

  /// Whether the data is compressed.
  final bool compressed;

  /// Schema version at the time of snapshot.
  final String? version;

  /// Number of entities captured in this snapshot.
  final int entityCount;

  /// Human-readable description of the snapshot.
  final String? description;

  /// Additional metadata stored with the snapshot.
  final Map<String, dynamic> metadata;

  /// Creates a new snapshot with the given parameters.
  ///
  /// Prefer using factory constructors like [Snapshot.fromEntities] or
  /// [Snapshot.fromBytes] rather than this constructor directly.
  Snapshot({
    this.id,
    required this.timestamp,
    required this.data,
    required this.checksum,
    this.compressed = false,
    this.version,
    required this.entityCount,
    this.description,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? const {};

  /// Creates a snapshot from entity data.
  ///
  /// - [entities]: Map of entity ID to entity data.
  /// - [version]: Optional schema version string.
  /// - [description]: Optional human-readable description.
  /// - [compressed]: Whether to compress the data (default: false).
  /// - [metadata]: Additional metadata to store.
  ///
  /// Returns a new [Snapshot] with computed checksum and serialized data.
  factory Snapshot.fromEntities({
    String? id,
    required Map<String, Map<String, dynamic>> entities,
    String? version,
    String? description,
    bool compressed = false,
    Map<String, dynamic>? metadata,
  }) {
    final timestamp = DateTime.now();

    // Serialize entities to JSON
    final jsonString = jsonEncode(entities);
    Uint8List data;

    if (compressed) {
      // Use gzip compression
      data = Uint8List.fromList(gzip.encode(utf8.encode(jsonString)));
    } else {
      data = Uint8List.fromList(utf8.encode(jsonString));
    }

    // Compute checksum
    final checksum = _computeChecksum(data);

    return Snapshot(
      id: id,
      timestamp: timestamp,
      data: data,
      checksum: checksum,
      compressed: compressed,
      version: version,
      entityCount: entities.length,
      description: description,
      metadata: metadata,
    );
  }

  /// Creates an empty snapshot.
  ///
  /// Useful for representing an initial state before any data exists.
  factory Snapshot.empty({String? id, String? version, String? description}) {
    final data = Uint8List.fromList(utf8.encode('{}'));
    return Snapshot(
      id: id,
      timestamp: DateTime.now(),
      data: data,
      checksum: _computeChecksum(data),
      compressed: false,
      version: version,
      entityCount: 0,
      description: description ?? 'Empty snapshot',
    );
  }

  /// Deserializes a snapshot from raw bytes.
  ///
  /// The bytes should have been created by [toBytes].
  ///
  /// Throws [FormatException] if the bytes are invalid or corrupted.
  factory Snapshot.fromBytes(Uint8List bytes) {
    try {
      // Read header
      final view = ByteData.view(bytes.buffer, bytes.offsetInBytes);
      var offset = 0;

      // Magic number (4 bytes)
      final magic = view.getUint32(offset, Endian.big);
      offset += 4;
      if (magic != _magicNumber) {
        throw FormatException('Invalid snapshot format: bad magic number');
      }

      // Version (1 byte)
      final formatVersion = view.getUint8(offset);
      offset += 1;
      if (formatVersion != _formatVersion) {
        throw FormatException(
          'Unsupported snapshot format version: $formatVersion',
        );
      }

      // Flags (1 byte)
      final flags = view.getUint8(offset);
      offset += 1;
      final compressed = (flags & 0x01) != 0;

      // Timestamp (8 bytes)
      final timestampMs = view.getInt64(offset, Endian.big);
      offset += 8;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(timestampMs);

      // Entity count (4 bytes)
      final entityCount = view.getUint32(offset, Endian.big);
      offset += 4;

      // Checksum length (2 bytes) + checksum
      final checksumLength = view.getUint16(offset, Endian.big);
      offset += 2;
      final checksumBytes = bytes.sublist(offset, offset + checksumLength);
      final checksum = utf8.decode(checksumBytes);
      offset += checksumLength;

      // Metadata length (4 bytes) + metadata
      final metadataLength = view.getUint32(offset, Endian.big);
      offset += 4;
      Map<String, dynamic> metadata = {};
      String? id;
      String? version;
      String? description;
      if (metadataLength > 0) {
        final metadataBytes = bytes.sublist(offset, offset + metadataLength);
        final metadataJson = utf8.decode(metadataBytes);
        final decodedMeta = jsonDecode(metadataJson) as Map<String, dynamic>;
        id = decodedMeta['id'] as String?;
        version = decodedMeta['version'] as String?;
        description = decodedMeta['description'] as String?;
        metadata = (decodedMeta['metadata'] as Map<String, dynamic>?) ?? {};
      }
      offset += metadataLength;

      // Data (remaining bytes)
      final data = Uint8List.fromList(bytes.sublist(offset));

      return Snapshot(
        id: id,
        timestamp: timestamp,
        data: data,
        checksum: checksum,
        compressed: compressed,
        version: version,
        entityCount: entityCount,
        description: description,
        metadata: metadata,
      );
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Failed to parse snapshot: $e');
    }
  }

  /// Serializes this snapshot to bytes for file storage.
  ///
  /// The resulting bytes can be restored using [Snapshot.fromBytes].
  Uint8List toBytes() {
    // Prepare metadata
    final metadataMap = {
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
    final metadataBytes = metadataMap.isNotEmpty
        ? Uint8List.fromList(utf8.encode(jsonEncode(metadataMap)))
        : Uint8List(0);

    final checksumBytes = Uint8List.fromList(utf8.encode(checksum));

    // Calculate total size
    final headerSize =
        4 + // magic
        1 + // format version
        1 + // flags
        8 + // timestamp
        4 + // entity count
        2 + // checksum length
        checksumBytes.length +
        4 + // metadata length
        metadataBytes.length;

    final totalSize = headerSize + data.length;
    final buffer = Uint8List(totalSize);
    final view = ByteData.view(buffer.buffer);

    var offset = 0;

    // Write magic number
    view.setUint32(offset, _magicNumber, Endian.big);
    offset += 4;

    // Write format version
    view.setUint8(offset, _formatVersion);
    offset += 1;

    // Write flags
    var flags = 0;
    if (compressed) flags |= 0x01;
    view.setUint8(offset, flags);
    offset += 1;

    // Write timestamp
    view.setInt64(offset, timestamp.millisecondsSinceEpoch, Endian.big);
    offset += 8;

    // Write entity count
    view.setUint32(offset, entityCount, Endian.big);
    offset += 4;

    // Write checksum
    view.setUint16(offset, checksumBytes.length, Endian.big);
    offset += 2;
    buffer.setAll(offset, checksumBytes);
    offset += checksumBytes.length;

    // Write metadata
    view.setUint32(offset, metadataBytes.length, Endian.big);
    offset += 4;
    if (metadataBytes.isNotEmpty) {
      buffer.setAll(offset, metadataBytes);
      offset += metadataBytes.length;
    }

    // Write data
    buffer.setAll(offset, data);

    return buffer;
  }

  /// Extracts entity data from this snapshot.
  ///
  /// Returns a map of entity ID to entity data.
  ///
  /// Throws [FormatException] if the data is corrupted or invalid.
  Map<String, Map<String, dynamic>> toEntities() {
    try {
      String jsonString;
      if (compressed) {
        jsonString = utf8.decode(gzip.decode(data));
      } else {
        jsonString = utf8.decode(data);
      }

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );
    } catch (e) {
      throw FormatException('Failed to extract entities from snapshot: $e');
    }
  }

  /// Verifies the integrity of this snapshot.
  ///
  /// Returns `true` if the checksum matches the data, `false` otherwise.
  bool verifyIntegrity() {
    final computed = _computeChecksum(data);
    return computed == checksum;
  }

  /// Computes the SHA-256 checksum of the given data.
  static String _computeChecksum(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  /// Size of the snapshot data in bytes.
  int get sizeInBytes => data.length;

  @override
  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'checksum': checksum,
    'compressed': compressed,
    if (version != null) 'version': version,
    'entityCount': entityCount,
    if (description != null) 'description': description,
    if (metadata.isNotEmpty) 'metadata': metadata,
    'sizeInBytes': sizeInBytes,
  };

  /// Creates a snapshot from a stored map.
  ///
  /// Note: This does not restore the binary data. Use [fromBytes]
  /// for full restoration from binary storage.
  factory Snapshot.fromMap(String id, Map<String, dynamic> map) {
    return Snapshot(
      id: id,
      timestamp: DateTime.parse(map['timestamp'] as String),
      data: Uint8List(0), // Data must be loaded separately
      checksum: map['checksum'] as String,
      compressed: map['compressed'] as bool? ?? false,
      version: map['version'] as String?,
      entityCount: map['entityCount'] as int? ?? 0,
      description: map['description'] as String?,
      metadata: (map['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  String toString() =>
      'Snapshot(id: $id, timestamp: $timestamp, entities: $entityCount, '
      'size: $sizeInBytes bytes, compressed: $compressed)';

  /// Magic number for snapshot file format identification.
  static const int _magicNumber = 0x444F4342; // "DOCB"

  /// Current format version for backward compatibility.
  static const int _formatVersion = 1;
}
