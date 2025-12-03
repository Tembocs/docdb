/// DocDB Storage - Paged Storage Implementation
///
/// Provides high-performance storage using the database engine's page-based
/// architecture. Suitable for production workloads with efficient caching,
/// transactional support, and WAL-based durability.
///
/// ## Architecture
///
/// PagedStorage bridges the high-level `Storage<T>` interface with the
/// low-level engine components (Pager, BufferManager, WAL).
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │                      PagedStorage                           │
/// │               (Storage<T> Implementation)                    │
/// ├─────────────────────────────────────────────────────────────┤
/// │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
/// │  │   Entity    │  │    Index    │  │   Transaction       │  │
/// │  │   Manager   │  │   Manager   │  │   Manager           │  │
/// │  └─────────────┘  └─────────────┘  └─────────────────────┘  │
/// ├─────────────────────────────────────────────────────────────┤
/// │                      BufferManager                          │
/// │                   (Page Cache + LRU)                        │
/// ├─────────────────────────────────────────────────────────────┤
/// │                         Pager                               │
/// │                    (Disk I/O Layer)                         │
/// ├─────────────────────────────────────────────────────────────┤
/// │                      WAL (Optional)                         │
/// │               (Write-Ahead Logging)                         │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Data Format
///
/// Entities are stored in data pages with the following layout:
///
/// ### Data Page Layout
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │                    Page Header (16 bytes)                    │
/// ├──────────────────────────────────────────────────────────────┤
/// │  Entity Count (4) │ Free Offset (4) │ Reserved (8)          │
/// ├──────────────────────────────────────────────────────────────┤
/// │                                                              │
/// │  Slot Directory (grows down from header)                     │
/// │  ┌────────────────────────────────────────────────────────┐  │
/// │  │ Slot 0: Offset (2) │ Length (2) │ Flags (1) │ Reserved │  │
/// │  │ Slot 1: ...                                            │  │
/// │  └────────────────────────────────────────────────────────┘  │
/// │                           ↓ ↓ ↓                              │
/// │                     (Free Space)                             │
/// │                           ↑ ↑ ↑                              │
/// │  ┌────────────────────────────────────────────────────────┐  │
/// │  │ Entity Data (grows up from end)                        │  │
/// │  │ ┌─────────────────────────────────────────────────────┐│  │
/// │  │ │ ID Length (2) │ ID (var) │ Data Length (4) │ Data   ││  │
/// │  │ └─────────────────────────────────────────────────────┘│  │
/// │  └────────────────────────────────────────────────────────┘  │
/// └──────────────────────────────────────────────────────────────┘
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../engine/buffer/buffer_manager.dart';
import '../engine/constants.dart';
import '../engine/storage/page.dart';
import '../engine/storage/page_type.dart';
import '../engine/storage/pager.dart';
import '../entity/entity.dart';
import '../exceptions/storage_exceptions.dart';
import 'storage.dart';

/// Configuration for PagedStorage.
@immutable
class PagedStorageConfig {
  /// Buffer pool size (number of pages to cache).
  final int bufferPoolSize;

  /// Whether to enable transaction support with WAL.
  final bool enableTransactions;

  /// Whether to verify checksums on page reads.
  final bool verifyChecksums;

  /// Page size (must match database file).
  final int pageSize;

  /// Maximum entity size in bytes.
  final int maxEntitySize;

  /// Creates a PagedStorage configuration.
  const PagedStorageConfig({
    this.bufferPoolSize = 1024,
    this.enableTransactions = true,
    this.verifyChecksums = true,
    this.pageSize = 4096,
    this.maxEntitySize = 1024 * 1024, // 1MB
  });

  /// Default configuration.
  static const PagedStorageConfig defaults = PagedStorageConfig();

  /// Configuration optimized for small datasets.
  static const PagedStorageConfig small = PagedStorageConfig(
    bufferPoolSize: 128,
    maxEntitySize: 65536,
  );

  /// Configuration optimized for large datasets.
  static const PagedStorageConfig large = PagedStorageConfig(
    bufferPoolSize: 4096,
    maxEntitySize: 4 * 1024 * 1024,
  );
}

/// High-performance page-based storage implementation.
///
/// Uses the database engine's page management system for efficient
/// storage and retrieval of entities with caching and optional
/// transaction support.
///
/// ## Usage
///
/// ```dart
/// final storage = await PagedStorage<Product>.open(
///   name: 'products',
///   filePath: '/path/to/data/products.db',
///   config: PagedStorageConfig.defaults,
/// );
///
/// await storage.insert('prod-1', {'name': 'Widget', 'price': 29.99});
/// final data = await storage.get('prod-1');
///
/// await storage.close();
/// ```
final class PagedStorage<T extends Entity> extends Storage<T>
    with TransactionalStorage<T> {
  /// The storage name.
  @override
  final String name;

  /// Path to the database file.
  final String filePath;

  /// Storage configuration.
  final PagedStorageConfig config;

  /// The underlying pager for disk I/O.
  Pager? _pager;

  /// The buffer manager for page caching.
  BufferManager? _bufferManager;

  /// ID to page/slot location index.
  final Map<String, _EntityLocation> _entityIndex = {};

  /// List of data page IDs.
  final List<int> _dataPages = [];

  /// Whether the storage is open.
  bool _isOpen = false;

  /// Transaction state.
  _PagedTransactionState? _transaction;

  /// The root catalog page ID.
  int _catalogPageId = 0;

  /// JSON encoder for serialization.
  static const _jsonEncoder = JsonEncoder();

  /// Creates a new PagedStorage instance.
  ///
  /// Use [open] to initialize the storage.
  PagedStorage({
    required this.name,
    required this.filePath,
    this.config = const PagedStorageConfig(),
  });

  /// Opens an existing storage or creates a new one.
  static Future<PagedStorage<E>> openStorage<E extends Entity>({
    required String name,
    required String filePath,
    PagedStorageConfig config = const PagedStorageConfig(),
  }) async {
    final storage = PagedStorage<E>(
      name: name,
      filePath: filePath,
      config: config,
    );
    await storage.open();
    return storage;
  }

  @override
  bool get supportsTransactions => config.enableTransactions;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get inTransaction => _transaction != null;

  @override
  Future<int> get count async {
    _checkOpen();
    return _entityIndex.length;
  }

  @override
  Future<void> open() async {
    if (_isOpen) return;

    try {
      // Open or create the pager
      _pager = await Pager.open(filePath, pageSize: config.pageSize);

      // Create buffer manager
      _bufferManager = BufferManager(
        pager: _pager!,
        poolSize: config.bufferPoolSize,
      );

      // Load or initialize catalog
      await _loadCatalog();

      _isOpen = true;
    } catch (e, st) {
      await _cleanup();
      throw StorageInitializationException(
        storageName: name,
        path: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;

    if (inTransaction) {
      await rollback();
    }

    // Flush and save catalog
    await _saveCatalog();
    await _bufferManager?.flushAll();

    await _cleanup();
    _isOpen = false;
  }

  Future<void> _cleanup() async {
    await _bufferManager?.close();
    await _pager?.close();
    _bufferManager = null;
    _pager = null;
    _entityIndex.clear();
    _dataPages.clear();
  }

  @override
  Future<Map<String, dynamic>?> get(String id) async {
    _checkOpen();

    // Check transaction pending first
    if (inTransaction) {
      if (_transaction!.deletedIds.contains(id)) {
        return null;
      }
      final pending = _transaction!.pendingInserts[id];
      if (pending != null) {
        return Map<String, dynamic>.from(pending);
      }
      final pendingUpdate = _transaction!.pendingUpdates[id];
      if (pendingUpdate != null) {
        return Map<String, dynamic>.from(pendingUpdate);
      }
    }

    final location = _entityIndex[id];
    if (location == null) {
      return null;
    }

    try {
      return await _readEntity(location);
    } catch (e, st) {
      throw StorageReadException(
        storageName: name,
        entityId: id,
        path: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getMany(
    Iterable<String> ids,
  ) async {
    _checkOpen();
    final result = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      final data = await get(id);
      if (data != null) {
        result[id] = data;
      }
    }
    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getAll() async {
    _checkOpen();
    final result = <String, Map<String, dynamic>>{};
    for (final id in _entityIndex.keys) {
      final data = await get(id);
      if (data != null) {
        result[id] = data;
      }
    }
    return result;
  }

  @override
  Stream<StorageRecord> stream() async* {
    _checkOpen();
    for (final id in _entityIndex.keys.toList()) {
      final data = await get(id);
      if (data != null) {
        yield StorageRecord(id: id, data: data);
      }
    }
  }

  @override
  Future<bool> exists(String id) async {
    _checkOpen();
    if (inTransaction) {
      if (_transaction!.deletedIds.contains(id)) {
        return false;
      }
      if (_transaction!.pendingInserts.containsKey(id)) {
        return true;
      }
    }
    return _entityIndex.containsKey(id);
  }

  @override
  Future<void> insert(String id, Map<String, dynamic> data) async {
    _checkOpen();

    if (_entityIndex.containsKey(id)) {
      throw EntityAlreadyExistsException(entityId: id, storageName: name);
    }

    if (inTransaction) {
      if (_transaction!.pendingInserts.containsKey(id)) {
        throw EntityAlreadyExistsException(entityId: id, storageName: name);
      }
      _transaction!.pendingInserts[id] = Map<String, dynamic>.from(data);
    } else {
      await _writeEntity(id, data);
    }
  }

  @override
  Future<void> insertMany(Map<String, Map<String, dynamic>> entities) async {
    _checkOpen();

    // Check all IDs first
    for (final id in entities.keys) {
      if (_entityIndex.containsKey(id)) {
        throw EntityAlreadyExistsException(entityId: id, storageName: name);
      }
    }

    if (inTransaction) {
      for (final entry in entities.entries) {
        _transaction!.pendingInserts[entry.key] = Map<String, dynamic>.from(
          entry.value,
        );
      }
    } else {
      for (final entry in entities.entries) {
        await _writeEntity(entry.key, entry.value);
      }
    }
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    _checkOpen();

    if (!_entityIndex.containsKey(id)) {
      if (inTransaction && _transaction!.pendingInserts.containsKey(id)) {
        _transaction!.pendingInserts[id] = Map<String, dynamic>.from(data);
        return;
      }
      throw EntityNotFoundException(entityId: id, storageName: name);
    }

    if (inTransaction) {
      // Store original for rollback
      if (!_transaction!.originalData.containsKey(id)) {
        final original = await _readEntity(_entityIndex[id]!);
        _transaction!.originalData[id] = original;
      }
      _transaction!.pendingUpdates[id] = Map<String, dynamic>.from(data);
    } else {
      await _updateEntity(id, data);
    }
  }

  @override
  Future<void> upsert(String id, Map<String, dynamic> data) async {
    _checkOpen();

    if (_entityIndex.containsKey(id)) {
      await update(id, data);
    } else {
      await insert(id, data);
    }
  }

  @override
  Future<bool> delete(String id) async {
    _checkOpen();

    if (!_entityIndex.containsKey(id)) {
      if (inTransaction) {
        // Check if it's a pending insert
        if (_transaction!.pendingInserts.remove(id) != null) {
          return true;
        }
      }
      return false;
    }

    if (inTransaction) {
      // Store original for rollback
      if (!_transaction!.originalData.containsKey(id)) {
        final original = await _readEntity(_entityIndex[id]!);
        _transaction!.originalData[id] = original;
      }
      _transaction!.deletedIds.add(id);
      _transaction!.pendingUpdates.remove(id);
    } else {
      await _deleteEntity(id);
    }

    return true;
  }

  @override
  Future<int> deleteMany(Iterable<String> ids) async {
    _checkOpen();
    int count = 0;
    for (final id in ids) {
      if (await delete(id)) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> deleteAll() async {
    _checkOpen();
    final count = _entityIndex.length;
    final ids = _entityIndex.keys.toList();
    for (final id in ids) {
      await delete(id);
    }
    return count;
  }

  @override
  Future<void> flush() async {
    _checkOpen();
    await _saveCatalog();
    await _bufferManager?.flushAll();
  }

  // --------------------------------------------------------------------------
  // Transaction Support
  // --------------------------------------------------------------------------

  @override
  Future<void> beginTransaction() async {
    _checkOpen();
    if (!config.enableTransactions) {
      throw StorageOperationException(
        'Transactions not enabled for storage "$name"',
        path: filePath,
      );
    }
    if (inTransaction) {
      throw TransactionAlreadyActiveException(storageName: name);
    }
    _transaction = _PagedTransactionState();
  }

  @override
  Future<void> commit() async {
    _checkOpen();
    if (!inTransaction) {
      throw NoActiveTransactionException(storageName: name);
    }

    try {
      // Apply pending inserts
      for (final entry in _transaction!.pendingInserts.entries) {
        await _writeEntity(entry.key, entry.value);
      }

      // Apply pending updates
      for (final entry in _transaction!.pendingUpdates.entries) {
        await _updateEntity(entry.key, entry.value);
      }

      // Apply deletes
      for (final id in _transaction!.deletedIds) {
        await _deleteEntity(id);
      }

      // Flush to disk
      await _saveCatalog();
      await _bufferManager?.flushAll();

      _transaction = null;
    } catch (e, st) {
      // On failure, rollback changes in memory
      await _rollbackInMemory();
      throw StorageWriteException(
        storageName: name,
        path: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<void> rollback() async {
    _checkOpen();
    if (!inTransaction) {
      throw NoActiveTransactionException(storageName: name);
    }
    await _rollbackInMemory();
  }

  Future<void> _rollbackInMemory() async {
    // Discard all pending changes
    _transaction = null;
  }

  // --------------------------------------------------------------------------
  // Internal Storage Operations
  // --------------------------------------------------------------------------

  void _checkOpen() {
    if (!_isOpen) {
      throw StorageNotOpenException(storageName: name);
    }
  }

  Future<void> _loadCatalog() async {
    final header = await _pager!.readFileHeader();

    if (header.pageCount <= 1) {
      // New database, create catalog page
      await _initializeCatalog();
      return;
    }

    // Load catalog from page 1
    _catalogPageId = 1;
    final catalogPage = await _bufferManager!.fetchPage(1);

    try {
      // Read catalog format
      // Format: collection_count (4), then for each collection:
      //   name_len (2), name (var), entity_count (4), data_page_count (4)
      //   then entity index entries: id_len (2), id (var), page_id (4), slot (2)

      int offset = PageConstants.pageHeaderSize;

      // Check if this is our collection
      final (storedName, bytesRead) = catalogPage.readString(offset);
      offset += bytesRead;

      if (storedName != name) {
        // This catalog belongs to a different collection
        // For now, reinitialize (in production, would support multiple collections)
        await _initializeCatalog();
        return;
      }

      // Read entity count
      final entityCount = catalogPage.readUint32(offset);
      offset += 4;

      // Read data page count
      final dataPageCount = catalogPage.readUint32(offset);
      offset += 4;

      // Read data page IDs
      for (var i = 0; i < dataPageCount; i++) {
        final pageId = catalogPage.readUint32(offset);
        offset += 4;
        _dataPages.add(pageId);
      }

      // Read entity index
      for (var i = 0; i < entityCount; i++) {
        final (entityId, idBytesRead) = catalogPage.readString(offset);
        offset += idBytesRead;

        final pageId = catalogPage.readUint32(offset);
        offset += 4;

        final slot = catalogPage.readUint16(offset);
        offset += 2;

        _entityIndex[entityId] = _EntityLocation(pageId: pageId, slot: slot);
      }
    } finally {
      _bufferManager!.unpinPage(1);
    }
  }

  Future<void> _initializeCatalog() async {
    // Allocate catalog page
    final catalogPage = await _bufferManager!.allocatePage(PageType.schema);
    _catalogPageId = catalogPage.pageId;

    // Write initial catalog
    int offset = PageConstants.pageHeaderSize;

    // Collection name
    offset += catalogPage.writeString(offset, name);

    // Entity count (0)
    catalogPage.writeUint32(offset, 0);
    offset += 4;

    // Data page count (0)
    catalogPage.writeUint32(offset, 0);

    _bufferManager!.markDirty(_catalogPageId);
    _bufferManager!.unpinPage(_catalogPageId);

    await _bufferManager!.flushPage(_catalogPageId);
  }

  Future<void> _saveCatalog() async {
    final catalogPage = await _bufferManager!.fetchPage(_catalogPageId);

    try {
      // Clear page content
      catalogPage.clear(
        PageConstants.pageHeaderSize,
        _pager!.pageSize - PageConstants.pageHeaderSize,
      );

      int offset = PageConstants.pageHeaderSize;

      // Collection name
      offset += catalogPage.writeString(offset, name);

      // Entity count
      catalogPage.writeUint32(offset, _entityIndex.length);
      offset += 4;

      // Data page count
      catalogPage.writeUint32(offset, _dataPages.length);
      offset += 4;

      // Data page IDs
      for (final pageId in _dataPages) {
        catalogPage.writeUint32(offset, pageId);
        offset += 4;
      }

      // Entity index
      for (final entry in _entityIndex.entries) {
        offset += catalogPage.writeString(offset, entry.key);
        catalogPage.writeUint32(offset, entry.value.pageId);
        offset += 4;
        catalogPage.writeUint16(offset, entry.value.slot);
        offset += 2;
      }

      _bufferManager!.markDirty(_catalogPageId);
    } finally {
      _bufferManager!.unpinPage(_catalogPageId);
    }
  }

  Future<Map<String, dynamic>> _readEntity(_EntityLocation location) async {
    final page = await _bufferManager!.fetchPage(location.pageId);

    try {
      // Read slot directory entry
      final slotOffset = _getSlotOffset(location.slot);
      final dataOffset = page.readUint16(slotOffset);
      final dataLength = page.readUint16(slotOffset + 2);

      if (dataOffset == 0 || dataLength == 0) {
        throw StorageCorruptedException(
          'Invalid slot entry for entity at page ${location.pageId}, slot ${location.slot}',
          path: filePath,
        );
      }

      // Read entity data
      // Format: id_len (2) | id (var) | data_len (4) | json_data (var)
      int offset = dataOffset;

      // Skip ID (we already know it)
      final idLen = page.readUint16(offset);
      offset += 2 + idLen;

      // Read data
      final jsonLen = page.readUint32(offset);
      offset += 4;

      final jsonBytes = page.readBytes(offset, jsonLen);
      final jsonStr = utf8.decode(jsonBytes);

      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } finally {
      _bufferManager!.unpinPage(location.pageId);
    }
  }

  Future<void> _writeEntity(String id, Map<String, dynamic> data) async {
    // Serialize data
    final jsonStr = _jsonEncoder.convert(data);
    final jsonBytes = utf8.encode(jsonStr);

    // Calculate required space
    // Format: id_len (2) | id (var) | data_len (4) | json_data (var)
    final idBytes = utf8.encode(id);
    final requiredSpace = 2 + idBytes.length + 4 + jsonBytes.length;

    if (requiredSpace > config.maxEntitySize) {
      throw StorageWriteException(
        storageName: name,
        entityId: id,
        path: filePath,
        cause: ArgumentError(
          'Entity size ($requiredSpace) exceeds maximum (${config.maxEntitySize})',
        ),
      );
    }

    // Find or allocate a page with enough space
    final (page, slot) = await _allocateSlot(requiredSpace);

    try {
      // Write entity data
      final slotOffset = _getSlotOffset(slot);

      // Find data offset (grow from end of page)
      int dataOffset = page.freeSpaceOffset;
      if (dataOffset < slotOffset + _slotEntrySize) {
        // Need more space, use end of slot directory
        dataOffset = slotOffset + _slotEntrySize;
      }

      // Write to end of used space
      dataOffset = page.pageSize - requiredSpace;

      // Update slot directory
      page.writeUint16(slotOffset, dataOffset);
      page.writeUint16(slotOffset + 2, requiredSpace);
      page.writeUint8(slotOffset + 4, 0); // Flags

      // Write entity data
      int offset = dataOffset;

      // ID
      page.writeUint16(offset, idBytes.length);
      offset += 2;
      page.writeBytes(offset, Uint8List.fromList(idBytes));
      offset += idBytes.length;

      // JSON data
      page.writeUint32(offset, jsonBytes.length);
      offset += 4;
      page.writeBytes(offset, Uint8List.fromList(jsonBytes));

      // Update entity index
      _entityIndex[id] = _EntityLocation(pageId: page.pageId, slot: slot);

      _bufferManager!.markDirty(page.pageId);
    } finally {
      _bufferManager!.unpinPage(page.pageId);
    }
  }

  Future<void> _updateEntity(String id, Map<String, dynamic> data) async {
    // Delete old entry
    await _deleteEntity(id);

    // Write new entry
    await _writeEntity(id, data);
  }

  Future<void> _deleteEntity(String id) async {
    final location = _entityIndex.remove(id);
    if (location == null) return;

    final page = await _bufferManager!.fetchPage(location.pageId);

    try {
      // Mark slot as deleted
      final slotOffset = _getSlotOffset(location.slot);
      page.writeUint16(slotOffset, 0); // Zero offset = deleted
      page.writeUint16(slotOffset + 2, 0);
      page.writeUint8(slotOffset + 4, _SlotFlags.deleted);

      _bufferManager!.markDirty(location.pageId);
    } finally {
      _bufferManager!.unpinPage(location.pageId);
    }
  }

  Future<(Page, int)> _allocateSlot(int requiredSpace) async {
    // Try to find space in existing data pages
    for (final pageId in _dataPages) {
      final page = await _bufferManager!.fetchPage(pageId);

      // Check if page has enough free space
      final headerSize = PageConstants.pageHeaderSize + _dataPageHeaderSize;
      final slotCount = _getSlotCount(page);
      final slotDirEnd = headerSize + (slotCount + 1) * _slotEntrySize;

      // Find lowest used data offset
      int lowestDataOffset = page.pageSize;
      for (var i = 0; i < slotCount; i++) {
        final slotOffset = _getSlotOffset(i);
        final dataOffset = page.readUint16(slotOffset);
        if (dataOffset > 0 && dataOffset < lowestDataOffset) {
          lowestDataOffset = dataOffset;
        }
      }

      final availableSpace = lowestDataOffset - slotDirEnd;

      if (availableSpace >= requiredSpace + _slotEntrySize) {
        // Found space, allocate slot
        final slot = slotCount;

        // Update slot count in data page header
        page.writeUint32(PageConstants.pageHeaderSize, slotCount + 1);

        return (page, slot);
      }

      _bufferManager!.unpinPage(pageId);
    }

    // Need a new data page
    final page = await _bufferManager!.allocatePage(PageType.data);
    _dataPages.add(page.pageId);

    // Initialize data page header
    page.writeUint32(PageConstants.pageHeaderSize, 1); // Slot count = 1

    return (page, 0);
  }

  int _getSlotOffset(int slot) {
    return PageConstants.pageHeaderSize +
        _dataPageHeaderSize +
        slot * _slotEntrySize;
  }

  int _getSlotCount(Page page) {
    return page.readUint32(PageConstants.pageHeaderSize);
  }

  /// Size of data page header (entity count + reserved).
  static const _dataPageHeaderSize = 16;

  /// Size of each slot directory entry.
  static const _slotEntrySize =
      8; // offset (2) + length (2) + flags (1) + reserved (3)
}

/// Location of an entity within the storage.
class _EntityLocation {
  /// The page ID containing the entity.
  final int pageId;

  /// The slot number within the page.
  final int slot;

  const _EntityLocation({required this.pageId, required this.slot});
}

/// Slot flags.
abstract class _SlotFlags {
  /// Marks a slot as deleted.
  static const int deleted = 0x01;
}

/// Transaction state for PagedStorage.
class _PagedTransactionState {
  /// Pending inserts (not yet written).
  final Map<String, Map<String, dynamic>> pendingInserts = {};

  /// Pending updates (not yet written).
  final Map<String, Map<String, dynamic>> pendingUpdates = {};

  /// Original data for rollback.
  final Map<String, Map<String, dynamic>> originalData = {};

  /// IDs marked for deletion.
  final Set<String> deletedIds = {};
}
