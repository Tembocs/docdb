/// DocDB Backup - Incremental Snapshot
///
/// Represents an incremental backup containing only changes since the
/// previous backup of any type.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An incremental backup snapshot containing changes since the previous backup.
///
/// Incremental backups store only the entities that have changed (added or
/// modified) since the previous backup (of any type), plus deleted entity IDs.
/// This makes them the smallest and fastest backup type.
///
/// ## Restore Process
///
/// To restore from incremental backups:
/// 1. Start with the base full backup
/// 2. Apply each incremental in chronological order
/// 3. For each incremental: add/update changed entities, remove deleted ones
///
/// ## Binary Format
///
/// ```
/// [0-3]   Magic number: "INCR" (0x49, 0x4E, 0x43, 0x52)
/// [4]     Version byte
/// [5]     Flags (bit 0: compressed)
/// [6-69]  SHA-256 checksum (64 bytes, null-padded)
/// [70-77] Timestamp (64-bit milliseconds since epoch)
/// [78-81] Previous path length (32-bit)
/// [82-N]  Previous backup path (UTF-8)
/// [N+1-M] JSON data (changed entities + deleted IDs)
/// ```
final class IncrementalSnapshot {
  /// Magic number for incremental snapshots: "INCR"
  static const List<int> magic = [0x49, 0x4E, 0x43, 0x52];

  /// Current format version.
  static const int formatVersion = 1;

  /// Path to the previous backup this incremental is based on.
  final String previousBackupPath;

  /// Entities that were added or modified since the previous backup.
  final Map<String, Map<String, dynamic>> changedEntities;

  /// IDs of entities that were deleted since the previous backup.
  final List<String> deletedEntityIds;

  /// Timestamp when this incremental was created.
  final DateTime timestamp;

  /// Schema version at time of backup.
  final String? version;

  /// Human-readable description.
  final String? description;

  /// Whether the data is compressed.
  final bool compressed;

  /// Checksum of the data.
  late final String _checksum;

  /// Serialized data bytes.
  late final Uint8List _data;

  /// Creates a new incremental snapshot.
  IncrementalSnapshot({
    required this.previousBackupPath,
    required this.changedEntities,
    required this.deletedEntityIds,
    required this.timestamp,
    this.version,
    this.description,
    this.compressed = false,
  }) {
    _data = _serializeData();
    _checksum = _computeChecksum(_data);
  }

  /// Private constructor for deserialization.
  IncrementalSnapshot._fromParts({
    required this.previousBackupPath,
    required this.changedEntities,
    required this.deletedEntityIds,
    required this.timestamp,
    required this.version,
    required this.description,
    required this.compressed,
    required Uint8List data,
    required String checksum,
  }) : _data = data,
       _checksum = checksum;

  /// The checksum for integrity verification.
  String get checksum => _checksum;

  /// Size of the serialized data in bytes.
  int get sizeInBytes => _data.length + 82 + previousBackupPath.length;

  /// Number of changed entities.
  int get changeCount => changedEntities.length;

  /// Number of deleted entities.
  int get deleteCount => deletedEntityIds.length;

  /// Serializes the entity data to bytes.
  Uint8List _serializeData() {
    final jsonData = jsonEncode({
      'changed': changedEntities,
      'deleted': deletedEntityIds,
      'version': version,
      'description': description,
    });

    List<int> bytes = utf8.encode(jsonData);

    if (compressed) {
      bytes = gzip.encode(bytes);
    }

    return Uint8List.fromList(bytes);
  }

  /// Computes SHA-256 checksum.
  String _computeChecksum(Uint8List data) {
    return sha256.convert(data).toString();
  }

  /// Verifies data integrity using the checksum.
  bool verifyIntegrity() {
    final computed = _computeChecksum(_data);
    return computed == _checksum;
  }

  /// Serializes to bytes for storage.
  Uint8List toBytes() {
    final prevPathBytes = utf8.encode(previousBackupPath);
    final checksumBytes = utf8.encode(_checksum);

    final buffer = BytesBuilder();

    // Magic number
    buffer.add(magic);

    // Version
    buffer.addByte(formatVersion);

    // Flags
    buffer.addByte(compressed ? 0x01 : 0x00);

    // Checksum (padded to 64 bytes for consistency)
    buffer.add(checksumBytes);
    buffer.add(List.filled(64 - checksumBytes.length, 0));

    // Timestamp
    final timestampBytes = ByteData(8);
    timestampBytes.setInt64(0, timestamp.millisecondsSinceEpoch);
    buffer.add(timestampBytes.buffer.asUint8List());

    // Previous path length and data
    final pathLengthBytes = ByteData(4);
    pathLengthBytes.setInt32(0, prevPathBytes.length);
    buffer.add(pathLengthBytes.buffer.asUint8List());
    buffer.add(prevPathBytes);

    // Data
    buffer.add(_data);

    return buffer.toBytes();
  }

  /// Deserializes from bytes.
  factory IncrementalSnapshot.fromBytes(List<int> bytes) {
    if (bytes.length < 82) {
      throw FormatException(
        'Invalid incremental snapshot: too short (${bytes.length} bytes)',
      );
    }

    // Verify magic number
    if (bytes[0] != magic[0] ||
        bytes[1] != magic[1] ||
        bytes[2] != magic[2] ||
        bytes[3] != magic[3]) {
      throw const FormatException(
        'Invalid incremental snapshot: wrong magic number',
      );
    }

    // Read version
    final version = bytes[4];
    if (version > formatVersion) {
      throw FormatException(
        'Unsupported incremental snapshot version: $version',
      );
    }

    // Read flags
    final compressed = (bytes[5] & 0x01) != 0;

    // Read checksum
    final checksumBytes = bytes.sublist(6, 70);
    final checksum = utf8.decode(checksumBytes.where((b) => b != 0).toList());

    // Read timestamp
    final timestampData = ByteData.view(
      Uint8List.fromList(bytes.sublist(70, 78)).buffer,
    );
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      timestampData.getInt64(0),
    );

    // Read previous path length
    final pathLengthData = ByteData.view(
      Uint8List.fromList(bytes.sublist(78, 82)).buffer,
    );
    final pathLength = pathLengthData.getInt32(0);

    // Read previous path
    final previousBackupPath = utf8.decode(bytes.sublist(82, 82 + pathLength));

    // Read data
    final dataStart = 82 + pathLength;
    var data = Uint8List.fromList(bytes.sublist(dataStart));

    // Decompress if needed
    if (compressed) {
      data = Uint8List.fromList(gzip.decode(data));
    }

    // Parse JSON
    final jsonStr = utf8.decode(data);
    final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

    final changedEntities = <String, Map<String, dynamic>>{};
    final changedRaw = jsonData['changed'] as Map<String, dynamic>;
    for (final entry in changedRaw.entries) {
      changedEntities[entry.key] = Map<String, dynamic>.from(entry.value);
    }

    final deletedIds = (jsonData['deleted'] as List).cast<String>();
    final schemaVersion = jsonData['version'] as String?;
    final description = jsonData['description'] as String?;

    return IncrementalSnapshot._fromParts(
      previousBackupPath: previousBackupPath,
      changedEntities: changedEntities,
      deletedEntityIds: deletedIds,
      timestamp: timestamp,
      version: schemaVersion,
      description: description,
      compressed: compressed,
      data: compressed ? Uint8List.fromList(gzip.encode(data)) : data,
      checksum: checksum,
    );
  }

  @override
  String toString() {
    return 'IncrementalSnapshot('
        'changed: ${changedEntities.length}, '
        'deleted: ${deletedEntityIds.length}, '
        'previous: $previousBackupPath'
        ')';
  }
}
