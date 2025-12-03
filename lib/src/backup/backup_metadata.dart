/// DocDB Backup - Backup Metadata
///
/// Provides metadata tracking for backup files including identification,
/// timestamps, integrity information, and descriptive details.
library;

import '../entity/entity.dart';

/// Represents metadata for a backup file.
///
/// Tracks essential information about a backup including:
/// - Identification (unique ID and file path)
/// - Timing (creation timestamp)
/// - Size and integrity (file size, entity count, checksum)
/// - Version information (schema version at backup time)
/// - Descriptive details (name, description, tags)
///
/// ## Usage
///
/// ```dart
/// // Create metadata for a new backup
/// final metadata = BackupMetadata.create(
///   filePath: '/backups/data_2024-01-15.snap',
///   entityCount: 1500,
///   sizeInBytes: 2048576,
///   checksum: 'abc123...',
///   schemaVersion: '2.0.0',
///   name: 'Pre-migration backup',
///   description: 'Backup before upgrading to v2.1',
/// );
///
/// // Store metadata as JSON
/// final json = metadata.toMap();
/// await metadataStorage.save(metadata.id, json);
///
/// // Restore metadata from storage
/// final restored = BackupMetadata.fromMap('backup-001', json);
/// ```
///
/// ## Backup Lifecycle
///
/// ```dart
/// // 1. Create backup
/// final snapshot = await backupService.createBackup();
/// await File(path).writeAsBytes(snapshot.toBytes());
///
/// // 2. Record metadata
/// final metadata = BackupMetadata.create(
///   filePath: path,
///   entityCount: snapshot.entityCount,
///   sizeInBytes: snapshot.sizeInBytes,
///   checksum: snapshot.checksum,
/// );
///
/// // 3. Index for later retrieval
/// await metadataIndex.add(metadata);
/// ```
final class BackupMetadata implements Entity {
  /// Unique identifier for this backup.
  @override
  final String? id;

  /// File path where the backup is stored.
  final String filePath;

  /// Timestamp when the backup was created.
  final DateTime createdAt;

  /// Size of the backup file in bytes.
  final int sizeInBytes;

  /// Number of entities captured in the backup.
  final int entityCount;

  /// SHA-256 checksum of the backup data for integrity verification.
  final String checksum;

  /// Schema version at the time of backup.
  final String? schemaVersion;

  /// Human-readable name for the backup.
  final String? name;

  /// Detailed description of the backup purpose.
  final String? description;

  /// Whether the backup data is compressed.
  final bool compressed;

  /// Tags for categorization and searching.
  final List<String> tags;

  /// Type of backup (full, incremental, differential).
  final BackupType type;

  /// Source storage name this backup was created from.
  final String? sourceName;

  /// Creates a new backup metadata instance.
  const BackupMetadata({
    this.id,
    required this.filePath,
    required this.createdAt,
    required this.sizeInBytes,
    required this.entityCount,
    required this.checksum,
    this.schemaVersion,
    this.name,
    this.description,
    this.compressed = false,
    this.tags = const [],
    this.type = BackupType.full,
    this.sourceName,
  });

  /// Creates metadata for a newly created backup.
  ///
  /// Automatically sets the creation timestamp to now and generates
  /// an ID if not provided.
  factory BackupMetadata.create({
    String? id,
    required String filePath,
    required int entityCount,
    required int sizeInBytes,
    required String checksum,
    String? schemaVersion,
    String? name,
    String? description,
    bool compressed = false,
    List<String> tags = const [],
    BackupType type = BackupType.full,
    String? sourceName,
  }) {
    return BackupMetadata(
      id: id,
      filePath: filePath,
      createdAt: DateTime.now(),
      sizeInBytes: sizeInBytes,
      entityCount: entityCount,
      checksum: checksum,
      schemaVersion: schemaVersion,
      name: name,
      description: description,
      compressed: compressed,
      tags: tags,
      type: type,
      sourceName: sourceName,
    );
  }

  /// Returns the file name portion of the backup path.
  String get fileName {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash >= 0) {
      return filePath.substring(lastSlash + 1);
    }
    final lastBackslash = filePath.lastIndexOf('\\');
    if (lastBackslash >= 0) {
      return filePath.substring(lastBackslash + 1);
    }
    return filePath;
  }

  /// Returns the age of this backup.
  Duration get age => DateTime.now().difference(createdAt);

  /// Returns human-readable size string.
  String get humanReadableSize {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    } else if (sizeInBytes < 1024 * 1024 * 1024) {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// Creates a copy of this metadata with the given fields replaced.
  BackupMetadata copyWith({
    String? id,
    String? filePath,
    DateTime? createdAt,
    int? sizeInBytes,
    int? entityCount,
    String? checksum,
    String? schemaVersion,
    String? name,
    String? description,
    bool? compressed,
    List<String>? tags,
    BackupType? type,
    String? sourceName,
  }) {
    return BackupMetadata(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      sizeInBytes: sizeInBytes ?? this.sizeInBytes,
      entityCount: entityCount ?? this.entityCount,
      checksum: checksum ?? this.checksum,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      name: name ?? this.name,
      description: description ?? this.description,
      compressed: compressed ?? this.compressed,
      tags: tags ?? this.tags,
      type: type ?? this.type,
      sourceName: sourceName ?? this.sourceName,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
    'sizeInBytes': sizeInBytes,
    'entityCount': entityCount,
    'checksum': checksum,
    if (schemaVersion != null) 'schemaVersion': schemaVersion,
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    'compressed': compressed,
    if (tags.isNotEmpty) 'tags': tags,
    'type': type.name,
    if (sourceName != null) 'sourceName': sourceName,
  };

  /// Creates metadata from a stored map.
  factory BackupMetadata.fromMap(String id, Map<String, dynamic> map) {
    return BackupMetadata(
      id: id,
      filePath: map['filePath'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      sizeInBytes: map['sizeInBytes'] as int,
      entityCount: map['entityCount'] as int,
      checksum: map['checksum'] as String,
      schemaVersion: map['schemaVersion'] as String?,
      name: map['name'] as String?,
      description: map['description'] as String?,
      compressed: map['compressed'] as bool? ?? false,
      tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      type: BackupType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => BackupType.full,
      ),
      sourceName: map['sourceName'] as String?,
    );
  }

  @override
  String toString() =>
      'BackupMetadata(id: $id, name: $name, entities: $entityCount, '
      'size: $humanReadableSize, created: $createdAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackupMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          checksum == other.checksum;

  @override
  int get hashCode => Object.hash(id, checksum);
}

/// Types of backup operations.
///
/// Different backup types offer trade-offs between storage space,
/// backup speed, and restore complexity.
enum BackupType {
  /// Complete backup of all data.
  ///
  /// Contains all entities at the time of backup. Largest size but
  /// simplest to restore.
  full,

  /// Backup of changes since the last full backup.
  ///
  /// Requires the last full backup plus this differential to restore.
  /// Faster than full backup, moderate size.
  differential,

  /// Backup of changes since the last backup (any type).
  ///
  /// Requires all backups in the chain since the last full backup.
  /// Fastest and smallest, but most complex to restore.
  incremental,

  /// Migration-specific backup.
  ///
  /// Created automatically before schema migrations to enable rollback.
  migration,
}
