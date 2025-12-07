/// EntiDB Migration - Data Migration
///
/// Provides migration support for application data storage.
/// This is a convenience wrapper around [MigrationRunner] for data entities.
library;

import '../entity/entity.dart';
import '../storage/storage.dart';
import 'migration_config.dart';
import 'migration_runner.dart';

export 'migration_runner.dart' show MigrationRunner;

/// Migration runner specialized for application data entities.
///
/// This is a convenience type alias for [MigrationRunner] when working
/// with application data (as opposed to user/authentication data).
///
/// ## Usage
///
/// ```dart
/// final dataMigration = DataMigration<Product>(
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
/// await dataMigration.initialize();
///
/// if (await dataMigration.needsMigration()) {
///   await dataMigration.migrate();
/// }
/// ```
///
/// ## See Also
///
/// - [MigrationRunner]: The core migration execution engine.
/// - [UserMigration]: Migration runner for user/auth data.
/// - [MigrationManager]: Coordinated migration for both data and user storage.
typedef DataMigration<T extends Entity> = MigrationRunner<T>;

/// Creates a data migration runner with the given storage and configuration.
///
/// This factory function provides a convenient way to create a
/// [DataMigration] instance with explicit type parameters.
///
/// - [storage]: The data storage to migrate.
/// - [config]: Migration configuration.
///
/// Returns a configured [DataMigration] instance.
DataMigration<T> createDataMigration<T extends Entity>({
  required Storage<T> storage,
  required MigrationConfig config,
}) {
  return MigrationRunner<T>(storage: storage, config: config);
}
