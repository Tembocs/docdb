/// EntiDB Migration - Versioned Data
///
/// Provides version tracking for entity data during migrations.
library;

import '../entity/entity.dart';

/// Represents versioned entity data with metadata for migration tracking.
///
/// This class wraps entity data with version information, enabling the
/// migration system to track which schema version an entity conforms to
/// and when it was last migrated.
///
/// ## Example
///
/// ```dart
/// final versioned = VersionedData(
///   entityId: 'user-123',
///   version: '1.0.0',
///   data: {'name': 'Alice', 'email': 'alice@example.com'},
///   lastMigrated: DateTime.now(),
/// );
///
/// // Serialize for storage
/// final map = versioned.toMap();
///
/// // Deserialize
/// final restored = VersionedData.fromMap('user-123', map);
/// ```
final class VersionedData implements Entity {
  @override
  final String? id;

  /// The schema version of the data.
  final String version;

  /// The entity data conforming to the schema version.
  final Map<String, dynamic> data;

  /// When the data was created.
  final DateTime createdAt;

  /// When the data was last migrated.
  final DateTime? lastMigrated;

  /// Checksum of the data for integrity verification.
  final String? checksum;

  /// Creates a new versioned data wrapper.
  ///
  /// - [id]: The entity identifier.
  /// - [version]: The schema version of the data.
  /// - [data]: The entity data.
  /// - [createdAt]: When the data was created.
  /// - [lastMigrated]: When the data was last migrated.
  /// - [checksum]: Optional data integrity checksum.
  VersionedData({
    this.id,
    required this.version,
    required this.data,
    DateTime? createdAt,
    this.lastMigrated,
    this.checksum,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Creates versioned data for a new entity.
  ///
  /// Sets [createdAt] to now and leaves [lastMigrated] null.
  factory VersionedData.create({
    String? id,
    required String version,
    required Map<String, dynamic> data,
    String? checksum,
  }) {
    return VersionedData(
      id: id,
      version: version,
      data: data,
      createdAt: DateTime.now(),
      checksum: checksum,
    );
  }

  /// Creates a new version of this data after migration.
  ///
  /// - [newVersion]: The new schema version.
  /// - [newData]: The migrated data.
  /// - [newChecksum]: Optional new checksum.
  VersionedData migrated({
    required String newVersion,
    required Map<String, dynamic> newData,
    String? newChecksum,
  }) {
    return VersionedData(
      id: id,
      version: newVersion,
      data: newData,
      createdAt: createdAt,
      lastMigrated: DateTime.now(),
      checksum: newChecksum,
    );
  }

  /// Whether this data has ever been migrated.
  bool get hasMigrated => lastMigrated != null;

  @override
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'data': data,
      'createdAt': createdAt.toIso8601String(),
      if (lastMigrated != null) 'lastMigrated': lastMigrated!.toIso8601String(),
      if (checksum != null) 'checksum': checksum,
    };
  }

  /// Deserializes versioned data from a map.
  factory VersionedData.fromMap(String id, Map<String, dynamic> map) {
    return VersionedData(
      id: id,
      version: map['version'] as String,
      data: Map<String, dynamic>.from(map['data'] as Map),
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastMigrated: map['lastMigrated'] != null
          ? DateTime.parse(map['lastMigrated'] as String)
          : null,
      checksum: map['checksum'] as String?,
    );
  }

  @override
  String toString() {
    return 'VersionedData(id: $id, version: $version, '
        'createdAt: $createdAt, lastMigrated: $lastMigrated)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VersionedData && other.id == id && other.version == version;
  }

  @override
  int get hashCode => Object.hash(id, version);
}

/// Represents schema version metadata stored in the database.
///
/// Tracks the current schema version for a storage unit (data or user).
final class SchemaVersion implements Entity {
  @override
  final String? id;

  /// The schema version string (semantic versioning recommended).
  final String version;

  /// When this version was set.
  final DateTime updatedAt;

  /// Optional description of this version.
  final String? description;

  /// Creates a schema version record.
  const SchemaVersion({
    this.id,
    required this.version,
    required this.updatedAt,
    this.description,
  });

  /// Creates a new schema version with the current timestamp.
  factory SchemaVersion.now({
    String? id,
    required String version,
    String? description,
  }) {
    return SchemaVersion(
      id: id,
      version: version,
      updatedAt: DateTime.now(),
      description: description,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'updatedAt': updatedAt.toIso8601String(),
      if (description != null) 'description': description,
    };
  }

  /// Deserializes a schema version from a map.
  factory SchemaVersion.fromMap(String id, Map<String, dynamic> map) {
    return SchemaVersion(
      id: id,
      version: map['version'] as String,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      description: map['description'] as String?,
    );
  }

  @override
  String toString() => 'SchemaVersion($version, updatedAt: $updatedAt)';
}
