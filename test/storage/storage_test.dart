/// Storage Implementation Tests.
///
/// Comprehensive tests for FileStorage and PagedStorage implementations.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:docdb/src/entity/entity.dart';
import 'package:docdb/src/exceptions/storage_exceptions.dart';
import 'package:docdb/src/storage/file_storage.dart';
import 'package:docdb/src/storage/memory_storage.dart';
import 'package:docdb/src/storage/paged_storage.dart';
import 'package:docdb/src/storage/storage.dart';

/// Test entity implementation.
class TestProduct implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final List<String> tags;

  const TestProduct({
    this.id,
    required this.name,
    required this.price,
    this.tags = const [],
  });

  @override
  Map<String, dynamic> toMap() => {'name': name, 'price': price, 'tags': tags};

  factory TestProduct.fromMap(String id, Map<String, dynamic> map) {
    return TestProduct(
      id: id,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      tags: (map['tags'] as List?)?.cast<String>() ?? [],
    );
  }
}

void main() {
  group('FileStorage', () {
    late Directory tempDir;
    late FileStorage<TestProduct> storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_storage_test_');
      storage = FileStorage<TestProduct>(
        name: 'products',
        directory: '${tempDir.path}/products',
        config: const FileStorageConfig(
          prettyPrint: true,
          enableTransactions: true,
          syncOnWrite: false,
        ),
      );
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should open and close storage', () async {
      expect(storage.isOpen, isFalse);
      await storage.open();
      expect(storage.isOpen, isTrue);
      await storage.close();
      expect(storage.isOpen, isFalse);
    });

    test('should insert and retrieve entity', () async {
      await storage.open();

      await storage.insert('prod-1', {
        'name': 'Widget',
        'price': 29.99,
        'tags': ['popular', 'sale'],
      });

      final data = await storage.get('prod-1');
      expect(data, isNotNull);
      expect(data!['name'], 'Widget');
      expect(data['price'], 29.99);
      expect(data['tags'], ['popular', 'sale']);
    });

    test('should throw when inserting duplicate ID', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

      expect(
        () => storage.insert('prod-1', {'name': 'Gadget', 'price': 20}),
        throwsA(isA<EntityAlreadyExistsException>()),
      );
    });

    test('should update entity', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      await storage.update('prod-1', {'name': 'Widget Pro', 'price': 20});

      final data = await storage.get('prod-1');
      expect(data!['name'], 'Widget Pro');
      expect(data['price'], 20);
    });

    test('should throw when updating non-existent entity', () async {
      await storage.open();

      expect(
        () => storage.update('missing', {'name': 'Test', 'price': 10}),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('should upsert entity', () async {
      await storage.open();

      // Insert via upsert
      await storage.upsert('prod-1', {'name': 'Widget', 'price': 10});
      expect(await storage.exists('prod-1'), isTrue);

      // Update via upsert
      await storage.upsert('prod-1', {'name': 'Widget Pro', 'price': 20});
      final data = await storage.get('prod-1');
      expect(data!['name'], 'Widget Pro');
    });

    test('should delete entity', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      expect(await storage.exists('prod-1'), isTrue);

      final deleted = await storage.delete('prod-1');
      expect(deleted, isTrue);
      expect(await storage.exists('prod-1'), isFalse);

      final deletedAgain = await storage.delete('prod-1');
      expect(deletedAgain, isFalse);
    });

    test('should get many entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
      await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});

      final data = await storage.getMany(['prod-1', 'prod-3', 'missing']);
      expect(data.length, 2);
      expect(data['prod-1']!['name'], 'Widget 1');
      expect(data['prod-3']!['name'], 'Widget 3');
    });

    test('should get all entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

      final data = await storage.getAll();
      expect(data.length, 2);
    });

    test('should stream entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

      final records = await storage.stream().toList();
      expect(records.length, 2);
    });

    test('should delete many entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
      await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});

      final deleted = await storage.deleteMany(['prod-1', 'prod-3', 'missing']);
      expect(deleted, 2);
      expect(await storage.count, 1);
    });

    test('should delete all entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

      final deleted = await storage.deleteAll();
      expect(deleted, 2);
      expect(await storage.count, 0);
    });

    test('should insert many entities', () async {
      await storage.open();

      await storage.insertMany({
        'prod-1': {'name': 'Widget 1', 'price': 10},
        'prod-2': {'name': 'Widget 2', 'price': 20},
        'prod-3': {'name': 'Widget 3', 'price': 30},
      });

      expect(await storage.count, 3);
    });

    test('should persist data across open/close', () async {
      await storage.open();
      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      await storage.close();

      // Reopen
      await storage.open();
      final data = await storage.get('prod-1');
      expect(data, isNotNull);
      expect(data!['name'], 'Widget');
    });

    group('Transactions', () {
      test('should support transactions', () async {
        await storage.open();
        expect(storage.supportsTransactions, isTrue);
      });

      test('should commit transaction', () async {
        await storage.open();

        await storage.beginTransaction();
        expect(storage.inTransaction, isTrue);

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.commit();

        expect(storage.inTransaction, isFalse);
        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should rollback transaction', () async {
        await storage.open();

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.insert('prod-2', {'name': 'Gadget', 'price': 20});
        await storage.rollback();

        expect(storage.inTransaction, isFalse);
        expect(await storage.exists('prod-1'), isTrue);
        expect(await storage.exists('prod-2'), isFalse);
      });

      test('should isolate transaction changes', () async {
        await storage.open();

        await storage.beginTransaction();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        // The insert should be visible within the transaction
        expect(await storage.exists('prod-1'), isTrue);

        await storage.rollback();

        // After rollback, should not exist
        expect(await storage.exists('prod-1'), isFalse);
      });

      test('should handle transaction update rollback', () async {
        await storage.open();

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.update('prod-1', {'name': 'Updated', 'price': 20});
        await storage.rollback();

        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget');
        expect(data['price'], 10);
      });

      test('should handle transaction delete rollback', () async {
        await storage.open();

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.delete('prod-1');
        await storage.rollback();

        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should throw on nested transaction', () async {
        await storage.open();

        await storage.beginTransaction();
        expect(
          () => storage.beginTransaction(),
          throwsA(isA<TransactionAlreadyActiveException>()),
        );
        await storage.rollback();
      });

      test('should throw on commit without transaction', () async {
        await storage.open();

        expect(
          () => storage.commit(),
          throwsA(isA<NoActiveTransactionException>()),
        );
      });

      test('should throw on rollback without transaction', () async {
        await storage.open();

        expect(
          () => storage.rollback(),
          throwsA(isA<NoActiveTransactionException>()),
        );
      });
    });
  });

  group('PagedStorage', () {
    late Directory tempDir;
    late PagedStorage<TestProduct> storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('paged_storage_test_');
      storage = PagedStorage<TestProduct>(
        name: 'products',
        filePath: '${tempDir.path}/products.db',
        config: const PagedStorageConfig(
          bufferPoolSize: 128,
          enableTransactions: true,
          verifyChecksums: true,
        ),
      );
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should open and close storage', () async {
      expect(storage.isOpen, isFalse);
      await storage.open();
      expect(storage.isOpen, isTrue);
      await storage.close();
      expect(storage.isOpen, isFalse);
    });

    test('should insert and retrieve entity', () async {
      await storage.open();

      await storage.insert('prod-1', {
        'name': 'Widget',
        'price': 29.99,
        'tags': ['popular', 'sale'],
      });

      final data = await storage.get('prod-1');
      expect(data, isNotNull);
      expect(data!['name'], 'Widget');
      expect(data['price'], 29.99);
      expect(data['tags'], ['popular', 'sale']);
    });

    test('should throw when inserting duplicate ID', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

      expect(
        () => storage.insert('prod-1', {'name': 'Gadget', 'price': 20}),
        throwsA(isA<EntityAlreadyExistsException>()),
      );
    });

    test('should update entity', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      await storage.update('prod-1', {'name': 'Widget Pro', 'price': 20});

      final data = await storage.get('prod-1');
      expect(data!['name'], 'Widget Pro');
      expect(data['price'], 20);
    });

    test('should upsert entity', () async {
      await storage.open();

      // Insert via upsert
      await storage.upsert('prod-1', {'name': 'Widget', 'price': 10});
      expect(await storage.exists('prod-1'), isTrue);

      // Update via upsert
      await storage.upsert('prod-1', {'name': 'Widget Pro', 'price': 20});
      final data = await storage.get('prod-1');
      expect(data!['name'], 'Widget Pro');
    });

    test('should delete entity', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      expect(await storage.exists('prod-1'), isTrue);

      final deleted = await storage.delete('prod-1');
      expect(deleted, isTrue);
      expect(await storage.exists('prod-1'), isFalse);
    });

    test('should get many entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
      await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});

      final data = await storage.getMany(['prod-1', 'prod-3', 'missing']);
      expect(data.length, 2);
    });

    test('should get all entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

      final data = await storage.getAll();
      expect(data.length, 2);
    });

    test('should stream entities', () async {
      await storage.open();

      await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
      await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

      final records = await storage.stream().toList();
      expect(records.length, 2);
    });

    test('should persist data across open/close', () async {
      await storage.open();
      await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
      await storage.close();

      // Reopen
      await storage.open();
      final data = await storage.get('prod-1');
      expect(data, isNotNull);
      expect(data!['name'], 'Widget');
    });

    group('Transactions', () {
      test('should commit transaction', () async {
        await storage.open();

        await storage.beginTransaction();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.commit();

        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should rollback transaction', () async {
        await storage.open();

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.insert('prod-2', {'name': 'Gadget', 'price': 20});
        await storage.rollback();

        expect(await storage.exists('prod-1'), isTrue);
        expect(await storage.exists('prod-2'), isFalse);
      });
    });
  });

  group('Storage Interface Compatibility', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('storage_compat_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    /// Tests that all storage implementations support the same interface.
    void testStorageImplementation(
      String name,
      Future<Storage<TestProduct>> Function() createStorage,
    ) {
      group(name, () {
        late Storage<TestProduct> storage;

        setUp(() async {
          storage = await createStorage();
          await storage.open();
        });

        tearDown(() async {
          if (storage.isOpen) {
            await storage.close();
          }
        });

        test('implements Storage interface', () {
          expect(storage, isA<Storage<TestProduct>>());
        });

        test('has name property', () {
          expect(storage.name, isNotEmpty);
        });

        test('supports CRUD operations', () async {
          // Create
          await storage.insert('id-1', {
            'name': 'Test',
            'price': 10,
            'tags': <String>[],
          });
          expect(await storage.exists('id-1'), isTrue);

          // Read
          final data = await storage.get('id-1');
          expect(data, isNotNull);
          expect(data!['name'], 'Test');

          // Update
          await storage.update('id-1', {
            'name': 'Updated',
            'price': 20,
            'tags': <String>[],
          });
          final updated = await storage.get('id-1');
          expect(updated!['name'], 'Updated');

          // Delete
          final deleted = await storage.delete('id-1');
          expect(deleted, isTrue);
          expect(await storage.exists('id-1'), isFalse);
        });
      });
    }

    testStorageImplementation('MemoryStorage', () async {
      return MemoryStorage<TestProduct>(name: 'test');
    });

    testStorageImplementation('FileStorage', () async {
      return FileStorage<TestProduct>(
        name: 'test',
        directory: '${tempDir.path}/file_test',
      );
    });

    testStorageImplementation('PagedStorage', () async {
      return PagedStorage<TestProduct>(
        name: 'test',
        filePath: '${tempDir.path}/paged_test.db',
      );
    });
  });
}
