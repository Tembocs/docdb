/// DocDB Storage Module
///
/// Provides the storage layer for entity persistence. This module defines
/// the abstract storage interface and various implementations for different
/// use cases.
///
/// ## Overview
///
/// The storage layer handles the low-level persistence of entity data,
/// abstracting away the details of how data is stored on disk or in memory.
///
/// ## Available Implementations
///
/// - [MemoryStorage]: Fast, volatile storage for testing and development.
///   All data is lost when the storage is closed.
///
/// - [FileStorage]: File-per-entity JSON storage for development and
///   small datasets. Provides human-readable storage with good durability.
///
/// - [PagedStorage]: High-performance page-based storage using the engine
///   module. Suitable for production workloads with efficient caching
///   and optional WAL-based durability.
///
/// ## Usage
///
/// ```dart
/// import 'package:docdb/src/storage/storage_module.dart';
///
/// // For testing
/// final memoryStorage = MemoryStorage<Product>(name: 'products');
/// await memoryStorage.open();
///
/// // For development (human-readable JSON files)
/// final fileStorage = FileStorage<Product>(
///   name: 'products',
///   directory: './data/products',
/// );
/// await fileStorage.open();
///
/// // For production (high-performance paged storage)
/// final pagedStorage = await PagedStorage.openStorage<Product>(
///   name: 'products',
///   filePath: './data/products.db',
/// );
///
/// await storage.insert('prod-1', {'name': 'Widget', 'price': 29.99});
/// final data = await storage.get('prod-1');
///
/// await storage.close();
/// ```
///
/// ## Transactions
///
/// Storage implementations that support transactions implement the
/// [TransactionalStorage] mixin:
///
/// ```dart
/// if (storage.supportsTransactions) {
///   final txnStorage = storage as TransactionalStorage;
///   await txnStorage.beginTransaction();
///   try {
///     await storage.insert('id1', data1);
///     await storage.insert('id2', data2);
///     await txnStorage.commit();
///   } catch (e) {
///     await txnStorage.rollback();
///     rethrow;
///   }
/// }
/// ```
library;

export 'file_storage.dart' show FileStorage, FileStorageConfig;
export 'memory_storage.dart' show MemoryStorage;
export 'paged_storage.dart' show PagedStorage, PagedStorageConfig;
export 'storage.dart'
    show EntityFromMap, Storage, StorageRecord, TransactionalStorage;
