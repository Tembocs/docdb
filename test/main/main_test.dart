/// Comprehensive tests for the Main module.
///
/// Tests cover:
/// - DocDB class lifecycle and operations
/// - DocDBConfig configurations and factory methods
/// - DocDBStats statistics collection
/// - StorageBackend enum
/// - CollectionEntry internal helper
/// - Edge cases and error handling
import 'dart:io';

import 'package:docdb/docdb.dart';
import 'package:docdb/src/collection/collection.dart';
import 'package:docdb/src/encryption/no_encryption_service.dart';
import 'package:docdb/src/main/collection_entry.dart';
import 'package:docdb/src/storage/memory_storage.dart';
import 'package:test/test.dart';

// =============================================================================
// Test Entities
// =============================================================================

/// Simple test entity for basic operations.
class TestProduct implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final int quantity;

  TestProduct({
    this.id,
    required this.name,
    required this.price,
    this.quantity = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'quantity': quantity,
  };

  static TestProduct fromMap(String id, Map<String, dynamic> map) {
    return TestProduct(
      id: id,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestProduct &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          price == other.price &&
          quantity == other.quantity;

  @override
  int get hashCode => name.hashCode ^ price.hashCode ^ quantity.hashCode;
}

/// Another test entity for type mismatch testing.
class TestUser implements Entity {
  @override
  final String? id;
  final String username;
  final String email;
  final bool isActive;

  TestUser({
    this.id,
    required this.username,
    required this.email,
    this.isActive = true,
  });

  @override
  Map<String, dynamic> toMap() => {
    'username': username,
    'email': email,
    'isActive': isActive,
  };

  static TestUser fromMap(String id, Map<String, dynamic> map) {
    return TestUser(
      id: id,
      username: map['username'] as String,
      email: map['email'] as String,
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}

/// Minimal entity for edge case testing.
class MinimalEntity implements Entity {
  @override
  final String? id;

  MinimalEntity({this.id});

  @override
  Map<String, dynamic> toMap() => {};

  static MinimalEntity fromMap(String id, Map<String, dynamic> map) {
    return MinimalEntity(id: id);
  }
}

/// Entity with complex nested data.
class ComplexEntity implements Entity {
  @override
  final String? id;
  final Map<String, dynamic> metadata;
  final List<String> tags;

  ComplexEntity({this.id, required this.metadata, required this.tags});

  @override
  Map<String, dynamic> toMap() => {'metadata': metadata, 'tags': tags};

  static ComplexEntity fromMap(String id, Map<String, dynamic> map) {
    return ComplexEntity(
      id: id,
      metadata: Map<String, dynamic>.from(map['metadata'] as Map),
      tags: List<String>.from(map['tags'] as List),
    );
  }
}

void main() {
  // ===========================================================================
  // StorageBackend Enum Tests
  // ===========================================================================

  group('StorageBackend', () {
    test('should have paged backend', () {
      expect(StorageBackend.paged, isNotNull);
      expect(StorageBackend.paged.name, 'paged');
    });

    test('should have memory backend', () {
      expect(StorageBackend.memory, isNotNull);
      expect(StorageBackend.memory.name, 'memory');
    });

    test('should have exactly 2 values', () {
      expect(StorageBackend.values.length, 2);
    });

    test('should be comparable', () {
      expect(StorageBackend.paged == StorageBackend.paged, isTrue);
      expect(StorageBackend.paged == StorageBackend.memory, isFalse);
    });

    test('should support index access', () {
      expect(StorageBackend.values[0], StorageBackend.paged);
      expect(StorageBackend.values[1], StorageBackend.memory);
    });
  });

  // ===========================================================================
  // DocDBConfig Tests
  // ===========================================================================

  group('DocDBConfig', () {
    group('Default constructor', () {
      test('should create with default values', () {
        const config = DocDBConfig();

        expect(config.storageBackend, StorageBackend.paged);
        expect(config.bufferPoolSize, 1024);
        expect(config.pageSize, 4096);
        expect(config.enableTransactions, isTrue);
        expect(config.verifyChecksums, isTrue);
        expect(config.maxEntitySize, 1024 * 1024);
        expect(config.encryptionService, isNull);
        expect(config.enableDebugLogging, isFalse);
        expect(config.autoFlushOnClose, isTrue);
      });

      test('should create with custom values', () {
        const config = DocDBConfig(
          storageBackend: StorageBackend.memory,
          bufferPoolSize: 2048,
          pageSize: 8192,
          enableTransactions: false,
          verifyChecksums: false,
          maxEntitySize: 2 * 1024 * 1024,
          enableDebugLogging: true,
          autoFlushOnClose: false,
        );

        expect(config.storageBackend, StorageBackend.memory);
        expect(config.bufferPoolSize, 2048);
        expect(config.pageSize, 8192);
        expect(config.enableTransactions, isFalse);
        expect(config.verifyChecksums, isFalse);
        expect(config.maxEntitySize, 2 * 1024 * 1024);
        expect(config.enableDebugLogging, isTrue);
        expect(config.autoFlushOnClose, isFalse);
      });

      test('should handle zero buffer pool size', () {
        const config = DocDBConfig(bufferPoolSize: 0);
        expect(config.bufferPoolSize, 0);
      });

      test('should handle large buffer pool size', () {
        const config = DocDBConfig(bufferPoolSize: 1000000);
        expect(config.bufferPoolSize, 1000000);
      });

      test('should handle minimum page size', () {
        const config = DocDBConfig(pageSize: 4096);
        expect(config.pageSize, 4096);
      });

      test('should handle large page size', () {
        const config = DocDBConfig(pageSize: 65536);
        expect(config.pageSize, 65536);
      });
    });

    group('Factory constructors', () {
      test('production() should use optimized settings', () {
        final config = DocDBConfig.production();

        expect(config.storageBackend, StorageBackend.paged);
        expect(config.bufferPoolSize, 2048);
        expect(config.pageSize, 4096);
        expect(config.enableTransactions, isTrue);
        expect(config.verifyChecksums, isTrue);
        expect(config.maxEntitySize, 4 * 1024 * 1024);
        expect(config.enableDebugLogging, isFalse);
        expect(config.autoFlushOnClose, isTrue);
      });

      test('production() should accept encryption service', () {
        final encryption = NoEncryptionService();
        final config = DocDBConfig.production(encryptionService: encryption);

        expect(config.encryptionService, encryption);
      });

      test('development() should enable debug logging', () {
        final config = DocDBConfig.development();

        expect(config.storageBackend, StorageBackend.paged);
        expect(config.bufferPoolSize, 256);
        expect(config.enableDebugLogging, isTrue);
        expect(config.enableTransactions, isTrue);
        expect(config.verifyChecksums, isTrue);
      });

      test('development() should accept encryption service', () {
        final encryption = NoEncryptionService();
        final config = DocDBConfig.development(encryptionService: encryption);

        expect(config.encryptionService, encryption);
      });

      test('inMemory() should use memory backend', () {
        final config = DocDBConfig.inMemory();

        expect(config.storageBackend, StorageBackend.memory);
        expect(config.enableTransactions, isFalse);
        expect(config.enableDebugLogging, isTrue);
        expect(config.autoFlushOnClose, isFalse);
      });
    });

    group('encryptionEnabled property', () {
      test('should return false when no encryption service', () {
        const config = DocDBConfig();
        expect(config.encryptionEnabled, isFalse);
      });

      test('should return false when encryption service is disabled', () {
        final encryption = NoEncryptionService();
        final config = DocDBConfig(encryptionService: encryption);
        expect(config.encryptionEnabled, isFalse);
      });
    });

    group('copyWith', () {
      test('should copy with no changes', () {
        final original = DocDBConfig.production();
        final copy = original.copyWith();

        expect(copy.storageBackend, original.storageBackend);
        expect(copy.bufferPoolSize, original.bufferPoolSize);
        expect(copy.pageSize, original.pageSize);
        expect(copy.enableTransactions, original.enableTransactions);
        expect(copy.verifyChecksums, original.verifyChecksums);
        expect(copy.maxEntitySize, original.maxEntitySize);
        expect(copy.enableDebugLogging, original.enableDebugLogging);
        expect(copy.autoFlushOnClose, original.autoFlushOnClose);
      });

      test('should copy with single change', () {
        final original = DocDBConfig.production();
        final copy = original.copyWith(bufferPoolSize: 4096);

        expect(copy.bufferPoolSize, 4096);
        expect(copy.storageBackend, original.storageBackend);
        expect(copy.pageSize, original.pageSize);
      });

      test('should copy with multiple changes', () {
        final original = DocDBConfig.production();
        final copy = original.copyWith(
          storageBackend: StorageBackend.memory,
          bufferPoolSize: 512,
          enableDebugLogging: true,
          autoFlushOnClose: false,
        );

        expect(copy.storageBackend, StorageBackend.memory);
        expect(copy.bufferPoolSize, 512);
        expect(copy.enableDebugLogging, isTrue);
        expect(copy.autoFlushOnClose, isFalse);
        // Unchanged
        expect(copy.pageSize, original.pageSize);
        expect(copy.enableTransactions, original.enableTransactions);
      });

      test('should copy with all changes', () {
        const original = DocDBConfig();
        final encryption = NoEncryptionService();
        final copy = original.copyWith(
          storageBackend: StorageBackend.memory,
          bufferPoolSize: 100,
          pageSize: 16384,
          enableTransactions: false,
          verifyChecksums: false,
          maxEntitySize: 500000,
          encryptionService: encryption,
          enableDebugLogging: true,
          autoFlushOnClose: false,
        );

        expect(copy.storageBackend, StorageBackend.memory);
        expect(copy.bufferPoolSize, 100);
        expect(copy.pageSize, 16384);
        expect(copy.enableTransactions, isFalse);
        expect(copy.verifyChecksums, isFalse);
        expect(copy.maxEntitySize, 500000);
        expect(copy.encryptionService, encryption);
        expect(copy.enableDebugLogging, isTrue);
        expect(copy.autoFlushOnClose, isFalse);
      });

      test('should preserve encryption service when not overridden', () {
        final encryption = NoEncryptionService();
        final original = DocDBConfig(encryptionService: encryption);
        final copy = original.copyWith(bufferPoolSize: 1000);

        expect(copy.encryptionService, encryption);
      });
    });
  });

  // ===========================================================================
  // DocDBStats Tests
  // ===========================================================================

  group('DocDBStats', () {
    test('should create with required fields', () {
      const stats = DocDBStats(
        path: '/data/db',
        isOpen: true,
        collectionCount: 3,
        collections: {},
        encryptionEnabled: false,
        storageBackend: StorageBackend.paged,
      );

      expect(stats.path, '/data/db');
      expect(stats.isOpen, isTrue);
      expect(stats.collectionCount, 3);
      expect(stats.collections, isEmpty);
      expect(stats.encryptionEnabled, isFalse);
      expect(stats.storageBackend, StorageBackend.paged);
    });

    test('should handle null path for in-memory', () {
      const stats = DocDBStats(
        path: null,
        isOpen: true,
        collectionCount: 0,
        collections: {},
        encryptionEnabled: false,
        storageBackend: StorageBackend.memory,
      );

      expect(stats.path, isNull);
      expect(stats.storageBackend, StorageBackend.memory);
    });

    test('should calculate totalEntityCount from collections', () {
      final stats = DocDBStats(
        path: '/data/db',
        isOpen: true,
        collectionCount: 3,
        collections: {
          'products': const CollectionStats(
            name: 'products',
            entityCount: 100,
            indexCount: 2,
          ),
          'users': const CollectionStats(
            name: 'users',
            entityCount: 50,
            indexCount: 1,
          ),
          'orders': const CollectionStats(
            name: 'orders',
            entityCount: 25,
            indexCount: 3,
          ),
        },
        encryptionEnabled: true,
        storageBackend: StorageBackend.paged,
      );

      expect(stats.totalEntityCount, 175); // 100 + 50 + 25
    });

    test('should calculate totalIndexCount from collections', () {
      final stats = DocDBStats(
        path: '/data/db',
        isOpen: true,
        collectionCount: 2,
        collections: {
          'products': const CollectionStats(
            name: 'products',
            entityCount: 10,
            indexCount: 3,
          ),
          'users': const CollectionStats(
            name: 'users',
            entityCount: 5,
            indexCount: 2,
          ),
        },
        encryptionEnabled: false,
        storageBackend: StorageBackend.paged,
      );

      expect(stats.totalIndexCount, 5); // 3 + 2
    });

    test('should return zero counts for empty collections', () {
      const stats = DocDBStats(
        path: '/data/db',
        isOpen: true,
        collectionCount: 0,
        collections: {},
        encryptionEnabled: false,
        storageBackend: StorageBackend.paged,
      );

      expect(stats.totalEntityCount, 0);
      expect(stats.totalIndexCount, 0);
    });

    test('toString should include relevant info', () {
      const stats = DocDBStats(
        path: '/data/db',
        isOpen: true,
        collectionCount: 2,
        collections: {
          'products': CollectionStats(
            name: 'products',
            entityCount: 10,
            indexCount: 1,
          ),
        },
        encryptionEnabled: true,
        storageBackend: StorageBackend.paged,
      );

      final str = stats.toString();
      expect(str, contains('/data/db'));
      expect(str, contains('collections'));
      expect(str, contains('entities'));
      expect(str, contains('encrypted'));
    });

    test('toString should handle in-memory path', () {
      const stats = DocDBStats(
        path: null,
        isOpen: true,
        collectionCount: 0,
        collections: {},
        encryptionEnabled: false,
        storageBackend: StorageBackend.memory,
      );

      final str = stats.toString();
      expect(str, contains('in-memory'));
    });
  });

  // ===========================================================================
  // CollectionStats Tests
  // ===========================================================================

  group('CollectionStats', () {
    test('should create with required fields', () {
      const stats = CollectionStats(
        name: 'products',
        entityCount: 100,
        indexCount: 3,
      );

      expect(stats.name, 'products');
      expect(stats.entityCount, 100);
      expect(stats.indexCount, 3);
    });

    test('should handle zero counts', () {
      const stats = CollectionStats(
        name: 'empty',
        entityCount: 0,
        indexCount: 0,
      );

      expect(stats.entityCount, 0);
      expect(stats.indexCount, 0);
    });

    test('should handle large counts', () {
      const stats = CollectionStats(
        name: 'large',
        entityCount: 1000000,
        indexCount: 100,
      );

      expect(stats.entityCount, 1000000);
      expect(stats.indexCount, 100);
    });

    test('should handle empty name', () {
      const stats = CollectionStats(name: '', entityCount: 0, indexCount: 0);

      expect(stats.name, '');
    });

    test('should handle special characters in name', () {
      const stats = CollectionStats(
        name: 'user_data_2024',
        entityCount: 50,
        indexCount: 2,
      );

      expect(stats.name, 'user_data_2024');
    });

    test('toString should include all info', () {
      const stats = CollectionStats(
        name: 'products',
        entityCount: 42,
        indexCount: 3,
      );

      final str = stats.toString();
      expect(str, contains('products'));
      expect(str, contains('42'));
      expect(str, contains('entities'));
      expect(str, contains('3'));
      expect(str, contains('indexes'));
    });
  });

  // ===========================================================================
  // CollectionEntry Tests
  // ===========================================================================

  group('CollectionEntry', () {
    test('should create with required fields', () {
      final storage = MemoryStorage<TestProduct>(name: 'test');
      final collection = Collection<TestProduct>(
        storage: storage,
        fromMap: TestProduct.fromMap,
        name: 'products',
      );

      final entry = CollectionEntry(
        name: 'products',
        entityType: TestProduct,
        collection: collection,
        storage: storage,
      );

      expect(entry.name, 'products');
      expect(entry.entityType, TestProduct);
      expect(entry.collection, collection);
      expect(entry.storage, storage);
    });

    test('should preserve type information', () {
      final storage = MemoryStorage<TestUser>(name: 'users');
      final collection = Collection<TestUser>(
        storage: storage,
        fromMap: TestUser.fromMap,
        name: 'users',
      );

      final entry = CollectionEntry(
        name: 'users',
        entityType: TestUser,
        collection: collection,
        storage: storage,
      );

      expect(entry.entityType, TestUser);
      expect(entry.entityType != TestProduct, isTrue);
    });

    test('should handle short name', () {
      final storage = MemoryStorage<MinimalEntity>(name: 'x');
      final collection = Collection<MinimalEntity>(
        storage: storage,
        fromMap: MinimalEntity.fromMap,
        name: 'x',
      );

      final entry = CollectionEntry(
        name: 'x',
        entityType: MinimalEntity,
        collection: collection,
        storage: storage,
      );

      expect(entry.name, 'x');
    });
  });

  // ===========================================================================
  // DocDB Class Tests
  // ===========================================================================

  group('DocDB', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docdb_main_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Lifecycle', () {
      test('should open in-memory database', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        expect(db.isOpen, isTrue);
        expect(db.path, isNull);
        expect(db.collectionCount, 0);
        expect(db.collectionNames, isEmpty);

        await db.close();
        expect(db.isOpen, isFalse);
      });

      test('should open with default config', () async {
        final db = await DocDB.open(path: tempDir.path);

        expect(db.isOpen, isTrue);
        expect(db.path, tempDir.path);

        await db.close();
      });

      test('should open file-based database', () async {
        final db = await DocDB.open(
          path: tempDir.path,
          config: DocDBConfig.development(),
        );

        expect(db.isOpen, isTrue);
        expect(db.path, tempDir.path);

        await db.close();
      });

      test('should create directory if not exists', () async {
        final newPath = '${tempDir.path}/nested/deep/path';
        final db = await DocDB.open(
          path: newPath,
          config: DocDBConfig.development(),
        );

        expect(db.isOpen, isTrue);
        expect(await Directory(newPath).exists(), isTrue);

        await db.close();
      });

      test('should handle multiple open/close cycles', () async {
        for (var i = 0; i < 3; i++) {
          final db = await DocDB.open(
            path: null,
            config: DocDBConfig.inMemory(),
          );
          expect(db.isOpen, isTrue);
          await db.close();
          expect(db.isOpen, isFalse);
        }
      });

      test('should handle close being called multiple times', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.close();
        await db.close(); // Should not throw
        await db.close(); // Should not throw

        expect(db.isOpen, isFalse);
      });

      test('toString should return descriptive string', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final str = db.toString();
        expect(str, contains('DocDB'));
        expect(str, contains('in-memory'));
        expect(str, contains('open'));

        await db.close();
      });

      test('toString should include collection count', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final str = db.toString();
        expect(str, contains('collections'));
        expect(str, contains('1'));

        await db.close();
      });
    });

    group('Collection Management', () {
      test('should create collection', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(products, isNotNull);
        expect(db.hasCollection('products'), isTrue);
        expect(db.collectionCount, 1);
        expect(db.collectionNames, contains('products'));

        await db.close();
      });

      test('should return same collection on repeated access', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products1 = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final products2 = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(identical(products1, products2), isTrue);
        expect(db.collectionCount, 1);

        await db.close();
      });

      test('should support multiple collections', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        await db.collection<TestUser>('users', fromMap: TestUser.fromMap);
        await db.collection<MinimalEntity>(
          'misc',
          fromMap: MinimalEntity.fromMap,
        );

        expect(db.collectionCount, 3);
        expect(db.collectionNames, containsAll(['products', 'users', 'misc']));

        await db.close();
      });

      test('should check if collection exists', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        expect(db.hasCollection('products'), isFalse);

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(db.hasCollection('products'), isTrue);
        expect(db.hasCollection('nonexistent'), isFalse);

        await db.close();
      });

      test('should throw on type mismatch', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>('items', fromMap: TestProduct.fromMap);

        expect(
          () => db.collection<TestUser>('items', fromMap: TestUser.fromMap),
          throwsA(isA<CollectionTypeMismatchException>()),
        );

        await db.close();
      });

      test('should drop collection', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(db.hasCollection('products'), isTrue);

        final dropped = await db.dropCollection('products');
        expect(dropped, isTrue);
        expect(db.hasCollection('products'), isFalse);
        expect(db.collectionCount, 0);

        await db.close();
      });

      test(
        'should return false when dropping non-existent collection',
        () async {
          final db = await DocDB.open(
            path: null,
            config: DocDBConfig.inMemory(),
          );

          final dropped = await db.dropCollection('nonexistent');
          expect(dropped, isFalse);

          await db.close();
        },
      );

      test('should allow recreating dropped collection', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await db.dropCollection('products');

        // Recreate with same type
        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(products, isNotNull);
        expect(db.hasCollection('products'), isTrue);

        await db.close();
      });

      test(
        'should allow recreating dropped collection with different type',
        () async {
          final db = await DocDB.open(
            path: null,
            config: DocDBConfig.inMemory(),
          );

          await db.collection<TestProduct>(
            'items',
            fromMap: TestProduct.fromMap,
          );

          await db.dropCollection('items');

          // Recreate with different type
          final users = await db.collection<TestUser>(
            'items',
            fromMap: TestUser.fromMap,
          );

          expect(users, isNotNull);

          await db.close();
        },
      );

      test('should throw on collection with empty name', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        // Empty names are not allowed (logger rejects them)
        expect(
          () =>
              db.collection<MinimalEntity>('', fromMap: MinimalEntity.fromMap),
          throwsA(isA<CollectionOperationException>()),
        );

        await db.close();
      });

      test(
        'should handle collection with special characters in name',
        () async {
          final db = await DocDB.open(
            path: null,
            config: DocDBConfig.inMemory(),
          );

          final collection = await db.collection<TestProduct>(
            'user_data_2024',
            fromMap: TestProduct.fromMap,
          );

          expect(collection, isNotNull);
          expect(db.hasCollection('user_data_2024'), isTrue);

          await db.close();
        },
      );
    });

    group('Data Operations', () {
      test('should insert and retrieve entity', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Widget', price: 29.99, quantity: 10),
        );

        final retrieved = await products.get(id);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Widget');
        expect(retrieved.price, 29.99);
        expect(retrieved.quantity, 10);

        await db.close();
      });

      test('should insert multiple entities', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        for (var i = 0; i < 10; i++) {
          await products.insert(
            TestProduct(name: 'Product $i', price: i * 10.0),
          );
        }

        expect(await products.count, 10);

        await db.close();
      });

      test('should update entity', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Widget', price: 29.99),
        );

        await products.update(
          TestProduct(id: id, name: 'Updated Widget', price: 39.99),
        );

        final retrieved = await products.get(id);
        expect(retrieved!.name, 'Updated Widget');
        expect(retrieved.price, 39.99);

        await db.close();
      });

      test('should delete entity', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Widget', price: 29.99),
        );

        await products.delete(id);

        final retrieved = await products.get(id);
        expect(retrieved, isNull);

        await db.close();
      });

      test('should query entities', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await products.insert(TestProduct(name: 'Cheap', price: 10.0));
        await products.insert(TestProduct(name: 'Medium', price: 50.0));
        await products.insert(TestProduct(name: 'Expensive', price: 100.0));

        final expensive = await products.find(
          QueryBuilder().whereGreaterThan('price', 40.0).build(),
        );

        expect(expensive.length, 2);

        await db.close();
      });

      test('should handle complex entities', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final entities = await db.collection<ComplexEntity>(
          'complex',
          fromMap: ComplexEntity.fromMap,
        );

        final id = await entities.insert(
          ComplexEntity(
            metadata: {
              'key': 'value',
              'nested': {'a': 1, 'b': 2},
            },
            tags: ['tag1', 'tag2', 'tag3'],
          ),
        );

        final retrieved = await entities.get(id);
        expect(retrieved, isNotNull);
        expect(retrieved!.metadata['key'], 'value');
        expect(retrieved.tags.length, 3);

        await db.close();
      });
    });

    group('Flush Operations', () {
      test('should flush all collections', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await products.insert(TestProduct(name: 'Widget', price: 29.99));

        // Should not throw
        await db.flush();

        await db.close();
      });

      test('should flush empty database', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        // Should not throw even with no collections
        await db.flush();

        await db.close();
      });

      test('should flush multiple collections', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        await db.collection<TestUser>('users', fromMap: TestUser.fromMap);

        // Should not throw
        await db.flush();

        await db.close();
      });
    });

    group('Statistics', () {
      test('should get stats for empty database', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final stats = await db.getStats();

        expect(stats.isOpen, isTrue);
        expect(stats.path, isNull);
        expect(stats.collectionCount, 0);
        expect(stats.totalEntityCount, 0);
        expect(stats.collections, isEmpty);
        expect(stats.storageBackend, StorageBackend.memory);

        await db.close();
      });

      test('should get stats with collections', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await products.insert(TestProduct(name: 'Widget', price: 29.99));
        await products.insert(TestProduct(name: 'Gadget', price: 49.99));

        final stats = await db.getStats();

        expect(stats.collectionCount, 1);
        expect(stats.totalEntityCount, 2);
        expect(stats.collections.containsKey('products'), isTrue);
        expect(stats.collections['products']!.entityCount, 2);

        await db.close();
      });

      test('should get stats for file-based database', () async {
        final db = await DocDB.open(
          path: tempDir.path,
          config: DocDBConfig.development(),
        );

        final stats = await db.getStats();

        expect(stats.path, tempDir.path);
        expect(stats.storageBackend, StorageBackend.paged);

        await db.close();
      });

      test('should reflect encryption status in stats', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final stats = await db.getStats();
        expect(stats.encryptionEnabled, isFalse);

        await db.close();
      });
    });

    group('Error Handling', () {
      test('should throw DatabaseDisposedException when disposed', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());
        await db.close();

        expect(
          () => db.collection<TestProduct>(
            'products',
            fromMap: TestProduct.fromMap,
          ),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });

      test('should throw on flush after dispose', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());
        await db.close();

        expect(
          () async => await db.flush(),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });

      test('should throw on getStats after dispose', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());
        await db.close();

        expect(
          () async => await db.getStats(),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });

      test('should throw on dropCollection after dispose', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await db.close();

        expect(
          () async => await db.dropCollection('products'),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });

      test('hasCollection should work after close (no throw)', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        await db.close();

        // hasCollection checks internal map, doesn't require open db
        // After close, collections are cleared, so it returns false
        expect(db.hasCollection('products'), isFalse);
      });
    });

    group('Persistence', () {
      test('should persist data across sessions', () async {
        final dbPath = tempDir.path;

        // First session - insert data
        var db = await DocDB.open(
          path: dbPath,
          config: DocDBConfig.development(),
        );

        var products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Persistent Widget', price: 99.99),
        );

        await db.close();

        // Second session - verify data
        db = await DocDB.open(path: dbPath, config: DocDBConfig.development());

        products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final retrieved = await products.get(id);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Persistent Widget');
        expect(retrieved.price, 99.99);

        await db.close();
      });

      test('should persist multiple collections', () async {
        final dbPath = tempDir.path;

        // First session
        var db = await DocDB.open(
          path: dbPath,
          config: DocDBConfig.development(),
        );

        var products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        var users = await db.collection<TestUser>(
          'users',
          fromMap: TestUser.fromMap,
        );

        final productId = await products.insert(
          TestProduct(name: 'Widget', price: 29.99),
        );
        final userId = await users.insert(
          TestUser(username: 'john', email: 'john@example.com'),
        );

        await db.close();

        // Second session
        db = await DocDB.open(path: dbPath, config: DocDBConfig.development());

        products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        users = await db.collection<TestUser>(
          'users',
          fromMap: TestUser.fromMap,
        );

        expect((await products.get(productId))!.name, 'Widget');
        expect((await users.get(userId))!.username, 'john');

        await db.close();
      });
    });

    group('Concurrent Access', () {
      test('should handle concurrent collection access', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        // Access same collection concurrently
        final futures = List.generate(10, (i) async {
          final products = await db.collection<TestProduct>(
            'products',
            fromMap: TestProduct.fromMap,
          );
          await products.insert(
            TestProduct(name: 'Product $i', price: i * 10.0),
          );
        });

        await Future.wait(futures);

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        expect(await products.count, 10);

        await db.close();
      });

      test('should handle concurrent different collection access', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        // Access different collections concurrently
        final productsFuture = db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );
        final usersFuture = db.collection<TestUser>(
          'users',
          fromMap: TestUser.fromMap,
        );

        final results = await Future.wait([productsFuture, usersFuture]);
        expect(results.length, 2);
        expect(db.collectionCount, 2);

        await db.close();
      });
    });

    group('Edge Cases', () {
      test('should handle minimal entity', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final collection = await db.collection<MinimalEntity>(
          'minimal',
          fromMap: MinimalEntity.fromMap,
        );

        final id = await collection.insert(MinimalEntity());
        final retrieved = await collection.get(id);

        expect(retrieved, isNotNull);
        expect(retrieved!.id, id);

        await db.close();
      });

      test('should handle entity with null values in map', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Widget', price: 0.0, quantity: 0),
        );

        final retrieved = await products.get(id);
        expect(retrieved!.price, 0.0);
        expect(retrieved.quantity, 0);

        await db.close();
      });

      test('should handle unicode in entity data', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: '日本語テスト 🎉', price: 29.99),
        );

        final retrieved = await products.get(id);
        expect(retrieved!.name, '日本語テスト 🎉');

        await db.close();
      });

      test('should handle very long collection name', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final longName = 'a' * 200;
        final collection = await db.collection<MinimalEntity>(
          longName,
          fromMap: MinimalEntity.fromMap,
        );

        expect(collection, isNotNull);
        expect(db.hasCollection(longName), isTrue);

        await db.close();
      });

      test('should handle very long entity name', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final longName = 'x' * 10000;
        final id = await products.insert(
          TestProduct(name: longName, price: 29.99),
        );

        final retrieved = await products.get(id);
        expect(retrieved!.name, longName);

        await db.close();
      });

      test('should handle negative price', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Discount', price: -10.0),
        );

        final retrieved = await products.get(id);
        expect(retrieved!.price, -10.0);

        await db.close();
      });

      test('should handle special double values', () async {
        final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        // Very small number
        var id = await products.insert(
          TestProduct(name: 'Tiny', price: 0.0000001),
        );
        var retrieved = await products.get(id);
        expect(retrieved!.price, closeTo(0.0000001, 0.00000001));

        // Very large number
        id = await products.insert(
          TestProduct(name: 'Huge', price: 99999999999.99),
        );
        retrieved = await products.get(id);
        expect(retrieved!.price, closeTo(99999999999.99, 0.01));

        await db.close();
      });

      test('should handle rapid open/close cycles', () async {
        for (var i = 0; i < 5; i++) {
          final db = await DocDB.open(
            path: tempDir.path,
            config: DocDBConfig.development(),
          );

          final products = await db.collection<TestProduct>(
            'products',
            fromMap: TestProduct.fromMap,
          );

          await products.insert(
            TestProduct(name: 'Product $i', price: i * 10.0),
          );

          await db.close();
        }

        // Verify all data persisted
        final db = await DocDB.open(
          path: tempDir.path,
          config: DocDBConfig.development(),
        );

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        expect(await products.count, 5);

        await db.close();
      });
    });

    group('Auto-flush on close', () {
      test('should flush when autoFlushOnClose is true', () async {
        final db = await DocDB.open(
          path: tempDir.path,
          config: DocDBConfig.development().copyWith(autoFlushOnClose: true),
        );

        final products = await db.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final id = await products.insert(
          TestProduct(name: 'Widget', price: 29.99),
        );

        await db.close();

        // Reopen and verify data was flushed
        final db2 = await DocDB.open(
          path: tempDir.path,
          config: DocDBConfig.development(),
        );

        final products2 = await db2.collection<TestProduct>(
          'products',
          fromMap: TestProduct.fromMap,
        );

        final retrieved = await products2.get(id);
        expect(retrieved, isNotNull);

        await db2.close();
      });
    });
  });
}
