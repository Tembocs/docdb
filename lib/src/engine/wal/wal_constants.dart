/// Write-Ahead Log (WAL) constants for EntiDB storage engine.
///
/// Defines constants for the WAL file format, record types, and limits.
/// The WAL provides crash recovery and durability guarantees.
library;

/// Constants for WAL file header configuration.
abstract final class WalHeaderConstants {
  /// Magic number identifying WAL files.
  ///
  /// ASCII: "DWAL" (0x44 0x57 0x41 0x4C)
  static const int magicNumber = 0x4457414C;

  /// Current WAL file format version.
  static const int currentVersion = 1;

  /// Size of the WAL file header in bytes.
  ///
  /// Contains:
  /// - Magic number (4 bytes)
  /// - Version (4 bytes)
  /// - Database ID (16 bytes, UUID)
  /// - Sequence number (8 bytes)
  /// - Checkpoint LSN (8 bytes)
  /// - Flags (4 bytes)
  /// - Reserved (20 bytes)
  static const int headerSize = 64;
}

/// Offsets within the WAL file header.
abstract final class WalHeaderOffsets {
  /// Magic number offset (4 bytes).
  static const int magic = 0;

  /// Version offset (4 bytes).
  static const int version = 4;

  /// Database ID offset (16 bytes, UUID).
  static const int databaseId = 8;

  /// Current sequence number offset (8 bytes).
  static const int sequenceNumber = 24;

  /// Checkpoint LSN offset (8 bytes).
  static const int checkpointLsn = 32;

  /// Flags offset (4 bytes).
  static const int flags = 40;

  /// Reserved space offset (20 bytes).
  static const int reserved = 44;
}

/// WAL file header flags.
abstract final class WalHeaderFlags {
  /// WAL file is currently open for writing.
  static const int open = 0x01;

  /// WAL file was closed cleanly.
  static const int cleanClose = 0x02;

  /// WAL file requires recovery.
  static const int needsRecovery = 0x04;
}

/// Types of WAL log records.
///
/// Each record type represents a specific operation that can be
/// replayed during recovery.
enum WalRecordType {
  /// Begin transaction marker.
  beginTransaction(1),

  /// Commit transaction marker.
  commitTransaction(2),

  /// Rollback/abort transaction marker.
  abortTransaction(3),

  /// Insert operation.
  insert(4),

  /// Update operation (contains before and after images).
  update(5),

  /// Delete operation (contains before image).
  delete(6),

  /// Checkpoint record.
  checkpoint(7),

  /// Page write record (full page image).
  pageWrite(8),

  /// Compensation log record (for rollback).
  compensation(9),

  /// End of log marker.
  endOfLog(255);

  /// The numeric value stored in the log.
  final int value;

  const WalRecordType(this.value);

  /// Creates a [WalRecordType] from its numeric value.
  static WalRecordType fromValue(int value) {
    return switch (value) {
      1 => WalRecordType.beginTransaction,
      2 => WalRecordType.commitTransaction,
      3 => WalRecordType.abortTransaction,
      4 => WalRecordType.insert,
      5 => WalRecordType.update,
      6 => WalRecordType.delete,
      7 => WalRecordType.checkpoint,
      8 => WalRecordType.pageWrite,
      9 => WalRecordType.compensation,
      255 => WalRecordType.endOfLog,
      _ => throw ArgumentError('Unknown WAL record type: $value'),
    };
  }
}

/// Constants for WAL record format.
abstract final class WalRecordConstants {
  /// Minimum record size (header only).
  ///
  /// Record header:
  /// - Record type (1 byte)
  /// - Flags (1 byte)
  /// - Transaction ID (8 bytes)
  /// - LSN (8 bytes)
  /// - Previous LSN (8 bytes)
  /// - Payload length (4 bytes)
  /// - Checksum (4 bytes)
  static const int headerSize = 34;

  /// Maximum payload size per record.
  ///
  /// Larger data is split across multiple records.
  static const int maxPayloadSize = 1024 * 1024; // 1 MB

  /// Maximum total record size.
  static const int maxRecordSize = headerSize + maxPayloadSize;
}

/// Offsets within a WAL record header.
abstract final class WalRecordOffsets {
  /// Record type offset (1 byte).
  static const int recordType = 0;

  /// Flags offset (1 byte).
  static const int flags = 1;

  /// Transaction ID offset (8 bytes).
  static const int transactionId = 2;

  /// Log Sequence Number offset (8 bytes).
  static const int lsn = 10;

  /// Previous LSN offset (8 bytes).
  static const int prevLsn = 18;

  /// Payload length offset (4 bytes).
  static const int payloadLength = 26;

  /// Checksum offset (4 bytes).
  static const int checksum = 30;

  /// Payload data starts at this offset.
  static const int payload = 34;
}

/// WAL record flags.
abstract final class WalRecordFlags {
  /// Record is part of a multi-record sequence.
  static const int continuation = 0x01;

  /// Record is the last in a multi-record sequence.
  static const int lastInSequence = 0x02;

  /// Record contains a full page image.
  static const int fullPageImage = 0x04;

  /// Record is a redo-only record.
  static const int redoOnly = 0x08;
}

/// Constants for WAL checkpointing.
abstract final class WalCheckpointConstants {
  /// Default checkpoint interval in bytes.
  ///
  /// A checkpoint is triggered after this many bytes are written.
  static const int defaultIntervalBytes = 16 * 1024 * 1024; // 16 MB

  /// Default checkpoint interval in seconds.
  ///
  /// A checkpoint is triggered after this duration even if
  /// the byte threshold isn't reached.
  static const int defaultIntervalSeconds = 60;

  /// Minimum time between forced checkpoints.
  static const int minCheckpointIntervalMs = 1000;
}

/// Log Sequence Number (LSN) constants.
abstract final class LsnConstants {
  /// Invalid/null LSN value.
  static const int invalid = 0;

  /// First valid LSN (after header).
  static const int first = WalHeaderConstants.headerSize;
}
