/// EntiDB Collection Module Tests
///
/// Comprehensive tests for the Collection class including CRUD operations,
/// indexing, querying, concurrency control, and version tracking.
library;

import 'package:test/test.dart';

import 'package:entidb/src/collection/collection.dart';
import 'package:entidb/src/entity/entity.dart';
import 'package:entidb/src/exceptions/exceptions.dart';
import 'package:entidb/src/index/i_index.dart';
import 'package:entidb/src/query/query.dart';
import 'package:entidb/src/storage/memory_storage.dart';

/// Test entity for collection tests.
class Product implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final String? category;
  final int stock;

  Product({
    this.id,
    required this.name,
    required this.price,
    this.category,
    this.stock = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    if (category != null) 'category': category,
    'stock': stock,
  };

  static Product fromMap(String id, Map<String, dynamic> map) {
    return Product(
      id: id,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      category: map['category'] as String?,
      stock: (map['stock'] as int?) ?? 0,
    );
  }

  Product copyWith({
    String? id,
    String? name,
    double? price,
    String? category,
    int? stock,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      stock: stock ?? this.stock,
    );
  }

  @override
  String toString() => 'Product(id: $id, name: $name, price: $price)';
}

void main() {
  group('Collection', () {
    late MemoryStorage<Product> storage;
    late Collection<Product> collection;

    setUp(() async {
      storage = MemoryStorage<Product>(name: 'products');
      await storage.open();
      collection = Collection<Product>(
        storage: storage,
        fromMap: Product.fromMap,
        name: 'products',
      );
    });

    tearDown(() async {
      await collection.dispose();
      await storage.close();
    });

    group('Construction', () {
      test('should create collection with correct name', () {
        expect(collection.name, equals('products'));
      });

      test('should have zero count initially', () async {
        expect(await collection.count, equals(0));
      });

      test('should have no indexes initially', () {
        expect(collection.indexCount, equals(0));
        expect(collection.indexedFields, isEmpty);
      });
    });

    group('Insert Operations', () {
      test('should insert entity and return auto-generated ID', () async {
        final product = Product(name: 'Widget', price: 29.99);
        final id = await collection.insert(product);

        expect(id, isNotEmpty);
        expect(await collection.count, equals(1));
      });

      test('should insert entity with custom ID', () async {
        final product = Product(id: 'custom-id', name: 'Gadget', price: 49.99);
        final id = await collection.insert(product);

        expect(id, equals('custom-id'));
      });

      test('should throw on duplicate ID', () async {
        final product = Product(id: 'dup-id', name: 'Item', price: 10.00);
        await collection.insert(product);

        expect(
          () => collection.insert(product),
          throwsA(isA<EntityAlreadyExistsException>()),
        );
      });

      test('should insert many entities', () async {
        final products = [
          Product(name: 'Product 1', price: 10.00),
          Product(name: 'Product 2', price: 20.00),
          Product(name: 'Product 3', price: 30.00),
        ];

        final ids = await collection.insertMany(products);

        expect(ids, hasLength(3));
        expect(await collection.count, equals(3));
      });

      test('should insert many entities with custom IDs', () async {
        final products = [
          Product(id: 'id-1', name: 'Product 1', price: 10.00),
          Product(id: 'id-2', name: 'Product 2', price: 20.00),
        ];

        final ids = await collection.insertMany(products);

        expect(ids, equals(['id-1', 'id-2']));
      });
    });

    group('Get Operations', () {
      late String productId;

      setUp(() async {
        productId = await collection.insert(
          Product(name: 'Test Product', price: 99.99, category: 'Electronics'),
        );
      });

      test('should get entity by ID', () async {
        final product = await collection.get(productId);

        expect(product, isNotNull);
        expect(product!.name, equals('Test Product'));
        expect(product.price, equals(99.99));
        expect(product.category, equals('Electronics'));
      });

      test('should return null for non-existent ID', () async {
        final product = await collection.get('non-existent');
        expect(product, isNull);
      });

      test('should get entity or throw', () async {
        final product = await collection.getOrThrow(productId);
        expect(product.name, equals('Test Product'));
      });

      test(
        'should throw EntityNotFoundException for non-existent ID',
        () async {
          expect(
            () => collection.getOrThrow('non-existent'),
            throwsA(isA<EntityNotFoundException>()),
          );
        },
      );

      test('should get many entities by IDs', () async {
        final id2 = await collection.insert(
          Product(name: 'Another Product', price: 49.99),
        );

        final products = await collection.getMany([productId, id2, 'missing']);

        expect(products, hasLength(2));
        expect(products.keys, containsAll([productId, id2]));
        expect(products.keys, isNot(contains('missing')));
      });

      test('should get all entities', () async {
        await collection.insert(Product(name: 'Product 2', price: 20.00));
        await collection.insert(Product(name: 'Product 3', price: 30.00));

        final products = await collection.getAll();

        expect(products, hasLength(3));
      });

      test('should check if entity exists', () async {
        expect(await collection.exists(productId), isTrue);
        expect(await collection.exists('non-existent'), isFalse);
      });
    });

    group('Update Operations', () {
      late String productId;
      late Product originalProduct;

      setUp(() async {
        originalProduct = Product(name: 'Original', price: 50.00, stock: 10);
        productId = await collection.insert(originalProduct);
      });

      test('should update entity', () async {
        final updated = Product(
          id: productId,
          name: 'Updated',
          price: 75.00,
          stock: 20,
        );

        await collection.update(updated);

        final retrieved = await collection.get(productId);
        expect(retrieved!.name, equals('Updated'));
        expect(retrieved.price, equals(75.00));
        expect(retrieved.stock, equals(20));
      });

      test('should throw when updating entity without ID', () async {
        final noId = Product(name: 'No ID', price: 10.00);

        expect(
          () => collection.update(noId),
          throwsA(isA<CollectionException>()),
        );
      });

      test('should throw when updating non-existent entity', () async {
        final nonExistent = Product(
          id: 'non-existent',
          name: 'Test',
          price: 10.00,
        );

        expect(
          () => collection.update(nonExistent),
          throwsA(isA<EntityNotFoundException>()),
        );
      });

      test('should update where with modifier function', () async {
        final updated = await collection.updateWhere(
          productId,
          (product) => product.copyWith(price: product.price * 1.1),
        );

        expect(updated.price, closeTo(55.00, 0.01));
      });

      test('should upsert new entity', () async {
        final newProduct = Product(
          id: 'new-product',
          name: 'New',
          price: 100.00,
        );

        final id = await collection.upsert(newProduct);

        expect(id, equals('new-product'));
        expect(await collection.exists('new-product'), isTrue);
      });

      test('should upsert existing entity', () async {
        final updated = Product(id: productId, name: 'Upserted', price: 60.00);

        await collection.upsert(updated);

        final retrieved = await collection.get(productId);
        expect(retrieved!.name, equals('Upserted'));
      });
    });

    group('Delete Operations', () {
      late String productId;

      setUp(() async {
        productId = await collection.insert(
          Product(name: 'To Delete', price: 10.00),
        );
      });

      test('should delete entity and return true', () async {
        final deleted = await collection.delete(productId);

        expect(deleted, isTrue);
        expect(await collection.exists(productId), isFalse);
      });

      test('should return false for non-existent entity', () async {
        final deleted = await collection.delete('non-existent');
        expect(deleted, isFalse);
      });

      test('should delete or throw', () async {
        await collection.deleteOrThrow(productId);
        expect(await collection.exists(productId), isFalse);
      });

      test('should throw when deleteOrThrow with non-existent ID', () async {
        expect(
          () => collection.deleteOrThrow('non-existent'),
          throwsA(isA<EntityNotFoundException>()),
        );
      });

      test('should delete many entities', () async {
        final id2 = await collection.insert(
          Product(name: 'Product 2', price: 20.00),
        );
        final id3 = await collection.insert(
          Product(name: 'Product 3', price: 30.00),
        );

        final deletedCount = await collection.deleteMany([
          productId,
          id2,
          'non-existent',
        ]);

        expect(deletedCount, equals(2));
        expect(await collection.count, equals(1));
        expect(await collection.exists(id3), isTrue);
      });

      test('should delete all entities', () async {
        await collection.insert(Product(name: 'Product 2', price: 20.00));
        await collection.insert(Product(name: 'Product 3', price: 30.00));

        final deletedCount = await collection.deleteAll();

        expect(deletedCount, equals(3));
        expect(await collection.count, equals(0));
      });
    });

    group('Index Operations', () {
      test('should create hash index', () async {
        await collection.createIndex('name', IndexType.hash);

        expect(collection.hasIndex('name'), isTrue);
        expect(collection.hasIndexOfType('name', IndexType.hash), isTrue);
        expect(collection.indexCount, equals(1));
        expect(collection.indexedFields, contains('name'));
      });

      test('should create btree index', () async {
        await collection.createIndex('price', IndexType.btree);

        expect(collection.hasIndex('price'), isTrue);
        expect(collection.hasIndexOfType('price', IndexType.btree), isTrue);
      });

      test('should throw when creating duplicate index', () async {
        await collection.createIndex('name', IndexType.hash);

        expect(
          () => collection.createIndex('name', IndexType.hash),
          throwsA(isA<IndexAlreadyExistsException>()),
        );
      });

      test('should remove index', () async {
        await collection.createIndex('name', IndexType.hash);
        await collection.removeIndex('name');

        expect(collection.hasIndex('name'), isFalse);
        expect(collection.indexCount, equals(0));
      });

      test('should throw when removing non-existent index', () async {
        expect(
          () => collection.removeIndex('nonexistent'),
          throwsA(isA<IndexNotFoundException>()),
        );
      });

      test('should populate index with existing entities', () async {
        await collection.insert(Product(name: 'A', price: 10.00));
        await collection.insert(Product(name: 'B', price: 20.00));
        await collection.insert(Product(name: 'C', price: 30.00));

        await collection.createIndex('price', IndexType.btree);

        // Index should contain existing entities
        final results = await collection.find(
          QueryBuilder().whereGreaterThan('price', 15.0).build(),
        );
        expect(results, hasLength(2));
      });

      test('should update index on insert', () async {
        await collection.createIndex('name', IndexType.hash);

        await collection.insert(Product(name: 'Widget', price: 29.99));

        final results = await collection.find(
          QueryBuilder().whereEquals('name', 'Widget').build(),
        );
        expect(results, hasLength(1));
      });

      test('should update index on delete', () async {
        await collection.createIndex('name', IndexType.hash);
        final id = await collection.insert(
          Product(name: 'Widget', price: 29.99),
        );

        await collection.delete(id);

        final results = await collection.find(
          QueryBuilder().whereEquals('name', 'Widget').build(),
        );
        expect(results, isEmpty);
      });

      test('should remove all indexes', () async {
        await collection.createIndex('name', IndexType.hash);
        await collection.createIndex('price', IndexType.btree);

        await collection.removeAllIndexes();

        expect(collection.indexCount, equals(0));
      });

      test('should clear all index entries', () async {
        await collection.insert(Product(name: 'Widget', price: 29.99));
        await collection.createIndex('name', IndexType.hash);

        await collection.clearAllIndexEntries();

        // Index structure remains but entries are cleared
        expect(collection.hasIndex('name'), isTrue);
      });

      test('should rebuild all indexes', () async {
        await collection.insert(Product(name: 'Widget', price: 29.99));
        await collection.createIndex('name', IndexType.hash);

        await collection.rebuildAllIndexes();

        final results = await collection.find(
          QueryBuilder().whereEquals('name', 'Widget').build(),
        );
        expect(results, hasLength(1));
      });
    });

    group('Query Operations', () {
      setUp(() async {
        await collection.insert(
          Product(
            name: 'Widget',
            price: 29.99,
            category: 'Electronics',
            stock: 100,
          ),
        );
        await collection.insert(
          Product(
            name: 'Gadget',
            price: 49.99,
            category: 'Electronics',
            stock: 50,
          ),
        );
        await collection.insert(
          Product(name: 'Tool', price: 19.99, category: 'Hardware', stock: 200),
        );
        await collection.insert(
          Product(name: 'Book', price: 9.99, category: 'Media', stock: 500),
        );
      });

      test('should find with equals query', () async {
        final results = await collection.find(
          QueryBuilder().whereEquals('category', 'Electronics').build(),
        );

        expect(results, hasLength(2));
        expect(results.every((p) => p.category == 'Electronics'), isTrue);
      });

      test('should find with greater than query', () async {
        final results = await collection.find(
          QueryBuilder().whereGreaterThan('price', 20.0).build(),
        );

        expect(results, hasLength(2));
        expect(results.every((p) => p.price > 20.0), isTrue);
      });

      test('should find with less than query', () async {
        final results = await collection.find(
          QueryBuilder().whereLessThan('price', 20.0).build(),
        );

        expect(results, hasLength(2));
        expect(results.every((p) => p.price < 20.0), isTrue);
      });

      test('should find with between query', () async {
        final results = await collection.find(
          QueryBuilder().whereBetween('price', 20.0, 50.0).build(),
        );

        expect(results, hasLength(2));
      });

      test('should find with in query', () async {
        final results = await collection.find(
          QueryBuilder().whereIn('category', ['Electronics', 'Media']).build(),
        );

        expect(results, hasLength(3));
      });

      test('should find one entity', () async {
        final result = await collection.findOne(
          QueryBuilder().whereEquals('name', 'Widget').build(),
        );

        expect(result, isNotNull);
        expect(result!.name, equals('Widget'));
      });

      test('should return null when findOne finds nothing', () async {
        final result = await collection.findOne(
          QueryBuilder().whereEquals('name', 'NonExistent').build(),
        );

        expect(result, isNull);
      });

      test('should findOneOrThrow', () async {
        final result = await collection.findOneOrThrow(
          QueryBuilder().whereEquals('name', 'Widget').build(),
        );

        expect(result.name, equals('Widget'));
      });

      test('should throw when findOneOrThrow finds nothing', () async {
        expect(
          () => collection.findOneOrThrow(
            QueryBuilder().whereEquals('name', 'NonExistent').build(),
          ),
          throwsA(isA<EntityNotFoundException>()),
        );
      });

      test('should count where', () async {
        final count = await collection.countWhere(
          QueryBuilder().whereEquals('category', 'Electronics').build(),
        );

        expect(count, equals(2));
      });

      test('should count all when no query provided', () async {
        final count = await collection.countWhere();

        expect(count, equals(4));
      });

      test('should use hash index for equals query', () async {
        await collection.createIndex('category', IndexType.hash);

        final results = await collection.find(
          QueryBuilder().whereEquals('category', 'Electronics').build(),
        );

        expect(results, hasLength(2));
      });

      test('should use btree index for range query', () async {
        await collection.createIndex('price', IndexType.btree);

        final results = await collection.find(
          QueryBuilder().whereGreaterThan('price', 20.0).build(),
        );

        expect(results, hasLength(2));
      });

      test('should use btree index for between query', () async {
        await collection.createIndex('price', IndexType.btree);

        final results = await collection.find(
          QueryBuilder().whereBetween('price', 10.0, 30.0).build(),
        );

        expect(results, hasLength(2));
      });
    });

    group('Stream Operations', () {
      test('should stream all entities', () async {
        await collection.insert(Product(name: 'A', price: 10.00));
        await collection.insert(Product(name: 'B', price: 20.00));
        await collection.insert(Product(name: 'C', price: 30.00));

        final products = await collection.stream().toList();

        expect(products, hasLength(3));
      });
    });

    group('Disposal', () {
      test('should throw when disposed', () async {
        await collection.dispose();

        expect(
          () => collection.insert(Product(name: 'Test', price: 10.00)),
          throwsA(isA<CollectionException>()),
        );
      });

      test('should be idempotent for dispose', () async {
        await collection.dispose();
        await collection.dispose(); // Should not throw
      });
    });

    group('Flush', () {
      test('should flush without error', () async {
        await collection.insert(Product(name: 'Test', price: 10.00));
        await collection.flush(); // Should complete without error
      });
    });

    group('ToString', () {
      test('should have meaningful string representation', () {
        final str = collection.toString();

        expect(str, contains('Collection'));
        expect(str, contains('Product'));
        expect(str, contains('products'));
      });
    });
  });

  group('CollectionConfig', () {
    test('should have default values', () {
      const config = CollectionConfig();

      expect(config.enableVersioning, isTrue);
      expect(config.enableDebugLogging, isFalse);
      expect(config.maxCachedLocks, equals(1000));
    });

    test('should have production preset', () {
      expect(CollectionConfig.production.enableVersioning, isTrue);
      expect(CollectionConfig.production.enableDebugLogging, isFalse);
      expect(CollectionConfig.production.maxCachedLocks, equals(10000));
    });

    test('should have development preset', () {
      expect(CollectionConfig.development.enableVersioning, isTrue);
      expect(CollectionConfig.development.enableDebugLogging, isTrue);
      expect(CollectionConfig.development.maxCachedLocks, equals(100));
    });

    test('should have testing preset', () {
      expect(CollectionConfig.testing.enableVersioning, isFalse);
      expect(CollectionConfig.testing.enableDebugLogging, isTrue);
      expect(CollectionConfig.testing.maxCachedLocks, equals(10));
    });
  });
}
