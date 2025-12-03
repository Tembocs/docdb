/// Write-Ahead Log (WAL) Writer.
///
/// Provides durable logging of database operations for crash recovery.
/// All modifications are written to the WAL before being applied to
/// the main database file.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import 'wal_constants.dart';
import 'wal_record.dart';

/// Configuration for the WAL writer.
class WalConfig {
  /// The directory for WAL files.
  final String walDirectory;

  /// Maximum size of a single WAL file before rotation.
  final int maxFileSize;

  /// Whether to sync after every write (durable but slower).
  final bool syncOnWrite;

  /// Checkpoint interval in bytes.
  final int checkpointIntervalBytes;

  /// Checkpoint interval in seconds.
  final int checkpointIntervalSeconds;

  /// Buffer size for WAL writes.
  final int bufferSize;

  /// Creates a new WAL configuration.
  const WalConfig({
    required this.walDirectory,
    this.maxFileSize = 64 * 1024 * 1024, // 64 MB
    this.syncOnWrite = true,
    this.checkpointIntervalBytes = WalCheckpointConstants.defaultIntervalBytes,
    this.checkpointIntervalSeconds =
        WalCheckpointConstants.defaultIntervalSeconds,
    this.bufferSize = 64 * 1024, // 64 KB
  });

  /// Development configuration (faster, less durable).
  static WalConfig development(String directory) => WalConfig(
    walDirectory: directory,
    syncOnWrite: false,
    checkpointIntervalBytes: 4 * 1024 * 1024, // 4 MB
    checkpointIntervalSeconds: 10,
  );

  /// Production configuration (slower, fully durable).
  static WalConfig production(String directory) => WalConfig(
    walDirectory: directory,
    syncOnWrite: true,
    checkpointIntervalBytes: WalCheckpointConstants.defaultIntervalBytes,
    checkpointIntervalSeconds: WalCheckpointConstants.defaultIntervalSeconds,
  );
}

/// Statistics for the WAL writer.
class WalStatistics {
  /// Total bytes written to WAL.
  final int totalBytesWritten;

  /// Total records written.
  final int totalRecordsWritten;

  /// Total syncs performed.
  final int totalSyncs;

  /// Total checkpoints completed.
  final int totalCheckpoints;

  /// Current WAL file size.
  final int currentFileSize;

  /// Current LSN.
  final int currentLsn;

  /// Creates WAL statistics.
  const WalStatistics({
    required this.totalBytesWritten,
    required this.totalRecordsWritten,
    required this.totalSyncs,
    required this.totalCheckpoints,
    required this.currentFileSize,
    required this.currentLsn,
  });
}

/// The Write-Ahead Log writer.
///
/// Provides atomic, durable logging of database operations.
/// Supports:
/// - Sequential log record writing
/// - Transaction tracking
/// - Checkpointing
/// - Crash recovery
///
/// ## Usage
///
/// ```dart
/// final wal = WalWriter(config: WalConfig.production('./wal'));
/// await wal.open();
///
/// // Begin a transaction
/// final txnId = await wal.beginTransaction();
///
/// // Log operations
/// await wal.logInsert(
///   transactionId: txnId,
///   collectionName: 'users',
///   entityId: 'user-1',
///   data: {'name': 'Alice'},
/// );
///
/// // Commit
/// await wal.commitTransaction(txnId);
///
/// await wal.close();
/// ```
class WalWriter {
  /// Configuration.
  final WalConfig _config;

  /// The current WAL file.
  RandomAccessFile? _file;

  /// Current WAL file path.
  String? _currentFilePath;

  /// Lock for thread-safe access.
  final Lock _lock = Lock();

  /// Database ID (UUID).
  late final String _databaseId;

  /// Current Log Sequence Number.
  Lsn _currentLsn = Lsn.first;

  /// Bytes written since last checkpoint.
  int _bytesSinceCheckpoint = 0;

  /// Last checkpoint timestamp.
  DateTime _lastCheckpointTime = DateTime.now();

  /// Active transactions: transactionId -> previous LSN for that transaction.
  final Map<int, Lsn> _activeTransactions = {};

  /// Next transaction ID.
  int _nextTransactionId = 1;

  /// Write buffer for batching.
  final List<Uint8List> _writeBuffer = [];
  int _bufferSize = 0;

  /// Whether the WAL is open.
  bool _isOpen = false;

  /// Statistics.
  int _totalBytesWritten = 0;
  int _totalRecordsWritten = 0;
  int _totalSyncs = 0;
  int _totalCheckpoints = 0;

  /// Creates a new WAL writer.
  WalWriter({required WalConfig config}) : _config = config;

  /// Whether the WAL is open.
  bool get isOpen => _isOpen;

  /// Current LSN.
  Lsn get currentLsn => _currentLsn;

  /// Number of active transactions.
  int get activeTransactionCount => _activeTransactions.length;

  /// Gets the current statistics.
  WalStatistics get statistics => WalStatistics(
    totalBytesWritten: _totalBytesWritten,
    totalRecordsWritten: _totalRecordsWritten,
    totalSyncs: _totalSyncs,
    totalCheckpoints: _totalCheckpoints,
    currentFileSize: _currentLsn.value,
    currentLsn: _currentLsn.value,
  );

  /// Opens the WAL for writing.
  ///
  /// Creates the WAL directory if it doesn't exist.
  /// If a WAL file exists and needs recovery, returns the recovery info.
  Future<WalRecoveryInfo?> open() async {
    return await _lock.synchronized(() async {
      if (_isOpen) {
        throw StateError('WAL is already open');
      }

      // Create WAL directory
      final dir = Directory(_config.walDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Check for existing WAL files needing recovery
      final existingFiles = await _findExistingWalFiles();
      WalRecoveryInfo? recoveryInfo;

      if (existingFiles.isNotEmpty) {
        recoveryInfo = await _checkForRecovery(existingFiles);
      }

      // Create or open current WAL file
      _databaseId = const Uuid().v4();
      _currentFilePath = _generateWalFileName();
      _file = await File(
        _currentFilePath!,
      ).open(mode: FileMode.writeOnlyAppend);

      // Write header
      await _writeHeader();

      _isOpen = true;
      _lastCheckpointTime = DateTime.now();

      return recoveryInfo;
    });
  }

  /// Closes the WAL writer.
  ///
  /// Flushes pending writes and marks the file as cleanly closed.
  Future<void> close() async {
    await _lock.synchronized(() async {
      if (!_isOpen) return;

      // Flush any buffered writes
      await _flushBuffer();

      // Write end-of-log marker
      await _writeEndOfLog();

      // Update header to mark clean close
      await _markCleanClose();

      await _file?.flush();
      await _file?.close();
      _file = null;
      _isOpen = false;
    });
  }

  /// Begins a new transaction.
  ///
  /// Returns the transaction ID to use for subsequent operations.
  Future<int> beginTransaction() async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      final txnId = _nextTransactionId++;
      final prevLsn = Lsn.invalid;

      final record = WalRecord(
        type: WalRecordType.beginTransaction,
        transactionId: txnId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: Uint8List(0),
      );

      await _appendRecord(record);
      _activeTransactions[txnId] = _currentLsn;

      return txnId;
    });
  }

  /// Commits a transaction.
  ///
  /// The commit record is force-synced to disk to ensure durability.
  Future<void> commitTransaction(int transactionId) async {
    _ensureOpen();

    await _lock.synchronized(() async {
      if (!_activeTransactions.containsKey(transactionId)) {
        throw StateError('Transaction $transactionId is not active');
      }

      final prevLsn = _activeTransactions[transactionId]!;

      final record = WalRecord(
        type: WalRecordType.commitTransaction,
        transactionId: transactionId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: Uint8List(0),
      );

      await _appendRecord(record);
      await _flushBuffer();
      await _sync(); // Force sync on commit

      _activeTransactions.remove(transactionId);
    });
  }

  /// Aborts a transaction.
  Future<void> abortTransaction(int transactionId) async {
    _ensureOpen();

    await _lock.synchronized(() async {
      if (!_activeTransactions.containsKey(transactionId)) {
        throw StateError('Transaction $transactionId is not active');
      }

      final prevLsn = _activeTransactions[transactionId]!;

      final record = WalRecord(
        type: WalRecordType.abortTransaction,
        transactionId: transactionId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: Uint8List(0),
      );

      await _appendRecord(record);
      _activeTransactions.remove(transactionId);
    });
  }

  /// Logs an insert operation.
  Future<Lsn> logInsert({
    required int transactionId,
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      _validateTransaction(transactionId);

      final prevLsn = _activeTransactions[transactionId]!;
      final payload = DataOperationPayload.insert(
        collectionName: collectionName,
        entityId: entityId,
        data: data,
      );

      final record = WalRecord(
        type: WalRecordType.insert,
        transactionId: transactionId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: payload.toBytes(),
      );

      await _appendRecord(record);
      _activeTransactions[transactionId] = _currentLsn;

      return _currentLsn;
    });
  }

  /// Logs an update operation.
  Future<Lsn> logUpdate({
    required int transactionId,
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> before,
    required Map<String, dynamic> after,
  }) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      _validateTransaction(transactionId);

      final prevLsn = _activeTransactions[transactionId]!;
      final payload = DataOperationPayload.update(
        collectionName: collectionName,
        entityId: entityId,
        before: before,
        after: after,
      );

      final record = WalRecord(
        type: WalRecordType.update,
        transactionId: transactionId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: payload.toBytes(),
      );

      await _appendRecord(record);
      _activeTransactions[transactionId] = _currentLsn;

      return _currentLsn;
    });
  }

  /// Logs a delete operation.
  Future<Lsn> logDelete({
    required int transactionId,
    required String collectionName,
    required String entityId,
    required Map<String, dynamic> data,
  }) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      _validateTransaction(transactionId);

      final prevLsn = _activeTransactions[transactionId]!;
      final payload = DataOperationPayload.delete(
        collectionName: collectionName,
        entityId: entityId,
        data: data,
      );

      final record = WalRecord(
        type: WalRecordType.delete,
        transactionId: transactionId,
        lsn: _currentLsn,
        prevLsn: prevLsn,
        payload: payload.toBytes(),
      );

      await _appendRecord(record);
      _activeTransactions[transactionId] = _currentLsn;

      return _currentLsn;
    });
  }

  /// Forces a checkpoint.
  ///
  /// A checkpoint records the current state and allows truncation
  /// of older WAL records.
  Future<Lsn> checkpoint({Map<int, int>? dirtyPages}) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      // Flush pending writes first
      await _flushBuffer();

      final payload = CheckpointPayload(
        timestamp: DateTime.now(),
        activeTransactions: _activeTransactions.keys.toList(),
        dirtyPages: dirtyPages ?? {},
      );

      final record = WalRecord(
        type: WalRecordType.checkpoint,
        transactionId: 0, // System record
        lsn: _currentLsn,
        prevLsn: Lsn.invalid,
        payload: payload.toBytes(),
      );

      await _appendRecord(record);
      await _sync();

      _bytesSinceCheckpoint = 0;
      _lastCheckpointTime = DateTime.now();
      _totalCheckpoints++;

      return _currentLsn;
    });
  }

  /// Checks if a checkpoint should be triggered.
  bool shouldCheckpoint() {
    if (_bytesSinceCheckpoint >= _config.checkpointIntervalBytes) {
      return true;
    }
    final elapsed = DateTime.now().difference(_lastCheckpointTime).inSeconds;
    return elapsed >= _config.checkpointIntervalSeconds;
  }

  /// Syncs pending writes to disk.
  Future<void> sync() async {
    _ensureOpen();
    await _lock.synchronized(() async {
      await _flushBuffer();
      await _sync();
    });
  }

  // ============================================================
  // Internal Methods
  // ============================================================

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('WAL is not open');
    }
  }

  void _validateTransaction(int transactionId) {
    if (!_activeTransactions.containsKey(transactionId)) {
      throw StateError('Transaction $transactionId is not active');
    }
  }

  String _generateWalFileName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${_config.walDirectory}/wal_$timestamp.log';
  }

  Future<List<String>> _findExistingWalFiles() async {
    final dir = Directory(_config.walDirectory);
    if (!await dir.exists()) {
      return [];
    }

    final files = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) {
        files.add(entity.path);
      }
    }
    files.sort(); // Sort by name (timestamp)
    return files;
  }

  Future<WalRecoveryInfo?> _checkForRecovery(List<String> files) async {
    for (final filePath in files.reversed) {
      final file = File(filePath);
      if (!await file.exists()) continue;

      final length = await file.length();
      if (length < WalHeaderConstants.headerSize) continue;

      final raf = await file.open(mode: FileMode.read);
      try {
        final headerBytes = await raf.read(WalHeaderConstants.headerSize);
        final header = ByteData.sublistView(Uint8List.fromList(headerBytes));

        final magic = header.getUint32(WalHeaderOffsets.magic, Endian.little);
        if (magic != WalHeaderConstants.magicNumber) continue;

        final flags = header.getUint32(WalHeaderOffsets.flags, Endian.little);
        if ((flags & WalHeaderFlags.cleanClose) == 0) {
          // This file needs recovery
          return WalRecoveryInfo(
            walFilePath: filePath,
            lastCheckpointLsn: Lsn(
              header.getInt64(WalHeaderOffsets.checkpointLsn, Endian.little),
            ),
          );
        }
      } finally {
        await raf.close();
      }
    }
    return null;
  }

  Future<void> _writeHeader() async {
    final header = Uint8List(WalHeaderConstants.headerSize);
    final data = ByteData.sublistView(header);

    data.setUint32(
      WalHeaderOffsets.magic,
      WalHeaderConstants.magicNumber,
      Endian.little,
    );
    data.setUint32(
      WalHeaderOffsets.version,
      WalHeaderConstants.currentVersion,
      Endian.little,
    );

    // Write database ID as bytes
    final idBytes = _databaseId.codeUnits;
    for (var i = 0; i < 16 && i < idBytes.length; i++) {
      header[WalHeaderOffsets.databaseId + i] = idBytes[i];
    }

    data.setInt64(WalHeaderOffsets.sequenceNumber, 0, Endian.little);
    data.setInt64(WalHeaderOffsets.checkpointLsn, 0, Endian.little);
    data.setUint32(WalHeaderOffsets.flags, WalHeaderFlags.open, Endian.little);

    await _file!.writeFrom(header);
    await _file!.flush();

    _currentLsn = Lsn.first;
  }

  Future<void> _appendRecord(WalRecord record) async {
    final bytes = record.toBytes();

    _writeBuffer.add(bytes);
    _bufferSize += bytes.length;

    // Update LSN for next record
    _currentLsn = _currentLsn.advance(bytes.length);
    _bytesSinceCheckpoint += bytes.length;
    _totalRecordsWritten++;

    // Flush if buffer is full
    if (_bufferSize >= _config.bufferSize) {
      await _flushBuffer();
    }
  }

  Future<void> _flushBuffer() async {
    if (_writeBuffer.isEmpty) return;

    for (final bytes in _writeBuffer) {
      await _file!.writeFrom(bytes);
      _totalBytesWritten += bytes.length;
    }

    _writeBuffer.clear();
    _bufferSize = 0;

    if (_config.syncOnWrite) {
      await _sync();
    }
  }

  Future<void> _sync() async {
    await _file!.flush();
    _totalSyncs++;
  }

  Future<void> _writeEndOfLog() async {
    final record = WalRecord(
      type: WalRecordType.endOfLog,
      transactionId: 0,
      lsn: _currentLsn,
      prevLsn: Lsn.invalid,
      payload: Uint8List(0),
    );

    final bytes = record.toBytes();
    await _file!.writeFrom(bytes);
  }

  Future<void> _markCleanClose() async {
    // Seek to flags position and update
    await _file!.setPosition(WalHeaderOffsets.flags);
    final flagsBytes = Uint8List(4);
    ByteData.sublistView(
      flagsBytes,
    ).setUint32(0, WalHeaderFlags.cleanClose, Endian.little);
    await _file!.writeFrom(flagsBytes);
  }
}

/// Information about WAL recovery needed.
class WalRecoveryInfo {
  /// Path to the WAL file needing recovery.
  final String walFilePath;

  /// LSN of the last checkpoint.
  final Lsn lastCheckpointLsn;

  /// Creates recovery info.
  const WalRecoveryInfo({
    required this.walFilePath,
    required this.lastCheckpointLsn,
  });
}
