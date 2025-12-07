/// EntiDB - Main Database Class
///
/// The primary entry point for the EntiDB embedded document database.
/// Provides a unified interface for managing collections, transactions,
/// backups, and database lifecycle.
///
/// ## Overview
///
/// EntiDB is a robust, embedded document database for Dart applications,
/// providing:
///
/// - **Type-Safe Collections**: Generic `Collection<T>` with compile-time safety
/// - **ACID Transactions**: Full transaction support with isolation levels
/// - **Flexible Storage**: Pluggable backends (paged, file, memory)
/// - **Encryption**: Optional AES-GCM encryption at rest
/// - **Indexing**: B-tree and hash indexes for fast queries
/// - **Migrations**: Schema versioning with bidirectional transforms
/// - **Backups**: Point-in-time snapshots with integrity verification
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/entidb.dart';
///
/// // Define your entity
/// class Product implements Entity {
///   @override
///   final String? id;
///   final String name;
///   final double price;
///
///   Product({this.id, required this.name, required this.price});
///
///   @override
///   Map<String, dynamic> toMap() => {'name': name, 'price': price};
///
///   static Product fromMap(String id, Map<String, dynamic> map) =>
///     Product(id: id, name: map['name'], price: map['price']);
/// }
///
/// // Open database
/// final db = await EntiDB.open(
///   path: './myapp.db',
///   config: EntiDBConfig.production(),
/// );
///
/// // Get or create a collection
/// final products = await db.collection<Product>(
///   'products',
///   fromMap: Product.fromMap,
/// );
///
/// // Use the collection
/// await products.insert(Product(name: 'Widget', price: 29.99));
/// final results = await products.find(
///   QueryBuilder().whereGreaterThan('price', 20.0).build(),
/// );
///
/// // Close when done
/// await db.close();
/// ```
///
/// ## With Encryption
///
/// ```dart
/// final derivation = KeyDerivationService();
/// final derived = await derivation.deriveKey('user-password');
/// final encryption = AesGcmEncryptionService(secretKey: derived.secretKey);
///
/// final db = await EntiDB.open(
///   path: './secure.db',
///   config: EntiDBConfig.production(encryptionService: encryption),
/// );
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:synchronized/synchronized.dart';

import '../collection/collection.dart';
import '../entity/entity.dart';
import '../exceptions/exceptions.dart';
import '../logger/logger.dart';
import '../storage/memory_storage.dart';
import '../storage/paged_storage.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';
import 'collection_entry.dart';
import 'entidb_config.dart';
import 'entidb_stats.dart';

/// The main EntiDB database class.
///
/// Provides a unified interface for managing collections, handling the
/// database lifecycle, and coordinating cross-cutting concerns like
/// transactions and backups.
///
/// ## Lifecycle
///
/// 1. **Open**: Use [EntiDB.open] to open or create a database
/// 2. **Use**: Access collections via [collection] method
/// 3. **Close**: Call [close] to flush and release resources
///
/// ## Thread Safety
///
/// EntiDB is thread-safe for concurrent access from multiple isolates.
/// Collections are protected by internal locking mechanisms.
class EntiDB {
  /// The database file path (null for in-memory).
  final String? path;

  /// Database configuration.
  final EntiDBConfig config;

  /// Logger for database operations.
  final EntiDBLogger _logger;

  /// Lock for thread-safe operations.
  final Lock _lock = Lock();

  /// Registered collections by name.
  final Map<String, CollectionEntry> _collections = {};

  /// Whether the database is open.
  bool _isOpen = false;

  /// Whether the database has been disposed.
  bool _disposed = false;

  /// Private constructor - use [open] factory.
  EntiDB._({required this.path, required this.config})
    : _logger = EntiDBLogger(LoggerNameConstants.entidb);

  /// Opens or creates a database at the specified path.
  ///
  /// For in-memory databases, pass `null` as the path or use [EntiDBConfig.inMemory].
  ///
  /// ## Parameters
  ///
  /// - [path]: Path to the database directory (null for in-memory)
  /// - [config]: Database configuration
  ///
  /// ## Returns
  ///
  /// An open [EntiDB] instance ready for use.
  ///
  /// ## Throws
  ///
  /// - [EntiDBException]: If the database cannot be opened
  ///
  /// ## Example
  ///
  /// ```dart
  /// // File-based database
  /// final db = await EntiDB.open(
  ///   path: './myapp_data',
  ///   config: EntiDBConfig.production(),
  /// );
  ///
  /// // In-memory database
  /// final testDb = await EntiDB.open(
  ///   path: null,
  ///   config: EntiDBConfig.inMemory(),
  /// );
  /// ```
  static Future<EntiDB> open({
    String? path,
    EntiDBConfig config = const EntiDBConfig(),
  }) async {
    final db = EntiDB._(path: path, config: config);

    try {
      await db._initialize();
      return db;
    } catch (e, st) {
      db._logger.error('Failed to open database', e, st);
      throw DatabaseOpenException(path: path, cause: e, stackTrace: st);
    }
  }

  /// Initializes the database.
  Future<void> _initialize() async {
    await _lock.synchronized(() async {
      if (_isOpen) return;

      // Create directory if needed for file-based storage
      if (path != null && config.storageBackend == StorageBackend.paged) {
        final dir = Directory(path!);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
          _logger.debug('Created database directory: $path');
        }
      }

      _isOpen = true;
      _logger.info('Database opened: ${path ?? "in-memory"}');
    });
  }

  /// Whether the database is currently open.
  bool get isOpen => _isOpen;

  /// The names of all registered collections.
  List<String> get collectionNames => _collections.keys.toList();

  /// The number of registered collections.
  int get collectionCount => _collections.length;

  /// Gets or creates a typed collection.
  ///
  /// If the collection already exists, it is returned. Otherwise, a new
  /// collection is created with the appropriate storage backend.
  ///
  /// ## Type Parameters
  ///
  /// - [T]: The entity type for this collection
  ///
  /// ## Parameters
  ///
  /// - [name]: Unique collection name
  /// - [fromMap]: Factory function to deserialize entities
  ///
  /// ## Returns
  ///
  /// A typed [Collection<T>] instance.
  ///
  /// ## Throws
  ///
  /// - [EntiDBException]: If the database is not open or collection creation fails
  ///
  /// ## Example
  ///
  /// ```dart
  /// final products = await db.collection<Product>(
  ///   'products',
  ///   fromMap: Product.fromMap,
  /// );
  /// ```
  Future<Collection<T>> collection<T extends Entity>(
    String name, {
    required EntityFromMap<T> fromMap,
  }) async {
    _checkOpen();

    return await _lock.synchronized(() async {
      // Check if collection already exists
      final existing = _collections[name];
      if (existing != null) {
        if (existing.entityType != T) {
          throw CollectionTypeMismatchException(
            collectionName: name,
            expectedType: existing.entityType,
            actualType: T,
          );
        }
        return existing.collection as Collection<T>;
      }

      // Create new collection
      try {
        final storage = await _createStorage<T>(name);
        await storage.open();

        final collection = Collection<T>(
          storage: storage,
          fromMap: fromMap,
          name: name,
        );

        _collections[name] = CollectionEntry(
          name: name,
          entityType: T,
          collection: collection,
          storage: storage,
        );

        _logger.info('Created collection: $name');
        return collection;
      } catch (e, st) {
        _logger.error('Failed to create collection "$name"', e, st);
        throw CollectionOperationException(
          collectionName: name,
          operation: 'create',
          cause: e,
          stackTrace: st,
        );
      }
    });
  }

  /// Creates the appropriate storage backend for a collection.
  Future<Storage<T>> _createStorage<T extends Entity>(String name) async {
    switch (config.storageBackend) {
      case StorageBackend.paged:
        final storagePath = _getStoragePath(name);
        return PagedStorage<T>(
          name: name,
          filePath: storagePath,
          config: PagedStorageConfig(
            bufferPoolSize: config.bufferPoolSize,
            pageSize: config.pageSize,
            enableTransactions: config.enableTransactions,
            verifyChecksums: config.verifyChecksums,
            maxEntitySize: config.maxEntitySize,
            encryptionService: config.encryptionService,
          ),
        );

      case StorageBackend.memory:
        return MemoryStorage<T>(name: name);
    }
  }

  /// Gets the storage file path for a collection.
  String _getStoragePath(String collectionName) {
    if (path == null) {
      // Use temp directory for in-memory mode with file storage
      return '${Directory.systemTemp.path}/entidb_$collectionName.db';
    }
    return '$path/$collectionName.db';
  }

  /// Checks if a collection exists.
  ///
  /// ## Parameters
  ///
  /// - [name]: The collection name to check
  ///
  /// ## Returns
  ///
  /// `true` if the collection exists, `false` otherwise.
  bool hasCollection(String name) {
    return _collections.containsKey(name);
  }

  /// Drops a collection and deletes its data.
  ///
  /// **Warning**: This operation is irreversible.
  ///
  /// ## Parameters
  ///
  /// - [name]: The collection to drop
  ///
  /// ## Returns
  ///
  /// `true` if the collection was dropped, `false` if it didn't exist.
  ///
  /// ## Throws
  ///
  /// - [EntiDBException]: If the drop operation fails
  Future<bool> dropCollection(String name) async {
    _checkOpen();

    return await _lock.synchronized(() async {
      final entry = _collections.remove(name);
      if (entry == null) {
        return false;
      }

      try {
        await entry.collection.dispose();
        await entry.storage.close();

        // Delete storage file if applicable
        if (config.storageBackend == StorageBackend.paged && path != null) {
          final file = File(_getStoragePath(name));
          if (await file.exists()) {
            await file.delete();
            _logger.debug('Deleted storage file for collection: $name');
          }
        }

        _logger.info('Dropped collection: $name');
        return true;
      } catch (e, st) {
        _logger.error('Failed to drop collection "$name"', e, st);
        throw CollectionOperationException(
          collectionName: name,
          operation: 'drop',
          cause: e,
          stackTrace: st,
        );
      }
    });
  }

  /// Flushes all pending writes to disk.
  ///
  /// This ensures all data is persisted before continuing.
  Future<void> flush() async {
    _checkOpen();

    await _lock.synchronized(() async {
      for (final entry in _collections.values) {
        await entry.collection.flush();
      }
      _logger.debug('Flushed all collections');
    });
  }

  /// Closes the database and releases all resources.
  ///
  /// After closing, the database cannot be used until reopened.
  /// All collections are disposed and their storage is closed.
  ///
  /// ## Example
  ///
  /// ```dart
  /// await db.close();
  /// // db is now unusable
  /// ```
  Future<void> close() async {
    if (_disposed || !_isOpen) return;

    await _lock.synchronized(() async {
      _logger.info('Closing database...');

      // Flush if configured
      if (config.autoFlushOnClose) {
        for (final entry in _collections.values) {
          try {
            await entry.collection.flush();
          } catch (e) {
            _logger.warning('Failed to flush collection "${entry.name}": $e');
          }
        }
      }

      // Close all collections
      for (final entry in _collections.values) {
        try {
          await entry.collection.dispose();
          await entry.storage.close();
        } catch (e) {
          _logger.warning('Failed to close collection "${entry.name}": $e');
        }
      }

      _collections.clear();
      _isOpen = false;
      _disposed = true;

      _logger.info('Database closed: ${path ?? "in-memory"}');
    });
  }

  /// Gets database statistics.
  ///
  /// ## Returns
  ///
  /// A [EntiDBStats] object with current database metrics.
  Future<EntiDBStats> getStats() async {
    _checkOpen();

    return await _lock.synchronized(() async {
      final collectionStats = <String, CollectionStats>{};

      for (final entry in _collections.entries) {
        final count = await entry.value.collection.count;
        collectionStats[entry.key] = CollectionStats(
          name: entry.key,
          entityCount: count,
          indexCount: entry.value.collection.indexCount,
        );
      }

      return EntiDBStats(
        path: path,
        isOpen: _isOpen,
        collectionCount: _collections.length,
        collections: collectionStats,
        encryptionEnabled: config.encryptionEnabled,
        storageBackend: config.storageBackend,
      );
    });
  }

  /// Ensures the database is open.
  void _checkOpen() {
    if (_disposed) {
      throw const DatabaseDisposedException();
    }
    if (!_isOpen) {
      throw const DatabaseNotOpenException();
    }
  }

  @override
  String toString() {
    return 'EntiDB(path: ${path ?? "in-memory"}, '
        'collections: ${_collections.length}, '
        'open: $_isOpen)';
  }
}
