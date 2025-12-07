/// EntiDB Backup - Backup Service
///
/// Provides a robust, generic backup service for entity storage with
/// integrity verification, compression, and flexible storage options.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../entity/entity.dart';
import '../exceptions/backup_exceptions.dart';
import '../logger/entidb_logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'backup_metadata.dart';
import 'backup_result.dart';
import 'differential_snapshot.dart';
import 'incremental_snapshot.dart';
import 'snapshot.dart';

/// Represents entity changes between two states.
class _EntityChanges {
  /// Entities that were added or modified.
  final Map<String, Map<String, dynamic>> changedEntities;

  /// IDs of entities that were deleted.
  final List<String> deletedIds;

  const _EntityChanges({
    required this.changedEntities,
    required this.deletedIds,
  });
}

/// Configuration options for the backup service.
///
/// Controls backup behavior including compression, retention,
/// and verification settings.
final class BackupConfig {
  /// Directory where backups are stored.
  final String backupDirectory;

  /// Whether to compress backup data.
  final bool compress;

  /// Whether to verify backup integrity after creation.
  final bool verifyAfterCreate;

  /// Whether to verify backup integrity before restore.
  final bool verifyBeforeRestore;

  /// Maximum number of backups to retain (null = unlimited).
  final int? maxBackups;

  /// Maximum age of backups to retain (null = unlimited).
  final Duration? maxAge;

  /// File extension for backup files.
  final String fileExtension;

  /// Creates a new backup configuration.
  const BackupConfig({
    required this.backupDirectory,
    this.compress = false,
    this.verifyAfterCreate = true,
    this.verifyBeforeRestore = true,
    this.maxBackups,
    this.maxAge,
    this.fileExtension = '.snap',
  });

  /// Default configuration for development.
  factory BackupConfig.development(String backupDirectory) {
    return BackupConfig(
      backupDirectory: backupDirectory,
      compress: false,
      verifyAfterCreate: true,
      verifyBeforeRestore: true,
    );
  }

  /// Configuration optimized for production.
  factory BackupConfig.production(String backupDirectory) {
    return BackupConfig(
      backupDirectory: backupDirectory,
      compress: true,
      verifyAfterCreate: true,
      verifyBeforeRestore: true,
      maxBackups: 10,
      maxAge: const Duration(days: 30),
    );
  }

  /// Configuration for migration backups.
  factory BackupConfig.migration(String backupDirectory) {
    return BackupConfig(
      backupDirectory: backupDirectory,
      compress: false,
      verifyAfterCreate: true,
      verifyBeforeRestore: true,
      maxBackups: 5,
      fileExtension: '.migration.snap',
    );
  }
}

/// A robust backup service for entity storage.
///
/// Provides comprehensive backup and restore capabilities including:
/// - Full storage backups with integrity verification
/// - Snapshot-based backup format with checksums
/// - Optional compression for storage efficiency
/// - Backup retention policies
/// - Metadata tracking for backup management
///
/// ## Basic Usage
///
/// ```dart
/// final backupService = BackupService<Product>(
///   storage: productStorage,
///   config: BackupConfig(backupDirectory: '/backups/products'),
/// );
///
/// // Create a backup
/// final result = await backupService.createBackup(
///   description: 'Before price update',
/// );
///
/// if (result.isSuccess) {
///   print('Backup saved: ${result.filePath}');
/// }
///
/// // Restore from backup
/// final restoreResult = await backupService.restore(result.filePath!);
/// ```
///
/// ## Migration Integration
///
/// ```dart
/// // Create backup before migration
/// final backup = await backupService.createBackup(
///   type: BackupType.migration,
///   description: 'Pre-migration backup for v2.0',
/// );
///
/// try {
///   await migrationRunner.migrate();
/// } catch (e) {
///   // Rollback on failure
///   await backupService.restore(backup.filePath!);
/// }
/// ```
final class BackupService<T extends Entity> {
  final Storage<T> _storage;
  final BackupConfig _config;
  final EntiDBLogger _logger;

  /// Creates a new backup service.
  ///
  /// - [storage]: The entity storage to backup.
  /// - [config]: Backup configuration options.
  /// - [logger]: Optional custom logger.
  BackupService({
    required Storage<T> storage,
    required BackupConfig config,
    EntiDBLogger? logger,
  }) : _storage = storage,
       _config = config,
       _logger = logger ?? EntiDBLogger(LoggerNameConstants.backup);

  /// The storage being backed up.
  Storage<T> get storage => _storage;

  /// The backup configuration.
  BackupConfig get config => _config;

  /// Initializes the backup service.
  ///
  /// Creates the backup directory if it doesn't exist.
  ///
  /// Throws [BackupException] if initialization fails.
  Future<void> initialize() async {
    try {
      final dir = Directory(_config.backupDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _logger.info(
          jsonEncode({
            'event': 'backup_init',
            'directory': _config.backupDirectory,
          }),
        );
      }
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'backup_init_failed', 'error': e.toString()}),
      );
      throw BackupException(
        'Failed to initialize backup service: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Creates a backup of the current storage state.
  ///
  /// - [description]: Optional description for the backup.
  /// - [type]: Type of backup (default: full).
  /// - [schemaVersion]: Optional schema version to record.
  /// - [metadata]: Additional metadata to store.
  ///
  /// Returns a [BackupResult] with details about the operation.
  ///
  /// Throws [BackupException] if backup creation fails.
  Future<BackupResult> createBackup({
    String? description,
    BackupType type = BackupType.full,
    String? schemaVersion,
    Map<String, dynamic>? metadata,
  }) async {
    final startedAt = DateTime.now();
    final warnings = <String>[];

    try {
      _logger.info(
        jsonEncode({
          'event': 'backup_start',
          'storage': _storage.name,
          'type': type.name,
        }),
      );

      // Get all entities from storage
      final entities = await _storage.getAll();

      // Create snapshot
      final snapshot = Snapshot.fromEntities(
        entities: entities,
        version: schemaVersion,
        description: description,
        compressed: _config.compress,
        metadata: metadata,
      );

      // Verify integrity if configured
      if (_config.verifyAfterCreate && !snapshot.verifyIntegrity()) {
        throw const BackupException(
          'Snapshot integrity verification failed after creation',
        );
      }

      // Generate backup file path
      final fileName = _generateFileName(type);
      final filePath = p.join(_config.backupDirectory, fileName);

      // Write to file
      final file = File(filePath);
      await file.writeAsBytes(snapshot.toBytes(), flush: true);

      // Create metadata
      final backupMetadata = BackupMetadata.create(
        filePath: filePath,
        entityCount: snapshot.entityCount,
        sizeInBytes: snapshot.sizeInBytes,
        checksum: snapshot.checksum,
        schemaVersion: schemaVersion,
        name: description,
        description: description,
        compressed: _config.compress,
        type: type,
        sourceName: _storage.name,
      );

      // Apply retention policy
      await _applyRetentionPolicy(warnings);

      _logger.info(
        jsonEncode({
          'event': 'backup_complete',
          'storage': _storage.name,
          'path': filePath,
          'entities': snapshot.entityCount,
          'sizeBytes': snapshot.sizeInBytes,
          'compressed': _config.compress,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.create,
        metadata: backupMetadata,
        message: 'Backup created successfully',
        warnings: warnings,
        entitiesAffected: snapshot.entityCount,
        bytesProcessed: snapshot.sizeInBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'backup_failed', 'error': e.toString()}),
      );

      return BackupResult.failure(
        operation: BackupOperation.create,
        error: e.toString(),
        stackTrace: stack.toString(),
        warnings: warnings,
        startedAt: startedAt,
      );
    }
  }

  /// Creates a quick in-memory backup for rollback scenarios.
  ///
  /// This is faster than file-based backup but doesn't persist to disk.
  /// Useful for short-term rollback during migrations or batch operations.
  ///
  /// Returns a [Snapshot] that can be used with [restoreFromSnapshot].
  Future<Snapshot> createMemoryBackup({
    String? description,
    String? schemaVersion,
  }) async {
    try {
      _logger.debug(
        jsonEncode({'event': 'memory_backup_start', 'storage': _storage.name}),
      );

      final entities = await _storage.getAll();

      final snapshot = Snapshot.fromEntities(
        entities: entities,
        version: schemaVersion,
        description: description ?? 'In-memory backup',
        compressed: false,
      );

      _logger.debug(
        jsonEncode({
          'event': 'memory_backup_complete',
          'entities': snapshot.entityCount,
        }),
      );

      return snapshot;
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'memory_backup_failed', 'error': e.toString()}),
      );
      throw BackupException(
        'Failed to create memory backup: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Restores storage from a backup file.
  ///
  /// - [filePath]: Path to the backup file.
  /// - [clearExisting]: Whether to clear existing data before restore.
  ///
  /// Returns a [BackupResult] with details about the operation.
  ///
  /// Throws [BackupException] if restore fails.
  Future<BackupResult> restore(
    String filePath, {
    bool clearExisting = true,
  }) async {
    final startedAt = DateTime.now();

    try {
      _logger.info(
        jsonEncode({
          'event': 'restore_start',
          'storage': _storage.name,
          'path': filePath,
        }),
      );

      // Read backup file
      final file = File(filePath);
      if (!await file.exists()) {
        throw DataBackupFileNotFoundException(
          'Backup file not found: $filePath',
        );
      }

      final bytes = await file.readAsBytes();
      final snapshot = Snapshot.fromBytes(bytes);

      // Verify integrity if configured
      if (_config.verifyBeforeRestore && !snapshot.verifyIntegrity()) {
        throw const BackupException(
          'Backup integrity verification failed - file may be corrupted',
        );
      }

      // Restore from snapshot
      await restoreFromSnapshot(snapshot, clearExisting: clearExisting);

      _logger.info(
        jsonEncode({
          'event': 'restore_complete',
          'storage': _storage.name,
          'entities': snapshot.entityCount,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.restore,
        filePath: filePath,
        message: 'Restore completed successfully',
        entitiesAffected: snapshot.entityCount,
        bytesProcessed: snapshot.sizeInBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'restore_failed', 'error': e.toString()}),
      );

      return BackupResult.failure(
        operation: BackupOperation.restore,
        error: e.toString(),
        filePath: filePath,
        stackTrace: stack.toString(),
        startedAt: startedAt,
      );
    }
  }

  /// Restores storage from an in-memory snapshot.
  ///
  /// - [snapshot]: The snapshot to restore from.
  /// - [clearExisting]: Whether to clear existing data before restore.
  ///
  /// Throws [BackupException] if restore fails.
  Future<void> restoreFromSnapshot(
    Snapshot snapshot, {
    bool clearExisting = true,
  }) async {
    try {
      _logger.debug(
        jsonEncode({
          'event': 'snapshot_restore_start',
          'entities': snapshot.entityCount,
        }),
      );

      // Verify integrity
      if (!snapshot.verifyIntegrity()) {
        throw const BackupException('Snapshot integrity verification failed');
      }

      // Extract entities
      final entities = snapshot.toEntities();

      // Clear existing data if requested
      if (clearExisting) {
        await _storage.deleteAll();
      }

      // Insert restored entities
      if (entities.isNotEmpty) {
        await _storage.insertMany(entities);
      }

      _logger.debug(
        jsonEncode({
          'event': 'snapshot_restore_complete',
          'entities': entities.length,
        }),
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'snapshot_restore_failed', 'error': e.toString()}),
      );
      throw BackupException(
        'Failed to restore from snapshot: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Verifies the integrity of a backup file.
  ///
  /// Returns a [BackupResult] indicating whether the backup is valid.
  Future<BackupResult> verify(String filePath) async {
    final startedAt = DateTime.now();

    try {
      _logger.info(jsonEncode({'event': 'verify_start', 'path': filePath}));

      final file = File(filePath);
      if (!await file.exists()) {
        return BackupResult.failure(
          operation: BackupOperation.verify,
          error: 'Backup file not found',
          filePath: filePath,
          startedAt: startedAt,
        );
      }

      final bytes = await file.readAsBytes();
      final snapshot = Snapshot.fromBytes(bytes);

      if (!snapshot.verifyIntegrity()) {
        return BackupResult.failure(
          operation: BackupOperation.verify,
          error: 'Checksum mismatch - backup may be corrupted',
          filePath: filePath,
          startedAt: startedAt,
        );
      }

      _logger.info(
        jsonEncode({
          'event': 'verify_complete',
          'path': filePath,
          'entities': snapshot.entityCount,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.verify,
        filePath: filePath,
        message: 'Backup verification passed',
        entitiesAffected: snapshot.entityCount,
        bytesProcessed: snapshot.sizeInBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'verify_failed', 'error': e.toString()}),
      );

      return BackupResult.failure(
        operation: BackupOperation.verify,
        error: e.toString(),
        filePath: filePath,
        stackTrace: stack.toString(),
        startedAt: startedAt,
      );
    }
  }

  /// Lists all available backups.
  ///
  /// Returns backups sorted by creation time (newest first).
  Future<List<BackupMetadata>> listBackups() async {
    try {
      final dir = Directory(_config.backupDirectory);
      if (!await dir.exists()) {
        return [];
      }

      final backups = <BackupMetadata>[];

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith(_config.fileExtension)) {
          try {
            final stat = await entity.stat();
            final bytes = await entity.readAsBytes();
            final snapshot = Snapshot.fromBytes(bytes);

            backups.add(
              BackupMetadata(
                filePath: entity.path,
                createdAt: stat.modified,
                sizeInBytes: bytes.length,
                entityCount: snapshot.entityCount,
                checksum: snapshot.checksum,
                schemaVersion: snapshot.version,
                description: snapshot.description,
                compressed: snapshot.compressed,
                sourceName: _storage.name,
              ),
            );
          } catch (e) {
            _logger.warning(
              jsonEncode({
                'event': 'backup_parse_failed',
                'path': entity.path,
                'error': e.toString(),
              }),
            );
          }
        }
      }

      // Sort by creation time (newest first)
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return backups;
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'list_backups_failed', 'error': e.toString()}),
      );
      throw BackupException(
        'Failed to list backups: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Finds the latest backup.
  ///
  /// Returns `null` if no backups exist.
  Future<BackupMetadata?> findLatestBackup() async {
    final backups = await listBackups();
    return backups.isNotEmpty ? backups.first : null;
  }

  /// Deletes a backup file.
  ///
  /// Returns a [BackupResult] indicating success or failure.
  Future<BackupResult> deleteBackup(String filePath) async {
    final startedAt = DateTime.now();

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return BackupResult.failure(
          operation: BackupOperation.delete,
          error: 'Backup file not found',
          filePath: filePath,
          startedAt: startedAt,
        );
      }

      final stat = await file.stat();
      await file.delete();

      _logger.info(jsonEncode({'event': 'backup_deleted', 'path': filePath}));

      return BackupResult.success(
        operation: BackupOperation.delete,
        filePath: filePath,
        message: 'Backup deleted successfully',
        bytesProcessed: stat.size,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'delete_backup_failed', 'error': e.toString()}),
      );

      return BackupResult.failure(
        operation: BackupOperation.delete,
        error: e.toString(),
        filePath: filePath,
        stackTrace: stack.toString(),
        startedAt: startedAt,
      );
    }
  }

  /// Generates a unique backup file name.
  String _generateFileName(BackupType type) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final typePrefix = switch (type) {
      BackupType.full => 'full',
      BackupType.differential => 'diff',
      BackupType.incremental => 'incr',
      BackupType.migration => 'migration',
    };
    return '${_storage.name}_${typePrefix}_$timestamp${_config.fileExtension}';
  }

  // ===========================================================================
  // Differential & Incremental Backup Support
  // ===========================================================================

  /// Creates a differential backup containing only changes since the last
  /// full backup.
  ///
  /// A differential backup stores all entities that are new or modified
  /// compared to the base full backup, plus a list of deleted entity IDs.
  ///
  /// - [baseBackupPath]: Path to the full backup to compare against.
  /// - [description]: Optional description for this backup.
  /// - [schemaVersion]: Optional schema version to record.
  ///
  /// ## Restore Process
  ///
  /// To restore from a differential backup:
  /// 1. First restore the base full backup
  /// 2. Then apply this differential backup
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Create full backup weekly
  /// final fullBackup = await backupService.createBackup(
  ///   type: BackupType.full,
  /// );
  ///
  /// // Create differential backups daily
  /// final diffBackup = await backupService.createDifferentialBackup(
  ///   baseBackupPath: fullBackup.filePath!,
  /// );
  /// ```
  Future<BackupResult> createDifferentialBackup({
    required String baseBackupPath,
    String? description,
    String? schemaVersion,
  }) async {
    final startedAt = DateTime.now();
    final warnings = <String>[];

    try {
      _logger.info(
        jsonEncode({
          'event': 'differential_backup_start',
          'storage': _storage.name,
          'base': baseBackupPath,
        }),
      );

      // Load the base backup
      final baseFile = File(baseBackupPath);
      if (!await baseFile.exists()) {
        throw DataBackupFileNotFoundException(
          'Base backup file not found: $baseBackupPath',
        );
      }

      final baseBytes = await baseFile.readAsBytes();
      final baseSnapshot = Snapshot.fromBytes(baseBytes);
      final baseEntities = baseSnapshot.toEntities();

      // Get current entities
      final currentEntities = await _storage.getAll();

      // Find changes
      final changes = _computeChanges(baseEntities, currentEntities);

      // Create differential snapshot
      final diffSnapshot = DifferentialSnapshot(
        baseBackupPath: baseBackupPath,
        baseTimestamp: baseSnapshot.timestamp,
        changedEntities: changes.changedEntities,
        deletedEntityIds: changes.deletedIds,
        timestamp: DateTime.now(),
        version: schemaVersion,
        description: description ?? 'Differential backup',
        compressed: _config.compress,
      );

      // Verify if configured
      if (_config.verifyAfterCreate && !diffSnapshot.verifyIntegrity()) {
        throw const BackupException(
          'Differential snapshot integrity verification failed',
        );
      }

      // Generate file path and write
      final fileName = _generateFileName(BackupType.differential);
      final filePath = p.join(_config.backupDirectory, fileName);

      final file = File(filePath);
      await file.writeAsBytes(diffSnapshot.toBytes(), flush: true);

      // Create metadata
      final backupMetadata = BackupMetadata.create(
        filePath: filePath,
        entityCount: changes.changedEntities.length,
        sizeInBytes: diffSnapshot.sizeInBytes,
        checksum: diffSnapshot.checksum,
        schemaVersion: schemaVersion,
        name: description,
        description:
            'Differential backup: ${changes.changedEntities.length} changed, '
            '${changes.deletedIds.length} deleted',
        compressed: _config.compress,
        type: BackupType.differential,
        sourceName: _storage.name,
      );

      _logger.info(
        jsonEncode({
          'event': 'differential_backup_complete',
          'changed': changes.changedEntities.length,
          'deleted': changes.deletedIds.length,
          'path': filePath,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.create,
        metadata: backupMetadata,
        message:
            'Differential backup created: ${changes.changedEntities.length} '
            'changed, ${changes.deletedIds.length} deleted',
        warnings: warnings,
        entitiesAffected:
            changes.changedEntities.length + changes.deletedIds.length,
        bytesProcessed: diffSnapshot.sizeInBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({
          'event': 'differential_backup_failed',
          'error': e.toString(),
        }),
      );

      return BackupResult.failure(
        operation: BackupOperation.create,
        error: e.toString(),
        stackTrace: stack.toString(),
        warnings: warnings,
        startedAt: startedAt,
      );
    }
  }

  /// Creates an incremental backup containing only changes since the last
  /// backup of any type.
  ///
  /// An incremental backup is smaller than a differential backup because it
  /// only stores changes since the most recent backup, not since the last
  /// full backup.
  ///
  /// - [previousBackupPath]: Path to the previous backup (any type).
  /// - [description]: Optional description for this backup.
  /// - [schemaVersion]: Optional schema version to record.
  ///
  /// ## Restore Process
  ///
  /// To restore from incremental backups:
  /// 1. Restore the base full backup
  /// 2. Apply each incremental backup in chronological order
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Create hourly incremental backups
  /// final incrBackup = await backupService.createIncrementalBackup(
  ///   previousBackupPath: lastBackup.filePath!,
  /// );
  /// ```
  Future<BackupResult> createIncrementalBackup({
    required String previousBackupPath,
    String? description,
    String? schemaVersion,
  }) async {
    final startedAt = DateTime.now();
    final warnings = <String>[];

    try {
      _logger.info(
        jsonEncode({
          'event': 'incremental_backup_start',
          'storage': _storage.name,
          'previous': previousBackupPath,
        }),
      );

      // Load the previous backup to determine its type and state
      final prevFile = File(previousBackupPath);
      if (!await prevFile.exists()) {
        throw DataBackupFileNotFoundException(
          'Previous backup file not found: $previousBackupPath',
        );
      }

      final prevBytes = await prevFile.readAsBytes();
      final prevEntities = _loadEntitiesFromBackup(prevBytes);

      // Get current entities
      final currentEntities = await _storage.getAll();

      // Find changes
      final changes = _computeChanges(prevEntities, currentEntities);

      // Create incremental snapshot
      final incrSnapshot = IncrementalSnapshot(
        previousBackupPath: previousBackupPath,
        changedEntities: changes.changedEntities,
        deletedEntityIds: changes.deletedIds,
        timestamp: DateTime.now(),
        version: schemaVersion,
        description: description ?? 'Incremental backup',
        compressed: _config.compress,
      );

      // Verify if configured
      if (_config.verifyAfterCreate && !incrSnapshot.verifyIntegrity()) {
        throw const BackupException(
          'Incremental snapshot integrity verification failed',
        );
      }

      // Generate file path and write
      final fileName = _generateFileName(BackupType.incremental);
      final filePath = p.join(_config.backupDirectory, fileName);

      final file = File(filePath);
      await file.writeAsBytes(incrSnapshot.toBytes(), flush: true);

      // Create metadata
      final backupMetadata = BackupMetadata.create(
        filePath: filePath,
        entityCount: changes.changedEntities.length,
        sizeInBytes: incrSnapshot.sizeInBytes,
        checksum: incrSnapshot.checksum,
        schemaVersion: schemaVersion,
        name: description,
        description:
            'Incremental backup: ${changes.changedEntities.length} changed, '
            '${changes.deletedIds.length} deleted',
        compressed: _config.compress,
        type: BackupType.incremental,
        sourceName: _storage.name,
      );

      _logger.info(
        jsonEncode({
          'event': 'incremental_backup_complete',
          'changed': changes.changedEntities.length,
          'deleted': changes.deletedIds.length,
          'path': filePath,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.create,
        metadata: backupMetadata,
        message:
            'Incremental backup created: ${changes.changedEntities.length} '
            'changed, ${changes.deletedIds.length} deleted',
        warnings: warnings,
        entitiesAffected:
            changes.changedEntities.length + changes.deletedIds.length,
        bytesProcessed: incrSnapshot.sizeInBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({
          'event': 'incremental_backup_failed',
          'error': e.toString(),
        }),
      );

      return BackupResult.failure(
        operation: BackupOperation.create,
        error: e.toString(),
        stackTrace: stack.toString(),
        warnings: warnings,
        startedAt: startedAt,
      );
    }
  }

  /// Restores storage from a chain of backups.
  ///
  /// For differential backups: applies the base full backup then the
  /// differential.
  /// For incremental backups: applies the full backup then all incrementals
  /// in order.
  ///
  /// - [backupPaths]: List of backup file paths in chronological order.
  ///   The first path should be a full backup.
  /// - [clearExisting]: Whether to clear existing data before restore.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Restore from incremental chain
  /// await backupService.restoreChain([
  ///   fullBackupPath,
  ///   incremental1Path,
  ///   incremental2Path,
  /// ]);
  /// ```
  Future<BackupResult> restoreChain(
    List<String> backupPaths, {
    bool clearExisting = true,
  }) async {
    final startedAt = DateTime.now();
    final warnings = <String>[];
    var totalEntities = 0;
    var totalBytes = 0;

    if (backupPaths.isEmpty) {
      return BackupResult.failure(
        operation: BackupOperation.restore,
        error: 'No backup paths provided',
        startedAt: startedAt,
      );
    }

    try {
      _logger.info(
        jsonEncode({
          'event': 'restore_chain_start',
          'storage': _storage.name,
          'backups': backupPaths.length,
        }),
      );

      // Start with the first (full) backup
      final firstBytes = await File(backupPaths.first).readAsBytes();
      totalBytes += firstBytes.length;

      // Determine if it's a full backup or differential/incremental
      final firstType = _detectBackupType(firstBytes);
      if (firstType != BackupType.full && firstType != BackupType.migration) {
        throw BackupException(
          'First backup in chain must be a full backup, got: ${firstType.name}',
        );
      }

      // Restore the full backup
      final fullSnapshot = Snapshot.fromBytes(firstBytes);
      if (_config.verifyBeforeRestore && !fullSnapshot.verifyIntegrity()) {
        throw const BackupException('Full backup integrity check failed');
      }

      // Build the complete state by applying each backup
      var currentState = Map<String, Map<String, dynamic>>.from(
        fullSnapshot.toEntities(),
      );
      totalEntities = currentState.length;

      // Apply each subsequent backup
      for (var i = 1; i < backupPaths.length; i++) {
        final path = backupPaths[i];
        final bytes = await File(path).readAsBytes();
        totalBytes += bytes.length;

        final type = _detectBackupType(bytes);

        switch (type) {
          case BackupType.differential:
            final diff = DifferentialSnapshot.fromBytes(bytes);
            if (_config.verifyBeforeRestore && !diff.verifyIntegrity()) {
              throw BackupException(
                'Differential backup integrity check failed: $path',
              );
            }
            // Apply changes
            currentState.addAll(diff.changedEntities);
            for (final id in diff.deletedEntityIds) {
              currentState.remove(id);
            }
            totalEntities = currentState.length;

          case BackupType.incremental:
            final incr = IncrementalSnapshot.fromBytes(bytes);
            if (_config.verifyBeforeRestore && !incr.verifyIntegrity()) {
              throw BackupException(
                'Incremental backup integrity check failed: $path',
              );
            }
            // Apply changes
            currentState.addAll(incr.changedEntities);
            for (final id in incr.deletedEntityIds) {
              currentState.remove(id);
            }
            totalEntities = currentState.length;

          case BackupType.full:
          case BackupType.migration:
            warnings.add(
              'Unexpected full backup in chain at position $i: $path',
            );
            // Replace entire state
            final snapshot = Snapshot.fromBytes(bytes);
            currentState = Map.from(snapshot.toEntities());
            totalEntities = currentState.length;
        }
      }

      // Clear existing if requested
      if (clearExisting) {
        await _storage.deleteAll();
      }

      // Insert the final state
      if (currentState.isNotEmpty) {
        await _storage.insertMany(currentState);
      }

      _logger.info(
        jsonEncode({
          'event': 'restore_chain_complete',
          'storage': _storage.name,
          'backups': backupPaths.length,
          'entities': totalEntities,
        }),
      );

      return BackupResult.success(
        operation: BackupOperation.restore,
        message:
            'Restored from ${backupPaths.length} backups, '
            '$totalEntities entities',
        warnings: warnings,
        entitiesAffected: totalEntities,
        bytesProcessed: totalBytes,
        startedAt: startedAt,
      );
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'restore_chain_failed', 'error': e.toString()}),
      );

      return BackupResult.failure(
        operation: BackupOperation.restore,
        error: e.toString(),
        stackTrace: stack.toString(),
        warnings: warnings,
        startedAt: startedAt,
      );
    }
  }

  /// Computes the changes between a base state and current state.
  _EntityChanges _computeChanges(
    Map<String, Map<String, dynamic>> baseEntities,
    Map<String, Map<String, dynamic>> currentEntities,
  ) {
    final changedEntities = <String, Map<String, dynamic>>{};
    final deletedIds = <String>[];

    // Find new and modified entities
    for (final entry in currentEntities.entries) {
      final id = entry.key;
      final currentData = entry.value;
      final baseData = baseEntities[id];

      if (baseData == null) {
        // New entity
        changedEntities[id] = currentData;
      } else if (!_mapsAreEqual(baseData, currentData)) {
        // Modified entity
        changedEntities[id] = currentData;
      }
    }

    // Find deleted entities
    for (final id in baseEntities.keys) {
      if (!currentEntities.containsKey(id)) {
        deletedIds.add(id);
      }
    }

    return _EntityChanges(
      changedEntities: changedEntities,
      deletedIds: deletedIds,
    );
  }

  /// Deep equality check for entity maps.
  bool _mapsAreEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;

    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;

      final aValue = a[key];
      final bValue = b[key];

      if (aValue is Map && bValue is Map) {
        if (!_mapsAreEqual(
          aValue.cast<String, dynamic>(),
          bValue.cast<String, dynamic>(),
        )) {
          return false;
        }
      } else if (aValue is List && bValue is List) {
        if (!_listsAreEqual(aValue, bValue)) return false;
      } else if (aValue != bValue) {
        return false;
      }
    }

    return true;
  }

  /// Deep equality check for lists.
  bool _listsAreEqual(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] is Map && b[i] is Map) {
        if (!_mapsAreEqual(
          (a[i] as Map).cast<String, dynamic>(),
          (b[i] as Map).cast<String, dynamic>(),
        )) {
          return false;
        }
      } else if (a[i] is List && b[i] is List) {
        if (!_listsAreEqual(a[i], b[i])) return false;
      } else if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Detects the backup type from raw bytes.
  BackupType _detectBackupType(List<int> bytes) {
    // Check magic numbers
    if (bytes.length < 4) return BackupType.full;

    // Full snapshot magic: [0x53, 0x4E, 0x41, 0x50] = "SNAP"
    if (bytes[0] == 0x53 &&
        bytes[1] == 0x4E &&
        bytes[2] == 0x41 &&
        bytes[3] == 0x50) {
      return BackupType.full;
    }

    // Differential magic: [0x44, 0x49, 0x46, 0x46] = "DIFF"
    if (bytes[0] == 0x44 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return BackupType.differential;
    }

    // Incremental magic: [0x49, 0x4E, 0x43, 0x52] = "INCR"
    if (bytes[0] == 0x49 &&
        bytes[1] == 0x4E &&
        bytes[2] == 0x43 &&
        bytes[3] == 0x52) {
      return BackupType.incremental;
    }

    // Default to full for unknown formats
    return BackupType.full;
  }

  /// Loads entities from a backup of any type.
  Map<String, Map<String, dynamic>> _loadEntitiesFromBackup(List<int> bytes) {
    final type = _detectBackupType(Uint8List.fromList(bytes));

    switch (type) {
      case BackupType.full:
      case BackupType.migration:
        final snapshot = Snapshot.fromBytes(Uint8List.fromList(bytes));
        return snapshot.toEntities();

      case BackupType.differential:
        final diff = DifferentialSnapshot.fromBytes(bytes);
        return diff.changedEntities;

      case BackupType.incremental:
        final incr = IncrementalSnapshot.fromBytes(bytes);
        return incr.changedEntities;
    }
  }

  /// Applies retention policy to remove old backups.
  Future<void> _applyRetentionPolicy(List<String> warnings) async {
    if (_config.maxBackups == null && _config.maxAge == null) {
      return;
    }

    try {
      var backups = await listBackups();

      // Apply max age policy
      if (_config.maxAge != null) {
        final cutoff = DateTime.now().subtract(_config.maxAge!);
        final expired = backups
            .where((b) => b.createdAt.isBefore(cutoff))
            .toList();

        for (final backup in expired) {
          await deleteBackup(backup.filePath);
          warnings.add('Deleted expired backup: ${backup.fileName}');
        }

        // Refresh list after deletions
        backups = await listBackups();
      }

      // Apply max backups policy
      if (_config.maxBackups != null && backups.length > _config.maxBackups!) {
        final toDelete = backups.sublist(_config.maxBackups!);

        for (final backup in toDelete) {
          await deleteBackup(backup.filePath);
          warnings.add('Deleted excess backup: ${backup.fileName}');
        }
      }
    } catch (e) {
      warnings.add('Failed to apply retention policy: $e');
      _logger.warning(
        jsonEncode({'event': 'retention_policy_failed', 'error': e.toString()}),
      );
    }
  }
}
