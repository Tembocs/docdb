/// EntiDB Backup - Backup Manager
///
/// Provides a high-level manager for coordinating backup and restore
/// operations across multiple storage instances.
library;

import 'dart:convert';

import '../entity/entity.dart';
import '../exceptions/backup_exceptions.dart';
import '../logger/entidb_logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'backup_metadata.dart';
import 'backup_result.dart';
import 'backup_service.dart';
import 'snapshot.dart';

/// Manages backup and restore operations for data and user storage.
///
/// Provides coordinated backup functionality for systems with multiple
/// storage instances (e.g., separate data and user storage). Wraps
/// [BackupService] instances to provide unified operations.
///
/// ## Basic Usage
///
/// ```dart
/// final manager = BackupManager<Product, User>(
///   dataStorage: productStorage,
///   userStorage: userStorage,
///   dataBackupPath: '/backups/data',
///   userBackupPath: '/backups/users',
/// );
///
/// await manager.initialize();
///
/// // Backup both storages
/// final results = await manager.createFullBackup(
///   description: 'Daily backup',
/// );
///
/// print('Data: ${results.dataResult.summary}');
/// print('User: ${results.userResult.summary}');
/// ```
///
/// ## Migration Support
///
/// ```dart
/// // Create pre-migration backups
/// final backups = await manager.createMigrationBackups();
///
/// try {
///   await migrationManager.migrateAll();
/// } catch (e) {
///   // Rollback on failure
///   await manager.restoreFromLatest();
/// }
/// ```
///
/// ## Individual Operations
///
/// ```dart
/// // Backup only data storage
/// final dataResult = await manager.createDataBackup();
///
/// // List available user backups
/// final userBackups = await manager.listUserBackups();
///
/// // Restore specific backup
/// await manager.restoreDataBackup(userBackups.first.filePath);
/// ```
final class BackupManager<D extends Entity, U extends Entity> {
  final BackupService<D> _dataBackupService;
  final BackupService<U> _userBackupService;
  final EntiDBLogger _logger;

  bool _initialized = false;

  /// Creates a new backup manager.
  ///
  /// - [dataStorage]: Storage for application data.
  /// - [userStorage]: Storage for user/authentication data.
  /// - [dataBackupPath]: Directory for data backups.
  /// - [userBackupPath]: Directory for user backups.
  /// - [config]: Optional shared backup configuration.
  /// - [logger]: Optional custom logger.
  BackupManager({
    required Storage<D> dataStorage,
    required Storage<U> userStorage,
    required String dataBackupPath,
    required String userBackupPath,
    BackupConfig? config,
    EntiDBLogger? logger,
  }) : _dataBackupService = BackupService<D>(
         storage: dataStorage,
         config: config ?? BackupConfig(backupDirectory: dataBackupPath),
       ),
       _userBackupService = BackupService<U>(
         storage: userStorage,
         config: config ?? BackupConfig(backupDirectory: userBackupPath),
       ),
       _logger = logger ?? EntiDBLogger(LoggerNameConstants.backup);

  /// Creates a backup manager with custom configurations.
  ///
  /// Allows different configurations for data and user backups.
  BackupManager.withConfigs({
    required Storage<D> dataStorage,
    required Storage<U> userStorage,
    required BackupConfig dataConfig,
    required BackupConfig userConfig,
    EntiDBLogger? logger,
  }) : _dataBackupService = BackupService<D>(
         storage: dataStorage,
         config: dataConfig,
       ),
       _userBackupService = BackupService<U>(
         storage: userStorage,
         config: userConfig,
       ),
       _logger = logger ?? EntiDBLogger(LoggerNameConstants.backup);

  /// The data backup service.
  BackupService<D> get dataBackupService => _dataBackupService;

  /// The user backup service.
  BackupService<U> get userBackupService => _userBackupService;

  /// Whether the manager has been initialized.
  bool get isInitialized => _initialized;

  /// Initializes both backup services.
  ///
  /// Creates backup directories if they don't exist.
  ///
  /// Throws [BackupException] if initialization fails.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _logger.info(jsonEncode({'event': 'backup_manager_init'}));

      await _dataBackupService.initialize();
      await _userBackupService.initialize();

      _initialized = true;

      _logger.info(jsonEncode({'event': 'backup_manager_init_complete'}));
    } catch (e, stack) {
      _logger.error(
        jsonEncode({
          'event': 'backup_manager_init_failed',
          'error': e.toString(),
        }),
      );
      throw BackupException(
        'Failed to initialize backup manager: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Data Backup Operations
  // ---------------------------------------------------------------------------

  /// Creates a backup of data storage.
  Future<BackupResult> createDataBackup({
    String? description,
    BackupType type = BackupType.full,
    String? schemaVersion,
  }) async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'data_backup_start', 'type': type.name}));

    final result = await _dataBackupService.createBackup(
      description: description,
      type: type,
      schemaVersion: schemaVersion,
    );

    _logger.info(
      jsonEncode({
        'event': 'data_backup_complete',
        'success': result.isSuccess,
        'path': result.filePath,
      }),
    );

    return result;
  }

  /// Restores data storage from a backup file.
  Future<BackupResult> restoreDataBackup(
    String filePath, {
    bool clearExisting = true,
  }) async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'data_restore_start', 'path': filePath}));

    final result = await _dataBackupService.restore(
      filePath,
      clearExisting: clearExisting,
    );

    _logger.info(
      jsonEncode({
        'event': 'data_restore_complete',
        'success': result.isSuccess,
      }),
    );

    return result;
  }

  /// Lists available data backups.
  Future<List<BackupMetadata>> listDataBackups() async {
    _ensureInitialized();
    return _dataBackupService.listBackups();
  }

  /// Finds the latest data backup.
  Future<BackupMetadata?> findLatestDataBackup() async {
    _ensureInitialized();
    return _dataBackupService.findLatestBackup();
  }

  /// Verifies a data backup file.
  Future<BackupResult> verifyDataBackup(String filePath) async {
    _ensureInitialized();
    return _dataBackupService.verify(filePath);
  }

  /// Creates an in-memory backup of data storage.
  Future<Snapshot> createDataMemoryBackup({String? schemaVersion}) async {
    _ensureInitialized();
    return _dataBackupService.createMemoryBackup(schemaVersion: schemaVersion);
  }

  /// Restores data storage from a snapshot.
  Future<void> restoreDataFromSnapshot(
    Snapshot snapshot, {
    bool clearExisting = true,
  }) async {
    _ensureInitialized();
    await _dataBackupService.restoreFromSnapshot(
      snapshot,
      clearExisting: clearExisting,
    );
  }

  // ---------------------------------------------------------------------------
  // User Backup Operations
  // ---------------------------------------------------------------------------

  /// Creates a backup of user storage.
  Future<BackupResult> createUserBackup({
    String? description,
    BackupType type = BackupType.full,
    String? schemaVersion,
  }) async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'user_backup_start', 'type': type.name}));

    final result = await _userBackupService.createBackup(
      description: description,
      type: type,
      schemaVersion: schemaVersion,
    );

    _logger.info(
      jsonEncode({
        'event': 'user_backup_complete',
        'success': result.isSuccess,
        'path': result.filePath,
      }),
    );

    return result;
  }

  /// Restores user storage from a backup file.
  Future<BackupResult> restoreUserBackup(
    String filePath, {
    bool clearExisting = true,
  }) async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'user_restore_start', 'path': filePath}));

    final result = await _userBackupService.restore(
      filePath,
      clearExisting: clearExisting,
    );

    _logger.info(
      jsonEncode({
        'event': 'user_restore_complete',
        'success': result.isSuccess,
      }),
    );

    return result;
  }

  /// Lists available user backups.
  Future<List<BackupMetadata>> listUserBackups() async {
    _ensureInitialized();
    return _userBackupService.listBackups();
  }

  /// Finds the latest user backup.
  Future<BackupMetadata?> findLatestUserBackup() async {
    _ensureInitialized();
    return _userBackupService.findLatestBackup();
  }

  /// Verifies a user backup file.
  Future<BackupResult> verifyUserBackup(String filePath) async {
    _ensureInitialized();
    return _userBackupService.verify(filePath);
  }

  /// Creates an in-memory backup of user storage.
  Future<Snapshot> createUserMemoryBackup({String? schemaVersion}) async {
    _ensureInitialized();
    return _userBackupService.createMemoryBackup(schemaVersion: schemaVersion);
  }

  /// Restores user storage from a snapshot.
  Future<void> restoreUserFromSnapshot(
    Snapshot snapshot, {
    bool clearExisting = true,
  }) async {
    _ensureInitialized();
    await _userBackupService.restoreFromSnapshot(
      snapshot,
      clearExisting: clearExisting,
    );
  }

  // ---------------------------------------------------------------------------
  // Combined Operations
  // ---------------------------------------------------------------------------

  /// Creates backups of both data and user storage.
  ///
  /// Returns a [CombinedBackupResult] with results for both operations.
  Future<CombinedBackupResult> createFullBackup({
    String? description,
    BackupType type = BackupType.full,
    String? schemaVersion,
  }) async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'full_backup_start'}));

    final dataResult = await createDataBackup(
      description: description != null ? '$description (data)' : null,
      type: type,
      schemaVersion: schemaVersion,
    );

    final userResult = await createUserBackup(
      description: description != null ? '$description (user)' : null,
      type: type,
      schemaVersion: schemaVersion,
    );

    _logger.info(
      jsonEncode({
        'event': 'full_backup_complete',
        'dataSuccess': dataResult.isSuccess,
        'userSuccess': userResult.isSuccess,
      }),
    );

    return CombinedBackupResult(dataResult: dataResult, userResult: userResult);
  }

  /// Creates migration backups for both storages.
  Future<CombinedBackupResult> createMigrationBackups({
    String? schemaVersion,
    String? description,
  }) async {
    return createFullBackup(
      description: description ?? 'Pre-migration backup',
      type: BackupType.migration,
      schemaVersion: schemaVersion,
    );
  }

  /// Restores both storages from their latest backups.
  ///
  /// Returns a [CombinedBackupResult] with results for both operations.
  Future<CombinedBackupResult> restoreFromLatest() async {
    _ensureInitialized();

    _logger.info(jsonEncode({'event': 'restore_latest_start'}));

    final latestData = await findLatestDataBackup();
    final latestUser = await findLatestUserBackup();

    BackupResult dataResult;
    BackupResult userResult;

    if (latestData != null) {
      dataResult = await restoreDataBackup(latestData.filePath);
    } else {
      dataResult = BackupResult.failure(
        operation: BackupOperation.restore,
        error: 'No data backups found',
      );
    }

    if (latestUser != null) {
      userResult = await restoreUserBackup(latestUser.filePath);
    } else {
      userResult = BackupResult.failure(
        operation: BackupOperation.restore,
        error: 'No user backups found',
      );
    }

    _logger.info(
      jsonEncode({
        'event': 'restore_latest_complete',
        'dataSuccess': dataResult.isSuccess,
        'userSuccess': userResult.isSuccess,
      }),
    );

    return CombinedBackupResult(dataResult: dataResult, userResult: userResult);
  }

  /// Creates in-memory backups of both storages.
  ///
  /// Useful for quick rollback during transactions or migrations.
  Future<CombinedMemoryBackup> createMemoryBackups({
    String? schemaVersion,
  }) async {
    _ensureInitialized();

    final dataSnapshot = await createDataMemoryBackup(
      schemaVersion: schemaVersion,
    );
    final userSnapshot = await createUserMemoryBackup(
      schemaVersion: schemaVersion,
    );

    return CombinedMemoryBackup(
      dataSnapshot: dataSnapshot,
      userSnapshot: userSnapshot,
    );
  }

  /// Restores both storages from memory backups.
  Future<void> restoreFromMemoryBackups(
    CombinedMemoryBackup backups, {
    bool clearExisting = true,
  }) async {
    _ensureInitialized();

    await restoreDataFromSnapshot(
      backups.dataSnapshot,
      clearExisting: clearExisting,
    );
    await restoreUserFromSnapshot(
      backups.userSnapshot,
      clearExisting: clearExisting,
    );
  }

  /// Ensures the manager has been initialized.
  void _ensureInitialized() {
    if (!_initialized) {
      throw const BackupException(
        'BackupManager not initialized. Call initialize() first.',
      );
    }
  }
}

/// Result of a combined backup/restore operation.
///
/// Contains results for both data and user storage operations.
final class CombinedBackupResult {
  /// Result of the data storage operation.
  final BackupResult dataResult;

  /// Result of the user storage operation.
  final BackupResult userResult;

  /// Creates a new combined result.
  const CombinedBackupResult({
    required this.dataResult,
    required this.userResult,
  });

  /// Whether both operations succeeded.
  bool get isSuccess => dataResult.isSuccess && userResult.isSuccess;

  /// Whether both operations failed.
  bool get isFailure => dataResult.isFailure && userResult.isFailure;

  /// Whether only one operation succeeded.
  bool get isPartialSuccess =>
      (dataResult.isSuccess && userResult.isFailure) ||
      (dataResult.isFailure && userResult.isSuccess);

  /// Combined summary of both operations.
  String get summary =>
      'Data: ${dataResult.summary}\nUser: ${userResult.summary}';

  /// Converts to a map for logging.
  Map<String, dynamic> toMap() => {
    'isSuccess': isSuccess,
    'dataResult': dataResult.toMap(),
    'userResult': userResult.toMap(),
  };

  @override
  String toString() => summary;
}

/// Combined in-memory backups for both storages.
final class CombinedMemoryBackup {
  /// Snapshot of data storage.
  final Snapshot dataSnapshot;

  /// Snapshot of user storage.
  final Snapshot userSnapshot;

  /// Creates a new combined memory backup.
  const CombinedMemoryBackup({
    required this.dataSnapshot,
    required this.userSnapshot,
  });

  /// Total entities in both snapshots.
  int get totalEntityCount =>
      dataSnapshot.entityCount + userSnapshot.entityCount;

  /// Total size of both snapshots.
  int get totalSizeInBytes =>
      dataSnapshot.sizeInBytes + userSnapshot.sizeInBytes;

  @override
  String toString() =>
      'CombinedMemoryBackup(data: ${dataSnapshot.entityCount} entities, '
      'user: ${userSnapshot.entityCount} entities)';
}
