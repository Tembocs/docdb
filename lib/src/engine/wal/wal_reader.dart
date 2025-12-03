/// Write-Ahead Log (WAL) Reader and Recovery.
///
/// Provides functionality to read WAL records and perform crash recovery
/// by replaying committed transactions.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'wal_constants.dart';
import 'wal_record.dart';

/// Callback for processing WAL records during recovery.
///
/// Return `true` to continue processing, `false` to stop.
typedef WalRecordCallback = Future<bool> Function(WalRecord record);

/// Handler for redo operations during recovery.
abstract interface class WalRedoHandler {
  /// Redo an insert operation.
  Future<void> redoInsert(DataOperationPayload payload);

  /// Redo an update operation.
  Future<void> redoUpdate(DataOperationPayload payload);

  /// Redo a delete operation.
  Future<void> redoDelete(DataOperationPayload payload);
}

/// Handler for undo operations during recovery.
abstract interface class WalUndoHandler {
  /// Undo an insert operation.
  Future<void> undoInsert(DataOperationPayload payload);

  /// Undo an update operation.
  Future<void> undoUpdate(DataOperationPayload payload);

  /// Undo a delete operation.
  Future<void> undoDelete(DataOperationPayload payload);
}

/// The Write-Ahead Log reader.
///
/// Reads WAL files and provides record iteration for recovery
/// and analysis purposes.
class WalReader {
  /// The path to the WAL file.
  final String filePath;

  /// The underlying file.
  RandomAccessFile? _file;

  /// File length in bytes.
  int _fileLength = 0;

  /// Current read position.
  int _position = 0;

  /// Whether the reader is open.
  bool _isOpen = false;

  /// Creates a new WAL reader.
  WalReader({required this.filePath});

  /// Whether the reader is open.
  bool get isOpen => _isOpen;

  /// Current read position.
  int get position => _position;

  /// File length.
  int get length => _fileLength;

  /// Opens the WAL file for reading.
  Future<WalFileHeader> open() async {
    if (_isOpen) {
      throw StateError('WAL reader is already open');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw WalRecoveryException('WAL file not found: $filePath');
    }

    _file = await file.open(mode: FileMode.read);
    _fileLength = await _file!.length();

    if (_fileLength < WalHeaderConstants.headerSize) {
      await _file!.close();
      throw WalRecoveryException('WAL file too small: $filePath');
    }

    // Read and validate header
    final headerBytes = await _file!.read(WalHeaderConstants.headerSize);
    final header = _parseHeader(Uint8List.fromList(headerBytes));

    _position = WalHeaderConstants.headerSize;
    _isOpen = true;

    return header;
  }

  /// Closes the WAL reader.
  Future<void> close() async {
    if (!_isOpen) return;
    await _file?.close();
    _file = null;
    _isOpen = false;
  }

  /// Reads the next record from the WAL.
  ///
  /// Returns `null` if there are no more records.
  Future<WalRecord?> readNext() async {
    _ensureOpen();

    if (_position >= _fileLength) {
      return null;
    }

    // Read record header first
    await _file!.setPosition(_position);
    final headerBytes = await _file!.read(WalRecordConstants.headerSize);

    if (headerBytes.length < WalRecordConstants.headerSize) {
      return null; // Incomplete header, end of valid data
    }

    final headerData = ByteData.sublistView(Uint8List.fromList(headerBytes));
    final payloadLength = headerData.getUint32(
      WalRecordOffsets.payloadLength,
      Endian.little,
    );

    // Read full record
    await _file!.setPosition(_position);
    final recordSize = WalRecordConstants.headerSize + payloadLength;
    final recordBytes = await _file!.read(recordSize);

    if (recordBytes.length < recordSize) {
      return null; // Incomplete record
    }

    try {
      final record = WalRecord.fromBytes(Uint8List.fromList(recordBytes));
      _position += recordSize;

      // Stop at end-of-log marker
      if (record.type == WalRecordType.endOfLog) {
        return null;
      }

      return record;
    } on WalCorruptedException {
      // Corrupted record, stop reading
      return null;
    }
  }

  /// Seeks to a specific LSN.
  Future<void> seekToLsn(Lsn lsn) async {
    _ensureOpen();

    if (lsn.value < WalHeaderConstants.headerSize || lsn.value >= _fileLength) {
      throw ArgumentError.value(lsn.value, 'lsn', 'LSN out of range');
    }

    _position = lsn.value;
    await _file!.setPosition(_position);
  }

  /// Iterates over all records, calling the callback for each.
  ///
  /// Returns the number of records processed.
  Future<int> forEach(WalRecordCallback callback) async {
    _ensureOpen();

    // Reset to start
    _position = WalHeaderConstants.headerSize;

    int count = 0;
    WalRecord? record;

    while ((record = await readNext()) != null) {
      count++;
      final shouldContinue = await callback(record!);
      if (!shouldContinue) break;
    }

    return count;
  }

  /// Collects all records into a list.
  ///
  /// Use with caution for large WAL files.
  Future<List<WalRecord>> readAll() async {
    final records = <WalRecord>[];
    await forEach((record) async {
      records.add(record);
      return true;
    });
    return records;
  }

  WalFileHeader _parseHeader(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    final magic = data.getUint32(WalHeaderOffsets.magic, Endian.little);
    if (magic != WalHeaderConstants.magicNumber) {
      throw WalRecoveryException(
        'Invalid WAL magic number: 0x${magic.toRadixString(16)}',
      );
    }

    final version = data.getUint32(WalHeaderOffsets.version, Endian.little);
    if (version > WalHeaderConstants.currentVersion) {
      throw WalRecoveryException(
        'WAL version $version is newer than supported ${WalHeaderConstants.currentVersion}',
      );
    }

    return WalFileHeader(
      version: version,
      databaseId: String.fromCharCodes(
        bytes.sublist(
          WalHeaderOffsets.databaseId,
          WalHeaderOffsets.databaseId + 16,
        ),
      ).replaceAll('\x00', ''),
      sequenceNumber: data.getInt64(
        WalHeaderOffsets.sequenceNumber,
        Endian.little,
      ),
      checkpointLsn: Lsn(
        data.getInt64(WalHeaderOffsets.checkpointLsn, Endian.little),
      ),
      flags: data.getUint32(WalHeaderOffsets.flags, Endian.little),
    );
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('WAL reader is not open');
    }
  }
}

/// WAL file header information.
class WalFileHeader {
  /// File format version.
  final int version;

  /// Database ID.
  final String databaseId;

  /// Sequence number.
  final int sequenceNumber;

  /// Last checkpoint LSN.
  final Lsn checkpointLsn;

  /// Header flags.
  final int flags;

  /// Creates a WAL file header.
  const WalFileHeader({
    required this.version,
    required this.databaseId,
    required this.sequenceNumber,
    required this.checkpointLsn,
    required this.flags,
  });

  /// Whether the file was closed cleanly.
  bool get isClean => (flags & WalHeaderFlags.cleanClose) != 0;

  /// Whether recovery is needed.
  bool get needsRecovery => !isClean;
}

/// Performs crash recovery using the WAL.
///
/// The recovery process:
/// 1. Analysis pass: Identify committed and uncommitted transactions
/// 2. Redo pass: Replay committed transactions
/// 3. Undo pass: Roll back uncommitted transactions
class WalRecovery {
  /// The WAL file to recover from.
  final String walFilePath;

  /// Handler for redo operations.
  final WalRedoHandler redoHandler;

  /// Handler for undo operations (optional).
  final WalUndoHandler? undoHandler;

  /// Statistics from recovery.
  WalRecoveryStatistics? _statistics;

  /// Creates a WAL recovery instance.
  WalRecovery({
    required this.walFilePath,
    required this.redoHandler,
    this.undoHandler,
  });

  /// Gets the recovery statistics (available after recover()).
  WalRecoveryStatistics? get statistics => _statistics;

  /// Performs crash recovery.
  ///
  /// Returns the recovery statistics.
  Future<WalRecoveryStatistics> recover() async {
    final reader = WalReader(filePath: walFilePath);
    final header = await reader.open();

    try {
      // Analysis pass: categorize transactions
      final analysis = await _analyzeTransactions(reader);

      // Reset reader
      await reader.seekToLsn(Lsn.first);

      // Redo pass: replay committed transactions
      final redoCount = await _redoPass(reader, analysis.committedTransactions);

      // Undo pass: roll back uncommitted transactions
      int undoCount = 0;
      if (undoHandler != null && analysis.uncommittedTransactions.isNotEmpty) {
        await reader.seekToLsn(Lsn.first);
        undoCount = await _undoPass(reader, analysis.uncommittedTransactions);
      }

      _statistics = WalRecoveryStatistics(
        walFilePath: walFilePath,
        needsRecovery: header.needsRecovery,
        totalRecords: analysis.totalRecords,
        committedTransactions: analysis.committedTransactions.length,
        abortedTransactions: analysis.abortedTransactions.length,
        uncommittedTransactions: analysis.uncommittedTransactions.length,
        redoOperations: redoCount,
        undoOperations: undoCount,
        lastCheckpointLsn: header.checkpointLsn,
      );

      return _statistics!;
    } finally {
      await reader.close();
    }
  }

  Future<_TransactionAnalysis> _analyzeTransactions(WalReader reader) async {
    final committed = <int>{};
    final aborted = <int>{};
    final active = <int, List<WalRecord>>{};
    int totalRecords = 0;

    await reader.forEach((record) async {
      totalRecords++;

      switch (record.type) {
        case WalRecordType.beginTransaction:
          active[record.transactionId] = [];
          break;

        case WalRecordType.commitTransaction:
          committed.add(record.transactionId);
          active.remove(record.transactionId);
          break;

        case WalRecordType.abortTransaction:
          aborted.add(record.transactionId);
          active.remove(record.transactionId);
          break;

        case WalRecordType.insert:
        case WalRecordType.update:
        case WalRecordType.delete:
          active[record.transactionId]?.add(record);
          break;

        default:
          break;
      }

      return true;
    });

    return _TransactionAnalysis(
      totalRecords: totalRecords,
      committedTransactions: committed,
      abortedTransactions: aborted,
      uncommittedTransactions: active.keys.toSet(),
      uncommittedRecords: active,
    );
  }

  Future<int> _redoPass(WalReader reader, Set<int> committedTxns) async {
    int count = 0;

    await reader.forEach((record) async {
      // Only redo operations from committed transactions
      if (!committedTxns.contains(record.transactionId)) {
        return true;
      }

      try {
        switch (record.type) {
          case WalRecordType.insert:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await redoHandler.redoInsert(payload);
            count++;
            break;

          case WalRecordType.update:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await redoHandler.redoUpdate(payload);
            count++;
            break;

          case WalRecordType.delete:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await redoHandler.redoDelete(payload);
            count++;
            break;

          default:
            break;
        }
      } catch (e) {
        // Log but continue recovery
        // In production, would use proper logging
      }

      return true;
    });

    return count;
  }

  Future<int> _undoPass(WalReader reader, Set<int> uncommittedTxns) async {
    if (undoHandler == null) return 0;

    int count = 0;

    // Collect records in reverse order for proper undo
    final recordsToUndo = <WalRecord>[];

    await reader.forEach((record) async {
      if (!uncommittedTxns.contains(record.transactionId)) {
        return true;
      }

      if (record.type == WalRecordType.insert ||
          record.type == WalRecordType.update ||
          record.type == WalRecordType.delete) {
        recordsToUndo.add(record);
      }

      return true;
    });

    // Undo in reverse order
    for (final record in recordsToUndo.reversed) {
      try {
        switch (record.type) {
          case WalRecordType.insert:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await undoHandler!.undoInsert(payload);
            count++;
            break;

          case WalRecordType.update:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await undoHandler!.undoUpdate(payload);
            count++;
            break;

          case WalRecordType.delete:
            final payload = DataOperationPayload.fromBytes(record.payload);
            await undoHandler!.undoDelete(payload);
            count++;
            break;

          default:
            break;
        }
      } catch (e) {
        // Log but continue recovery
      }
    }

    return count;
  }
}

class _TransactionAnalysis {
  final int totalRecords;
  final Set<int> committedTransactions;
  final Set<int> abortedTransactions;
  final Set<int> uncommittedTransactions;
  final Map<int, List<WalRecord>> uncommittedRecords;

  const _TransactionAnalysis({
    required this.totalRecords,
    required this.committedTransactions,
    required this.abortedTransactions,
    required this.uncommittedTransactions,
    required this.uncommittedRecords,
  });
}

/// Statistics from WAL recovery.
class WalRecoveryStatistics {
  /// Path to the recovered WAL file.
  final String walFilePath;

  /// Whether recovery was needed.
  final bool needsRecovery;

  /// Total records in the WAL.
  final int totalRecords;

  /// Number of committed transactions.
  final int committedTransactions;

  /// Number of aborted transactions.
  final int abortedTransactions;

  /// Number of uncommitted transactions (rolled back).
  final int uncommittedTransactions;

  /// Number of redo operations performed.
  final int redoOperations;

  /// Number of undo operations performed.
  final int undoOperations;

  /// Last checkpoint LSN.
  final Lsn lastCheckpointLsn;

  /// Creates recovery statistics.
  const WalRecoveryStatistics({
    required this.walFilePath,
    required this.needsRecovery,
    required this.totalRecords,
    required this.committedTransactions,
    required this.abortedTransactions,
    required this.uncommittedTransactions,
    required this.redoOperations,
    required this.undoOperations,
    required this.lastCheckpointLsn,
  });

  @override
  String toString() {
    return 'WalRecoveryStatistics('
        'needsRecovery: $needsRecovery, '
        'totalRecords: $totalRecords, '
        'committed: $committedTransactions, '
        'aborted: $abortedTransactions, '
        'uncommitted: $uncommittedTransactions, '
        'redoOps: $redoOperations, '
        'undoOps: $undoOperations)';
  }
}
