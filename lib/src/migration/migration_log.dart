/// DocDB Migration - Migration Log
///
/// Provides logging and audit trail for migration operations.
library;

/// The outcome of a migration step.
enum MigrationOutcome {
  /// Migration completed successfully.
  success,

  /// Migration failed with an error.
  failed,

  /// Migration was skipped (e.g., already at target version).
  skipped,

  /// Migration was rolled back after failure.
  rolledBack,
}

/// A record of a single migration execution.
///
/// Each log entry captures the details of a migration step including
/// the versions involved, timing, outcome, and any error information.
///
/// ## Example
///
/// ```dart
/// final log = MigrationLog(
///   timestamp: DateTime.now(),
///   fromVersion: '1.0.0',
///   toVersion: '1.1.0',
///   outcome: MigrationOutcome.success,
///   durationMs: 1250,
/// );
///
/// // Serialize for storage
/// final json = log.toMap();
///
/// // Deserialize
/// final restored = MigrationLog.fromMap(json);
/// ```
final class MigrationLog {
  /// When the migration was executed.
  final DateTime timestamp;

  /// The schema version before migration.
  final String fromVersion;

  /// The schema version after migration.
  final String toVersion;

  /// Whether this was an upgrade (true) or downgrade (false).
  final bool isUpgrade;

  /// The outcome of the migration.
  final MigrationOutcome outcome;

  /// Duration of the migration in milliseconds.
  final int? durationMs;

  /// Number of entities affected by the migration.
  final int? entitiesAffected;

  /// Error message if the migration failed.
  final String? error;

  /// Stack trace if the migration failed.
  final String? stackTrace;

  /// Additional metadata about the migration.
  final Map<String, dynamic>? metadata;

  /// Creates a new migration log entry.
  const MigrationLog({
    required this.timestamp,
    required this.fromVersion,
    required this.toVersion,
    required this.outcome,
    this.isUpgrade = true,
    this.durationMs,
    this.entitiesAffected,
    this.error,
    this.stackTrace,
    this.metadata,
  });

  /// Creates a log entry for a successful migration.
  factory MigrationLog.success({
    required String fromVersion,
    required String toVersion,
    required int durationMs,
    int? entitiesAffected,
    bool isUpgrade = true,
    Map<String, dynamic>? metadata,
  }) {
    return MigrationLog(
      timestamp: DateTime.now(),
      fromVersion: fromVersion,
      toVersion: toVersion,
      outcome: MigrationOutcome.success,
      isUpgrade: isUpgrade,
      durationMs: durationMs,
      entitiesAffected: entitiesAffected,
      metadata: metadata,
    );
  }

  /// Creates a log entry for a failed migration.
  factory MigrationLog.failed({
    required String fromVersion,
    required String toVersion,
    required String error,
    String? stackTrace,
    int? durationMs,
    bool isUpgrade = true,
    Map<String, dynamic>? metadata,
  }) {
    return MigrationLog(
      timestamp: DateTime.now(),
      fromVersion: fromVersion,
      toVersion: toVersion,
      outcome: MigrationOutcome.failed,
      isUpgrade: isUpgrade,
      durationMs: durationMs,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );
  }

  /// Creates a log entry for a skipped migration.
  factory MigrationLog.skipped({
    required String fromVersion,
    required String toVersion,
    String? reason,
    bool isUpgrade = true,
  }) {
    return MigrationLog(
      timestamp: DateTime.now(),
      fromVersion: fromVersion,
      toVersion: toVersion,
      outcome: MigrationOutcome.skipped,
      isUpgrade: isUpgrade,
      metadata: reason != null ? {'reason': reason} : null,
    );
  }

  /// Whether the migration was successful.
  bool get isSuccess => outcome == MigrationOutcome.success;

  /// Whether the migration failed.
  bool get isFailed => outcome == MigrationOutcome.failed;

  /// Serializes this log entry to a map.
  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'fromVersion': fromVersion,
      'toVersion': toVersion,
      'isUpgrade': isUpgrade,
      'outcome': outcome.name,
      if (durationMs != null) 'durationMs': durationMs,
      if (entitiesAffected != null) 'entitiesAffected': entitiesAffected,
      if (error != null) 'error': error,
      if (stackTrace != null) 'stackTrace': stackTrace,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// Deserializes a log entry from a map.
  factory MigrationLog.fromMap(Map<String, dynamic> map) {
    return MigrationLog(
      timestamp: DateTime.parse(map['timestamp'] as String),
      fromVersion: map['fromVersion'] as String,
      toVersion: map['toVersion'] as String,
      isUpgrade: map['isUpgrade'] as bool? ?? true,
      outcome: MigrationOutcome.values.firstWhere(
        (e) => e.name == map['outcome'],
        orElse: () => MigrationOutcome.failed,
      ),
      durationMs: map['durationMs'] as int?,
      entitiesAffected: map['entitiesAffected'] as int?,
      error: map['error'] as String?,
      stackTrace: map['stackTrace'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    final buffer = StringBuffer('MigrationLog(');
    buffer.write('$fromVersion → $toVersion, ');
    buffer.write('outcome: ${outcome.name}');
    if (durationMs != null) buffer.write(', ${durationMs}ms');
    if (entitiesAffected != null) buffer.write(', $entitiesAffected entities');
    if (error != null) buffer.write(', error: $error');
    buffer.write(')');
    return buffer.toString();
  }
}
