/// DocDB Backup - Backup Service
///
/// Provides a robust, generic backup service for entity storage with
/// integrity verification, compression, and flexible storage options.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../entity/entity.dart';
import '../exceptions/backup_exceptions.dart';
import '../logger/docdb_logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'backup_metadata.dart';
import 'backup_result.dart';
import 'snapshot.dart';

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
  final DocDBLogger _logger;

  /// Creates a new backup service.
  ///
  /// - [storage]: The entity storage to backup.
  /// - [config]: Backup configuration options.
  /// - [logger]: Optional custom logger.
  BackupService({
    required Storage<T> storage,
    required BackupConfig config,
    DocDBLogger? logger,
  }) : _storage = storage,
       _config = config,
       _logger = logger ?? DocDBLogger(LoggerNameConstants.backup);

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
    final prefix = type == BackupType.migration ? 'migration' : 'backup';
    return '${_storage.name}_${prefix}_$timestamp${_config.fileExtension}';
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
