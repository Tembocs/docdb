/// DocDB Migration - Migration Strategy Interface
///
/// Defines the contract for migration transformations between schema versions.
/// Strategies implement bidirectional transformations (upgrade and downgrade).
library;

/// Abstract interface for migration strategies.
///
/// Each migration strategy defines how to transform entity data between
/// two adjacent schema versions. Strategies must be reversible - if `up`
/// transforms data from version N to N+1, then `down` must transform it
/// back from N+1 to N.
///
/// ## Implementation Guidelines
///
/// 1. **Idempotency**: Migrations should be idempotent when possible.
/// 2. **Data Preservation**: Never discard data that might be needed for rollback.
/// 3. **Error Handling**: Throw [MigrationException] for recoverable errors.
/// 4. **Logging**: Log significant transformations for debugging.
///
/// ## Example
///
/// ```dart
/// class AddEmailFieldMigration implements MigrationStrategy {
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
///   Future<Map<String, Map<String, dynamic>>> up(
///     Map<String, Map<String, dynamic>> entities,
///   ) async {
///     return entities.map((id, data) => MapEntry(
///       id,
///       {...data, 'email': data['email'] ?? 'unknown@example.com'},
///     ));
///   }
///
///   @override
///   Future<Map<String, Map<String, dynamic>>> down(
///     Map<String, Map<String, dynamic>> entities,
///   ) async {
///     return entities.map((id, data) {
///       final newData = Map<String, dynamic>.from(data);
///       newData.remove('email');
///       return MapEntry(id, newData);
///     });
///   }
/// }
/// ```
abstract interface class MigrationStrategy {
  /// Human-readable description of what this migration does.
  ///
  /// Used for logging and audit trails.
  String get description;

  /// The source version this migration transforms from.
  ///
  /// Format should be semantic versioning (e.g., '1.0.0').
  String get fromVersion;

  /// The target version this migration transforms to.
  ///
  /// Format should be semantic versioning (e.g., '1.1.0').
  String get toVersion;

  /// Transforms entity data from [fromVersion] to [toVersion].
  ///
  /// Takes a map of entity ID to entity data representing all entities
  /// in the storage that need migration. Returns the transformed map.
  ///
  /// - [entities]: Map of entity ID to entity data.
  ///
  /// Returns the transformed entity map.
  ///
  /// Throws [MigrationException] if the transformation fails.
  Future<Map<String, Map<String, dynamic>>> up(
    Map<String, Map<String, dynamic>> entities,
  );

  /// Transforms entity data from [toVersion] back to [fromVersion].
  ///
  /// This is the reverse of [up]. Takes entity data in the newer format
  /// and transforms it back to the older format.
  ///
  /// - [entities]: Map of entity ID to entity data.
  ///
  /// Returns the transformed entity map.
  ///
  /// Throws [MigrationException] if the transformation fails.
  Future<Map<String, Map<String, dynamic>>> down(
    Map<String, Map<String, dynamic>> entities,
  );
}

/// A migration strategy that transforms entities individually.
///
/// This is a convenience base class for migrations that only need to
/// transform one entity at a time, without considering relationships
/// between entities.
///
/// ## Example
///
/// ```dart
/// class RenameFieldMigration extends SingleEntityMigrationStrategy {
///   @override
///   String get description => 'Rename "userName" to "username"';
///
///   @override
///   String get fromVersion => '1.0.0';
///
///   @override
///   String get toVersion => '1.1.0';
///
///   @override
///   Map<String, dynamic> transformUp(String id, Map<String, dynamic> data) {
///     return {...data, 'username': data.remove('userName')};
///   }
///
///   @override
///   Map<String, dynamic> transformDown(String id, Map<String, dynamic> data) {
///     return {...data, 'userName': data.remove('username')};
///   }
/// }
/// ```
abstract class SingleEntityMigrationStrategy implements MigrationStrategy {
  /// Creates a single entity migration strategy.
  const SingleEntityMigrationStrategy();

  /// Transforms a single entity's data during upgrade.
  ///
  /// - [id]: The entity's unique identifier.
  /// - [data]: The entity's current data.
  ///
  /// Returns the transformed data.
  Map<String, dynamic> transformUp(String id, Map<String, dynamic> data);

  /// Transforms a single entity's data during downgrade.
  ///
  /// - [id]: The entity's unique identifier.
  /// - [data]: The entity's current data.
  ///
  /// Returns the transformed data.
  Map<String, dynamic> transformDown(String id, Map<String, dynamic> data);

  @override
  Future<Map<String, Map<String, dynamic>>> up(
    Map<String, Map<String, dynamic>> entities,
  ) async {
    return entities.map((id, data) => MapEntry(id, transformUp(id, data)));
  }

  @override
  Future<Map<String, Map<String, dynamic>>> down(
    Map<String, Map<String, dynamic>> entities,
  ) async {
    return entities.map((id, data) => MapEntry(id, transformDown(id, data)));
  }
}

/// A no-op migration strategy that passes data through unchanged.
///
/// Useful for version bumps that don't require data transformation,
/// such as metadata-only changes or code-only updates.
final class NoOpMigrationStrategy implements MigrationStrategy {
  @override
  final String description;

  @override
  final String fromVersion;

  @override
  final String toVersion;

  /// Creates a no-op migration strategy.
  ///
  /// - [fromVersion]: The source version.
  /// - [toVersion]: The target version.
  /// - [description]: Optional description (defaults to 'No data changes').
  const NoOpMigrationStrategy({
    required this.fromVersion,
    required this.toVersion,
    this.description = 'No data changes required',
  });

  @override
  Future<Map<String, Map<String, dynamic>>> up(
    Map<String, Map<String, dynamic>> entities,
  ) async => entities;

  @override
  Future<Map<String, Map<String, dynamic>>> down(
    Map<String, Map<String, dynamic>> entities,
  ) async => entities;
}
