/// DocDB - Main Database Class
///
/// The primary entry point for the DocDB embedded document database.
/// Provides a unified interface for managing collections, transactions,
/// backups, and database lifecycle.
///
/// ## Overview
///
/// DocDB is a robust, embedded document database for Dart applications,
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
/// import 'package:docdb/docdb.dart';
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
/// final db = await DocDB.open(
///   path: './myapp.db',
///   config: DocDBConfig.production(),
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
/// final db = await DocDB.open(
///   path: './secure.db',
///   config: DocDBConfig.production(encryptionService: encryption),
/// );
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';

import 'collection/collection.dart';
import 'encryption/encryption_service.dart';
import 'entity/entity.dart';
import 'exceptions/exceptions.dart';
import 'logger/logger.dart';
import 'storage/memory_storage.dart';
import 'storage/paged_storage.dart';
import 'storage/storage.dart';
import 'utils/constants.dart';

/// Configuration for DocDB database instance.
///
/// Controls storage behavior, caching, encryption, and other database options.
@immutable
class DocDBConfig {
  /// The storage backend to use.
  final StorageBackend storageBackend;

  /// Buffer pool size for paged storage (number of pages).
  final int bufferPoolSize;

  /// Page size in bytes (must be power of 2, >= 4096).
  final int pageSize;

  /// Whether to enable transaction support.
  final bool enableTransactions;

  /// Whether to verify page checksums on read.
  final bool verifyChecksums;

  /// Maximum entity size in bytes.
  final int maxEntitySize;

  /// Encryption service for data-at-rest encryption.
  final EncryptionService? encryptionService;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// Whether to auto-flush on close.
  final bool autoFlushOnClose;

  /// Whether encryption is enabled.
  bool get encryptionEnabled =>
      encryptionService != null && encryptionService!.isEnabled;

  /// Creates a DocDB configuration.
  const DocDBConfig({
    this.storageBackend = StorageBackend.paged,
    this.bufferPoolSize = 1024,
    this.pageSize = 4096,
    this.enableTransactions = true,
    this.verifyChecksums = true,
    this.maxEntitySize = 1024 * 1024,
    this.encryptionService,
    this.enableDebugLogging = false,
    this.autoFlushOnClose = true,
  });

  /// Production configuration optimized for performance and durability.
  factory DocDBConfig.production({EncryptionService? encryptionService}) {
    return DocDBConfig(
      storageBackend: StorageBackend.paged,
      bufferPoolSize: 2048,
      pageSize: 4096,
      enableTransactions: true,
      verifyChecksums: true,
      maxEntitySize: 4 * 1024 * 1024,
      encryptionService: encryptionService,
      enableDebugLogging: false,
      autoFlushOnClose: true,
    );
  }

  /// Development configuration with verbose logging.
  factory DocDBConfig.development({EncryptionService? encryptionService}) {
    return DocDBConfig(
      storageBackend: StorageBackend.paged,
      bufferPoolSize: 256,
      pageSize: 4096,
      enableTransactions: true,
      verifyChecksums: true,
      maxEntitySize: 1024 * 1024,
      encryptionService: encryptionService,
      enableDebugLogging: true,
      autoFlushOnClose: true,
    );
  }

  /// In-memory configuration for testing.
  factory DocDBConfig.inMemory() {
    return const DocDBConfig(
      storageBackend: StorageBackend.memory,
      enableTransactions: false,
      enableDebugLogging: true,
      autoFlushOnClose: false,
    );
  }

  /// Creates a copy with modified properties.
  DocDBConfig copyWith({
    StorageBackend? storageBackend,
    int? bufferPoolSize,
    int? pageSize,
    bool? enableTransactions,
    bool? verifyChecksums,
    int? maxEntitySize,
    EncryptionService? encryptionService,
    bool? enableDebugLogging,
    bool? autoFlushOnClose,
  }) {
    return DocDBConfig(
      storageBackend: storageBackend ?? this.storageBackend,
      bufferPoolSize: bufferPoolSize ?? this.bufferPoolSize,
      pageSize: pageSize ?? this.pageSize,
      enableTransactions: enableTransactions ?? this.enableTransactions,
      verifyChecksums: verifyChecksums ?? this.verifyChecksums,
      maxEntitySize: maxEntitySize ?? this.maxEntitySize,
      encryptionService: encryptionService ?? this.encryptionService,
      enableDebugLogging: enableDebugLogging ?? this.enableDebugLogging,
      autoFlushOnClose: autoFlushOnClose ?? this.autoFlushOnClose,
    );
  }
}

/// Storage backend types.
enum StorageBackend {
  /// Page-based storage using the engine (production).
  paged,

  /// In-memory storage (testing).
  memory,
}

/// The main DocDB database class.
///
/// Provides a unified interface for managing collections, handling the
/// database lifecycle, and coordinating cross-cutting concerns like
/// transactions and backups.
///
/// ## Lifecycle
///
/// 1. **Open**: Use [DocDB.open] to open or create a database
/// 2. **Use**: Access collections via [collection] method
/// 3. **Close**: Call [close] to flush and release resources
///
/// ## Thread Safety
///
/// DocDB is thread-safe for concurrent access from multiple isolates.
/// Collections are protected by internal locking mechanisms.
class DocDB {
  /// The database file path (null for in-memory).
  final String? path;

  /// Database configuration.
  final DocDBConfig config;

  /// Logger for database operations.
  final DocDBLogger _logger;

  /// Lock for thread-safe operations.
  final Lock _lock = Lock();

  /// Registered collections by name.
  final Map<String, _CollectionEntry> _collections = {};

  /// Whether the database is open.
  bool _isOpen = false;

  /// Whether the database has been disposed.
  bool _disposed = false;

  /// Private constructor - use [open] factory.
  DocDB._({required this.path, required this.config})
    : _logger = DocDBLogger(LoggerNameConstants.docdb);

  /// Opens or creates a database at the specified path.
  ///
  /// For in-memory databases, pass `null` as the path or use [DocDBConfig.inMemory].
  ///
  /// ## Parameters
  ///
  /// - [path]: Path to the database directory (null for in-memory)
  /// - [config]: Database configuration
  ///
  /// ## Returns
  ///
  /// An open [DocDB] instance ready for use.
  ///
  /// ## Throws
  ///
  /// - [DocDBException]: If the database cannot be opened
  ///
  /// ## Example
  ///
  /// ```dart
  /// // File-based database
  /// final db = await DocDB.open(
  ///   path: './myapp_data',
  ///   config: DocDBConfig.production(),
  /// );
  ///
  /// // In-memory database
  /// final testDb = await DocDB.open(
  ///   path: null,
  ///   config: DocDBConfig.inMemory(),
  /// );
  /// ```
  static Future<DocDB> open({
    String? path,
    DocDBConfig config = const DocDBConfig(),
  }) async {
    final db = DocDB._(path: path, config: config);

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
  /// - [DocDBException]: If the database is not open or collection creation fails
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

        _collections[name] = _CollectionEntry(
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
      return '${Directory.systemTemp.path}/docdb_$collectionName.db';
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
  /// - [DocDBException]: If the drop operation fails
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
  /// A [DocDBStats] object with current database metrics.
  Future<DocDBStats> getStats() async {
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

      return DocDBStats(
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
    return 'DocDB(path: ${path ?? "in-memory"}, '
        'collections: ${_collections.length}, '
        'open: $_isOpen)';
  }
}

/// Internal entry tracking a registered collection.
class _CollectionEntry {
  final String name;
  final Type entityType;
  final Collection<dynamic> collection;
  final Storage<dynamic> storage;

  _CollectionEntry({
    required this.name,
    required this.entityType,
    required this.collection,
    required this.storage,
  });
}

/// Database statistics.
@immutable
class DocDBStats {
  /// Database path (null for in-memory).
  final String? path;

  /// Whether the database is open.
  final bool isOpen;

  /// Number of registered collections.
  final int collectionCount;

  /// Statistics for each collection.
  final Map<String, CollectionStats> collections;

  /// Whether encryption is enabled.
  final bool encryptionEnabled;

  /// The storage backend type.
  final StorageBackend storageBackend;

  /// Creates database statistics.
  const DocDBStats({
    required this.path,
    required this.isOpen,
    required this.collectionCount,
    required this.collections,
    required this.encryptionEnabled,
    required this.storageBackend,
  });

  /// Total entity count across all collections.
  int get totalEntityCount =>
      collections.values.fold(0, (sum, c) => sum + c.entityCount);

  /// Total index count across all collections.
  int get totalIndexCount =>
      collections.values.fold(0, (sum, c) => sum + c.indexCount);

  @override
  String toString() {
    return 'DocDBStats('
        'path: ${path ?? "in-memory"}, '
        'collections: $collectionCount, '
        'entities: $totalEntityCount, '
        'indexes: $totalIndexCount, '
        'encrypted: $encryptionEnabled)';
  }
}

/// Statistics for a single collection.
@immutable
class CollectionStats {
  /// Collection name.
  final String name;

  /// Number of entities.
  final int entityCount;

  /// Number of indexes.
  final int indexCount;

  /// Creates collection statistics.
  const CollectionStats({
    required this.name,
    required this.entityCount,
    required this.indexCount,
  });

  @override
  String toString() {
    return 'CollectionStats($name: $entityCount entities, $indexCount indexes)';
  }
}
