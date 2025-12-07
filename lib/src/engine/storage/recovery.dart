/// Recovery module for PagedStorage.
///
/// Provides crash recovery integration between PagedStorage and the
/// Write-Ahead Log (WAL) system. Handles redo operations to restore
/// committed transactions after an unclean shutdown.
library;

import 'dart:io';

import '../wal/wal_reader.dart';
import '../wal/wal_record.dart';

/// Configuration for database recovery.
///
/// Specifies how recovery should be performed when the database
/// detects a dirty shutdown (crash or power failure).
class RecoveryConfig {
  /// Path to the WAL directory.
  ///
  /// If null, WAL-based recovery is disabled.
  final String? walDirectory;

  /// Whether to delete WAL files after successful recovery.
  final bool deleteWalAfterRecovery;

  /// Whether to throw on recovery errors or just log and continue.
  final bool throwOnRecoveryError;

  /// Creates a recovery configuration.
  const RecoveryConfig({
    this.walDirectory,
    this.deleteWalAfterRecovery = true,
    this.throwOnRecoveryError = true,
  });

  /// Default configuration (no WAL recovery).
  static const RecoveryConfig disabled = RecoveryConfig();

  /// Creates a configuration with WAL recovery enabled.
  factory RecoveryConfig.enabled({
    required String walDirectory,
    bool deleteWalAfterRecovery = true,
    bool throwOnRecoveryError = true,
  }) {
    return RecoveryConfig(
      walDirectory: walDirectory,
      deleteWalAfterRecovery: deleteWalAfterRecovery,
      throwOnRecoveryError: throwOnRecoveryError,
    );
  }

  /// Whether WAL recovery is enabled.
  bool get isEnabled => walDirectory != null;
}

/// Callback for applying recovered entity data.
///
/// Called during recovery for each entity that needs to be restored.
/// The implementer should apply the operation to the storage.
typedef RecoveryEntityCallback =
    Future<void> Function(
      String collectionName,
      String entityId,
      Map<String, dynamic>? data,
    );

/// A recovery handler for storage systems.
///
/// Implements [WalRedoHandler] to apply recovered operations to storage.
/// This is typically used by PagedStorage to recover after a crash.
///
/// ## Usage
///
/// ```dart
/// final handler = StorageRecoveryHandler(
///   onInsert: (collection, id, data) async {
///     await storage.insert(id, data!);
///   },
///   onUpdate: (collection, id, data) async {
///     await storage.update(id, data!);
///   },
///   onDelete: (collection, id, data) async {
///     await storage.delete(id);
///   },
/// );
///
/// final recovery = WalRecovery(
///   walFilePath: '/path/to/wal.log',
///   redoHandler: handler,
/// );
/// await recovery.recover();
/// ```
class StorageRecoveryHandler implements WalRedoHandler {
  /// Callback for insert operations.
  final RecoveryEntityCallback _onInsert;

  /// Callback for update operations.
  final RecoveryEntityCallback _onUpdate;

  /// Callback for delete operations.
  final RecoveryEntityCallback _onDelete;

  /// Count of recovered insert operations.
  int _insertCount = 0;

  /// Count of recovered update operations.
  int _updateCount = 0;

  /// Count of recovered delete operations.
  int _deleteCount = 0;

  /// Creates a storage recovery handler.
  StorageRecoveryHandler({
    required RecoveryEntityCallback onInsert,
    required RecoveryEntityCallback onUpdate,
    required RecoveryEntityCallback onDelete,
  }) : _onInsert = onInsert,
       _onUpdate = onUpdate,
       _onDelete = onDelete;

  /// Number of insert operations recovered.
  int get insertCount => _insertCount;

  /// Number of update operations recovered.
  int get updateCount => _updateCount;

  /// Number of delete operations recovered.
  int get deleteCount => _deleteCount;

  /// Total number of operations recovered.
  int get totalCount => _insertCount + _updateCount + _deleteCount;

  @override
  Future<void> redoInsert(DataOperationPayload payload) async {
    if (payload.afterImage != null) {
      await _onInsert(
        payload.collectionName,
        payload.entityId,
        payload.afterImage,
      );
      _insertCount++;
    }
  }

  @override
  Future<void> redoUpdate(DataOperationPayload payload) async {
    if (payload.afterImage != null) {
      await _onUpdate(
        payload.collectionName,
        payload.entityId,
        payload.afterImage,
      );
      _updateCount++;
    }
  }

  @override
  Future<void> redoDelete(DataOperationPayload payload) async {
    await _onDelete(payload.collectionName, payload.entityId, null);
    _deleteCount++;
  }

  /// Resets the operation counters.
  void reset() {
    _insertCount = 0;
    _updateCount = 0;
    _deleteCount = 0;
  }
}

/// Result of a recovery operation.
class RecoveryResult {
  /// Whether recovery was needed.
  final bool recoveryNeeded;

  /// Whether recovery was successful.
  final bool success;

  /// Number of insert operations recovered.
  final int insertCount;

  /// Number of update operations recovered.
  final int updateCount;

  /// Number of delete operations recovered.
  final int deleteCount;

  /// Total operations recovered.
  int get totalOperations => insertCount + updateCount + deleteCount;

  /// Number of committed transactions recovered.
  final int committedTransactions;

  /// Number of aborted transactions found.
  final int abortedTransactions;

  /// Number of uncommitted transactions rolled back.
  final int rolledBackTransactions;

  /// Error message if recovery failed.
  final String? errorMessage;

  /// Duration of recovery process.
  final Duration duration;

  /// Creates a recovery result.
  const RecoveryResult({
    required this.recoveryNeeded,
    required this.success,
    this.insertCount = 0,
    this.updateCount = 0,
    this.deleteCount = 0,
    this.committedTransactions = 0,
    this.abortedTransactions = 0,
    this.rolledBackTransactions = 0,
    this.errorMessage,
    this.duration = Duration.zero,
  });

  /// Result when no recovery was needed.
  static const RecoveryResult noRecoveryNeeded = RecoveryResult(
    recoveryNeeded: false,
    success: true,
  );

  @override
  String toString() {
    if (!recoveryNeeded) {
      return 'RecoveryResult(no recovery needed)';
    }
    if (!success) {
      return 'RecoveryResult(failed: $errorMessage)';
    }
    return 'RecoveryResult('
        'operations: $totalOperations, '
        'committed: $committedTransactions, '
        'rolledBack: $rolledBackTransactions, '
        'duration: ${duration.inMilliseconds}ms)';
  }
}

/// Performs recovery for a storage using WAL files.
///
/// Scans the WAL directory for log files and applies committed
/// transactions to the storage.
class DatabaseRecovery {
  /// The recovery configuration.
  final RecoveryConfig config;

  /// Creates a database recovery instance.
  const DatabaseRecovery({required this.config});

  /// Performs recovery using the provided handler.
  ///
  /// Returns the recovery result.
  Future<RecoveryResult> recover(StorageRecoveryHandler handler) async {
    if (!config.isEnabled || config.walDirectory == null) {
      return RecoveryResult.noRecoveryNeeded;
    }

    final stopwatch = Stopwatch()..start();
    final walDir = Directory(config.walDirectory!);

    if (!await walDir.exists()) {
      return RecoveryResult.noRecoveryNeeded;
    }

    // Find all WAL files
    final walFiles = await walDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              (entity.path.endsWith('.log') || entity.path.endsWith('.wal')),
        )
        .cast<File>()
        .toList();

    if (walFiles.isEmpty) {
      return RecoveryResult.noRecoveryNeeded;
    }

    // Sort by name to process in order
    walFiles.sort((a, b) => a.path.compareTo(b.path));

    int totalCommitted = 0;
    int totalAborted = 0;
    int totalRolledBack = 0;

    try {
      for (final walFile in walFiles) {
        final recovery = WalRecovery(
          walFilePath: walFile.path,
          redoHandler: handler,
        );

        final stats = await recovery.recover();
        totalCommitted += stats.committedTransactions;
        totalAborted += stats.abortedTransactions;
        totalRolledBack += stats.uncommittedTransactions;

        // Delete WAL file after successful recovery
        if (config.deleteWalAfterRecovery) {
          await walFile.delete();
        }
      }

      stopwatch.stop();

      return RecoveryResult(
        recoveryNeeded: true,
        success: true,
        insertCount: handler.insertCount,
        updateCount: handler.updateCount,
        deleteCount: handler.deleteCount,
        committedTransactions: totalCommitted,
        abortedTransactions: totalAborted,
        rolledBackTransactions: totalRolledBack,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();

      if (config.throwOnRecoveryError) {
        rethrow;
      }

      return RecoveryResult(
        recoveryNeeded: true,
        success: false,
        insertCount: handler.insertCount,
        updateCount: handler.updateCount,
        deleteCount: handler.deleteCount,
        committedTransactions: totalCommitted,
        abortedTransactions: totalAborted,
        rolledBackTransactions: totalRolledBack,
        errorMessage: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }
}
