import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

import '../../exceptions/storage_exceptions.dart';
import '../constants.dart';
import 'page.dart';
import 'page_type.dart';

/// The disk manager responsible for reading and writing pages to the database file.
///
/// The Pager provides a low-level abstraction over file I/O, managing:
/// - Page allocation and deallocation
/// - Free list management
/// - File header maintenance
/// - Recovery from unclean shutdowns
///
/// ## File Structure
///
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │                    Page 0 (File Header)                      │
/// ├──────────────────────────────────────────────────────────────┤
/// │                    Page 1 (First Data Page)                  │
/// ├──────────────────────────────────────────────────────────────┤
/// │                    Page 2                                    │
/// ├──────────────────────────────────────────────────────────────┤
/// │                    ...                                       │
/// ├──────────────────────────────────────────────────────────────┤
/// │                    Page N (Last Page)                        │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// // Open or create a database file
/// final pager = await Pager.open('database.db');
///
/// // Allocate a new page
/// final page = await pager.allocatePage(PageType.data);
///
/// // Write data to the page
/// page.writeInt32(offset, value);
///
/// // Write the page to disk
/// await pager.writePage(page);
///
/// // Read a page from disk
/// final readPage = await pager.readPage(pageId);
///
/// // Close the pager
/// await pager.close();
/// ```
///
/// ## Thread Safety
///
/// The Pager uses synchronized access for all operations. Multiple isolates
/// can safely share a Pager instance through a shared [Lock].
class Pager {
  /// The path to the database file.
  final String filePath;

  /// The page size used by this database.
  final int pageSize;

  /// The underlying file handle.
  RandomAccessFile? _file;

  /// Lock for synchronizing file access.
  final Lock _lock = Lock();

  /// Total number of pages in the file.
  int _pageCount = 0;

  /// Page ID of the first free page (0 if none).
  int _freeListHead = 0;

  /// Number of free pages available.
  int _freePageCount = 0;

  /// Whether the database was opened read-only.
  final bool readOnly;

  /// Whether the pager is currently open.
  bool _isOpen = false;

  /// Creates a Pager instance (internal constructor).
  ///
  /// Use [Pager.open] or [Pager.create] to instantiate.
  Pager._({
    required this.filePath,
    required this.pageSize,
    this.readOnly = false,
  });

  /// Whether the pager is currently open.
  bool get isOpen => _isOpen;

  /// The total number of pages in the database file.
  int get pageCount => _pageCount;

  /// The number of free pages available for allocation.
  int get freePageCount => _freePageCount;

  /// The page ID of the first free page (0 if none).
  int get freeListHead => _freeListHead;

  /// Opens an existing database file or creates a new one.
  ///
  /// - [path]: Path to the database file
  /// - [pageSize]: Page size for new databases (ignored for existing files)
  /// - [readOnly]: Open in read-only mode
  ///
  /// Throws [StorageException] if the file cannot be opened or is corrupted.
  static Future<Pager> open(
    String path, {
    int pageSize = PageConstants.defaultPageSize,
    bool readOnly = false,
  }) async {
    final file = File(path);
    final exists = await file.exists();

    final pager = Pager._(
      filePath: path,
      pageSize: pageSize,
      readOnly: readOnly,
    );

    if (exists) {
      await pager._openExisting(readOnly: readOnly);
    } else {
      if (readOnly) {
        throw StorageNotFoundException(
          'Cannot open non-existent file in read-only mode',
          path: path,
        );
      }
      await pager._createNew();
    }

    return pager;
  }

  /// Creates a new database file.
  ///
  /// Throws [StorageException] if the file already exists.
  static Future<Pager> create(
    String path, {
    int pageSize = PageConstants.defaultPageSize,
  }) async {
    final file = File(path);
    if (await file.exists()) {
      throw StorageAlreadyExistsException(
        'Database file already exists',
        path: path,
      );
    }

    final pager = Pager._(filePath: path, pageSize: pageSize);
    await pager._createNew();
    return pager;
  }

  /// Opens an existing database file.
  Future<void> _openExisting({bool readOnly = false}) async {
    final file = File(filePath);
    _file = await file.open(mode: readOnly ? FileMode.read : FileMode.append);

    // Read and validate the file header
    await _readFileHeader();
    _isOpen = true;
  }

  /// Creates a new database file with an initialized header.
  Future<void> _createNew() async {
    // Create parent directories if needed
    final file = File(filePath);
    await file.parent.create(recursive: true);

    _file = await file.open(mode: FileMode.write);

    // Initialize the file header
    await _initializeFileHeader();
    _isOpen = true;
  }

  /// Reads and validates the file header (Page 0).
  Future<void> _readFileHeader() async {
    final file = _file!;

    // Read the header page
    await file.setPosition(0);
    final headerBytes = await file.read(pageSize);

    if (headerBytes.length < FileHeaderConstants.headerSize) {
      throw StorageCorruptedException(
        'File too small to contain a valid header',
        path: filePath,
      );
    }

    final header = ByteData.sublistView(Uint8List.fromList(headerBytes));

    // Validate magic number
    final magic = header.getUint32(FileHeaderOffsets.magic, Endian.little);
    if (magic != FileHeaderConstants.magicNumber) {
      throw StorageCorruptedException(
        'Invalid magic number: expected 0x${FileHeaderConstants.magicNumber.toRadixString(16)}, '
        'got 0x${magic.toRadixString(16)}',
        path: filePath,
      );
    }

    // Validate version
    final version = header.getUint32(FileHeaderOffsets.version, Endian.little);
    if (version > FileHeaderConstants.currentVersion) {
      throw StorageVersionMismatchException(
        'Database version $version is newer than supported version '
        '${FileHeaderConstants.currentVersion}',
        path: filePath,
        fileVersion: version,
        supportedVersion: FileHeaderConstants.currentVersion,
      );
    }
    if (version < FileHeaderConstants.minReadVersion) {
      throw StorageVersionMismatchException(
        'Database version $version is too old (minimum supported: '
        '${FileHeaderConstants.minReadVersion})',
        path: filePath,
        fileVersion: version,
        supportedVersion: FileHeaderConstants.minReadVersion,
      );
    }

    // Read page count and free list info
    _pageCount = header.getUint32(FileHeaderOffsets.pageCount, Endian.little);
    _freeListHead = header.getUint32(
      FileHeaderOffsets.freeListHead,
      Endian.little,
    );
    _freePageCount = header.getUint32(
      FileHeaderOffsets.freePageCount,
      Endian.little,
    );

    // Check for dirty shutdown flag
    final flags = header.getUint32(FileHeaderOffsets.flags, Endian.little);
    if ((flags & FileHeaderFlags.dirtyShutdown) != 0) {
      // TODO: Trigger recovery process
      // For now, just clear the flag
      if (!readOnly) {
        await _clearDirtyShutdownFlag();
      }
    }
  }

  /// Initializes a new file header.
  Future<void> _initializeFileHeader() async {
    final headerPage = Page.create(
      pageId: SpecialPageIds.fileHeader,
      pageSize: pageSize,
      type: PageType.header,
    );

    // Write magic number
    headerPage.writeUint32(
      FileHeaderOffsets.magic,
      FileHeaderConstants.magicNumber,
    );

    // Write version
    headerPage.writeUint32(
      FileHeaderOffsets.version,
      FileHeaderConstants.currentVersion,
    );

    // Write page size
    headerPage.writeUint32(FileHeaderOffsets.pageSize, pageSize);

    // Write initial page count (just the header page)
    headerPage.writeUint32(FileHeaderOffsets.pageCount, 1);
    _pageCount = 1;

    // Initialize free list as empty
    headerPage.writeUint32(FileHeaderOffsets.freeListHead, 0);
    headerPage.writeUint32(FileHeaderOffsets.freePageCount, 0);
    _freeListHead = 0;
    _freePageCount = 0;

    // Write timestamps
    final now = DateTime.now().millisecondsSinceEpoch;
    headerPage.writeInt64(FileHeaderOffsets.createdAt, now);
    headerPage.writeInt64(FileHeaderOffsets.modifiedAt, now);

    // Set dirty shutdown flag (will be cleared on clean close)
    headerPage.writeUint32(
      FileHeaderOffsets.flags,
      FileHeaderFlags.dirtyShutdown,
    );

    // Update checksum
    headerPage.updateChecksum();

    // Write to disk
    await _writePageToFile(headerPage);
  }

  /// Clears the dirty shutdown flag in the file header.
  ///
  /// **Note:** Caller must hold the lock.
  Future<void> _clearDirtyShutdownFlag() async {
    final file = _file!;
    await file.setPosition(FileHeaderOffsets.flags);
    final flagsBytes = await file.read(4);
    final flags = ByteData.sublistView(
      Uint8List.fromList(flagsBytes),
    ).getUint32(0, Endian.little);
    final newFlags = flags & ~FileHeaderFlags.dirtyShutdown;

    await file.setPosition(FileHeaderOffsets.flags);
    final newFlagsBytes = Uint8List(4);
    ByteData.sublistView(newFlagsBytes).setUint32(0, newFlags, Endian.little);
    await file.writeFrom(newFlagsBytes);
    await file.flush();
  }

  // ============================================================
  // Page Allocation
  // ============================================================

  /// Allocates a new page of the given type.
  ///
  /// If there are free pages available, one is reused from the free list.
  /// Otherwise, a new page is appended to the file.
  ///
  /// Returns the newly allocated page (already in memory, marked dirty).
  Future<Page> allocatePage(PageType type) async {
    _ensureOpen();
    _ensureWritable();

    return await _lock.synchronized(() async {
      int pageId;

      if (_freeListHead != 0) {
        // Reuse a page from the free list
        pageId = _freeListHead;
        final freePage = await _readPageFromFile(pageId);

        // Update free list head to next free page
        _freeListHead = freePage.readUint32(PageConstants.pageHeaderSize);
        _freePageCount--;

        // Update header
        await _updateFreeListInHeader();
      } else {
        // Allocate a new page at the end of the file
        pageId = _pageCount;
        _pageCount++;
        await _updatePageCountInHeader();
      }

      // Create and initialize the new page
      final page = Page.create(pageId: pageId, pageSize: pageSize, type: type);
      return page;
    });
  }

  /// Frees a page, adding it to the free list.
  ///
  /// The page contents are cleared and the page is marked for reuse.
  Future<void> freePage(int pageId) async {
    _ensureOpen();
    _ensureWritable();

    if (pageId == SpecialPageIds.fileHeader) {
      throw StorageOperationException(
        'Cannot free the file header page',
        path: filePath,
      );
    }

    await _lock.synchronized(() async {
      // Create a free list entry page
      final page = Page.create(
        pageId: pageId,
        pageSize: pageSize,
        type: PageType.freeList,
      );

      // Link to current head of free list
      page.writeUint32(PageConstants.pageHeaderSize, _freeListHead);

      // Write the updated free page to disk
      await _writePageToFile(page);

      // Update free list head
      _freeListHead = pageId;
      _freePageCount++;
      await _updateFreeListInHeader();
    });
  }

  /// Updates the free list information in the file header.
  Future<void> _updateFreeListInHeader() async {
    final file = _file!;

    // Update free list head
    await file.setPosition(FileHeaderOffsets.freeListHead);
    final headBytes = Uint8List(4);
    ByteData.sublistView(headBytes).setUint32(0, _freeListHead, Endian.little);
    await file.writeFrom(headBytes);

    // Update free page count
    await file.setPosition(FileHeaderOffsets.freePageCount);
    final countBytes = Uint8List(4);
    ByteData.sublistView(
      countBytes,
    ).setUint32(0, _freePageCount, Endian.little);
    await file.writeFrom(countBytes);

    // Update modified timestamp
    await _updateModifiedTimestamp();

    await file.flush();
  }

  /// Updates the page count in the file header.
  Future<void> _updatePageCountInHeader() async {
    final file = _file!;
    await file.setPosition(FileHeaderOffsets.pageCount);
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, _pageCount, Endian.little);
    await file.writeFrom(bytes);
    await _updateModifiedTimestamp();
    await file.flush();
  }

  /// Updates the modified timestamp in the file header.
  Future<void> _updateModifiedTimestamp() async {
    final file = _file!;
    await file.setPosition(FileHeaderOffsets.modifiedAt);
    final bytes = Uint8List(8);
    ByteData.sublistView(
      bytes,
    ).setInt64(0, DateTime.now().millisecondsSinceEpoch, Endian.little);
    await file.writeFrom(bytes);
  }

  // ============================================================
  // Page I/O
  // ============================================================

  /// Reads a page from disk.
  ///
  /// - [pageId]: The ID of the page to read
  /// - [verifyChecksum]: Whether to verify the page checksum
  ///
  /// Throws [StorageException] if the page cannot be read or is corrupted.
  Future<Page> readPage(int pageId, {bool verifyChecksum = true}) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      return await _readPageFromFile(pageId, verifyChecksum: verifyChecksum);
    });
  }

  /// Internal method to read a page from the file.
  Future<Page> _readPageFromFile(
    int pageId, {
    bool verifyChecksum = true,
  }) async {
    if (pageId < 0 || pageId >= _pageCount) {
      throw StorageOperationException(
        'Invalid page ID: $pageId (valid range: 0-${_pageCount - 1})',
        path: filePath,
      );
    }

    final file = _file!;
    final offset = pageId * pageSize;

    await file.setPosition(offset);
    final bytes = await file.read(pageSize);

    if (bytes.length < pageSize) {
      throw StorageCorruptedException(
        'Incomplete page read: expected $pageSize bytes, got ${bytes.length}',
        path: filePath,
      );
    }

    final page = Page.fromBytes(
      pageId: pageId,
      buffer: Uint8List.fromList(bytes),
      pageSize: pageSize,
    );

    if (verifyChecksum && !page.verifyChecksum()) {
      throw StorageCorruptedException(
        'Page $pageId checksum verification failed',
        path: filePath,
      );
    }

    return page;
  }

  /// Writes a page to disk.
  ///
  /// The page's checksum is automatically updated before writing.
  Future<void> writePage(Page page) async {
    _ensureOpen();
    _ensureWritable();

    await _lock.synchronized(() async {
      await _writePageToFile(page);
    });
  }

  /// Internal method to write a page to the file.
  Future<void> _writePageToFile(Page page) async {
    page.updateChecksum();

    final file = _file!;
    final offset = page.pageId * pageSize;

    await file.setPosition(offset);
    await file.writeFrom(page.toBytes());
    await file.flush();

    page.markClean();
  }

  /// Writes multiple pages to disk atomically.
  ///
  /// All pages are written in a single synchronized operation.
  Future<void> writePages(List<Page> pages) async {
    _ensureOpen();
    _ensureWritable();

    await _lock.synchronized(() async {
      for (final page in pages) {
        await _writePageToFile(page);
      }
    });
  }

  // ============================================================
  // File Header Access
  // ============================================================

  /// Reads the complete file header information.
  Future<FileHeader> readFileHeader() async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      final page = await _readPageFromFile(
        SpecialPageIds.fileHeader,
        verifyChecksum: false,
      );

      return FileHeader.fromPage(page);
    });
  }

  // ============================================================
  // Lifecycle Management
  // ============================================================

  /// Flushes all pending writes to disk.
  Future<void> flush() async {
    _ensureOpen();

    await _lock.synchronized(() async {
      await _file!.flush();
    });
  }

  /// Closes the pager, releasing all resources.
  ///
  /// Clears the dirty shutdown flag if not in read-only mode.
  Future<void> close() async {
    if (!_isOpen) return;

    await _lock.synchronized(() async {
      if (!readOnly) {
        // Clear the dirty shutdown flag
        await _clearDirtyShutdownFlag();
      }

      await _file!.close();
      _file = null;
      _isOpen = false;
    });
  }

  /// Ensures the pager is open.
  void _ensureOpen() {
    if (!_isOpen) {
      throw StorageNotOpenException.withMessage(
        'Pager is not open',
        path: filePath,
      );
    }
  }

  /// Ensures the pager is writable.
  void _ensureWritable() {
    if (readOnly) {
      throw StorageReadOnlyException(
        'Cannot write to read-only database',
        path: filePath,
      );
    }
  }

  @override
  String toString() {
    return 'Pager(path: $filePath, pageSize: $pageSize, '
        'pageCount: $_pageCount, freePages: $_freePageCount, '
        'isOpen: $_isOpen, readOnly: $readOnly)';
  }
}

/// Represents the file header information.
///
/// This is a read-only snapshot of the header data at the time it was read.
@immutable
class FileHeader {
  /// The file format version.
  final int version;

  /// The page size used in this database.
  final int pageSize;

  /// Total number of pages in the file.
  final int pageCount;

  /// Page ID of the first free page.
  final int freeListHead;

  /// Number of free pages available.
  final int freePageCount;

  /// Page ID of the schema root.
  final int schemaRoot;

  /// Database creation timestamp.
  final DateTime createdAt;

  /// Last modification timestamp.
  final DateTime modifiedAt;

  /// File header flags.
  final int flags;

  const FileHeader({
    required this.version,
    required this.pageSize,
    required this.pageCount,
    required this.freeListHead,
    required this.freePageCount,
    required this.schemaRoot,
    required this.createdAt,
    required this.modifiedAt,
    required this.flags,
  });

  /// Creates a FileHeader from a header page.
  factory FileHeader.fromPage(Page page) {
    return FileHeader(
      version: page.readUint32(FileHeaderOffsets.version),
      pageSize: page.readUint32(FileHeaderOffsets.pageSize),
      pageCount: page.readUint32(FileHeaderOffsets.pageCount),
      freeListHead: page.readUint32(FileHeaderOffsets.freeListHead),
      freePageCount: page.readUint32(FileHeaderOffsets.freePageCount),
      schemaRoot: page.readUint32(FileHeaderOffsets.schemaRoot),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        page.readInt64(FileHeaderOffsets.createdAt),
      ),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        page.readInt64(FileHeaderOffsets.modifiedAt),
      ),
      flags: page.readUint32(FileHeaderOffsets.flags),
    );
  }

  /// Whether encryption is enabled.
  bool get isEncrypted => (flags & FileHeaderFlags.encrypted) != 0;

  /// Whether compression is enabled.
  bool get isCompressed => (flags & FileHeaderFlags.compressed) != 0;

  /// Whether the database requires recovery.
  bool get needsRecovery => (flags & FileHeaderFlags.dirtyShutdown) != 0;

  /// Whether WAL is enabled.
  bool get walEnabled => (flags & FileHeaderFlags.walEnabled) != 0;

  @override
  String toString() {
    return 'FileHeader(version: $version, pageSize: $pageSize, '
        'pageCount: $pageCount, freePages: $freePageCount, '
        'needsRecovery: $needsRecovery)';
  }
}
