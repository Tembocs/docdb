/// DocDB Migration - Migration Step
///
/// Represents a single step in a migration path between versions.
library;

import 'migration_strategy.dart';

/// Represents a single migration step in a migration path.
///
/// A migration step binds a [MigrationStrategy] to its execution context,
/// including the direction (upgrade vs downgrade) and position in the
/// overall migration sequence.
///
/// ## Example
///
/// ```dart
/// final step = MigrationStep(
///   strategy: AddEmailFieldMigration(),
///   isUpgrade: true,
///   sequenceNumber: 1,
/// );
///
/// // Execute the step
/// final migrated = step.isUpgrade
///     ? await step.strategy.up(entities)
///     : await step.strategy.down(entities);
/// ```
final class MigrationStep {
  /// The migration strategy that performs the actual transformation.
  final MigrationStrategy strategy;

  /// Whether this step is an upgrade (true) or downgrade (false).
  final bool isUpgrade;

  /// The sequence number of this step in the migration path.
  ///
  /// Steps are executed in order of their sequence number.
  final int sequenceNumber;

  /// Creates a new migration step.
  ///
  /// - [strategy]: The strategy that performs the transformation.
  /// - [isUpgrade]: Whether this is an upgrade (true) or downgrade (false).
  /// - [sequenceNumber]: The position in the migration sequence.
  const MigrationStep({
    required this.strategy,
    required this.isUpgrade,
    this.sequenceNumber = 0,
  });

  /// The source version for this step.
  ///
  /// For upgrades, this is the strategy's [fromVersion].
  /// For downgrades, this is the strategy's [toVersion].
  String get sourceVersion =>
      isUpgrade ? strategy.fromVersion : strategy.toVersion;

  /// The target version for this step.
  ///
  /// For upgrades, this is the strategy's [toVersion].
  /// For downgrades, this is the strategy's [fromVersion].
  String get targetVersion =>
      isUpgrade ? strategy.toVersion : strategy.fromVersion;

  /// Human-readable description of the migration.
  String get description => strategy.description;

  /// Executes the migration step.
  ///
  /// Applies the strategy's [up] method for upgrades or [down] method
  /// for downgrades.
  ///
  /// - [entities]: Map of entity ID to entity data to transform.
  ///
  /// Returns the transformed entity map.
  Future<Map<String, Map<String, dynamic>>> execute(
    Map<String, Map<String, dynamic>> entities,
  ) {
    return isUpgrade ? strategy.up(entities) : strategy.down(entities);
  }

  @override
  String toString() {
    final direction = isUpgrade ? 'upgrade' : 'downgrade';
    return 'MigrationStep($direction: $sourceVersion → $targetVersion)';
  }
}
