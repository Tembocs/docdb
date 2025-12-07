import 'dart:typed_data';

import '../constants.dart';
import 'page_type.dart';

/// A fixed-size block of data representing a database page.
///
/// Pages are the fundamental unit of I/O in EntiDB's storage engine.
/// All disk reads and writes operate on complete pages, never partial data.
///
/// ## Page Structure
///
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │                    Page Header (16 bytes)                    │
/// ├──────────────────────────────────────────────────────────────┤
/// │  Page ID (4)  │ Type (1) │ Flags (1) │ FreeOff (2) │ CRC (4) │ Reserved (4) │
/// ├──────────────────────────────────────────────────────────────┤
/// │                                                              │
/// │                      Data Area                               │
/// │                   (pageSize - 16 bytes)                      │
/// │                                                              │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// // Create a new page
/// final page = Page.create(pageId: 1, pageSize: 4096, type: PageType.data);
///
/// // Write data
/// page.writeInt32(offset, value);
/// page.writeString(offset, 'hello');
///
/// // Read data
/// final value = page.readInt32(offset);
/// final text = page.readString(offset, maxLength);
///
/// // Check if modified
/// if (page.isDirty) {
///   await pager.writePage(page);
/// }
/// ```
///
/// ## Thread Safety
///
/// Pages are NOT thread-safe. The [BufferManager] is responsible for
/// coordinating access to pages across multiple threads/isolates.
class Page {
  /// The unique identifier for this page within the database file.
  final int pageId;

  /// The size of this page in bytes.
  final int pageSize;

  /// The raw byte buffer containing page data.
  final ByteData _data;

  /// Whether this page has been modified since last flush.
  bool _isDirty = false;

  /// The pin count for this page in the buffer pool.
  ///
  /// A page with pinCount > 0 cannot be evicted from the buffer.
  int _pinCount = 0;

  /// Creates a new page with the given ID and size.
  ///
  /// The page is initialized with zeros and marked as dirty.
  ///
  /// - [pageId]: Unique identifier for this page
  /// - [pageSize]: Size in bytes (must be power of 2, >= 4096)
  /// - [type]: The type of page (data, index, etc.)
  factory Page.create({
    required int pageId,
    int pageSize = PageConstants.defaultPageSize,
    PageType type = PageType.data,
  }) {
    _validatePageSize(pageSize);

    final buffer = Uint8List(pageSize);
    final page = Page._(pageId, pageSize, ByteData.sublistView(buffer));

    // Initialize header
    page._writePageId(pageId);
    page._writePageType(type);
    page._writeFlags(0);
    page._writeFreeSpaceOffset(PageConstants.pageHeaderSize);
    page._isDirty = true;

    return page;
  }

  /// Creates a page from existing raw bytes.
  ///
  /// Used when reading pages from disk. The page is NOT marked as dirty.
  ///
  /// - [pageId]: The page ID (should match the ID stored in the buffer)
  /// - [buffer]: Raw page bytes (must be exactly [pageSize] bytes)
  /// - [pageSize]: Expected page size
  ///
  /// Throws [ArgumentError] if buffer size doesn't match page size.
  factory Page.fromBytes({
    required int pageId,
    required Uint8List buffer,
    int pageSize = PageConstants.defaultPageSize,
  }) {
    if (buffer.length != pageSize) {
      throw ArgumentError(
        'Buffer size (${buffer.length}) does not match page size ($pageSize)',
      );
    }

    return Page._(pageId, pageSize, ByteData.sublistView(buffer));
  }

  Page._(this.pageId, this.pageSize, this._data);

  /// Validates that the page size is acceptable.
  static void _validatePageSize(int pageSize) {
    if (pageSize < PageConstants.minPageSize) {
      throw ArgumentError(
        'Page size ($pageSize) is less than minimum (${PageConstants.minPageSize})',
      );
    }
    if (pageSize > PageConstants.maxPageSize) {
      throw ArgumentError(
        'Page size ($pageSize) exceeds maximum (${PageConstants.maxPageSize})',
      );
    }
    // Check if power of 2
    if (pageSize & (pageSize - 1) != 0) {
      throw ArgumentError('Page size ($pageSize) must be a power of 2');
    }
  }

  // ============================================================
  // Header Access
  // ============================================================

  /// The type of this page.
  PageType get type =>
      PageType.fromValue(_data.getUint8(PageHeaderOffsets.pageType));

  /// The flags set on this page.
  int get flags => _data.getUint8(PageHeaderOffsets.flags);

  /// The offset where free space begins in the data area.
  int get freeSpaceOffset =>
      _data.getUint16(PageHeaderOffsets.freeSpaceOffset, Endian.little);

  /// The amount of free space available in this page.
  int get freeSpace => pageSize - freeSpaceOffset;

  /// The stored checksum for this page.
  int get storedChecksum =>
      _data.getUint32(PageHeaderOffsets.checksum, Endian.little);

  /// Whether this page has been modified since last flush.
  bool get isDirty => _isDirty;

  /// The current pin count.
  int get pinCount => _pinCount;

  /// Whether this page is currently pinned (cannot be evicted).
  bool get isPinned => _pinCount > 0;

  /// The usable data area size (page size minus header).
  int get dataAreaSize => pageSize - PageConstants.pageHeaderSize;

  /// The start offset of the data area.
  int get dataAreaStart => PageConstants.pageHeaderSize;

  // ============================================================
  // Header Modification (internal)
  // ============================================================

  void _writePageId(int id) {
    _data.setUint32(PageHeaderOffsets.pageId, id, Endian.little);
  }

  void _writePageType(PageType type) {
    _data.setUint8(PageHeaderOffsets.pageType, type.value);
  }

  void _writeFlags(int flags) {
    _data.setUint8(PageHeaderOffsets.flags, flags);
  }

  void _writeFreeSpaceOffset(int offset) {
    _data.setUint16(PageHeaderOffsets.freeSpaceOffset, offset, Endian.little);
  }

  /// Updates the page type.
  void setType(PageType type) {
    _writePageType(type);
    _isDirty = true;
  }

  /// Sets a flag on this page.
  void setFlag(int flag) {
    final current = flags;
    _writeFlags(current | flag);
    _isDirty = true;
  }

  /// Clears a flag on this page.
  void clearFlag(int flag) {
    final current = flags;
    _writeFlags(current & ~flag);
    _isDirty = true;
  }

  /// Checks if a specific flag is set.
  bool hasFlag(int flag) => (flags & flag) != 0;

  /// Updates the free space offset.
  void setFreeSpaceOffset(int offset) {
    if (offset < PageConstants.pageHeaderSize || offset > pageSize) {
      throw RangeError.range(
        offset,
        PageConstants.pageHeaderSize,
        pageSize,
        'offset',
        'Free space offset out of valid range',
      );
    }
    _writeFreeSpaceOffset(offset);
    _isDirty = true;
  }

  // ============================================================
  // Pin Management
  // ============================================================

  /// Increments the pin count.
  ///
  /// Pinned pages cannot be evicted from the buffer pool.
  void pin() {
    _pinCount++;
  }

  /// Decrements the pin count.
  ///
  /// Throws [StateError] if the page is not currently pinned.
  void unpin() {
    if (_pinCount <= 0) {
      throw StateError('Cannot unpin page $pageId: not currently pinned');
    }
    _pinCount--;
  }

  // ============================================================
  // Primitive Read Operations
  // ============================================================

  /// Reads a signed 8-bit integer at the given offset.
  int readInt8(int offset) {
    _validateOffset(offset, 1);
    return _data.getInt8(offset);
  }

  /// Reads an unsigned 8-bit integer at the given offset.
  int readUint8(int offset) {
    _validateOffset(offset, 1);
    return _data.getUint8(offset);
  }

  /// Reads a signed 16-bit integer at the given offset (little-endian).
  int readInt16(int offset) {
    _validateOffset(offset, 2);
    return _data.getInt16(offset, Endian.little);
  }

  /// Reads an unsigned 16-bit integer at the given offset (little-endian).
  int readUint16(int offset) {
    _validateOffset(offset, 2);
    return _data.getUint16(offset, Endian.little);
  }

  /// Reads a signed 32-bit integer at the given offset (little-endian).
  int readInt32(int offset) {
    _validateOffset(offset, 4);
    return _data.getInt32(offset, Endian.little);
  }

  /// Reads an unsigned 32-bit integer at the given offset (little-endian).
  int readUint32(int offset) {
    _validateOffset(offset, 4);
    return _data.getUint32(offset, Endian.little);
  }

  /// Reads a signed 64-bit integer at the given offset (little-endian).
  int readInt64(int offset) {
    _validateOffset(offset, 8);
    return _data.getInt64(offset, Endian.little);
  }

  /// Reads an unsigned 64-bit integer at the given offset (little-endian).
  int readUint64(int offset) {
    _validateOffset(offset, 8);
    // Dart doesn't have getUint64, use getInt64 and interpret as unsigned
    return _data.getInt64(offset, Endian.little);
  }

  /// Reads a 32-bit floating point number at the given offset.
  double readFloat32(int offset) {
    _validateOffset(offset, 4);
    return _data.getFloat32(offset, Endian.little);
  }

  /// Reads a 64-bit floating point number at the given offset.
  double readFloat64(int offset) {
    _validateOffset(offset, 8);
    return _data.getFloat64(offset, Endian.little);
  }

  /// Reads raw bytes at the given offset.
  ///
  /// Returns a view into the page buffer. Modifications to the returned
  /// bytes will affect the page content.
  Uint8List readBytes(int offset, int length) {
    _validateOffset(offset, length);
    return Uint8List.sublistView(_data, offset, offset + length);
  }

  /// Reads a length-prefixed string at the given offset.
  ///
  /// Format: 2-byte length (little-endian) followed by UTF-8 bytes.
  ///
  /// Returns a tuple of (string, bytesRead).
  (String, int) readString(int offset) {
    final length = readUint16(offset);
    if (length == 0) {
      return ('', 2);
    }
    final bytes = readBytes(offset + 2, length);
    final string = String.fromCharCodes(bytes);
    return (string, 2 + length);
  }

  /// Reads a null-terminated string at the given offset.
  ///
  /// Scans for a null byte (0x00) up to [maxLength] bytes.
  String readNullTerminatedString(int offset, int maxLength) {
    _validateOffset(offset, 1);

    final endOffset = offset + maxLength;
    if (endOffset > pageSize) {
      throw RangeError('String read would exceed page bounds');
    }

    int length = 0;
    while (offset + length < endOffset &&
        _data.getUint8(offset + length) != 0) {
      length++;
    }

    if (length == 0) {
      return '';
    }

    return String.fromCharCodes(readBytes(offset, length));
  }

  // ============================================================
  // Primitive Write Operations
  // ============================================================

  /// Writes a signed 8-bit integer at the given offset.
  void writeInt8(int offset, int value) {
    _validateOffset(offset, 1);
    _data.setInt8(offset, value);
    _isDirty = true;
  }

  /// Writes an unsigned 8-bit integer at the given offset.
  void writeUint8(int offset, int value) {
    _validateOffset(offset, 1);
    _data.setUint8(offset, value);
    _isDirty = true;
  }

  /// Writes a signed 16-bit integer at the given offset (little-endian).
  void writeInt16(int offset, int value) {
    _validateOffset(offset, 2);
    _data.setInt16(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes an unsigned 16-bit integer at the given offset (little-endian).
  void writeUint16(int offset, int value) {
    _validateOffset(offset, 2);
    _data.setUint16(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes a signed 32-bit integer at the given offset (little-endian).
  void writeInt32(int offset, int value) {
    _validateOffset(offset, 4);
    _data.setInt32(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes an unsigned 32-bit integer at the given offset (little-endian).
  void writeUint32(int offset, int value) {
    _validateOffset(offset, 4);
    _data.setUint32(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes a signed 64-bit integer at the given offset (little-endian).
  void writeInt64(int offset, int value) {
    _validateOffset(offset, 8);
    _data.setInt64(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes a 32-bit floating point number at the given offset.
  void writeFloat32(int offset, double value) {
    _validateOffset(offset, 4);
    _data.setFloat32(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes a 64-bit floating point number at the given offset.
  void writeFloat64(int offset, double value) {
    _validateOffset(offset, 8);
    _data.setFloat64(offset, value, Endian.little);
    _isDirty = true;
  }

  /// Writes raw bytes at the given offset.
  void writeBytes(int offset, Uint8List bytes) {
    _validateOffset(offset, bytes.length);
    final view = Uint8List.sublistView(_data);
    view.setRange(offset, offset + bytes.length, bytes);
    _isDirty = true;
  }

  /// Writes a length-prefixed string at the given offset.
  ///
  /// Format: 2-byte length (little-endian) followed by UTF-8 bytes.
  ///
  /// Returns the number of bytes written.
  ///
  /// Throws [ArgumentError] if the string is too long (> 65535 bytes).
  int writeString(int offset, String value) {
    final bytes = Uint8List.fromList(value.codeUnits);
    if (bytes.length > 65535) {
      throw ArgumentError('String too long: ${bytes.length} bytes (max 65535)');
    }

    final totalLength = 2 + bytes.length;
    _validateOffset(offset, totalLength);

    writeUint16(offset, bytes.length);
    if (bytes.isNotEmpty) {
      writeBytes(offset + 2, bytes);
    }

    return totalLength;
  }

  /// Writes a null-terminated string at the given offset.
  ///
  /// Returns the number of bytes written (including null terminator).
  int writeNullTerminatedString(int offset, String value) {
    final bytes = Uint8List.fromList(value.codeUnits);
    final totalLength = bytes.length + 1;
    _validateOffset(offset, totalLength);

    if (bytes.isNotEmpty) {
      writeBytes(offset, bytes);
    }
    writeUint8(offset + bytes.length, 0); // Null terminator

    return totalLength;
  }

  /// Fills a range with zeros.
  void clear(int offset, int length) {
    _validateOffset(offset, length);
    final view = Uint8List.sublistView(_data);
    view.fillRange(offset, offset + length, 0);
    _isDirty = true;
  }

  // ============================================================
  // Checksum Operations
  // ============================================================

  /// Computes the CRC32 checksum of the page data.
  ///
  /// The checksum covers all bytes except the checksum field itself.
  int computeChecksum() {
    var crc = ChecksumConstants.crc32Initial;
    final bytes = Uint8List.sublistView(_data);

    for (var i = 0; i < pageSize; i++) {
      // Skip the checksum field (bytes 8-11)
      if (i >= PageHeaderOffsets.checksum &&
          i < PageHeaderOffsets.checksum + 4) {
        continue;
      }

      crc ^= bytes[i];
      for (var j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ ChecksumConstants.crc32Polynomial;
        } else {
          crc >>= 1;
        }
      }
    }

    return crc ^ ChecksumConstants.crc32Initial;
  }

  /// Updates the stored checksum to match the current page content.
  void updateChecksum() {
    final checksum = computeChecksum();
    _data.setUint32(PageHeaderOffsets.checksum, checksum, Endian.little);
  }

  /// Verifies that the stored checksum matches the computed checksum.
  ///
  /// Returns `true` if the checksums match, `false` if corrupted.
  bool verifyChecksum() {
    return storedChecksum == computeChecksum();
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  /// Returns a copy of the raw page bytes.
  ///
  /// Use this when writing the page to disk.
  Uint8List toBytes() {
    return Uint8List.fromList(Uint8List.sublistView(_data));
  }

  /// Marks this page as clean (not dirty).
  ///
  /// Called after successfully writing the page to disk.
  void markClean() {
    _isDirty = false;
  }

  /// Marks this page as dirty (modified).
  void markDirty() {
    _isDirty = true;
  }

  /// Validates that an offset and length are within page bounds.
  void _validateOffset(int offset, int length) {
    if (offset < 0) {
      throw RangeError.value(offset, 'offset', 'Offset cannot be negative');
    }
    if (length < 0) {
      throw RangeError.value(length, 'length', 'Length cannot be negative');
    }
    if (offset + length > pageSize) {
      throw RangeError(
        'Access at offset $offset with length $length exceeds page size $pageSize',
      );
    }
  }

  @override
  String toString() {
    return 'Page(id: $pageId, type: $type, dirty: $isDirty, '
        'pinCount: $pinCount, freeSpace: $freeSpace)';
  }
}
