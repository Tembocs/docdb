/// DocDB Migration - User Migration
///
/// Provides migration support for user/authentication data storage.
/// This is a convenience wrapper around [MigrationRunner] for user entities.
library;

import '../entity/entity.dart';
import '../storage/storage.dart';
import 'migration_config.dart';
import 'migration_runner.dart';

export 'migration_runner.dart' show MigrationRunner;

/// Migration runner specialized for user/authentication entities.
///
/// This is a convenience type alias for [MigrationRunner] when working
/// with user and authentication data (as opposed to application data).
///
/// User data often requires special handling due to security constraints,
/// such as re-hashing passwords when the hashing algorithm changes.
///
/// ## Usage
///
/// ```dart
/// final userMigration = UserMigration<User>(
///   storage: userStorage,
///   config: MigrationConfig(
///     currentVersion: '2.0.0',
///     migrations: [
///       AddRolesFieldMigration(),
///       UpdatePasswordHashMigration(),
///     ],
///   ),
/// );
///
/// await userMigration.initialize();
///
/// if (await userMigration.needsMigration()) {
///   await userMigration.migrate();
/// }
/// ```
///
/// ## Security Considerations
///
/// When migrating user data:
///
/// 1. **Password Changes**: If migrating password hashes, users may need
///    to reset their passwords.
/// 2. **Role Changes**: Audit any changes to user roles carefully.
/// 3. **Token Invalidation**: Consider invalidating existing auth tokens
///    after migration.
///
/// ## See Also
///
/// - [MigrationRunner]: The core migration execution engine.
/// - [DataMigration]: Migration runner for application data.
/// - [MigrationManager]: Coordinated migration for both data and user storage.
typedef UserMigration<T extends Entity> = MigrationRunner<T>;

/// Creates a user migration runner with the given storage and configuration.
///
/// This factory function provides a convenient way to create a
/// [UserMigration] instance with explicit type parameters.
///
/// - [storage]: The user storage to migrate.
/// - [config]: Migration configuration.
///
/// Returns a configured [UserMigration] instance.
UserMigration<T> createUserMigration<T extends Entity>({
  required Storage<T> storage,
  required MigrationConfig config,
}) {
  return MigrationRunner<T>(storage: storage, config: config);
}
