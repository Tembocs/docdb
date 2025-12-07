/// DocDB Collection Module
///
/// Provides type-safe, high-performance entity collections with support for
/// indexing, transactions, optimistic concurrency control, and querying.
///
/// ## Overview
///
/// The [Collection] class is the primary interface for storing and retrieving
/// entities in DocDB. It provides:
///
/// - **Type Safety**: Generic `Collection<T extends Entity>` returns typed results
/// - **Indexing**: B-tree and hash indexes for efficient queries
/// - **Transactions**: ACID-compliant operations with automatic rollback
/// - **Concurrency**: Optimistic locking with version-based conflict detection
/// - **Querying**: Fluent query builder with index optimization
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/collection/collection.dart';
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
///   factory Product.fromMap(String id, Map<String, dynamic> map) =>
///     Product(id: id, name: map['name'], price: map['price']);
/// }
///
/// // Create and use collection
/// final storage = MemoryStorage<Product>(name: 'products');
/// await storage.open();
///
/// final products = Collection<Product>(
///   storage: storage,
///   fromMap: Product.fromMap,
///   name: 'products',
/// );
///
/// // Insert entities
/// await products.insert(Product(name: 'Widget', price: 29.99));
///
/// // Query with type-safe results
/// final expensive = await products.find(
///   QueryBuilder().whereGreaterThan('price', 20.0).build(),
/// );
/// print(expensive.first.price); // 29.99 - fully typed!
/// ```
///
/// ## Indexing
///
/// Create indexes for efficient queries:
///
/// ```dart
/// // Hash index for equality queries
/// await products.createIndex('sku', IndexType.hash);
///
/// // B-tree index for range queries
/// await products.createIndex('price', IndexType.btree);
///
/// // Queries automatically use available indexes
/// final results = await products.find(
///   QueryBuilder().whereEquals('sku', 'WIDGET-001').build(),
/// );
/// ```
///
/// ## Transactions
///
/// Use [TransactionManager] for atomic operations:
///
/// ```dart
/// final txnManager = TransactionManager(storage);
/// final txn = await txnManager.beginTransaction();
///
/// try {
///   await products.insert(product1, transaction: txn);
///   await products.insert(product2, transaction: txn);
///   await txnManager.commit();
/// } catch (e) {
///   await txnManager.rollback();
/// }
/// ```
///
/// ## Concurrency Control
///
/// Collections support optimistic concurrency with version tracking:
///
/// ```dart
/// // Get entity with version
/// final product = await products.get('prod-1');
///
/// // Update with version check
/// await products.update('prod-1', updatedProduct);
/// // Throws ConcurrencyException if version changed
/// ```
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import '../entity/entity.dart';
import '../exceptions/exceptions.dart';
import '../index/index_manager.dart';
import '../index/i_index.dart';
import '../logger/logger.dart';
import '../query/query.dart';
import '../storage/storage.dart';
import '../utils/constants.dart';

/// UUID generator for entity IDs.
const _uuid = Uuid();

/// A type-safe collection of entities with indexing and query support.
///
/// [Collection] provides the primary interface for storing and retrieving
/// entities in DocDB. It wraps a [Storage] backend and adds:
///
/// - Type-safe operations with automatic serialization/deserialization
/// - Index management for efficient queries
/// - Optimistic concurrency control with version tracking
/// - Thread-safe operations with fine-grained locking
///
/// ## Type Parameters
///
/// - [T]: The entity type. Must implement [Entity].
///
/// ## Usage
///
/// ```dart
/// final products = Collection<Product>(
///   storage: storage,
///   fromMap: Product.fromMap,
///   name: 'products',
/// );
///
/// // All operations are type-safe
/// await products.insert(Product(name: 'Widget', price: 29.99));
/// final product = await products.get('prod-1'); // Returns Product?
/// final all = await products.find(AllQuery()); // Returns List<Product>
/// ```
///
/// ## Thread Safety
///
/// All public methods are thread-safe and use internal locking to prevent
/// concurrent modification issues. The locking strategy is:
///
/// - Collection-level lock for schema changes (index creation/removal)
/// - Entity-level locks for individual entity operations
///
/// ## Memory Management
///
/// Entity locks are automatically cleaned up when [dispose] is called.
/// For long-running applications, consider periodic cleanup of stale locks.
class Collection<T extends Entity> {
  /// The underlying storage backend.
  final Storage<T> _storage;

  /// Factory function for deserializing entities.
  final EntityFromMap<T> _fromMap;

  /// The collection name.
  final String _name;

  /// Logger for collection operations.
  final DocDBLogger _logger;

  /// Collection-level lock for schema operations.
  final Lock _collectionLock = Lock();

  /// Entity-level locks for fine-grained concurrency.
  final Map<String, Lock> _entityLocks = {};

  /// Version tracking for optimistic concurrency control.
  final Map<String, int> _entityVersions = {};

  /// Index manager for this collection.
  final IndexManager _indexManager = IndexManager();

  /// Query optimizer for this collection.
  late final QueryOptimizer _queryOptimizer;

  /// Query result cache for this collection.
  QueryCache<T>? _queryCache;

  /// Whether query result caching is enabled.
  bool _queryCacheEnabled = false;

  /// Whether the collection has been disposed.
  bool _disposed = false;

  /// Creates a new collection backed by the given storage.
  ///
  /// ## Parameters
  ///
  /// - [storage]: The storage backend for persistence.
  /// - [fromMap]: Factory function to deserialize entities.
  /// - [name]: The collection name (used for logging).
  /// - [enableQueryPlanCaching]: Whether to cache query plans (default: true).
  /// - [enableQueryResultCaching]: Whether to cache query results (default: false).
  /// - [queryCacheConfig]: Configuration for query result caching.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final products = Collection<Product>(
  ///   storage: productStorage,
  ///   fromMap: Product.fromMap,
  ///   name: 'products',
  /// );
  /// ```
  Collection({
    required Storage<T> storage,
    required EntityFromMap<T> fromMap,
    required String name,
    bool enableQueryPlanCaching = true,
    bool enableQueryResultCaching = false,
    QueryCacheConfig? queryCacheConfig,
  }) : _storage = storage,
       _fromMap = fromMap,
       _name = name,
       _logger = DocDBLogger('${LoggerNameConstants.collection}.$name') {
    _queryOptimizer = QueryOptimizer(
      _indexManager,
      enableCaching: enableQueryPlanCaching,
    );

    // Initialize query result cache if enabled
    if (enableQueryResultCaching) {
      _queryCacheEnabled = true;
      _queryCache = QueryCache<T>(
        config: queryCacheConfig ?? const QueryCacheConfig(),
      );
    }
  }

  /// The collection name.
  String get name => _name;

  /// The underlying storage backend.
  ///
  /// Use with caution - direct storage access bypasses collection
  /// features like indexing and version tracking.
  @visibleForTesting
  Storage<T> get storage => _storage;

  /// The number of entities in the collection.
  Future<int> get count async {
    _checkNotDisposed();
    return _storage.count;
  }

  /// The list of indexed fields.
  List<String> get indexedFields => _indexManager.indexedFields;

  /// The number of indexes on this collection.
  int get indexCount => _indexManager.indexCount;

  /// Whether query result caching is enabled.
  bool get isQueryCacheEnabled => _queryCacheEnabled;

  /// Gets the query cache statistics.
  ///
  /// Returns null if query caching is not enabled.
  CacheStatistics? get queryCacheStatistics => _queryCache?.statistics;

  /// Enables query result caching with the specified configuration.
  ///
  /// If caching is already enabled, the existing cache is cleared and
  /// reconfigured with the new settings.
  ///
  /// ## Parameters
  ///
  /// - [config]: Configuration for the query cache. Uses defaults if null.
  void enableQueryCache({QueryCacheConfig? config}) {
    _queryCacheEnabled = true;
    _queryCache = QueryCache<T>(config: config ?? const QueryCacheConfig());
    _logger.info('Query result caching enabled.');
  }

  /// Disables query result caching and clears the cache.
  void disableQueryCache() {
    _queryCacheEnabled = false;
    _queryCache?.clear();
    _queryCache = null;
    _logger.info('Query result caching disabled.');
  }

  /// Clears all cached query results.
  ///
  /// Does nothing if caching is not enabled.
  void clearQueryCache() {
    _queryCache?.invalidateAll();
  }

  /// Removes expired entries from the query cache.
  ///
  /// ## Returns
  ///
  /// The number of expired entries removed, or 0 if caching is not enabled.
  int pruneQueryCache() {
    return _queryCache?.removeExpired() ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Index Management
  // ---------------------------------------------------------------------------

  /// Creates an index on the specified field.
  ///
  /// Indexes improve query performance for fields that are frequently
  /// searched or sorted. The index type determines which operations
  /// are optimized:
  ///
  /// - [IndexType.hash]: O(1) equality lookups
  /// - [IndexType.btree]: O(log n) range queries and ordered iteration
  ///
  /// If the collection already contains entities, they will be indexed
  /// as part of this operation.
  ///
  /// ## Parameters
  ///
  /// - [field]: The entity field name to index (from [Entity.toMap] keys).
  /// - [indexType]: The type of index to create.
  ///
  /// ## Throws
  ///
  /// - [CollectionException]: If the collection is disposed.
  /// - [IndexAlreadyExistsException]: If an index already exists on [field].
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Create hash index for exact matches
  /// await collection.createIndex('email', IndexType.hash);
  ///
  /// // Create B-tree index for range queries
  /// await collection.createIndex('createdAt', IndexType.btree);
  /// ```
  Future<void> createIndex(String field, IndexType indexType) async {
    _checkNotDisposed();

    await _collectionLock.synchronized(() async {
      _indexManager.createIndex(field, indexType);

      // Populate index with existing entities
      await _populateIndex(field);

      // Invalidate cached query plans for this field
      _queryOptimizer.invalidateField(field);

      _logger.info('Created ${indexType.name} index on field "$field".');
    });
  }

  /// Removes the index on the specified field.
  ///
  /// ## Parameters
  ///
  /// - [field]: The field whose index should be removed.
  ///
  /// ## Throws
  ///
  /// - [CollectionException]: If the collection is disposed.
  /// - [IndexNotFoundException]: If no index exists on [field].
  Future<void> removeIndex(String field) async {
    _checkNotDisposed();

    await _collectionLock.synchronized(() async {
      _indexManager.removeIndex(field);

      // Invalidate cached query plans for this field
      _queryOptimizer.invalidateField(field);

      _logger.info('Removed index on field "$field".');
    });
  }

  /// Checks if an index exists on the specified field.
  bool hasIndex(String field) => _indexManager.hasIndex(field);

  /// Checks if an index of the specified type exists on the field.
  bool hasIndexOfType(String field, IndexType indexType) {
    return _indexManager.hasIndexOfType(field, indexType);
  }

  /// Populates an index with all existing entities.
  Future<void> _populateIndex(String field) async {
    const batchSize = 100;
    var processed = 0;
    var hasEntities = false;

    await for (final record in _storage.stream()) {
      if (!hasEntities) {
        hasEntities = true;
        _logger.debug('Populating index "$field" with existing entities...');
      }

      _indexManager.insert(record.id, record.data);
      processed++;

      if (processed % batchSize == 0) {
        _logger.debug('Indexed $processed entities on field "$field"...');
      }
    }

    if (hasEntities) {
      _logger.info('Populated index "$field" with $processed entities.');
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD Operations
  // ---------------------------------------------------------------------------

  /// Inserts a new entity into the collection.
  ///
  /// If the entity's [id] is `null`, a UUID v4 is generated automatically.
  /// The entity is added to all relevant indexes.
  ///
  /// ## Parameters
  ///
  /// - [entity]: The entity to insert.
  ///
  /// ## Returns
  ///
  /// The ID of the inserted entity (generated or provided).
  ///
  /// ## Throws
  ///
  /// - [CollectionException]: If the collection is disposed.
  /// - [EntityAlreadyExistsException]: If an entity with the same ID exists.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Auto-generated ID
  /// final id = await collection.insert(Product(name: 'Widget', price: 29.99));
  /// print(id); // 'a1b2c3d4-e5f6-...'
  ///
  /// // Custom ID
  /// await collection.insert(Product(id: 'custom-id', name: 'Gadget', price: 49.99));
  /// ```
  Future<String> insert(T entity) async {
    _checkNotDisposed();

    final entityId = entity.id ?? _uuid.v4();
    final data = entity.toMap();

    // Add version metadata for optimistic concurrency control
    data['__version'] = 1;

    final entityLock = _getEntityLock(entityId);
    await entityLock.synchronized(() async {
      try {
        await _storage.insert(entityId, data);
        _indexManager.insert(entityId, data);
        _entityVersions[entityId] = 1;

        // Invalidate query cache for affected fields
        _invalidateCacheForFields(data.keys.toSet());

        _logger.debug('Inserted entity "$entityId".');
      } catch (e, stackTrace) {
        _logger.error('Failed to insert entity "$entityId"', e, stackTrace);
        if (e is EntityAlreadyExistsException) rethrow;
        throw CollectionException(
          'Failed to insert entity "$entityId": $e',
          cause: e,
        );
      }
    });

    return entityId;
  }

  /// Inserts multiple entities in a batch operation.
  ///
  /// This is more efficient than calling [insert] multiple times.
  /// If any insertion fails, previously inserted entities in this
  /// batch remain in the collection.
  ///
  /// ## Parameters
  ///
  /// - [entities]: The entities to insert.
  ///
  /// ## Returns
  ///
  /// A list of IDs for all inserted entities.
  ///
  /// ## Throws
  ///
  /// - [CollectionException]: If any insertion fails.
  Future<List<String>> insertMany(List<T> entities) async {
    _checkNotDisposed();

    final ids = <String>[];
    final entitiesToInsert = <String, Map<String, dynamic>>{};

    // Prepare all entities with IDs and version metadata
    for (final entity in entities) {
      final entityId = entity.id ?? _uuid.v4();
      final data = entity.toMap();
      data['__version'] = 1;
      entitiesToInsert[entityId] = data;
      ids.add(entityId);
    }

    await _collectionLock.synchronized(() async {
      try {
        await _storage.insertMany(entitiesToInsert);

        // Collect all affected fields
        final affectedFields = <String>{};

        // Index all entities
        for (final entry in entitiesToInsert.entries) {
          _indexManager.insert(entry.key, entry.value);
          _entityVersions[entry.key] = 1;
          affectedFields.addAll(entry.value.keys);
        }

        // Invalidate query cache for affected fields
        _invalidateCacheForFields(affectedFields);

        _logger.info('Inserted ${entities.length} entities.');
      } catch (e, stackTrace) {
        _logger.error('Failed to insert batch', e, stackTrace);
        throw CollectionException('Failed to insert batch: $e', cause: e);
      }
    });

    return ids;
  }

  /// Retrieves an entity by its ID.
  ///
  /// ## Parameters
  ///
  /// - [id]: The unique identifier of the entity.
  ///
  /// ## Returns
  ///
  /// The entity, or `null` if not found.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final product = await collection.get('prod-1');
  /// if (product != null) {
  ///   print(product.name);
  /// }
  /// ```
  Future<T?> get(String id) async {
    _checkNotDisposed();

    final entityLock = _getEntityLock(id);
    return await entityLock.synchronized(() async {
      return await _getInternal(id);
    });
  }

  /// Internal get implementation without lock acquisition.
  ///
  /// Must be called within an already-acquired entity lock.
  Future<T?> _getInternal(String id) async {
    final data = await _storage.get(id);
    if (data == null) {
      return null;
    }

    // Track version for optimistic concurrency
    _entityVersions.putIfAbsent(id, () => 1);

    return _fromMap(id, data);
  }

  /// Retrieves an entity by its ID, throwing if not found.
  ///
  /// ## Parameters
  ///
  /// - [id]: The unique identifier of the entity.
  ///
  /// ## Returns
  ///
  /// The entity.
  ///
  /// ## Throws
  ///
  /// - [EntityNotFoundException]: If the entity does not exist.
  ///
  /// ## Example
  ///
  /// ```dart
  /// try {
  ///   final product = await collection.getOrThrow('prod-1');
  ///   print(product.name);
  /// } on EntityNotFoundException {
  ///   print('Product not found');
  /// }
  /// ```
  Future<T> getOrThrow(String id) async {
    final entity = await get(id);
    if (entity == null) {
      throw EntityNotFoundException(entityId: id, storageName: _name);
    }
    return entity;
  }

  /// Retrieves multiple entities by their IDs.
  ///
  /// Missing entities are silently omitted from the result.
  ///
  /// ## Parameters
  ///
  /// - [ids]: The entity IDs to retrieve.
  ///
  /// ## Returns
  ///
  /// A map of ID to entity for found entities.
  Future<Map<String, T>> getMany(Iterable<String> ids) async {
    _checkNotDisposed();

    final data = await _storage.getMany(ids);
    final result = <String, T>{};

    for (final entry in data.entries) {
      result[entry.key] = _fromMap(entry.key, entry.value);
      _entityVersions.putIfAbsent(entry.key, () => 1);
    }

    return result;
  }

  /// Retrieves all entities in the collection.
  ///
  /// For large collections, consider using [stream] instead to avoid
  /// loading everything into memory at once.
  ///
  /// ## Returns
  ///
  /// A list of all entities.
  Future<List<T>> getAll() async {
    _checkNotDisposed();

    final data = await _storage.getAll();
    return data.entries.map((entry) {
      _entityVersions.putIfAbsent(entry.key, () => 1);
      return _fromMap(entry.key, entry.value);
    }).toList();
  }

  /// Streams all entities in the collection.
  ///
  /// This is more memory-efficient than [getAll] for large collections.
  ///
  /// ## Returns
  ///
  /// A stream of entities.
  Stream<T> stream() async* {
    _checkNotDisposed();

    await for (final record in _storage.stream()) {
      _entityVersions.putIfAbsent(record.id, () => 1);
      yield _fromMap(record.id, record.data);
    }
  }

  /// Checks if an entity with the given ID exists.
  ///
  /// ## Parameters
  ///
  /// - [id]: The entity ID to check.
  ///
  /// ## Returns
  ///
  /// `true` if the entity exists, `false` otherwise.
  Future<bool> exists(String id) async {
    _checkNotDisposed();
    return _storage.exists(id);
  }

  /// Updates an existing entity.
  ///
  /// The entity is identified by the ID in the provided entity.
  /// Indexes are updated to reflect any field changes.
  ///
  /// ## Parameters
  ///
  /// - [entity]: The updated entity. Must have a non-null ID.
  ///
  /// ## Throws
  ///
  /// - [CollectionException]: If the entity has no ID.
  /// - [EntityNotFoundException]: If the entity does not exist.
  /// - [ConcurrencyException]: If the entity was modified since last read.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final product = await collection.get('prod-1');
  /// if (product != null) {
  ///   final updated = Product(
  ///     id: product.id,
  ///     name: product.name,
  ///     price: product.price * 1.1, // 10% increase
  ///   );
  ///   await collection.update(updated);
  /// }
  /// ```
  Future<void> update(T entity) async {
    _checkNotDisposed();

    final entityId = entity.id;
    if (entityId == null) {
      throw CollectionException('Cannot update entity without ID.');
    }

    final entityLock = _getEntityLock(entityId);
    await entityLock.synchronized(() async {
      await _updateInternal(entity);
    });
  }

  /// Internal update implementation without lock acquisition.
  ///
  /// Must be called within an already-acquired entity lock.
  /// Assumes entity.id is non-null.
  Future<void> _updateInternal(T entity) async {
    final entityId = entity.id!;
    final newData = entity.toMap();

    try {
      // Get current entity for index update
      final oldData = await _storage.get(entityId);
      if (oldData == null) {
        throw EntityNotFoundException(entityId: entityId, storageName: _name);
      }

      // Check version for optimistic concurrency
      final expectedVersion = _entityVersions[entityId] ?? 1;
      final storedVersion = (oldData['__version'] as int?) ?? 1;

      if (storedVersion != expectedVersion) {
        throw ConcurrencyException(
          'Entity "$entityId" was modified. '
          'Expected version $expectedVersion, found $storedVersion.',
        );
      }

      // Update indexes
      _indexManager.update(entityId, oldData, newData);

      // Store updated version in data
      final newVersion = expectedVersion + 1;
      newData['__version'] = newVersion;

      // Update storage
      await _storage.update(entityId, newData);

      // Increment version in memory
      _entityVersions[entityId] = newVersion;

      // Invalidate query cache for affected fields (both old and new)
      final affectedFields = <String>{...oldData.keys, ...newData.keys};
      _invalidateCacheForFields(affectedFields);

      _logger.debug('Updated entity "$entityId".');
    } catch (e, stackTrace) {
      if (e is EntityNotFoundException || e is ConcurrencyException) rethrow;
      _logger.error('Failed to update entity "$entityId"', e, stackTrace);
      throw CollectionException(
        'Failed to update entity "$entityId": $e',
        cause: e,
      );
    }
  }

  /// Updates an entity by ID with a modifier function.
  ///
  /// This is useful when you need to read the current state and apply
  /// changes atomically.
  ///
  /// ## Parameters
  ///
  /// - [id]: The entity ID to update.
  /// - [modifier]: Function that takes the current entity and returns updated.
  ///
  /// ## Returns
  ///
  /// The updated entity.
  ///
  /// ## Throws
  ///
  /// - [EntityNotFoundException]: If the entity does not exist.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final updated = await collection.updateWhere(
  ///   'prod-1',
  ///   (product) => Product(
  ///     id: product.id,
  ///     name: product.name,
  ///     price: product.price * 0.9, // 10% discount
  ///   ),
  /// );
  /// ```
  Future<T> updateWhere(String id, T Function(T current) modifier) async {
    _checkNotDisposed();

    final entityLock = _getEntityLock(id);
    return await entityLock.synchronized(() async {
      // Use internal methods to avoid nested lock acquisition
      final current = await _getInternal(id);
      if (current == null) {
        throw EntityNotFoundException(entityId: id, storageName: _name);
      }

      final updated = modifier(current);
      await _updateInternal(updated);
      return updated;
    });
  }

  /// Inserts or updates an entity.
  ///
  /// If the entity exists, it is updated. Otherwise, it is inserted.
  ///
  /// ## Parameters
  ///
  /// - [entity]: The entity to upsert.
  ///
  /// ## Returns
  ///
  /// The entity ID.
  Future<String> upsert(T entity) async {
    _checkNotDisposed();

    final entityId = entity.id ?? _uuid.v4();
    final data = entity.toMap();

    final entityLock = _getEntityLock(entityId);
    await entityLock.synchronized(() async {
      try {
        // Check if exists for index update
        final oldData = await _storage.get(entityId);
        Set<String> affectedFields;

        if (oldData != null) {
          // Update existing entity with new version
          final newVersion = (_entityVersions[entityId] ?? 1) + 1;
          data['__version'] = newVersion;
          _indexManager.update(entityId, oldData, data);
          _entityVersions[entityId] = newVersion;
          affectedFields = {...oldData.keys, ...data.keys};
        } else {
          // Insert new entity with version 1
          data['__version'] = 1;
          _indexManager.insert(entityId, data);
          _entityVersions[entityId] = 1;
          affectedFields = data.keys.toSet();
        }

        await _storage.upsert(entityId, data);

        // Invalidate query cache for affected fields
        _invalidateCacheForFields(affectedFields);

        _logger.debug('Upserted entity "$entityId".');
      } catch (e, stackTrace) {
        _logger.error('Failed to upsert entity "$entityId"', e, stackTrace);
        throw CollectionException(
          'Failed to upsert entity "$entityId": $e',
          cause: e,
        );
      }
    });

    return entityId;
  }

  /// Deletes an entity by ID.
  ///
  /// ## Parameters
  ///
  /// - [id]: The entity ID to delete.
  ///
  /// ## Returns
  ///
  /// `true` if the entity was deleted, `false` if it didn't exist.
  Future<bool> delete(String id) async {
    _checkNotDisposed();

    final entityLock = _getEntityLock(id);
    return await entityLock.synchronized(() async {
      try {
        // Get current data for index removal
        final data = await _storage.get(id);
        if (data == null) {
          return false;
        }

        _indexManager.remove(id, data);
        await _storage.delete(id);
        _entityVersions.remove(id);
        _entityLocks.remove(id);

        // Invalidate query cache for affected fields
        _invalidateCacheForFields(data.keys.toSet());

        _logger.debug('Deleted entity "$id".');
        return true;
      } catch (e, stackTrace) {
        _logger.error('Failed to delete entity "$id"', e, stackTrace);
        throw CollectionException(
          'Failed to delete entity "$id": $e',
          cause: e,
        );
      }
    });
  }

  /// Deletes an entity by ID, throwing if not found.
  ///
  /// ## Parameters
  ///
  /// - [id]: The entity ID to delete.
  ///
  /// ## Throws
  ///
  /// - [EntityNotFoundException]: If the entity does not exist.
  Future<void> deleteOrThrow(String id) async {
    final deleted = await delete(id);
    if (!deleted) {
      throw EntityNotFoundException(entityId: id, storageName: _name);
    }
  }

  /// Deletes multiple entities by their IDs.
  ///
  /// ## Parameters
  ///
  /// - [ids]: The entity IDs to delete.
  ///
  /// ## Returns
  ///
  /// The number of entities actually deleted.
  Future<int> deleteMany(Iterable<String> ids) async {
    _checkNotDisposed();

    var count = 0;
    for (final id in ids) {
      if (await delete(id)) {
        count++;
      }
    }
    return count;
  }

  /// Deletes all entities in the collection.
  ///
  /// **Warning**: This operation cannot be undone.
  ///
  /// ## Returns
  ///
  /// The number of entities deleted.
  Future<int> deleteAll() async {
    _checkNotDisposed();

    return await _collectionLock.synchronized(() async {
      final count = await _storage.deleteAll();
      _indexManager.clearAllEntries();
      _entityVersions.clear();
      _entityLocks.clear();

      // Invalidate entire query cache
      _queryCache?.invalidateAll();

      _logger.info('Deleted all $count entities.');
      return count;
    });
  }

  // ---------------------------------------------------------------------------
  // Query Operations
  // ---------------------------------------------------------------------------

  /// Finds entities matching the given query.
  ///
  /// The query is automatically optimized to use available indexes
  /// when possible. If query result caching is enabled, cached results
  /// are returned when available.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to execute.
  /// - [bypassCache]: If true, bypasses the query cache even if enabled.
  ///
  /// ## Returns
  ///
  /// A list of matching entities.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Simple equality query
  /// final active = await collection.find(
  ///   QueryBuilder().whereEquals('status', 'active').build(),
  /// );
  ///
  /// // Range query
  /// final expensive = await collection.find(
  ///   QueryBuilder().whereGreaterThan('price', 100.0).build(),
  /// );
  ///
  /// // Complex query
  /// final results = await collection.find(
  ///   QueryBuilder()
  ///     .whereEquals('category', 'electronics')
  ///     .whereBetween('price', 100.0, 500.0)
  ///     .build(),
  /// );
  ///
  /// // Bypass cache for fresh results
  /// final fresh = await collection.find(query, bypassCache: true);
  /// ```
  Future<List<T>> find(IQuery query, {bool bypassCache = false}) async {
    _checkNotDisposed();

    return await _collectionLock.synchronized(() async {
      // Check query cache first
      if (_queryCacheEnabled && !bypassCache && _queryCache != null) {
        final cached = _queryCache!.get(query);
        if (cached != null) {
          _logger.debug('Query cache hit, returning ${cached.length} results.');
          return cached;
        }
      }

      // Use query optimizer to generate execution plan
      final totalEntities = await _storage.count;
      final plan = _queryOptimizer.optimize(query, totalEntities);

      _logger.debug(
        'Executing query with plan: ${plan.strategy.name}, '
        'estimated cost: ${plan.estimatedCost.toStringAsFixed(2)}',
      );

      // Execute based on plan strategy
      final results = await _executePlan(plan);

      // Cache results if caching is enabled
      if (_queryCacheEnabled && _queryCache != null) {
        _queryCache!.put(query, results);
        _logger.debug('Cached query results (${results.length} entities).');
      }

      return results;
    });
  }

  /// Executes a query plan and returns matching entities.
  Future<List<T>> _executePlan(QueryPlan plan) async {
    switch (plan.strategy) {
      case ExecutionStrategy.fullScan:
        return _executeFullScan(plan.query);

      case ExecutionStrategy.indexScan:
        return _executeIndexScan(plan);

      case ExecutionStrategy.indexScanWithFilter:
        return _executeIndexScanWithFilter(plan);

      case ExecutionStrategy.multiIndexIntersect:
        return _executeMultiIndexIntersect(plan);

      case ExecutionStrategy.multiIndexUnion:
        return _executeMultiIndexUnion(plan);
    }
  }

  /// Executes a full scan query.
  Future<List<T>> _executeFullScan(IQuery query) async {
    _logger.debug('Performing full scan for query.');
    final allData = await _storage.getAll();
    return allData.entries
        .where((entry) => query.matches(entry.value))
        .map((entry) => _fromMap(entry.key, entry.value))
        .toList();
  }

  /// Executes an index scan query.
  Future<List<T>> _executeIndexScan(QueryPlan plan) async {
    final field = plan.indexField!;

    List<String> ids;

    // Handle different index scan types
    if (plan.inValues != null) {
      // IN query - multiple lookups
      _logger.debug('Using index on field "$field" for IN query.');
      final allIds = <String>{};
      for (final value in plan.inValues!) {
        allIds.addAll(_indexManager.search(field, value));
      }
      ids = allIds.toList();
    } else if (plan.rangeBounds != null) {
      // Range query
      final bounds = plan.rangeBounds!;
      _logger.debug('Using btree index on field "$field" for range query.');

      if (bounds.lower != null && bounds.upper != null) {
        // Between query
        ids = _indexManager.rangeSearch(
          field,
          bounds.lower,
          bounds.upper,
          includeLower: bounds.includeLower,
          includeUpper: bounds.includeUpper,
        );
      } else if (bounds.lower != null) {
        // Greater than (or equal)
        if (bounds.includeLower) {
          ids = _indexManager.greaterThanOrEqual(field, bounds.lower);
        } else {
          ids = _indexManager.greaterThan(field, bounds.lower);
        }
      } else {
        // Less than (or equal)
        if (bounds.includeUpper) {
          ids = _indexManager.lessThanOrEqual(field, bounds.upper);
        } else {
          ids = _indexManager.lessThan(field, bounds.upper);
        }
      }
    } else {
      // Equality query
      _logger.debug(
        'Using ${plan.indexType?.name ?? "index"} on field "$field" for equality query.',
      );
      ids = _indexManager.search(field, plan.indexValue);
    }

    return _getEntitiesByIds(ids);
  }

  /// Executes an index scan with post-filter.
  Future<List<T>> _executeIndexScanWithFilter(QueryPlan plan) async {
    // First, execute the index scan
    final indexResults = await _executeIndexScan(plan);

    // Then apply the post-filter
    if (plan.postFilter == null) {
      return indexResults;
    }

    _logger.debug('Applying post-filter to ${indexResults.length} results.');
    return indexResults
        .where((entity) => plan.postFilter!.matches(entity.toMap()))
        .toList();
  }

  /// Executes a multi-index intersection (AND).
  Future<List<T>> _executeMultiIndexIntersect(QueryPlan plan) async {
    if (plan.subPlans == null || plan.subPlans!.isEmpty) {
      return [];
    }

    _logger.debug(
      'Executing multi-index intersection with ${plan.subPlans!.length} sub-plans.',
    );

    // Execute first sub-plan to get initial set
    Set<String>? resultIds;

    for (final subPlan in plan.subPlans!) {
      final subResults = await _executePlan(subPlan);
      final subIds = subResults.map((e) => e.id!).toSet();

      if (resultIds == null) {
        resultIds = subIds;
      } else {
        resultIds = resultIds.intersection(subIds);
      }

      // Early exit if intersection is empty
      if (resultIds.isEmpty) {
        return [];
      }
    }

    return _getEntitiesByIds(resultIds?.toList() ?? []);
  }

  /// Executes a multi-index union (OR).
  Future<List<T>> _executeMultiIndexUnion(QueryPlan plan) async {
    if (plan.subPlans == null || plan.subPlans!.isEmpty) {
      return [];
    }

    _logger.debug(
      'Executing multi-index union with ${plan.subPlans!.length} sub-plans.',
    );

    final resultIds = <String>{};

    for (final subPlan in plan.subPlans!) {
      final subResults = await _executePlan(subPlan);
      resultIds.addAll(subResults.map((e) => e.id!));
    }

    return _getEntitiesByIds(resultIds.toList());
  }

  /// Finds a single entity matching the query.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to execute.
  ///
  /// ## Returns
  ///
  /// The first matching entity, or `null` if none found.
  Future<T?> findOne(IQuery query) async {
    final results = await find(query);
    return results.isEmpty ? null : results.first;
  }

  /// Finds a single entity matching the query, throwing if not found.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to execute.
  ///
  /// ## Returns
  ///
  /// The first matching entity.
  ///
  /// ## Throws
  ///
  /// - [EntityNotFoundException]: If no entity matches.
  Future<T> findOneOrThrow(IQuery query) async {
    final result = await findOne(query);
    if (result == null) {
      throw EntityNotFoundException(
        entityId: 'query: ${query.toMap()}',
        storageName: _name,
      );
    }
    return result;
  }

  /// Counts entities matching the query.
  ///
  /// When an appropriate index is available, this method returns the count
  /// directly from the index without loading or deserializing any entities,
  /// providing O(1) to O(log n + k) performance.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to execute. If null, counts all entities.
  ///
  /// ## Returns
  ///
  /// The number of matching entities.
  ///
  /// ## Performance
  ///
  /// - With index: O(1) for equality, O(log n + k) for range queries
  /// - Without index: O(n) full scan with deserialization
  Future<int> countWhere([IQuery? query]) async {
    if (query == null) {
      return count;
    }

    // Try to use index-only counting (no deserialization needed)
    final indexCount = _tryIndexedCount(query);
    if (indexCount != null) {
      _logger.debug('Using index-only count for query.');
      return indexCount;
    }

    // Fall back to find + count (requires deserialization)
    final results = await find(query);
    return results.length;
  }

  /// Checks if any entity exists matching the query.
  ///
  /// When an appropriate index is available, this method checks existence
  /// directly from the index without loading or deserializing any entities,
  /// providing O(1) performance for most queries.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to execute.
  ///
  /// ## Returns
  ///
  /// `true` if at least one entity matches, `false` otherwise.
  ///
  /// ## Performance
  ///
  /// - With index: O(1) for most queries
  /// - Without index: O(n) full scan with deserialization
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Check if any product with this email exists (uses index)
  /// final hasAdmin = await users.existsWhere(
  ///   Query.equals('role', 'admin'),
  /// );
  /// ```
  Future<bool> existsWhere(IQuery query) async {
    // Try to use index-only existence check (no deserialization needed)
    final indexExists = _tryIndexedExists(query);
    if (indexExists != null) {
      _logger.debug('Using index-only existence check for query.');
      return indexExists;
    }

    // Fall back to findOne (requires deserialization of at most one entity)
    final result = await findOne(query);
    return result != null;
  }

  /// Tries to get count directly from index without loading entities.
  ///
  /// Returns null if no suitable index is available.
  int? _tryIndexedCount(IQuery query) {
    if (query is EqualsQuery) {
      if (_indexManager.hasIndex(query.field)) {
        return _indexManager.countEquals(query.field, query.value);
      }
    }

    if (query is GreaterThanQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.countGreaterThan(query.field, query.value);
      }
    }

    if (query is GreaterThanOrEqualsQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.countGreaterThanOrEqual(query.field, query.value);
      }
    }

    if (query is LessThanQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.countLessThan(query.field, query.value);
      }
    }

    if (query is LessThanOrEqualsQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.countLessThanOrEqual(query.field, query.value);
      }
    }

    if (query is BetweenQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.countRange(
          query.field,
          query.lowerBound,
          query.upperBound,
          includeLower: query.includeLower,
          includeUpper: query.includeUpper,
        );
      }
    }

    if (query is InQuery) {
      if (_indexManager.hasIndex(query.field)) {
        int total = 0;
        for (final value in query.values) {
          total += _indexManager.countEquals(query.field, value);
        }
        return total;
      }
    }

    // No suitable index found
    return null;
  }

  /// Tries to check existence directly from index without loading entities.
  ///
  /// Returns null if no suitable index is available.
  bool? _tryIndexedExists(IQuery query) {
    if (query is EqualsQuery) {
      if (_indexManager.hasIndex(query.field)) {
        return _indexManager.existsEquals(query.field, query.value);
      }
    }

    if (query is GreaterThanQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.existsGreaterThan(query.field, query.value);
      }
    }

    if (query is LessThanQuery) {
      if (_indexManager.hasIndexOfType(query.field, IndexType.btree)) {
        return _indexManager.existsLessThan(query.field, query.value);
      }
    }

    // For other queries, use count > 0
    if (query is GreaterThanOrEqualsQuery ||
        query is LessThanOrEqualsQuery ||
        query is BetweenQuery ||
        query is InQuery) {
      final indexCount = _tryIndexedCount(query);
      if (indexCount != null) {
        return indexCount > 0;
      }
    }

    // No suitable index found
    return null;
  }

  /// Retrieves entities by their IDs.
  Future<List<T>> _getEntitiesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];

    final dataMap = await _storage.getMany(ids);
    return dataMap.entries
        .map((entry) => _fromMap(entry.key, entry.value))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Query Optimizer Methods
  // ---------------------------------------------------------------------------

  /// Gets the query optimizer for this collection.
  ///
  /// Use this to inspect query plans or configure optimization behavior.
  @visibleForTesting
  QueryOptimizer get queryOptimizer => _queryOptimizer;

  /// Generates an execution plan for the query without executing it.
  ///
  /// Useful for analyzing query performance and index utilization.
  ///
  /// ## Returns
  ///
  /// A [QueryPlan] describing how the query would be executed.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final plan = await collection.explain(query);
  /// print('Strategy: ${plan.strategy}');
  /// print('Estimated cost: ${plan.estimatedCost}');
  /// print('Uses index: ${plan.usesIndex}');
  /// ```
  Future<QueryPlan> explain(IQuery query) async {
    _checkNotDisposed();
    final totalEntities = await _storage.count;
    return _queryOptimizer.optimize(query, totalEntities);
  }

  /// Gets statistics for all indexes in this collection.
  ///
  /// Returns information about cardinality, selectivity, and entry counts
  /// for each index.
  List<IndexStatistics> getIndexStatistics() {
    return _queryOptimizer.getAllIndexStatistics();
  }

  /// Clears the query plan cache.
  ///
  /// Forces re-optimization of all queries on next execution.
  void clearQueryPlanCache() {
    _queryOptimizer.clearCache();
  }

  // ---------------------------------------------------------------------------
  // Utility Methods
  // ---------------------------------------------------------------------------

  /// Gets or creates an entity-level lock.
  Lock _getEntityLock(String entityId) {
    return _entityLocks.putIfAbsent(entityId, () => Lock());
  }

  /// Ensures the collection is not disposed.
  void _checkNotDisposed() {
    if (_disposed) {
      throw CollectionException('Collection "$_name" has been disposed.');
    }
  }

  /// Invalidates query cache entries for queries using the given fields.
  ///
  /// If selective invalidation is disabled, invalidates the entire cache.
  void _invalidateCacheForFields(Set<String> fields) {
    if (!_queryCacheEnabled || _queryCache == null) return;

    final count = _queryCache!.invalidateFields(fields);
    if (count > 0) {
      _logger.debug('Invalidated $count cached queries for fields: $fields');
    }
  }

  /// Clears all indexes without removing them.
  ///
  /// The index structure is preserved, but all entries are removed.
  Future<void> clearAllIndexEntries() async {
    _checkNotDisposed();

    await _collectionLock.synchronized(() async {
      _indexManager.clearAllEntries();
      _logger.info('Cleared all index entries.');
    });
  }

  /// Removes all indexes from the collection.
  Future<void> removeAllIndexes() async {
    _checkNotDisposed();

    await _collectionLock.synchronized(() async {
      _indexManager.removeAllIndexes();
      _logger.info('Removed all indexes.');
    });
  }

  /// Rebuilds all indexes from current storage state.
  ///
  /// Useful after data migration or when indexes may be out of sync.
  Future<void> rebuildAllIndexes() async {
    _checkNotDisposed();

    await _collectionLock.synchronized(() async {
      _indexManager.clearAllEntries();

      await for (final record in _storage.stream()) {
        _indexManager.insert(record.id, record.data);
      }

      _logger.info('Rebuilt all indexes.');
    });
  }

  /// Flushes any pending writes to storage.
  Future<void> flush() async {
    _checkNotDisposed();
    await _storage.flush();
  }

  /// Disposes of the collection and releases resources.
  ///
  /// After calling this method, the collection cannot be used.
  Future<void> dispose() async {
    if (_disposed) return;

    await _collectionLock.synchronized(() async {
      _entityLocks.clear();
      _entityVersions.clear();
      _indexManager.removeAllIndexes();
      _disposed = true;
      _logger.info('Disposed collection "$_name".');
    });
  }

  @override
  String toString() {
    return 'Collection<$T>(name: $_name, indexes: ${_indexManager.indexCount})';
  }
}

/// Configuration for collection behavior.
///
/// Provides options for customizing collection operations such as
/// versioning, logging, and concurrency settings.
@immutable
class CollectionConfig {
  /// Whether to enable optimistic concurrency control.
  final bool enableVersioning;

  /// Whether to enable debug logging.
  final bool enableDebugLogging;

  /// Maximum number of entity locks to keep cached.
  final int maxCachedLocks;

  /// Creates a new collection configuration.
  const CollectionConfig({
    this.enableVersioning = true,
    this.enableDebugLogging = false,
    this.maxCachedLocks = 1000,
  });

  /// Default configuration for production use.
  static const CollectionConfig production = CollectionConfig(
    enableVersioning: true,
    enableDebugLogging: false,
    maxCachedLocks: 10000,
  );

  /// Configuration for development use.
  static const CollectionConfig development = CollectionConfig(
    enableVersioning: true,
    enableDebugLogging: true,
    maxCachedLocks: 100,
  );

  /// Configuration for testing.
  static const CollectionConfig testing = CollectionConfig(
    enableVersioning: false,
    enableDebugLogging: true,
    maxCachedLocks: 10,
  );
}
