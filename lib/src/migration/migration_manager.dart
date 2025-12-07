/// EntiDB Migration - Migration Manager
///
/// Provides coordinated migration management for both data and user storage.
library;

import 'dart:convert';

import '../entity/entity.dart';
import '../exceptions/migration_exceptions.dart';
import '../logger/entidb_logger.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'migration_config.dart';
import 'migration_log.dart';
import 'migration_runner.dart';

/// Manages migrations for both data and user storage.
///
/// The migration manager coordinates migrations across multiple storage
/// instances, ensuring they are executed in the correct order and providing
/// a unified interface for migration operations.
///
/// ## Usage
///
/// ```dart
/// final manager = MigrationManager(
///   dataRunner: MigrationRunner<Product>(
///     storage: productStorage,
///     config: dataConfig,
///   ),
///   userRunner: MigrationRunner<User>(
///     storage: userStorage,
///     config: userConfig,
///   ),
/// );
///
/// await manager.initialize();
///
/// // Check migration status
/// final status = await manager.getMigrationStatus();
/// print('Data needs migration: ${status.dataNeedsMigration}');
/// print('User needs migration: ${status.userNeedsMigration}');
///
/// // Perform all migrations
/// await manager.migrateAll();
/// ```
///
/// ## Migration Order
///
/// When both data and user migrations are needed, user migrations are
/// performed first. This ensures authentication data is up-to-date
/// before migrating application data that may depend on user references.
final class MigrationManager<D extends Entity, U extends Entity> {
  final MigrationRunner<D>? _dataRunner;
  final MigrationRunner<U>? _userRunner;
  final EntiDBLogger _logger;
  bool _initialized = false;

  /// Creates a migration manager.
  ///
  /// At least one of [dataRunner] or [userRunner] must be provided.
  ///
  /// - [dataRunner]: Migration runner for application data.
  /// - [userRunner]: Migration runner for user/auth data.
  /// - [logger]: Optional custom logger.
  MigrationManager({
    MigrationRunner<D>? dataRunner,
    MigrationRunner<U>? userRunner,
    EntiDBLogger? logger,
  }) : _dataRunner = dataRunner,
       _userRunner = userRunner,
       _logger = logger ?? EntiDBLogger(LoggerNameConstants.migration) {
    if (dataRunner == null && userRunner == null) {
      throw ArgumentError(
        'At least one of dataRunner or userRunner must be provided',
      );
    }
  }

  /// Creates a migration manager from storage instances and configurations.
  ///
  /// This is a convenience factory that creates the underlying
  /// [MigrationRunner] instances.
  ///
  /// - [dataStorage]: Storage for application data.
  /// - [dataConfig]: Migration configuration for data.
  /// - [userStorage]: Storage for user/auth data.
  /// - [userConfig]: Migration configuration for users.
  factory MigrationManager.fromStorage({
    Storage<D>? dataStorage,
    MigrationConfig? dataConfig,
    Storage<U>? userStorage,
    MigrationConfig? userConfig,
    EntiDBLogger? logger,
  }) {
    MigrationRunner<D>? dataRunner;
    MigrationRunner<U>? userRunner;

    if (dataStorage != null && dataConfig != null) {
      dataRunner = MigrationRunner<D>(storage: dataStorage, config: dataConfig);
    }

    if (userStorage != null && userConfig != null) {
      userRunner = MigrationRunner<U>(storage: userStorage, config: userConfig);
    }

    return MigrationManager(
      dataRunner: dataRunner,
      userRunner: userRunner,
      logger: logger,
    );
  }

  /// The data migration runner, if configured.
  MigrationRunner<D>? get dataRunner => _dataRunner;

  /// The user migration runner, if configured.
  MigrationRunner<U>? get userRunner => _userRunner;

  /// Whether the manager has been initialized.
  bool get isInitialized => _initialized;

  /// Initializes both migration runners.
  ///
  /// This loads the current schema versions and runs auto-migrations
  /// if configured.
  ///
  /// Throws [MigrationException] if initialization fails.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _logger.info(
        jsonEncode({
          'event': 'migration_manager_init',
          'hasDataRunner': _dataRunner != null,
          'hasUserRunner': _userRunner != null,
        }),
      );

      // Initialize user runner first (auth data takes priority)
      final userRunner = _userRunner;
      if (userRunner != null) {
        await userRunner.initialize();
      }

      // Then initialize data runner
      final dataRunner = _dataRunner;
      if (dataRunner != null) {
        await dataRunner.initialize();
      }

      _initialized = true;

      _logger.info(jsonEncode({'event': 'migration_manager_init_complete'}));
    } catch (e, stack) {
      _logger.error(
        jsonEncode({
          'event': 'migration_manager_init_failed',
          'error': e.toString(),
        }),
      );
      throw MigrationException(
        'Failed to initialize migration manager: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Gets the current migration status for both runners.
  Future<MigrationStatus> getMigrationStatus() async {
    final dataRunner = _dataRunner;
    final userRunner = _userRunner;

    final dataNeedsMigration =
        dataRunner != null && await dataRunner.needsMigration();
    final userNeedsMigration =
        userRunner != null && await userRunner.needsMigration();

    return MigrationStatus(
      dataCurrentVersion: dataRunner?.currentVersion,
      dataTargetVersion: dataRunner?.targetVersion,
      dataNeedsMigration: dataNeedsMigration,
      userCurrentVersion: userRunner?.currentVersion,
      userTargetVersion: userRunner?.targetVersion,
      userNeedsMigration: userNeedsMigration,
    );
  }

  /// Checks if any migration is needed.
  Future<bool> needsMigration() async {
    final status = await getMigrationStatus();
    return status.dataNeedsMigration || status.userNeedsMigration;
  }

  /// Performs all pending migrations.
  ///
  /// User migrations are performed first, followed by data migrations.
  ///
  /// Returns a [MigrationResult] with the outcome of both migrations.
  ///
  /// Throws [MigrationException] if any migration fails.
  Future<MigrationResult> migrateAll() async {
    _logger.info(jsonEncode({'event': 'migrate_all_start'}));

    MigrationLog? userLog;
    MigrationLog? dataLog;

    // Migrate users first
    final userRunner = _userRunner;
    if (userRunner != null && await userRunner.needsMigration()) {
      userLog = await userRunner.migrate();
    }

    // Then migrate data
    final dataRunner = _dataRunner;
    if (dataRunner != null && await dataRunner.needsMigration()) {
      dataLog = await dataRunner.migrate();
    }

    _logger.info(jsonEncode({'event': 'migrate_all_complete'}));

    return MigrationResult(dataLog: dataLog, userLog: userLog);
  }

  /// Performs only data migrations.
  ///
  /// Returns the migration log, or `null` if no data runner is configured.
  Future<MigrationLog?> migrateData() async {
    final dataRunner = _dataRunner;
    if (dataRunner == null) return null;
    if (!await dataRunner.needsMigration()) return null;
    return await dataRunner.migrate();
  }

  /// Performs only user migrations.
  ///
  /// Returns the migration log, or `null` if no user runner is configured.
  Future<MigrationLog?> migrateUsers() async {
    final userRunner = _userRunner;
    if (userRunner == null) return null;
    if (!await userRunner.needsMigration()) return null;
    return await userRunner.migrate();
  }

  /// Gets the combined migration history from both runners.
  Map<String, List<MigrationLog>> getMigrationHistories() {
    final dataRunner = _dataRunner;
    final userRunner = _userRunner;
    return {
      if (dataRunner != null) 'data': dataRunner.history,
      if (userRunner != null) 'user': userRunner.history,
    };
  }

  /// Exports version data from both runners for external persistence.
  Map<String, dynamic> exportVersionData() {
    final dataRunner = _dataRunner;
    final userRunner = _userRunner;
    return {
      if (dataRunner != null) 'data': dataRunner.exportVersionData(),
      if (userRunner != null) 'user': userRunner.exportVersionData(),
    };
  }

  /// Imports version data into both runners.
  void importVersionData(Map<String, dynamic> data) {
    final dataRunner = _dataRunner;
    final userRunner = _userRunner;
    if (data.containsKey('data') && dataRunner != null) {
      dataRunner.importVersionData(data['data'] as Map<String, dynamic>);
    }
    if (data.containsKey('user') && userRunner != null) {
      userRunner.importVersionData(data['user'] as Map<String, dynamic>);
    }
  }

  /// Disposes resources used by both runners.
  Future<void> dispose() async {
    final dataRunner = _dataRunner;
    final userRunner = _userRunner;
    if (dataRunner != null) {
      await dataRunner.dispose();
    }
    if (userRunner != null) {
      await userRunner.dispose();
    }
  }
}

/// Status of migrations for both data and user storage.
final class MigrationStatus {
  /// Current data schema version.
  final String? dataCurrentVersion;

  /// Target data schema version.
  final String? dataTargetVersion;

  /// Whether data migration is needed.
  final bool dataNeedsMigration;

  /// Current user schema version.
  final String? userCurrentVersion;

  /// Target user schema version.
  final String? userTargetVersion;

  /// Whether user migration is needed.
  final bool userNeedsMigration;

  /// Creates a migration status.
  const MigrationStatus({
    this.dataCurrentVersion,
    this.dataTargetVersion,
    required this.dataNeedsMigration,
    this.userCurrentVersion,
    this.userTargetVersion,
    required this.userNeedsMigration,
  });

  /// Whether any migration is needed.
  bool get needsMigration => dataNeedsMigration || userNeedsMigration;

  @override
  String toString() {
    return 'MigrationStatus('
        'data: $dataCurrentVersion → $dataTargetVersion (needs: $dataNeedsMigration), '
        'user: $userCurrentVersion → $userTargetVersion (needs: $userNeedsMigration))';
  }
}

/// Result of a migration operation.
final class MigrationResult {
  /// Migration log for data storage.
  final MigrationLog? dataLog;

  /// Migration log for user storage.
  final MigrationLog? userLog;

  /// Creates a migration result.
  const MigrationResult({this.dataLog, this.userLog});

  /// Whether any migration was performed.
  bool get anyMigrated => dataLog != null || userLog != null;

  /// Whether all migrations were successful.
  bool get allSuccessful =>
      (dataLog?.isSuccess ?? true) && (userLog?.isSuccess ?? true);

  /// Total number of entities affected.
  int get totalEntitiesAffected =>
      (dataLog?.entitiesAffected ?? 0) + (userLog?.entitiesAffected ?? 0);

  @override
  String toString() {
    final parts = <String>[];
    if (dataLog != null) parts.add('data: ${dataLog!.outcome.name}');
    if (userLog != null) parts.add('user: ${userLog!.outcome.name}');
    return 'MigrationResult(${parts.join(', ')})';
  }
}
