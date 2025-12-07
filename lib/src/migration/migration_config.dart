/// EntiDB Migration - Migration Configuration
///
/// Provides configuration options for the migration system.
library;

import 'migration_strategy.dart';

/// Configuration for the migration system.
///
/// Defines the current schema version, available migrations, and behavior
/// options for the migration process.
///
/// ## Example
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
final class MigrationConfig {
  /// The current (target) schema version.
  ///
  /// Migrations will be applied to reach this version from the
  /// stored version in the database.
  final String currentVersion;

  /// List of available migration strategies.
  ///
  /// Migrations are applied in order based on their version ranges.
  /// The system automatically determines the correct path from the
  /// current stored version to [currentVersion].
  final List<MigrationStrategy> migrations;

  /// Whether to automatically run migrations when storage is opened.
  ///
  /// If `true`, the migration manager will check for pending migrations
  /// and apply them automatically during initialization.
  ///
  /// If `false`, migrations must be triggered manually by calling
  /// [MigrationRunner.migrate].
  ///
  /// Default: `true`
  final bool autoMigrate;

  /// Whether to create a backup before applying migrations.
  ///
  /// If `true`, a snapshot of the current data will be saved before
  /// any migration steps are applied. This enables rollback in case
  /// of migration failure.
  ///
  /// Default: `true`
  final bool createBackupBeforeMigration;

  /// Maximum number of migration log entries to retain.
  ///
  /// Older entries are removed when this limit is exceeded.
  /// Set to `null` to retain all entries.
  ///
  /// Default: `100`
  final int? maxLogEntries;

  /// Whether to validate data after each migration step.
  ///
  /// If `true`, a validation pass is run after each step to ensure
  /// the migrated data is consistent. This adds overhead but provides
  /// early failure detection.
  ///
  /// Default: `false`
  final bool validateAfterEachStep;

  /// Creates a migration configuration.
  ///
  /// - [currentVersion]: The target schema version.
  /// - [migrations]: List of available migration strategies.
  /// - [autoMigrate]: Whether to auto-migrate on startup.
  /// - [createBackupBeforeMigration]: Whether to backup before migrating.
  /// - [maxLogEntries]: Maximum log entries to retain.
  /// - [validateAfterEachStep]: Whether to validate after each step.
  const MigrationConfig({
    required this.currentVersion,
    this.migrations = const [],
    this.autoMigrate = true,
    this.createBackupBeforeMigration = true,
    this.maxLogEntries = 100,
    this.validateAfterEachStep = false,
  });

  /// Creates a configuration for development/testing.
  ///
  /// Auto-migration and backups are disabled, and validation is enabled
  /// to catch issues early.
  factory MigrationConfig.development({
    required String currentVersion,
    List<MigrationStrategy> migrations = const [],
  }) {
    return MigrationConfig(
      currentVersion: currentVersion,
      migrations: migrations,
      autoMigrate: false,
      createBackupBeforeMigration: false,
      validateAfterEachStep: true,
    );
  }

  /// Creates a configuration for production.
  ///
  /// Auto-migration and backups are enabled, validation is disabled
  /// for performance.
  factory MigrationConfig.production({
    required String currentVersion,
    required List<MigrationStrategy> migrations,
  }) {
    return MigrationConfig(
      currentVersion: currentVersion,
      migrations: migrations,
      autoMigrate: true,
      createBackupBeforeMigration: true,
      validateAfterEachStep: false,
    );
  }

  /// Returns a copy of this configuration with the specified changes.
  MigrationConfig copyWith({
    String? currentVersion,
    List<MigrationStrategy>? migrations,
    bool? autoMigrate,
    bool? createBackupBeforeMigration,
    int? maxLogEntries,
    bool? validateAfterEachStep,
  }) {
    return MigrationConfig(
      currentVersion: currentVersion ?? this.currentVersion,
      migrations: migrations ?? this.migrations,
      autoMigrate: autoMigrate ?? this.autoMigrate,
      createBackupBeforeMigration:
          createBackupBeforeMigration ?? this.createBackupBeforeMigration,
      maxLogEntries: maxLogEntries ?? this.maxLogEntries,
      validateAfterEachStep:
          validateAfterEachStep ?? this.validateAfterEachStep,
    );
  }
}
