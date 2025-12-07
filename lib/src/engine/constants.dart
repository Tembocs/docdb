/// Engine-wide constants for EntiDB storage engine.
///
/// This file defines all constants used by the low-level storage engine,
/// including page sizes, header offsets, magic numbers, and limits.
///
/// These constants are carefully chosen to balance performance, storage
/// efficiency, and compatibility across platforms.
library;

/// Constants for page-based storage configuration.
///
/// The page size determines the fundamental unit of I/O for the database.
/// All reads and writes are performed in page-sized chunks.
abstract final class PageConstants {
  /// Default page size in bytes (4 KB).
  ///
  /// This value is chosen to:
  /// - Match common filesystem block sizes
  /// - Fit well in CPU cache lines
  /// - Balance between I/O efficiency and memory usage
  ///
  /// Supported values: 4096, 8192, 16384, 32768
  static const int defaultPageSize = 4096;

  /// Minimum supported page size in bytes (4 KB).
  static const int minPageSize = 4096;

  /// Maximum supported page size in bytes (32 KB).
  static const int maxPageSize = 32768;

  /// Size of the page header in bytes.
  ///
  /// The header contains:
  /// - Page ID (4 bytes)
  /// - Page type (1 byte)
  /// - Flags (1 byte)
  /// - Free space offset (2 bytes)
  /// - Checksum (4 bytes)
  /// - Reserved (4 bytes)
  static const int pageHeaderSize = 16;

  /// Maximum usable space per page (page size minus header).
  static int usableSpace(int pageSize) => pageSize - pageHeaderSize;
}

/// Offsets within the page header.
///
/// These offsets define where each field is located within the
/// 16-byte page header structure.
abstract final class PageHeaderOffsets {
  /// Offset of the page ID field (4 bytes, unsigned int).
  static const int pageId = 0;

  /// Offset of the page type field (1 byte).
  static const int pageType = 4;

  /// Offset of the flags field (1 byte).
  static const int flags = 5;

  /// Offset of the free space pointer (2 bytes, unsigned short).
  ///
  /// Points to the start of free space within the page's data area.
  static const int freeSpaceOffset = 6;

  /// Offset of the checksum field (4 bytes, CRC32).
  static const int checksum = 8;

  /// Offset of reserved space (4 bytes, for future use).
  static const int reserved = 12;
}

/// Page flag bit masks.
///
/// Flags are stored in a single byte and can be combined using bitwise OR.
abstract final class PageFlags {
  /// Page has been modified and needs to be written to disk.
  static const int dirty = 0x01;

  /// Page is pinned in the buffer pool and cannot be evicted.
  static const int pinned = 0x02;

  /// Page contains deleted data awaiting vacuum.
  static const int deleted = 0x04;

  /// Page is part of an overflow chain.
  static const int overflow = 0x08;

  /// Page is compressed.
  static const int compressed = 0x10;

  /// Page is encrypted.
  static const int encrypted = 0x20;
}

/// Constants for the database file header (Page 0).
///
/// The header page contains metadata about the database file,
/// including version information, configuration, and pointers
/// to critical data structures.
abstract final class FileHeaderConstants {
  /// Magic number identifying EntiDB files.
  ///
  /// ASCII: "DCDB" (0x44 0x43 0x44 0x42)
  static const int magicNumber = 0x44434442;

  /// Current database file format version.
  ///
  /// Increment this when making incompatible changes to the file format.
  static const int currentVersion = 1;

  /// Minimum supported file format version for reading.
  static const int minReadVersion = 1;

  /// Size of the file header in bytes.
  static const int headerSize = 128;
}

/// Offsets within the database file header (Page 0).
///
/// The file header is stored at the beginning of Page 0 and contains
/// critical metadata for opening and validating the database file.
abstract final class FileHeaderOffsets {
  /// Magic number for file identification (4 bytes).
  static const int magic = 0;

  /// File format version (4 bytes).
  static const int version = 4;

  /// Page size used in this database (4 bytes).
  static const int pageSize = 8;

  /// Total number of pages in the file (4 bytes).
  static const int pageCount = 12;

  /// Page ID of the first free page (4 bytes, 0 if none).
  static const int freeListHead = 16;

  /// Number of free pages available (4 bytes).
  static const int freePageCount = 20;

  /// Page ID of the schema root page (4 bytes).
  static const int schemaRoot = 24;

  /// Database creation timestamp (8 bytes, Unix milliseconds).
  static const int createdAt = 28;

  /// Last modification timestamp (8 bytes, Unix milliseconds).
  static const int modifiedAt = 36;

  /// Encryption salt (16 bytes, for key derivation).
  static const int encryptionSalt = 44;

  /// Flags (4 bytes).
  static const int flags = 60;

  /// Reserved space for future use (64 bytes).
  static const int reserved = 64;
}

/// File header flag bit masks.
abstract final class FileHeaderFlags {
  /// Database is encrypted.
  static const int encrypted = 0x01;

  /// Database uses compression.
  static const int compressed = 0x02;

  /// Database was not closed cleanly (requires recovery).
  static const int dirtyShutdown = 0x04;

  /// Write-ahead log is enabled.
  static const int walEnabled = 0x08;
}

/// Constants for the buffer manager.
abstract final class BufferConstants {
  /// Default buffer pool size (number of pages).
  ///
  /// At 4KB per page, 1024 pages = 4MB buffer pool.
  static const int defaultPoolSize = 1024;

  /// Minimum buffer pool size.
  static const int minPoolSize = 16;

  /// Maximum buffer pool size.
  static const int maxPoolSize = 1048576; // 1M pages = 4GB at 4KB/page

  /// Percentage of buffer pool to flush when full (0.0 to 1.0).
  static const double flushRatio = 0.25;
}

/// Constants for slot-based page organization.
///
/// Data pages use a slotted page structure where:
/// - Slot directory grows from the page header downward
/// - Record data grows from the end of the page upward
abstract final class SlotConstants {
  /// Size of each slot entry in bytes.
  ///
  /// Each slot contains:
  /// - Offset to record data (2 bytes)
  /// - Record length (2 bytes)
  static const int slotSize = 4;

  /// Slot offset field size (2 bytes, unsigned short).
  static const int offsetFieldSize = 2;

  /// Slot length field size (2 bytes, unsigned short).
  static const int lengthFieldSize = 2;

  /// Maximum record size that fits in a single page.
  ///
  /// Calculated as: pageSize - headerSize - slotSize
  static int maxRecordSize(int pageSize) =>
      pageSize - PageConstants.pageHeaderSize - slotSize;

  /// Marker for deleted slots (offset = 0xFFFF).
  static const int deletedSlotMarker = 0xFFFF;
}

/// Constants for overflow page handling.
///
/// Records larger than a single page are split across overflow pages.
abstract final class OverflowConstants {
  /// Size of the overflow page header (in addition to standard page header).
  ///
  /// Contains:
  /// - Next overflow page ID (4 bytes, 0 if last)
  /// - Data length in this page (4 bytes)
  static const int overflowHeaderSize = 8;

  /// Offset of next overflow page pointer.
  static const int nextPageOffset = 0;

  /// Offset of data length field.
  static const int dataLengthOffset = 4;

  /// Usable space in an overflow page.
  static int usableSpace(int pageSize) =>
      pageSize - PageConstants.pageHeaderSize - overflowHeaderSize;
}

/// Special page IDs with reserved meanings.
abstract final class SpecialPageIds {
  /// Invalid page ID (used as null marker).
  static const int invalid = 0xFFFFFFFF;

  /// File header page ID.
  static const int fileHeader = 0;

  /// First allocatable page ID.
  static const int firstAllocatable = 1;
}

/// Limits for the storage engine.
abstract final class EngineLimits {
  /// Maximum number of pages in a database file.
  ///
  /// At 4KB per page, this allows up to 16TB database files.
  static const int maxPages = 0xFFFFFFFE; // ~4 billion pages

  /// Maximum size of a single record in bytes.
  ///
  /// Records larger than this must be stored externally.
  static const int maxRecordSize = 1073741824; // 1GB

  /// Maximum number of collections in a database.
  static const int maxCollections = 65536;

  /// Maximum length of a collection name in bytes.
  static const int maxCollectionNameLength = 255;

  /// Maximum depth of nested documents.
  static const int maxNestingDepth = 100;
}

/// Checksum constants.
abstract final class ChecksumConstants {
  /// CRC32 polynomial (IEEE 802.3).
  static const int crc32Polynomial = 0xEDB88320;

  /// Initial CRC32 value.
  static const int crc32Initial = 0xFFFFFFFF;
}
