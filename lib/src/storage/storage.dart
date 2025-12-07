/// EntiDB Storage - Storage Interface
///
/// Defines the abstract interface for entity storage backends.
/// All storage implementations must implement this interface.
library;

import '../entity/entity.dart';

/// Factory function type for deserializing entities from stored data.
///
/// Takes the entity ID and the stored map data, returns a fully
/// constructed entity instance.
typedef EntityFromMap<T extends Entity> =
    T Function(String id, Map<String, dynamic> data);

/// Abstract interface for entity storage backends.
///
/// This interface defines the contract that all storage implementations
/// must fulfill. It provides CRUD operations for entities with generic
/// type safety through the `Entity` bound.
///
/// ## Implementations
///
/// - [FileStorage]: File-per-entity storage (development/small datasets)
/// - [PagedStorage]: Page-based storage using the engine module (production)
/// - [MemoryStorage]: In-memory storage (testing)
///
/// ## Usage
///
/// ```dart
/// // Storage is typically accessed through Collection<T>
/// final storage = await FileStorage<Product>.open(
///   directory: './data/products',
///   fromMap: Product.fromMap,
/// );
///
/// await storage.insert('prod-1', {'name': 'Widget', 'price': 29.99});
/// final data = await storage.get('prod-1');
/// ```
///
/// ## Transaction Support
///
/// Storage implementations may support transactions through the
/// [TransactionalStorage] mixin. Use [supportsTransactions] to check.
abstract class Storage<T extends Entity> {
  /// Unique name identifying this storage instance.
  ///
  /// Typically corresponds to the collection name.
  String get name;

  /// Whether this storage backend supports transactions.
  ///
  /// If `true`, the storage can be cast to [TransactionalStorage] for
  /// transaction-aware operations.
  bool get supportsTransactions;

  /// Whether this storage backend is currently open.
  bool get isOpen;

  /// Returns the number of entities in storage.
  Future<int> get count;

  /// Initializes the storage backend.
  ///
  /// Must be called before any other operations. Implementations should
  /// handle creation of necessary directories/files and loading of
  /// metadata/indexes.
  ///
  /// Throws [StorageInitializationException] if initialization fails.
  Future<void> open();

  /// Closes the storage backend and releases resources.
  ///
  /// Flushes any pending writes to disk. After closing, the storage
  /// cannot be used until [open] is called again.
  ///
  /// Throws [StorageException] if close fails.
  Future<void> close();

  /// Retrieves an entity by its unique identifier.
  ///
  /// Returns the entity data as a map, or `null` if not found.
  ///
  /// - [id]: The unique identifier of the entity.
  ///
  /// Throws [StorageReadException] if the read operation fails.
  Future<Map<String, dynamic>?> get(String id);

  /// Retrieves multiple entities by their identifiers.
  ///
  /// Returns a map of ID to entity data. Missing IDs are omitted from
  /// the result rather than included with null values.
  ///
  /// - [ids]: The identifiers of entities to retrieve.
  ///
  /// Throws [StorageReadException] if the read operation fails.
  Future<Map<String, Map<String, dynamic>>> getMany(Iterable<String> ids);

  /// Retrieves all entities from storage.
  ///
  /// Returns a map of ID to entity data. For large datasets, consider
  /// using [stream] instead to avoid memory issues.
  ///
  /// Throws [StorageReadException] if the read operation fails.
  Future<Map<String, Map<String, dynamic>>> getAll();

  /// Streams all entities from storage.
  ///
  /// Each record contains the entity ID and its data. Useful for
  /// processing large datasets without loading everything into memory.
  ///
  /// Throws [StorageReadException] if the read operation fails.
  Stream<StorageRecord> stream();

  /// Checks if an entity with the given ID exists.
  ///
  /// - [id]: The unique identifier to check.
  ///
  /// Returns `true` if the entity exists, `false` otherwise.
  Future<bool> exists(String id);

  /// Inserts a new entity into storage.
  ///
  /// - [id]: The unique identifier for the entity.
  /// - [data]: The entity data as a map.
  ///
  /// Throws [StorageWriteException] if the write fails.
  /// Throws [EntityAlreadyExistsException] if an entity with this ID exists.
  Future<void> insert(String id, Map<String, dynamic> data);

  /// Inserts multiple entities in a single operation.
  ///
  /// - [entities]: Map of ID to entity data.
  ///
  /// This operation should be atomic when possible - either all entities
  /// are inserted or none are.
  ///
  /// Throws [StorageWriteException] if the write fails.
  /// Throws [EntityAlreadyExistsException] if any entity ID already exists.
  Future<void> insertMany(Map<String, Map<String, dynamic>> entities);

  /// Updates an existing entity in storage.
  ///
  /// - [id]: The unique identifier of the entity to update.
  /// - [data]: The new entity data.
  ///
  /// Throws [StorageWriteException] if the write fails.
  /// Throws [EntityNotFoundException] if no entity with this ID exists.
  Future<void> update(String id, Map<String, dynamic> data);

  /// Inserts or updates an entity.
  ///
  /// If an entity with the given ID exists, it is updated. Otherwise,
  /// a new entity is inserted.
  ///
  /// - [id]: The unique identifier.
  /// - [data]: The entity data.
  ///
  /// Throws [StorageWriteException] if the operation fails.
  Future<void> upsert(String id, Map<String, dynamic> data);

  /// Deletes an entity by its identifier.
  ///
  /// - [id]: The unique identifier of the entity to delete.
  ///
  /// Returns `true` if an entity was deleted, `false` if not found.
  ///
  /// Throws [StorageWriteException] if the delete fails.
  Future<bool> delete(String id);

  /// Deletes multiple entities by their identifiers.
  ///
  /// - [ids]: The identifiers of entities to delete.
  ///
  /// Returns the number of entities actually deleted.
  ///
  /// Throws [StorageWriteException] if the delete fails.
  Future<int> deleteMany(Iterable<String> ids);

  /// Deletes all entities from storage.
  ///
  /// Use with caution - this operation cannot be undone.
  ///
  /// Returns the number of entities deleted.
  ///
  /// Throws [StorageWriteException] if the operation fails.
  Future<int> deleteAll();

  /// Flushes any buffered writes to persistent storage.
  ///
  /// This ensures durability of all previous write operations.
  /// May be a no-op for storage backends that write synchronously.
  Future<void> flush();
}

/// A record from storage containing entity ID and data.
///
/// Used by [Storage.stream] to provide both the ID and data together.
final class StorageRecord {
  /// The unique identifier of the entity.
  final String id;

  /// The entity data as a map.
  final Map<String, dynamic> data;

  /// Creates a new storage record.
  const StorageRecord({required this.id, required this.data});

  @override
  String toString() => 'StorageRecord(id: $id, data: $data)';
}

/// Mixin for storage backends that support transactions.
///
/// Provides transaction lifecycle management including begin, commit,
/// and rollback operations.
mixin TransactionalStorage<T extends Entity> on Storage<T> {
  /// Whether a transaction is currently active.
  bool get inTransaction;

  /// Begins a new transaction.
  ///
  /// All subsequent write operations will be part of this transaction
  /// until [commit] or [rollback] is called.
  ///
  /// Throws [TransactionException] if a transaction is already active.
  Future<void> beginTransaction();

  /// Commits the current transaction.
  ///
  /// All write operations since [beginTransaction] are made durable.
  ///
  /// Throws [TransactionException] if no transaction is active.
  /// Throws [StorageWriteException] if the commit fails.
  Future<void> commit();

  /// Rolls back the current transaction.
  ///
  /// All write operations since [beginTransaction] are discarded.
  ///
  /// Throws [TransactionException] if no transaction is active.
  Future<void> rollback();
}
