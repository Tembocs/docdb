/// EntiDB Backup - Backup Result
///
/// Represents the outcome of backup and restore operations with
/// detailed status, timing, and error information.
library;

import 'backup_metadata.dart';

/// Represents the result of a backup or restore operation.
///
/// Provides comprehensive information about operation outcomes including:
/// - Success/failure status
/// - Operation timing (start, end, duration)
/// - Metadata about the backup involved
/// - Error details when applicable
/// - Warnings and informational messages
///
/// ## Creating Results
///
/// ```dart
/// // Successful backup
/// final result = BackupResult.success(
///   operation: BackupOperation.create,
///   metadata: backupMetadata,
///   message: 'Backup completed successfully',
/// );
///
/// // Failed restore
/// final result = BackupResult.failure(
///   operation: BackupOperation.restore,
///   error: 'File not found: backup.snap',
///   filePath: '/backups/backup.snap',
/// );
/// ```
///
/// ## Checking Results
///
/// ```dart
/// final result = await backupService.createBackup();
///
/// if (result.isSuccess) {
///   print('Backup saved to: ${result.metadata?.filePath}');
///   print('Duration: ${result.duration.inSeconds}s');
/// } else {
///   print('Backup failed: ${result.error}');
///   // Handle retry or notify user
/// }
/// ```
final class BackupResult {
  /// The type of backup operation that was performed.
  final BackupOperation operation;

  /// Whether the operation completed successfully.
  final bool isSuccess;

  /// Metadata about the backup (available on success).
  final BackupMetadata? metadata;

  /// File path involved in the operation.
  final String? filePath;

  /// Timestamp when the operation started.
  final DateTime startedAt;

  /// Timestamp when the operation completed.
  final DateTime completedAt;

  /// Human-readable message about the operation.
  final String? message;

  /// Error message if the operation failed.
  final String? error;

  /// Stack trace if the operation failed with an exception.
  final String? stackTrace;

  /// Non-fatal warnings encountered during the operation.
  final List<String> warnings;

  /// Number of entities affected by the operation.
  final int entitiesAffected;

  /// Number of bytes read or written.
  final int bytesProcessed;

  /// Creates a new backup result.
  const BackupResult({
    required this.operation,
    required this.isSuccess,
    this.metadata,
    this.filePath,
    required this.startedAt,
    required this.completedAt,
    this.message,
    this.error,
    this.stackTrace,
    this.warnings = const [],
    this.entitiesAffected = 0,
    this.bytesProcessed = 0,
  });

  /// Creates a successful backup result.
  factory BackupResult.success({
    required BackupOperation operation,
    BackupMetadata? metadata,
    String? filePath,
    String? message,
    List<String> warnings = const [],
    int entitiesAffected = 0,
    int bytesProcessed = 0,
    DateTime? startedAt,
  }) {
    final now = DateTime.now();
    return BackupResult(
      operation: operation,
      isSuccess: true,
      metadata: metadata,
      filePath: filePath ?? metadata?.filePath,
      startedAt: startedAt ?? now,
      completedAt: now,
      message: message,
      warnings: warnings,
      entitiesAffected: entitiesAffected,
      bytesProcessed: bytesProcessed,
    );
  }

  /// Creates a failed backup result.
  factory BackupResult.failure({
    required BackupOperation operation,
    required String error,
    String? filePath,
    String? stackTrace,
    List<String> warnings = const [],
    int entitiesAffected = 0,
    int bytesProcessed = 0,
    DateTime? startedAt,
  }) {
    final now = DateTime.now();
    return BackupResult(
      operation: operation,
      isSuccess: false,
      filePath: filePath,
      startedAt: startedAt ?? now,
      completedAt: now,
      error: error,
      stackTrace: stackTrace,
      warnings: warnings,
      entitiesAffected: entitiesAffected,
      bytesProcessed: bytesProcessed,
    );
  }

  /// Whether the operation failed.
  bool get isFailure => !isSuccess;

  /// Duration of the operation.
  Duration get duration => completedAt.difference(startedAt);

  /// Duration in milliseconds.
  int get durationMs => duration.inMilliseconds;

  /// Returns a human-readable summary of the result.
  String get summary {
    final buffer = StringBuffer();
    buffer.write('${operation.displayName}: ');

    if (isSuccess) {
      buffer.write('SUCCESS');
      if (entitiesAffected > 0) {
        buffer.write(' ($entitiesAffected entities');
        if (bytesProcessed > 0) {
          buffer.write(', ${_humanReadableBytes(bytesProcessed)}');
        }
        buffer.write(')');
      }
    } else {
      buffer.write('FAILED - $error');
    }

    buffer.write(' [${duration.inMilliseconds}ms]');
    return buffer.toString();
  }

  /// Formats bytes to human-readable string.
  static String _humanReadableBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Converts this result to a map for logging or storage.
  Map<String, dynamic> toMap() => {
    'operation': operation.name,
    'isSuccess': isSuccess,
    if (metadata != null) 'metadata': metadata!.toMap(),
    if (filePath != null) 'filePath': filePath,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'durationMs': durationMs,
    if (message != null) 'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (warnings.isNotEmpty) 'warnings': warnings,
    'entitiesAffected': entitiesAffected,
    'bytesProcessed': bytesProcessed,
  };

  /// Creates a result from a map.
  factory BackupResult.fromMap(Map<String, dynamic> map) {
    return BackupResult(
      operation: BackupOperation.values.firstWhere(
        (o) => o.name == map['operation'],
        orElse: () => BackupOperation.create,
      ),
      isSuccess: map['isSuccess'] as bool,
      metadata: map['metadata'] != null
          ? BackupMetadata.fromMap('', map['metadata'] as Map<String, dynamic>)
          : null,
      filePath: map['filePath'] as String?,
      startedAt: DateTime.parse(map['startedAt'] as String),
      completedAt: DateTime.parse(map['completedAt'] as String),
      message: map['message'] as String?,
      error: map['error'] as String?,
      stackTrace: map['stackTrace'] as String?,
      warnings: (map['warnings'] as List<dynamic>?)?.cast<String>() ?? const [],
      entitiesAffected: map['entitiesAffected'] as int? ?? 0,
      bytesProcessed: map['bytesProcessed'] as int? ?? 0,
    );
  }

  @override
  String toString() => summary;
}

/// Types of backup operations.
enum BackupOperation {
  /// Creating a new backup.
  create,

  /// Restoring data from a backup.
  restore,

  /// Verifying backup integrity.
  verify,

  /// Deleting a backup.
  delete,

  /// Listing available backups.
  list,

  /// Exporting a backup to external format.
  export,

  /// Importing a backup from external format.
  import_;

  /// Human-readable name for the operation.
  String get displayName {
    return switch (this) {
      create => 'Backup Create',
      restore => 'Backup Restore',
      verify => 'Backup Verify',
      delete => 'Backup Delete',
      list => 'Backup List',
      export => 'Backup Export',
      import_ => 'Backup Import',
    };
  }
}
