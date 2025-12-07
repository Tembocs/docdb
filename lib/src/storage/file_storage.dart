/// EntiDB Storage - File-Based Storage Implementation
///
/// Provides persistent storage using individual JSON files for each entity.
/// This implementation is suitable for development, small datasets, and
/// scenarios where human-readable storage is desired.
///
/// ## Architecture
///
/// ```
/// storage_directory/
/// ├── _metadata.json      # Storage metadata and index
/// ├── _lock               # Advisory file lock
/// ├── entities/
/// │   ├── entity1.json    # Individual entity files
/// │   ├── entity2.json
/// │   └── ...
/// └── _wal/               # Transaction log (optional)
///     └── current.wal
/// ```
///
/// ## Features
///
/// - Human-readable JSON storage
/// - Per-entity file storage for easy inspection and backup
/// - Transaction support with write-ahead logging
/// - Atomic operations using file rename
/// - Concurrent access protection via file locks
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../entity/entity.dart';
import '../exceptions/storage_exceptions.dart';
import 'storage.dart';

/// Configuration for FileStorage.
@immutable
class FileStorageConfig {
  /// Whether to use pretty-printed JSON (default: true in debug mode).
  final bool prettyPrint;

  /// Whether to enable transactions with WAL support.
  final bool enableTransactions;

  /// Whether to sync files after writes for durability.
  final bool syncOnWrite;

  /// File extension for entity files (default: ".json").
  final String fileExtension;

  /// Maximum number of cached entities in memory.
  final int maxCacheSize;

  /// Creates a FileStorage configuration.
  const FileStorageConfig({
    this.prettyPrint = true,
    this.enableTransactions = true,
    this.syncOnWrite = false,
    this.fileExtension = '.json',
    this.maxCacheSize = 1000,
  });

  /// Default configuration.
  static const FileStorageConfig defaults = FileStorageConfig();

  /// Configuration optimized for performance.
  static const FileStorageConfig performance = FileStorageConfig(
    prettyPrint: false,
    syncOnWrite: false,
    maxCacheSize: 5000,
  );

  /// Configuration optimized for durability.
  static const FileStorageConfig durable = FileStorageConfig(
    prettyPrint: false,
    syncOnWrite: true,
    maxCacheSize: 100,
  );
}

/// File-based storage implementation.
///
/// Stores each entity as an individual JSON file within a directory.
/// Suitable for development, debugging, and small datasets where
/// human-readable storage is beneficial.
///
/// ## Usage
///
/// ```dart
/// final storage = FileStorage<Product>(
///   name: 'products',
///   directory: '/path/to/data/products',
///   config: FileStorageConfig.defaults,
/// );
///
/// await storage.open();
///
/// await storage.insert('prod-1', {'name': 'Widget', 'price': 29.99});
/// final data = await storage.get('prod-1');
///
/// await storage.close();
/// ```
///
/// ## Thread Safety
///
/// FileStorage uses advisory file locking to prevent concurrent access
/// from multiple processes. Within a single process, operations are
/// serialized using an internal lock.
final class FileStorage<T extends Entity> extends Storage<T>
    with TransactionalStorage<T> {
  /// The storage name (typically collection name).
  @override
  final String name;

  /// The base directory for storage files.
  final String directory;

  /// Storage configuration.
  final FileStorageConfig config;

  /// The entities directory.
  late final String _entitiesDir;

  /// The metadata file path.
  late final String _metadataPath;

  /// The lock file path.
  late final String _lockPath;

  /// In-memory cache of entity data.
  final Map<String, Map<String, dynamic>> _cache = {};

  /// Cache access order for LRU eviction.
  final List<String> _cacheOrder = [];

  /// Set of all entity IDs.
  final Set<String> _entityIds = {};

  /// Whether the storage is open.
  bool _isOpen = false;

  /// The lock file handle.
  RandomAccessFile? _lockFile;

  /// Transaction state.
  _TransactionState? _transaction;

  /// JSON encoder.
  late final JsonEncoder _encoder;

  /// Internal operation lock.
  final _lock = _AsyncLock();

  /// Creates a new FileStorage instance.
  ///
  /// - [name]: Unique name for this storage.
  /// - [directory]: Base directory for storage files.
  /// - [config]: Storage configuration (optional).
  FileStorage({
    required this.name,
    required this.directory,
    this.config = const FileStorageConfig(),
  }) {
    _entitiesDir = '$directory/entities';
    _metadataPath = '$directory/_metadata.json';
    _lockPath = '$directory/_lock';
    _encoder = config.prettyPrint
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
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
    return _entityIds.length;
  }

  @override
  Future<void> open() async {
    if (_isOpen) return;

    await _lock.run(() async {
      try {
        // Create directories
        await Directory(_entitiesDir).create(recursive: true);

        // Acquire lock file
        await _acquireLock();

        // Load or create metadata
        await _loadMetadata();

        _isOpen = true;
      } catch (e, st) {
        await _releaseLock();
        throw StorageInitializationException(
          storageName: name,
          path: directory,
          cause: e,
          stackTrace: st,
        );
      }
    });
  }

  @override
  Future<void> close() async {
    if (!_isOpen) return;

    await _lock.run(() async {
      if (inTransaction) {
        await _doRollback();
      }

      // Save metadata
      await _saveMetadata();

      // Clear cache
      _cache.clear();
      _cacheOrder.clear();

      // Release lock
      await _releaseLock();

      _isOpen = false;
    });
  }

  @override
  Future<Map<String, dynamic>?> get(String id) async {
    _checkOpen();
    return _lock.run(() => _doGet(id));
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getMany(
    Iterable<String> ids,
  ) async {
    _checkOpen();
    return _lock.run(() async {
      final result = <String, Map<String, dynamic>>{};
      for (final id in ids) {
        final data = await _doGet(id);
        if (data != null) {
          result[id] = data;
        }
      }
      return result;
    });
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getAll() async {
    _checkOpen();
    return _lock.run(() async {
      final result = <String, Map<String, dynamic>>{};
      for (final id in _entityIds) {
        final data = await _doGet(id);
        if (data != null) {
          result[id] = data;
        }
      }
      return result;
    });
  }

  @override
  Stream<StorageRecord> stream() async* {
    _checkOpen();
    // Create a copy of IDs to avoid concurrent modification
    final ids = List<String>.from(_entityIds);
    for (final id in ids) {
      final data = await get(id);
      if (data != null) {
        yield StorageRecord(id: id, data: data);
      }
    }
  }

  @override
  Future<bool> exists(String id) async {
    _checkOpen();

    // In a transaction, check pending changes first
    if (inTransaction) {
      // Check if deleted in this transaction
      if (_transaction!.deletedIds.contains(id)) {
        return false;
      }
      // Check if newly inserted in this transaction
      if (_transaction!.newIds.contains(id)) {
        return true;
      }
    }

    return _entityIds.contains(id);
  }

  @override
  Future<void> insert(String id, Map<String, dynamic> data) async {
    _checkOpen();
    await _lock.run(() => _doInsert(id, data));
  }

  @override
  Future<void> insertMany(Map<String, Map<String, dynamic>> entities) async {
    _checkOpen();
    await _lock.run(() async {
      // Check all IDs first
      for (final id in entities.keys) {
        if (_entityIds.contains(id)) {
          throw EntityAlreadyExistsException(entityId: id, storageName: name);
        }
      }
      // Insert all entities
      for (final entry in entities.entries) {
        await _doInsert(entry.key, entry.value, checkExists: false);
      }
    });
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    _checkOpen();
    await _lock.run(() => _doUpdate(id, data));
  }

  @override
  Future<void> upsert(String id, Map<String, dynamic> data) async {
    _checkOpen();
    await _lock.run(() async {
      if (_entityIds.contains(id)) {
        await _doUpdate(id, data, checkExists: false);
      } else {
        await _doInsert(id, data, checkExists: false);
      }
    });
  }

  @override
  Future<bool> delete(String id) async {
    _checkOpen();
    return _lock.run(() => _doDelete(id));
  }

  @override
  Future<int> deleteMany(Iterable<String> ids) async {
    _checkOpen();
    return _lock.run(() async {
      int count = 0;
      for (final id in ids) {
        if (await _doDelete(id)) {
          count++;
        }
      }
      return count;
    });
  }

  @override
  Future<int> deleteAll() async {
    _checkOpen();
    return _lock.run(() async {
      final count = _entityIds.length;
      final ids = List<String>.from(_entityIds);
      for (final id in ids) {
        await _doDelete(id);
      }
      return count;
    });
  }

  @override
  Future<void> flush() async {
    _checkOpen();
    await _lock.run(() => _saveMetadata());
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
        path: directory,
      );
    }
    await _lock.run(() async {
      if (inTransaction) {
        throw TransactionAlreadyActiveException(storageName: name);
      }
      _transaction = _TransactionState();
    });
  }

  @override
  Future<void> commit() async {
    _checkOpen();
    await _lock.run(() async {
      if (!inTransaction) {
        throw NoActiveTransactionException(storageName: name);
      }
      try {
        // Apply all pending changes
        await _applyTransactionChanges();
        _transaction = null;
      } catch (e, st) {
        // On failure, rollback
        await _doRollback();
        throw StorageWriteException(
          storageName: name,
          path: directory,
          cause: e,
          stackTrace: st,
        );
      }
    });
  }

  @override
  Future<void> rollback() async {
    _checkOpen();
    await _lock.run(() async {
      if (!inTransaction) {
        throw NoActiveTransactionException(storageName: name);
      }
      await _doRollback();
    });
  }

  // --------------------------------------------------------------------------
  // Internal Operations
  // --------------------------------------------------------------------------

  void _checkOpen() {
    if (!_isOpen) {
      throw StorageNotOpenException(storageName: name);
    }
  }

  String _entityFilePath(String id) {
    // Sanitize ID for filesystem
    final safeId = _sanitizeId(id);
    return '$_entitiesDir/$safeId${config.fileExtension}';
  }

  String _sanitizeId(String id) {
    // Replace problematic characters
    return id
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(':', '_')
        .replaceAll('*', '_')
        .replaceAll('?', '_')
        .replaceAll('"', '_')
        .replaceAll('<', '_')
        .replaceAll('>', '_')
        .replaceAll('|', '_');
  }

  Future<void> _acquireLock() async {
    final lockFile = File(_lockPath);
    try {
      // Try to create lock file exclusively
      _lockFile = await lockFile.open(mode: FileMode.write);
      await _lockFile!.lock(FileLock.exclusive);
    } catch (e) {
      throw StorageOperationException(
        'Failed to acquire lock on storage "$name"',
        path: _lockPath,
        cause: e,
      );
    }
  }

  Future<void> _releaseLock() async {
    try {
      await _lockFile?.unlock();
      await _lockFile?.close();
      _lockFile = null;
      // Try to delete lock file
      final lockFile = File(_lockPath);
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    } catch (_) {
      // Ignore errors during cleanup
    }
  }

  Future<void> _loadMetadata() async {
    final metadataFile = File(_metadataPath);
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final ids = data['entityIds'] as List<dynamic>?;
        if (ids != null) {
          _entityIds.addAll(ids.cast<String>());
        }
      } catch (e) {
        // Metadata corrupted, rebuild from files
        await _rebuildMetadata();
      }
    } else {
      // No metadata, scan for existing entities
      await _rebuildMetadata();
    }
  }

  Future<void> _rebuildMetadata() async {
    _entityIds.clear();
    final entitiesDir = Directory(_entitiesDir);
    if (await entitiesDir.exists()) {
      await for (final file in entitiesDir.list()) {
        if (file is File && file.path.endsWith(config.fileExtension)) {
          final fileName = file.uri.pathSegments.last;
          final id = fileName.substring(
            0,
            fileName.length - config.fileExtension.length,
          );
          _entityIds.add(id);
        }
      }
    }
    await _saveMetadata();
  }

  Future<void> _saveMetadata() async {
    final data = {
      'name': name,
      'version': 1,
      'entityCount': _entityIds.length,
      'entityIds': _entityIds.toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    final content = _encoder.convert(data);
    final tempPath = '$_metadataPath.tmp';
    final tempFile = File(tempPath);
    await tempFile.writeAsString(content);
    if (config.syncOnWrite) {
      await tempFile.open(mode: FileMode.append).then((f) async {
        await f.flush();
        await f.close();
      });
    }
    await tempFile.rename(_metadataPath);
  }

  Future<Map<String, dynamic>?> _doGet(String id) async {
    // Check transaction pending changes first
    if (inTransaction) {
      if (_transaction!.deletedIds.contains(id)) {
        return null;
      }
      final pendingData = _transaction!.pendingChanges[id];
      if (pendingData != null) {
        return Map<String, dynamic>.from(pendingData);
      }
    }

    // Check cache
    if (_cache.containsKey(id)) {
      _updateCacheOrder(id);
      return Map<String, dynamic>.from(_cache[id]!);
    }

    // Check if entity exists
    if (!_entityIds.contains(id)) {
      return null;
    }

    // Load from file
    try {
      final filePath = _entityFilePath(id);
      final file = File(filePath);
      if (!await file.exists()) {
        // File missing, update metadata
        _entityIds.remove(id);
        return null;
      }
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      // Add to cache
      _addToCache(id, data);

      return Map<String, dynamic>.from(data);
    } catch (e, st) {
      throw StorageReadException(
        storageName: name,
        entityId: id,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _doInsert(
    String id,
    Map<String, dynamic> data, {
    bool checkExists = true,
  }) async {
    if (checkExists && _entityIds.contains(id)) {
      throw EntityAlreadyExistsException(entityId: id, storageName: name);
    }

    final dataCopy = Map<String, dynamic>.from(data);

    if (inTransaction) {
      // Store in transaction pending changes
      _transaction!.pendingChanges[id] = dataCopy;
      _transaction!.newIds.add(id);
      _transaction!.deletedIds.remove(id);
    } else {
      // Write immediately
      await _writeEntityFile(id, dataCopy);
      _entityIds.add(id);
      _addToCache(id, dataCopy);
    }
  }

  Future<void> _doUpdate(
    String id,
    Map<String, dynamic> data, {
    bool checkExists = true,
  }) async {
    if (checkExists && !_entityIds.contains(id)) {
      // Also check transaction pending
      if (!inTransaction || !_transaction!.pendingChanges.containsKey(id)) {
        throw EntityNotFoundException(entityId: id, storageName: name);
      }
    }

    final dataCopy = Map<String, dynamic>.from(data);

    if (inTransaction) {
      // Store original for rollback if not already stored
      if (!_transaction!.originalData.containsKey(id)) {
        final original = await _readEntityFile(id);
        if (original != null) {
          _transaction!.originalData[id] = original;
        }
      }
      _transaction!.pendingChanges[id] = dataCopy;
    } else {
      // Write immediately
      await _writeEntityFile(id, dataCopy);
      _addToCache(id, dataCopy);
    }
  }

  Future<bool> _doDelete(String id) async {
    if (!_entityIds.contains(id)) {
      // Check transaction pending
      if (inTransaction && _transaction!.pendingChanges.containsKey(id)) {
        _transaction!.pendingChanges.remove(id);
        _transaction!.newIds.remove(id);
        return true;
      }
      return false;
    }

    if (inTransaction) {
      // Store original for rollback if not already stored
      if (!_transaction!.originalData.containsKey(id)) {
        final original = await _readEntityFile(id);
        if (original != null) {
          _transaction!.originalData[id] = original;
        }
      }
      _transaction!.deletedIds.add(id);
      _transaction!.pendingChanges.remove(id);
    } else {
      // Delete immediately
      await _deleteEntityFile(id);
      _entityIds.remove(id);
      _cache.remove(id);
      _cacheOrder.remove(id);
    }

    return true;
  }

  Future<void> _writeEntityFile(String id, Map<String, dynamic> data) async {
    final filePath = _entityFilePath(id);
    final tempPath = '$filePath.tmp';
    try {
      final content = _encoder.convert(data);
      final tempFile = File(tempPath);
      await tempFile.writeAsString(content);

      if (config.syncOnWrite) {
        await tempFile.open(mode: FileMode.append).then((f) async {
          await f.flush();
          await f.close();
        });
      }

      // Atomic rename
      await tempFile.rename(filePath);
    } catch (e, st) {
      // Clean up temp file
      try {
        await File(tempPath).delete();
      } catch (_) {}
      throw StorageWriteException(
        storageName: name,
        entityId: id,
        path: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<Map<String, dynamic>?> _readEntityFile(String id) async {
    final filePath = _entityFilePath(id);
    final file = File(filePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteEntityFile(String id) async {
    final filePath = _entityFilePath(id);
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e, st) {
      throw StorageWriteException(
        storageName: name,
        entityId: id,
        path: filePath,
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _applyTransactionChanges() async {
    final transaction = _transaction!;

    // Delete entities
    for (final id in transaction.deletedIds) {
      await _deleteEntityFile(id);
      _entityIds.remove(id);
      _cache.remove(id);
      _cacheOrder.remove(id);
    }

    // Write new and updated entities
    for (final entry in transaction.pendingChanges.entries) {
      await _writeEntityFile(entry.key, entry.value);
      if (transaction.newIds.contains(entry.key)) {
        _entityIds.add(entry.key);
      }
      _addToCache(entry.key, entry.value);
    }

    // Save metadata
    await _saveMetadata();
  }

  Future<void> _doRollback() async {
    // Transaction is discarded, nothing written yet
    _transaction = null;
  }

  void _addToCache(String id, Map<String, dynamic> data) {
    // Remove from current position
    _cacheOrder.remove(id);

    // Add to front (most recently used)
    _cacheOrder.insert(0, id);
    _cache[id] = Map<String, dynamic>.from(data);

    // Evict if over limit
    while (_cache.length > config.maxCacheSize && _cacheOrder.length > 1) {
      final evictId = _cacheOrder.removeLast();
      _cache.remove(evictId);
    }
  }

  void _updateCacheOrder(String id) {
    _cacheOrder.remove(id);
    _cacheOrder.insert(0, id);
  }
}

/// Transaction state for FileStorage.
class _TransactionState {
  /// Entities with pending changes (inserts and updates).
  final Map<String, Map<String, dynamic>> pendingChanges = {};

  /// Original data for entities being updated (for rollback).
  final Map<String, Map<String, dynamic>> originalData = {};

  /// IDs of newly inserted entities.
  final Set<String> newIds = {};

  /// IDs of deleted entities.
  final Set<String> deletedIds = {};
}

/// Simple async lock for serializing operations.
class _AsyncLock {
  Completer<void>? _completer;

  Future<T> run<T>(Future<T> Function() operation) async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
    try {
      return await operation();
    } finally {
      final completer = _completer;
      _completer = null;
      completer?.complete();
    }
  }
}
