/// Tests for the main EntiDB class.
import 'dart:io';

import 'package:entidb/entidb.dart';
import 'package:test/test.dart';

/// Test entity for EntiDB tests.
class Product implements Entity {
  @override
  final String? id;
  final String name;
  final double price;

  Product({this.id, required this.name, required this.price});

  @override
  Map<String, dynamic> toMap() => {'name': name, 'price': price};

  static Product fromMap(String id, Map<String, dynamic> map) {
    return Product(
      id: id,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
    );
  }
}

/// Another test entity to verify type safety.
class User implements Entity {
  @override
  final String? id;
  final String username;
  final String email;

  User({this.id, required this.username, required this.email});

  @override
  Map<String, dynamic> toMap() => {'username': username, 'email': email};

  static User fromMap(String id, Map<String, dynamic> map) {
    return User(
      id: id,
      username: map['username'] as String,
      email: map['email'] as String,
    );
  }
}

void main() {
  group('EntiDB', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('entidb_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('In-Memory Mode', () {
      test('should open in-memory database', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        expect(db.isOpen, isTrue);
        expect(db.collectionCount, 0);

        await db.close();
        expect(db.isOpen, isFalse);
      });

      test('should create and access collections', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        final products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        expect(products, isNotNull);
        expect(db.hasCollection('products'), isTrue);
        expect(db.collectionCount, 1);

        await db.close();
      });

      test('should insert and retrieve entities', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        final products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        final id = await products.insert(
          Product(name: 'Widget', price: 29.99),
        );

        final retrieved = await products.get(id);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Widget');
        expect(retrieved.price, 29.99);

        await db.close();
      });

      test('should support multiple collections', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        final products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        final users = await db.collection<User>(
          'users',
          fromMap: User.fromMap,
        );

        await products.insert(Product(name: 'Widget', price: 29.99));
        await users.insert(User(username: 'john', email: 'john@example.com'));

        expect(db.collectionCount, 2);
        expect(db.collectionNames, containsAll(['products', 'users']));

        await db.close();
      });

      test('should return same collection on repeated access', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        final products1 = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        final products2 = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        expect(identical(products1, products2), isTrue);

        await db.close();
      });

      test('should throw on type mismatch', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        await db.collection<Product>(
          'items',
          fromMap: Product.fromMap,
        );

        expect(
          () => db.collection<User>(
            'items',
            fromMap: User.fromMap,
          ),
          throwsA(isA<CollectionTypeMismatchException>()),
        );

        await db.close();
      });

      test('should drop collection', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        expect(db.hasCollection('products'), isTrue);

        final dropped = await db.dropCollection('products');
        expect(dropped, isTrue);
        expect(db.hasCollection('products'), isFalse);

        // Dropping non-existent collection returns false
        final droppedAgain = await db.dropCollection('products');
        expect(droppedAgain, isFalse);

        await db.close();
      });

      test('should get database stats', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        final products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        await products.insert(Product(name: 'Widget', price: 29.99));
        await products.insert(Product(name: 'Gadget', price: 49.99));

        final stats = await db.getStats();
        expect(stats.isOpen, isTrue);
        expect(stats.collectionCount, 1);
        expect(stats.totalEntityCount, 2);
        expect(stats.storageBackend, StorageBackend.memory);

        await db.close();
      });

      test('should throw when database not open', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );

        await db.close();

        expect(
          () => db.collection<Product>('products', fromMap: Product.fromMap),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });
    });

    group('Paged Storage Mode', () {
      test('should open file-based database', () async {
        final db = await EntiDB.open(
          path: tempDir.path,
          config: EntiDBConfig.development(),
        );

        expect(db.isOpen, isTrue);
        expect(db.path, tempDir.path);

        await db.close();
      });

      test('should persist data across sessions', () async {
        // First session
        var db = await EntiDB.open(
          path: tempDir.path,
          config: EntiDBConfig.development(),
        );

        var products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        final id = await products.insert(
          Product(name: 'Persistent Widget', price: 99.99),
        );

        await db.close();

        // Second session
        db = await EntiDB.open(
          path: tempDir.path,
          config: EntiDBConfig.development(),
        );

        products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        final retrieved = await products.get(id);
        expect(retrieved, isNotNull);
        expect(retrieved!.name, 'Persistent Widget');
        expect(retrieved.price, 99.99);

        await db.close();
      });

      test('should support queries', () async {
        final db = await EntiDB.open(
          path: tempDir.path,
          config: EntiDBConfig.development(),
        );

        final products = await db.collection<Product>(
          'products',
          fromMap: Product.fromMap,
        );

        await products.insert(Product(name: 'Cheap', price: 10.00));
        await products.insert(Product(name: 'Medium', price: 50.00));
        await products.insert(Product(name: 'Expensive', price: 100.00));

        final expensive = await products.find(
          QueryBuilder().whereGreaterThan('price', 40.0).build(),
        );

        expect(expensive.length, 2);

        await db.close();
      });
    });

    group('Configuration', () {
      test('should use production config', () {
        final config = EntiDBConfig.production();
        expect(config.storageBackend, StorageBackend.paged);
        expect(config.enableTransactions, isTrue);
        expect(config.enableDebugLogging, isFalse);
      });

      test('should use development config', () {
        final config = EntiDBConfig.development();
        expect(config.storageBackend, StorageBackend.paged);
        expect(config.enableTransactions, isTrue);
        expect(config.enableDebugLogging, isTrue);
      });

      test('should use in-memory config', () {
        final config = EntiDBConfig.inMemory();
        expect(config.storageBackend, StorageBackend.memory);
        expect(config.enableTransactions, isFalse);
      });

      test('should copy config with modifications', () {
        final original = EntiDBConfig.production();
        final modified = original.copyWith(
          bufferPoolSize: 4096,
          enableDebugLogging: true,
        );

        expect(modified.bufferPoolSize, 4096);
        expect(modified.enableDebugLogging, isTrue);
        expect(modified.storageBackend, original.storageBackend);
      });
    });

    group('Error Handling', () {
      test('should throw DatabaseDisposedException when disposed', () async {
        final db = await EntiDB.open(
          path: null,
          config: EntiDBConfig.inMemory(),
        );
        await db.close();

        expect(
          () async => await db.flush(),
          throwsA(isA<DatabaseDisposedException>()),
        );
      });
    });
  });
}
