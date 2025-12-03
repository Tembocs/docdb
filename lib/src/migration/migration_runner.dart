/// DocDB Migration - Migration Runner
///
/// Provides the core migration execution engine for entity storage.
library;

import 'dart:convert';

import '../backup/backup_service.dart';
import '../backup/snapshot.dart';
import '../entity/entity.dart';
import '../exceptions/migration_exceptions.dart';
import '../logger/docdb_logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'migration_config.dart';
import 'migration_log.dart';
import 'migration_step.dart';
import 'migration_strategy.dart';
import 'versioned_data.dart';

/// Executes migrations for an entity storage.
///
/// The migration runner handles the complete migration lifecycle including:
/// - Determining the migration path from current to target version
/// - Creating backups before migration (optional, using BackupService)
/// - Executing migration steps in order
/// - Logging migration results
/// - Rolling back on failure with integrity verification
///
/// ## Usage
///
/// ```dart
/// final runner = MigrationRunner<Product>(
///   storage: productStorage,
///   config: MigrationConfig(
///     currentVersion: '2.0.0',
///     migrations: [
///       AddPriceFieldMigration(),
///       RenameSkuMigration(),
///     ],
///   ),
/// );
///
/// // Check if migration is needed
/// if (await runner.needsMigration()) {
///   final result = await runner.migrate();
///   print('Migrated ${result.entitiesAffected} entities');
/// }
/// ```
///
/// ## Backup Integration
///
/// The runner integrates with [BackupService] for robust backup/restore:
///
/// ```dart
/// final runner = MigrationRunner<Product>(
///   storage: productStorage,
///   config: MigrationConfig(
///     currentVersion: '2.0.0',
///     migrations: [...],
///     createBackupBeforeMigration: true,
///   ),
///   backupService: BackupService<Product>(
///     storage: productStorage,
///     config: BackupConfig.migration('/backups/products'),
///   ),
/// );
/// ```
///
/// ## Migration Path Resolution
///
/// The runner automatically determines the shortest path between the
/// stored version and target version using the available migrations.
/// Both upgrades and downgrades are supported.
final class MigrationRunner<T extends Entity> {
  final Storage<T> _storage;
  final MigrationConfig _config;
  final DocDBLogger _logger;
  final BackupService<T>? _backupService;
  final List<MigrationLog> _history = [];

  String? _currentVersion;
  bool _initialized = false;

  /// Creates a new migration runner.
  ///
  /// - [storage]: The entity storage to migrate.
  /// - [config]: Migration configuration.
  /// - [backupService]: Optional backup service for robust backups.
  ///   If not provided, uses simple in-memory backup.
  /// - [logger]: Optional custom logger.
  MigrationRunner({
    required Storage<T> storage,
    required MigrationConfig config,
    BackupService<T>? backupService,
    DocDBLogger? logger,
  }) : _storage = storage,
       _config = config,
       _backupService = backupService,
       _logger = logger ?? DocDBLogger(LoggerNameConstants.migration);

  /// The storage being migrated.
  Storage<T> get storage => _storage;

  /// The migration configuration.
  MigrationConfig get config => _config;

  /// The current schema version of the storage.
  ///
  /// Returns `null` if not yet initialized.
  String? get currentVersion => _currentVersion;

  /// The target schema version from configuration.
  String get targetVersion => _config.currentVersion;

  /// The migration history log.
  List<MigrationLog> get history => List.unmodifiable(_history);

  /// Whether a backup service is configured.
  bool get hasBackupService => _backupService != null;

  /// Initializes the migration runner.
  ///
  /// Loads the current schema version from storage metadata and
  /// auto-migrates if configured to do so.
  ///
  /// Throws [MigrationException] if initialization fails.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _logger.info(
        jsonEncode({
          'event': 'migration_init',
          'storage': _storage.name,
          'targetVersion': targetVersion,
          'hasBackupService': hasBackupService,
        }),
      );

      // Initialize backup service if provided
      if (_backupService != null) {
        await _backupService.initialize();
      }

      await _loadCurrentVersion();

      if (_config.autoMigrate && await needsMigration()) {
        await migrate();
      }

      _initialized = true;
    } catch (e, stack) {
      _logger.error(
        jsonEncode({'event': 'migration_init_failed', 'error': e.toString()}),
      );
      throw MigrationException(
        'Failed to initialize migration runner: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Loads the current schema version from storage metadata.
  Future<void> _loadCurrentVersion() async {
    try {
      final versionData = await _storage.get('__schema_version__');
      if (versionData != null) {
        final schema = SchemaVersion.fromMap('__schema_version__', versionData);
        _currentVersion = schema.version;
      } else {
        // No version stored - assume initial version
        _currentVersion = '0.0.0';
        await _saveCurrentVersion();
      }
      _logger.debug(
        jsonEncode({'event': 'version_loaded', 'version': _currentVersion}),
      );
    } catch (e) {
      _logger.warning(
        jsonEncode({'event': 'version_load_failed', 'error': e.toString()}),
      );
      _currentVersion = '0.0.0';
    }
  }

  /// Saves the current schema version to storage metadata.
  Future<void> _saveCurrentVersion() async {
    if (_currentVersion == null) return;

    final schema = SchemaVersion.now(
      id: '__schema_version__',
      version: _currentVersion!,
    );

    try {
      await _storage.upsert('__schema_version__', schema.toMap());
    } catch (e) {
      _logger.error(
        jsonEncode({'event': 'version_save_failed', 'error': e.toString()}),
      );
      throw MigrationException('Failed to save schema version: $e');
    }
  }

  /// Checks if migration is needed.
  ///
  /// Returns `true` if the current version differs from the target version.
  Future<bool> needsMigration() async {
    if (_currentVersion == null) {
      await _loadCurrentVersion();
    }
    return _currentVersion != targetVersion;
  }

  /// Performs the migration from current to target version.
  ///
  /// Returns a [MigrationLog] with the result of the migration.
  ///
  /// Throws [MigrationException] if migration fails and cannot be rolled back.
  Future<MigrationLog> migrate() async {
    if (_currentVersion == null) {
      await _loadCurrentVersion();
    }

    final fromVersion = _currentVersion!;
    final stopwatch = Stopwatch()..start();

    _logger.info(
      jsonEncode({
        'event': 'migration_start',
        'from': fromVersion,
        'to': targetVersion,
      }),
    );

    // Skip if already at target version
    if (fromVersion == targetVersion) {
      final log = MigrationLog.skipped(
        fromVersion: fromVersion,
        toVersion: targetVersion,
        reason: 'Already at target version',
      );
      _history.add(log);
      return log;
    }

    // Get migration path
    List<MigrationStep> steps;
    try {
      steps = _buildMigrationPath(fromVersion, targetVersion);
    } catch (e) {
      final log = MigrationLog.failed(
        fromVersion: fromVersion,
        toVersion: targetVersion,
        error: 'Failed to build migration path: $e',
      );
      _history.add(log);
      throw MigrationException(
        'No migration path from $fromVersion to $targetVersion',
      );
    }

    // Create backup if configured
    Snapshot? backupSnapshot;
    if (_config.createBackupBeforeMigration) {
      backupSnapshot = await _createBackup(fromVersion);
    }

    // Load all entity data
    Map<String, Map<String, dynamic>> entities;
    try {
      entities = await _storage.getAll();
      // Remove metadata entries
      entities.remove('__schema_version__');
      entities.remove('__migration_history__');
    } catch (e) {
      final log = MigrationLog.failed(
        fromVersion: fromVersion,
        toVersion: targetVersion,
        error: 'Failed to load entities: $e',
        durationMs: stopwatch.elapsedMilliseconds,
      );
      _history.add(log);
      throw MigrationException('Failed to load entities for migration: $e');
    }

    // Execute migration steps
    try {
      for (final step in steps) {
        _logger.info(
          jsonEncode({
            'event': 'migration_step',
            'description': step.description,
            'from': step.sourceVersion,
            'to': step.targetVersion,
          }),
        );

        entities = await step.execute(entities);

        if (_config.validateAfterEachStep) {
          _validateMigratedData(entities);
        }
      }

      // Save migrated entities
      await _saveMigratedEntities(entities);

      // Update version
      _currentVersion = targetVersion;
      await _saveCurrentVersion();

      stopwatch.stop();

      final log = MigrationLog.success(
        fromVersion: fromVersion,
        toVersion: targetVersion,
        durationMs: stopwatch.elapsedMilliseconds,
        entitiesAffected: entities.length,
      );
      _history.add(log);
      await _persistHistory();

      _logger.info(
        jsonEncode({
          'event': 'migration_complete',
          'from': fromVersion,
          'to': targetVersion,
          'entities': entities.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        }),
      );

      return log;
    } catch (e, stack) {
      stopwatch.stop();

      _logger.error(
        jsonEncode({'event': 'migration_failed', 'error': e.toString()}),
      );

      // Attempt rollback
      if (backupSnapshot != null) {
        await _restoreBackup(backupSnapshot);
      }

      final log = MigrationLog.failed(
        fromVersion: fromVersion,
        toVersion: targetVersion,
        error: e.toString(),
        stackTrace: stack.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );
      _history.add(log);
      await _persistHistory();

      throw MigrationException(
        'Migration failed: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Builds the migration path from current to target version.
  List<MigrationStep> _buildMigrationPath(String from, String to) {
    final isUpgrade = _compareVersions(to, from) > 0;
    final steps = <MigrationStep>[];

    // Sort migrations by version
    final sortedMigrations = List<MigrationStrategy>.from(_config.migrations);
    sortedMigrations.sort((a, b) {
      final aVersion = isUpgrade ? a.toVersion : a.fromVersion;
      final bVersion = isUpgrade ? b.toVersion : b.fromVersion;
      return isUpgrade
          ? _compareVersions(aVersion, bVersion)
          : _compareVersions(bVersion, aVersion);
    });

    var currentVer = from;
    var sequence = 0;

    for (final migration in sortedMigrations) {
      if (isUpgrade) {
        // Check if this migration applies
        if (migration.fromVersion == currentVer &&
            _compareVersions(migration.toVersion, to) <= 0) {
          steps.add(
            MigrationStep(
              strategy: migration,
              isUpgrade: true,
              sequenceNumber: sequence++,
            ),
          );
          currentVer = migration.toVersion;
          if (currentVer == to) break;
        }
      } else {
        // Downgrade
        if (migration.toVersion == currentVer &&
            _compareVersions(migration.fromVersion, to) >= 0) {
          steps.add(
            MigrationStep(
              strategy: migration,
              isUpgrade: false,
              sequenceNumber: sequence++,
            ),
          );
          currentVer = migration.fromVersion;
          if (currentVer == to) break;
        }
      }
    }

    if (currentVer != to) {
      throw MigrationException(
        'Incomplete migration path: reached $currentVer but target is $to',
      );
    }

    return steps;
  }

  /// Compares two semantic version strings.
  ///
  /// Returns negative if a < b, zero if equal, positive if a > b.
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.tryParse).toList();
    final bParts = b.split('.').map(int.tryParse).toList();

    for (var i = 0; i < 3; i++) {
      final aVal = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bVal = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (aVal != bVal) return aVal.compareTo(bVal);
    }
    return 0;
  }

  /// Creates a backup before migration.
  ///
  /// Uses [BackupService] if available for robust, verified backups.
  /// Falls back to simple in-memory snapshot otherwise.
  Future<Snapshot> _createBackup(String version) async {
    _logger.debug(
      jsonEncode({
        'event': 'creating_migration_backup',
        'useBackupService': _backupService != null,
      }),
    );

    if (_backupService != null) {
      // Use BackupService for verified, file-persisted backup
      return await _backupService.createMemoryBackup(
        schemaVersion: version,
        description: 'Pre-migration backup from v$version to v$targetVersion',
      );
    } else {
      // Simple in-memory backup
      final entities = await _storage.getAll();
      return Snapshot.fromEntities(
        entities: entities,
        version: version,
        description: 'Pre-migration backup',
      );
    }
  }

  /// Restores from a backup snapshot.
  ///
  /// Uses [BackupService] if available for verified restore.
  Future<void> _restoreBackup(Snapshot snapshot) async {
    _logger.debug(jsonEncode({'event': 'restoring_migration_backup'}));

    try {
      // Verify snapshot integrity before restore
      if (!snapshot.verifyIntegrity()) {
        _logger.error(jsonEncode({'event': 'backup_integrity_failed'}));
        throw MigrationException(
          'Backup integrity verification failed - cannot rollback',
        );
      }

      if (_backupService != null) {
        await _backupService.restoreFromSnapshot(snapshot);
      } else {
        // Simple restore
        final entities = snapshot.toEntities();
        await _storage.deleteAll();
        await _storage.insertMany(entities);
      }

      _logger.info(jsonEncode({'event': 'migration_rolled_back'}));
    } catch (e) {
      _logger.error(
        jsonEncode({'event': 'rollback_failed', 'error': e.toString()}),
      );
      // Don't rethrow - we already logged the failure
    }
  }

  /// Saves migrated entities back to storage.
  Future<void> _saveMigratedEntities(
    Map<String, Map<String, dynamic>> entities,
  ) async {
    // Clear existing entities (except metadata)
    final allData = await _storage.getAll();
    for (final id in allData.keys) {
      if (!id.startsWith('__')) {
        await _storage.delete(id);
      }
    }

    // Insert migrated entities
    await _storage.insertMany(entities);
  }

  /// Validates migrated data.
  void _validateMigratedData(Map<String, Map<String, dynamic>> entities) {
    // Basic validation - ensure all entries are valid maps
    for (final entry in entities.entries) {
      if (entry.key.isEmpty) {
        throw MigrationException('Invalid entity: empty ID');
      }
    }
  }

  /// Persists migration history to storage.
  Future<void> _persistHistory() async {
    try {
      final historyData = _history.map((log) => log.toMap()).toList();

      // Trim history if needed
      final trimmed =
          _config.maxLogEntries != null &&
              historyData.length > _config.maxLogEntries!
          ? historyData.sublist(historyData.length - _config.maxLogEntries!)
          : historyData;

      await _storage.upsert('__migration_history__', {'entries': trimmed});
    } catch (e) {
      _logger.warning(
        jsonEncode({'event': 'history_persist_failed', 'error': e.toString()}),
      );
    }
  }

  /// Loads migration history from storage.
  Future<void> loadHistory() async {
    try {
      final data = await _storage.get('__migration_history__');
      if (data != null && data['entries'] is List) {
        _history.clear();
        for (final entry in data['entries'] as List) {
          _history.add(MigrationLog.fromMap(entry as Map<String, dynamic>));
        }
      }
    } catch (e) {
      _logger.warning(
        jsonEncode({'event': 'history_load_failed', 'error': e.toString()}),
      );
    }
  }

  /// Exports version data for external persistence.
  Map<String, dynamic> exportVersionData() {
    return {
      'currentVersion': _currentVersion,
      'targetVersion': targetVersion,
      'history': _history.map((log) => log.toMap()).toList(),
    };
  }

  /// Imports version data from external source.
  void importVersionData(Map<String, dynamic> data) {
    _currentVersion = data['currentVersion'] as String?;
    if (data['history'] is List) {
      _history.clear();
      for (final entry in data['history'] as List) {
        _history.add(MigrationLog.fromMap(entry as Map<String, dynamic>));
      }
    }
  }

  /// Disposes resources used by the migration runner.
  Future<void> dispose() async {
    await _persistHistory();
  }
}
