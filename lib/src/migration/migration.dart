/// DocDB Migration Module
///
/// Provides schema migration support for entity storage, enabling
/// seamless upgrades and downgrades between schema versions.
///
/// ## Overview
///
/// The migration module handles the transformation of entity data as
/// schema definitions evolve over time. It supports:
///
/// - **Bidirectional Migrations**: Both upgrade and downgrade paths
/// - **Automatic Execution**: Optional auto-migration on storage initialization
/// - **Backup & Rollback**: Automatic backup before migration with rollback on failure
/// - **Audit Trail**: Complete migration history logging
/// - **Separate Data/User Handling**: Independent migrations for data and auth storage
///
/// ## Quick Start
///
/// ### 1. Define Migration Strategies
///
/// ```dart
/// import 'package:docdb/src/migration/migration.dart';
///
/// class AddEmailFieldMigration extends SingleEntityMigrationStrategy {
///   @override
///   String get description => 'Add email field with default value';
///
///   @override
///   String get fromVersion => '1.0.0';
///
///   @override
///   String get toVersion => '1.1.0';
///
///   @override
///   Map<String, dynamic> transformUp(String id, Map<String, dynamic> data) {
///     return {...data, 'email': data['email'] ?? 'unknown@example.com'};
///   }
///
///   @override
///   Map<String, dynamic> transformDown(String id, Map<String, dynamic> data) {
///     final newData = Map<String, dynamic>.from(data);
///     newData.remove('email');
///     return newData;
///   }
/// }
/// ```
///
/// ### 2. Configure Migrations
///
/// ```dart
/// final config = MigrationConfig(
///   currentVersion: '2.0.0',
///   migrations: [
///     AddEmailFieldMigration(),
///     RenameFieldMigration(),
///   ],
///   autoMigrate: true,
///   createBackupBeforeMigration: true,
/// );
/// ```
///
/// ### 3. Run Migrations
///
/// ```dart
/// // Using MigrationRunner directly
/// final runner = MigrationRunner<Product>(
///   storage: productStorage,
///   config: config,
/// );
///
/// await runner.initialize();
///
/// if (await runner.needsMigration()) {
///   final result = await runner.migrate();
///   print('Migrated ${result.entitiesAffected} entities');
/// }
///
/// // Or using MigrationManager for both data and user storage
/// final manager = MigrationManager.fromStorage(
///   dataStorage: productStorage,
///   dataConfig: dataConfig,
///   userStorage: userStorage,
///   userConfig: userConfig,
/// );
///
/// await manager.initialize();
/// final result = await manager.migrateAll();
/// ```
///
/// ## Core Components
///
/// | Component | Purpose |
/// |-----------|---------|
/// | [MigrationStrategy] | Interface for migration transformations |
/// | [SingleEntityMigrationStrategy] | Base class for per-entity migrations |
/// | [NoOpMigrationStrategy] | Pass-through migration for version bumps |
/// | [MigrationConfig] | Configuration for migration behavior |
/// | [MigrationRunner] | Core migration execution engine |
/// | [MigrationManager] | Coordinates data and user migrations |
/// | [MigrationLog] | Audit trail entry for migration execution |
/// | [MigrationStep] | Single step in a migration path |
///
/// ## Migration Strategies
///
/// Strategies define how entity data is transformed:
///
/// ```dart
/// // Simple field transformation
/// class RenameFieldMigration extends SingleEntityMigrationStrategy {
///   @override
///   String get fromVersion => '1.1.0';
///   @override
///   String get toVersion => '1.2.0';
///   @override
///   String get description => 'Rename userName to username';
///
///   @override
///   Map<String, dynamic> transformUp(String id, Map<String, dynamic> data) {
///     final result = Map<String, dynamic>.from(data);
///     result['username'] = result.remove('userName');
///     return result;
///   }
///
///   @override
///   Map<String, dynamic> transformDown(String id, Map<String, dynamic> data) {
///     final result = Map<String, dynamic>.from(data);
///     result['userName'] = result.remove('username');
///     return result;
///   }
/// }
///
/// // Batch transformation (access to all entities)
/// class ComputeStatsMigration implements MigrationStrategy {
///   @override
///   String get fromVersion => '1.2.0';
///   @override
///   String get toVersion => '2.0.0';
///   @override
///   String get description => 'Compute aggregate statistics';
///
///   @override
///   Future<Map<String, Map<String, dynamic>>> up(
///     Map<String, Map<String, dynamic>> entities,
///   ) async {
///     final totalCount = entities.length;
///     return entities.map((id, data) => MapEntry(id, {
///       ...data,
///       'totalPeers': totalCount - 1,
///     }));
///   }
///
///   @override
///   Future<Map<String, Map<String, dynamic>>> down(
///     Map<String, Map<String, dynamic>> entities,
///   ) async {
///     return entities.map((id, data) {
///       final result = Map<String, dynamic>.from(data);
///       result.remove('totalPeers');
///       return MapEntry(id, result);
///     });
///   }
/// }
/// ```
///
/// ## Version Data Tracking
///
/// The module tracks schema versions using [SchemaVersion] and
/// [VersionedData] entities:
///
/// ```dart
/// // Current version stored in storage metadata
/// final versionData = await storage.get('__schema_version__');
/// final schema = SchemaVersion.fromMap('__schema_version__', versionData!);
/// print('Current version: ${schema.version}');
/// ```
///
/// ## Error Handling
///
/// All migration errors are wrapped in [MigrationException]:
///
/// ```dart
/// try {
///   await runner.migrate();
/// } on MigrationException catch (e) {
///   print('Migration failed: ${e.message}');
///   // Automatic rollback has been attempted if backup was enabled
/// }
/// ```
///
/// ## Best Practices
///
/// 1. **Keep migrations small**: One logical change per migration.
/// 2. **Test both directions**: Always test upgrade and downgrade paths.
/// 3. **Preserve data**: Never delete data that might be needed for rollback.
/// 4. **Use semantic versioning**: Follow semver for version strings.
/// 5. **Enable backups in production**: Set `createBackupBeforeMigration: true`.
/// 6. **Log migrations**: Review migration history for debugging.
library;

export 'data_migration.dart' show DataMigration, createDataMigration;
export 'migration_config.dart' show MigrationConfig;
export 'migration_log.dart' show MigrationLog, MigrationOutcome;
export 'migration_manager.dart'
    show MigrationManager, MigrationResult, MigrationStatus;
export 'migration_runner.dart' show MigrationRunner;
export 'migration_step.dart' show MigrationStep;
export 'migration_strategy.dart'
    show
        MigrationStrategy,
        NoOpMigrationStrategy,
        SingleEntityMigrationStrategy;
export 'user_migration.dart' show UserMigration, createUserMigration;
export 'versioned_data.dart' show SchemaVersion, VersionedData;
