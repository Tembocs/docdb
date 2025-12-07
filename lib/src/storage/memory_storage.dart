/// EntiDB Storage - In-Memory Storage Implementation
///
/// Provides a fast, volatile storage backend for testing and development.
/// All data is lost when the storage is closed or the application exits.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../entity/entity.dart';
import '../exceptions/storage_exceptions.dart';
import 'storage.dart';

/// In-memory storage implementation for testing and development.
///
/// This storage backend keeps all entities in memory using a simple map.
/// It's fast and suitable for testing, but does not persist data to disk.
///
/// ## Usage
///
/// ```dart
/// final storage = MemoryStorage<Product>(name: 'products');
/// await storage.open();
///
/// await storage.insert('prod-1', {'name': 'Widget', 'price': 29.99});
/// final data = await storage.get('prod-1');
///
/// await storage.close();
/// ```
///
/// ## Transaction Support
///
/// MemoryStorage supports basic transactions with snapshot-based rollback.
/// Transaction isolation level is effectively "serializable" since all
/// operations are synchronous and single-threaded.
final class MemoryStorage<T extends Entity> extends Storage<T>
    with TransactionalStorage<T> {
  @override
  final String name;

  /// The primary data store: ID -> entity data.
  final Map<String, Map<String, dynamic>> _data = {};

  /// Snapshot for transaction rollback.
  Map<String, Map<String, dynamic>>? _snapshot;

  /// Whether the storage is currently open.
  bool _isOpen = false;

  /// Creates a new in-memory storage instance.
  ///
  /// - [name]: Unique name for this storage (typically collection name).
  MemoryStorage({required this.name});

  @override
  bool get supportsTransactions => true;

  @override
  bool get isOpen => _isOpen;

  @override
  bool get inTransaction => _snapshot != null;

  @override
  Future<int> get count async => _data.length;

  /// Ensures the storage is open before operations.
  void _checkOpen() {
    if (!_isOpen) {
      throw StorageNotOpenException(storageName: name);
    }
  }

  @override
  Future<void> open() async {
    if (_isOpen) {
      return; // Already open, no-op
    }
    _isOpen = true;
  }

  @override
  Future<void> close() async {
    if (!_isOpen) {
      return; // Already closed, no-op
    }
    if (inTransaction) {
      await rollback(); // Rollback any pending transaction
    }
    _data.clear();
    _isOpen = false;
  }

  @override
  Future<Map<String, dynamic>?> get(String id) async {
    _checkOpen();
    final data = _data[id];
    // Return a copy to prevent external modification
    return data != null ? Map<String, dynamic>.from(data) : null;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getMany(
    Iterable<String> ids,
  ) async {
    _checkOpen();
    final result = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      final data = _data[id];
      if (data != null) {
        result[id] = Map<String, dynamic>.from(data);
      }
    }
    return result;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getAll() async {
    _checkOpen();
    return {
      for (final entry in _data.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
  }

  @override
  Stream<StorageRecord> stream() async* {
    _checkOpen();
    for (final entry in _data.entries) {
      yield StorageRecord(
        id: entry.key,
        data: Map<String, dynamic>.from(entry.value),
      );
    }
  }

  @override
  Future<bool> exists(String id) async {
    _checkOpen();
    return _data.containsKey(id);
  }

  @override
  Future<void> insert(String id, Map<String, dynamic> data) async {
    _checkOpen();
    if (_data.containsKey(id)) {
      throw EntityAlreadyExistsException(entityId: id, storageName: name);
    }
    // Store a copy to prevent external modification
    _data[id] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> insertMany(Map<String, Map<String, dynamic>> entities) async {
    _checkOpen();
    // Check all IDs first for atomicity
    for (final id in entities.keys) {
      if (_data.containsKey(id)) {
        throw EntityAlreadyExistsException(entityId: id, storageName: name);
      }
    }
    // Insert all entities
    for (final entry in entities.entries) {
      _data[entry.key] = Map<String, dynamic>.from(entry.value);
    }
  }

  @override
  Future<void> update(String id, Map<String, dynamic> data) async {
    _checkOpen();
    if (!_data.containsKey(id)) {
      throw EntityNotFoundException(entityId: id, storageName: name);
    }
    _data[id] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> upsert(String id, Map<String, dynamic> data) async {
    _checkOpen();
    _data[id] = Map<String, dynamic>.from(data);
  }

  @override
  Future<bool> delete(String id) async {
    _checkOpen();
    return _data.remove(id) != null;
  }

  @override
  Future<int> deleteMany(Iterable<String> ids) async {
    _checkOpen();
    int count = 0;
    for (final id in ids) {
      if (_data.remove(id) != null) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<int> deleteAll() async {
    _checkOpen();
    final count = _data.length;
    _data.clear();
    return count;
  }

  @override
  Future<void> flush() async {
    _checkOpen();
    // No-op for memory storage
  }

  @override
  Future<void> beginTransaction() async {
    _checkOpen();
    if (inTransaction) {
      throw TransactionAlreadyActiveException(storageName: name);
    }
    // Create deep copy of current state for rollback
    _snapshot = {
      for (final entry in _data.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
  }

  @override
  Future<void> commit() async {
    _checkOpen();
    if (!inTransaction) {
      throw NoActiveTransactionException(storageName: name);
    }
    // Simply discard the snapshot - changes are already in _data
    _snapshot = null;
  }

  @override
  Future<void> rollback() async {
    _checkOpen();
    if (!inTransaction) {
      throw NoActiveTransactionException(storageName: name);
    }
    // Restore from snapshot
    _data
      ..clear()
      ..addAll(_snapshot!);
    _snapshot = null;
  }

  /// Returns the current entity count (for testing).
  @visibleForTesting
  int get length => _data.length;

  /// Clears all data without closing the storage (for testing).
  @visibleForTesting
  void reset() {
    _data.clear();
    _snapshot = null;
  }
}
