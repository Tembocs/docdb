/// Write-Ahead Log (WAL) module.
///
/// This module provides durability guarantees for the database through
/// write-ahead logging. All modifications are logged before being applied
/// to ensure data can be recovered after a crash.
///
/// ## Key Components
///
/// - [WalWriter]: Writes WAL records to disk with configurable sync modes
/// - [WalReader]: Reads WAL records for recovery and analysis
/// - [WalRecovery]: Performs crash recovery using analysis, redo, and undo passes
/// - [WalRecord]: Represents individual log records
///
/// ## Usage
///
/// ```dart
/// // Writing WAL records
/// final writer = WalWriter(
///   walDirectory: '/path/to/wal',
///   config: WalWriterConfig(syncMode: WalSyncMode.normal),
/// );
/// await writer.open(databaseId: 'mydb');
///
/// // Log a transaction
/// final beginLsn = await writer.appendBeginTransaction(txnId: 1);
/// final insertLsn = await writer.appendInsert(
///   transactionId: 1,
///   collectionName: 'users',
///   documentId: 'user-1',
///   afterData: Uint8List.fromList([...]),
/// );
/// final commitLsn = await writer.appendCommitTransaction(txnId: 1);
///
/// // Recovery after crash
/// final recovery = WalRecovery(
///   walFilePath: '/path/to/wal/00000001.wal',
///   redoHandler: myRedoHandler,
///   undoHandler: myUndoHandler,
/// );
/// final stats = await recovery.recover();
/// print('Recovered ${stats.redoOperations} operations');
/// ```
///
/// ## Sync Modes
///
/// The WAL supports three sync modes for different durability/performance trade-offs:
///
/// - [WalSyncMode.full]: Sync every write (maximum durability, slowest)
/// - [WalSyncMode.normal]: Sync on commit (good balance)
/// - [WalSyncMode.off]: No sync (fastest, risk of data loss on power failure)
library;

export 'wal_constants.dart';
export 'wal_record.dart';
export 'wal_reader.dart';
export 'wal_writer.dart';
