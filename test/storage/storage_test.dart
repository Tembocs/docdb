/// Storage Implementation Tests.
///
/// Comprehensive tests for FileStorage, PagedStorage, and BinarySerializer.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:docdb/src/entity/entity.dart';
import 'package:docdb/src/exceptions/storage_exceptions.dart';
import 'package:docdb/src/storage/file_storage.dart';
import 'package:docdb/src/storage/memory_storage.dart';
import 'package:docdb/src/storage/paged_storage.dart';
import 'package:docdb/src/storage/serialization.dart';
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

  group('MemoryStorage', () {
    late MemoryStorage<TestProduct> storage;

    setUp(() async {
      storage = MemoryStorage<TestProduct>(name: 'products');
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    group('Basic Operations', () {
      test('should open and close storage', () async {
        expect(storage.isOpen, isFalse);
        await storage.open();
        expect(storage.isOpen, isTrue);
        await storage.close();
        expect(storage.isOpen, isFalse);
      });

      test('should allow multiple open calls without error', () async {
        await storage.open();
        await storage.open();
        expect(storage.isOpen, isTrue);
      });

      test('should allow multiple close calls without error', () async {
        await storage.open();
        await storage.close();
        await storage.close();
        expect(storage.isOpen, isFalse);
      });

      test('should have correct name', () {
        expect(storage.name, 'products');
      });

      test('should support transactions', () {
        expect(storage.supportsTransactions, isTrue);
      });

      test('should start with empty count', () async {
        await storage.open();
        expect(await storage.count, 0);
      });
    });

    group('CRUD Operations', () {
      setUp(() async {
        await storage.open();
      });

      test('should insert and retrieve entity', () async {
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

      test('should return null for non-existent entity', () async {
        final data = await storage.get('non-existent');
        expect(data, isNull);
      });

      test('should throw when inserting duplicate ID', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        expect(
          () => storage.insert('prod-1', {'name': 'Gadget', 'price': 20}),
          throwsA(isA<EntityAlreadyExistsException>()),
        );
      });

      test('should update entity', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.update('prod-1', {'name': 'Widget Pro', 'price': 20});

        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget Pro');
        expect(data['price'], 20);
      });

      test('should throw when updating non-existent entity', () async {
        expect(
          () => storage.update('missing', {'name': 'Test', 'price': 10}),
          throwsA(isA<EntityNotFoundException>()),
        );
      });

      test('should upsert entity - insert new', () async {
        await storage.upsert('prod-1', {'name': 'Widget', 'price': 10});
        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should upsert entity - update existing', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.upsert('prod-1', {'name': 'Widget Pro', 'price': 20});

        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget Pro');
      });

      test('should delete entity', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        expect(await storage.exists('prod-1'), isTrue);

        final deleted = await storage.delete('prod-1');
        expect(deleted, isTrue);
        expect(await storage.exists('prod-1'), isFalse);
      });

      test('should return false when deleting non-existent entity', () async {
        final deleted = await storage.delete('non-existent');
        expect(deleted, isFalse);
      });

      test('should check entity existence', () async {
        expect(await storage.exists('prod-1'), isFalse);
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        expect(await storage.exists('prod-1'), isTrue);
      });
    });

    group('Batch Operations', () {
      setUp(() async {
        await storage.open();
      });

      test('should get many entities', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
        await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});

        final data = await storage.getMany(['prod-1', 'prod-3', 'missing']);
        expect(data.length, 2);
        expect(data['prod-1']!['name'], 'Widget 1');
        expect(data['prod-3']!['name'], 'Widget 3');
        expect(data.containsKey('missing'), isFalse);
      });

      test('should get all entities', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

        final data = await storage.getAll();
        expect(data.length, 2);
        expect(data.containsKey('prod-1'), isTrue);
        expect(data.containsKey('prod-2'), isTrue);
      });

      test('should stream entities', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

        final records = await storage.stream().toList();
        expect(records.length, 2);
        expect(records.map((r) => r.id), containsAll(['prod-1', 'prod-2']));
      });

      test('should insert many entities', () async {
        await storage.insertMany({
          'prod-1': {'name': 'Widget 1', 'price': 10},
          'prod-2': {'name': 'Widget 2', 'price': 20},
          'prod-3': {'name': 'Widget 3', 'price': 30},
        });

        expect(await storage.count, 3);
      });

      test('should throw when insert many has duplicate ID', () async {
        await storage.insert('prod-1', {'name': 'Existing', 'price': 5});

        expect(
          () => storage.insertMany({
            'prod-1': {'name': 'Widget 1', 'price': 10},
            'prod-2': {'name': 'Widget 2', 'price': 20},
          }),
          throwsA(isA<EntityAlreadyExistsException>()),
        );

        // Atomic - no partial inserts
        expect(await storage.count, 1);
      });

      test('should delete many entities', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
        await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});

        final deleted = await storage.deleteMany([
          'prod-1',
          'prod-3',
          'missing',
        ]);
        expect(deleted, 2);
        expect(await storage.count, 1);
      });

      test('should delete all entities', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});

        final deleted = await storage.deleteAll();
        expect(deleted, 2);
        expect(await storage.count, 0);
      });
    });

    group('Transactions', () {
      setUp(() async {
        await storage.open();
      });

      test('should not be in transaction initially', () {
        expect(storage.inTransaction, isFalse);
      });

      test('should begin transaction', () async {
        await storage.beginTransaction();
        expect(storage.inTransaction, isTrue);
      });

      test('should commit transaction', () async {
        await storage.beginTransaction();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.commit();

        expect(storage.inTransaction, isFalse);
        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should rollback transaction - insert', () async {
        await storage.beginTransaction();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        expect(await storage.exists('prod-1'), isTrue);

        await storage.rollback();
        expect(storage.inTransaction, isFalse);
        expect(await storage.exists('prod-1'), isFalse);
      });

      test('should rollback transaction - update', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.update('prod-1', {'name': 'Updated', 'price': 20});
        await storage.rollback();

        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget');
        expect(data['price'], 10);
      });

      test('should rollback transaction - delete', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.delete('prod-1');
        expect(await storage.exists('prod-1'), isFalse);

        await storage.rollback();
        expect(await storage.exists('prod-1'), isTrue);
      });

      test('should rollback transaction - multiple operations', () async {
        await storage.insert('prod-1', {'name': 'Widget 1', 'price': 10});

        await storage.beginTransaction();
        await storage.insert('prod-2', {'name': 'Widget 2', 'price': 20});
        await storage.update('prod-1', {'name': 'Updated', 'price': 15});
        await storage.insert('prod-3', {'name': 'Widget 3', 'price': 30});
        await storage.rollback();

        expect(await storage.count, 1);
        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget 1');
      });

      test('should throw on nested transaction', () async {
        await storage.beginTransaction();

        expect(
          () => storage.beginTransaction(),
          throwsA(isA<TransactionAlreadyActiveException>()),
        );

        await storage.rollback();
      });

      test('should throw on commit without transaction', () async {
        expect(
          () => storage.commit(),
          throwsA(isA<NoActiveTransactionException>()),
        );
      });

      test('should throw on rollback without transaction', () async {
        expect(
          () => storage.rollback(),
          throwsA(isA<NoActiveTransactionException>()),
        );
      });

      test('should rollback on close with active transaction', () async {
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        await storage.beginTransaction();
        await storage.insert('prod-2', {'name': 'Gadget', 'price': 20});
        await storage.close();

        // Reopen and verify rollback occurred
        await storage.open();
        expect(await storage.exists('prod-1'), isFalse); // Memory cleared
        expect(await storage.exists('prod-2'), isFalse);
      });
    });

    group('Error Handling', () {
      test('should throw when operating on closed storage', () async {
        expect(
          () => storage.get('id'),
          throwsA(isA<StorageNotOpenException>()),
        );

        expect(
          () => storage.insert('id', {}),
          throwsA(isA<StorageNotOpenException>()),
        );

        expect(
          () => storage.update('id', {}),
          throwsA(isA<StorageNotOpenException>()),
        );

        expect(
          () => storage.delete('id'),
          throwsA(isA<StorageNotOpenException>()),
        );
      });

      test('should throw when streaming on closed storage', () async {
        expect(
          () => storage.stream().toList(),
          throwsA(isA<StorageNotOpenException>()),
        );
      });
    });

    group('Data Isolation', () {
      test('should return copies of data on get', () async {
        await storage.open();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});

        final data1 = await storage.get('prod-1');
        final data2 = await storage.get('prod-1');

        // Modify data1
        data1!['name'] = 'Modified';

        // data2 should not be affected
        expect(data2!['name'], 'Widget');

        // Stored data should not be affected
        final data3 = await storage.get('prod-1');
        expect(data3!['name'], 'Widget');
      });

      test('should store copies of data on insert', () async {
        await storage.open();
        final original = {'name': 'Widget', 'price': 10};
        await storage.insert('prod-1', original);

        // Modify original
        original['name'] = 'Modified';

        // Stored data should not be affected
        final data = await storage.get('prod-1');
        expect(data!['name'], 'Widget');
      });
    });

    group('Testing Utilities', () {
      test('should expose length for testing', () async {
        await storage.open();
        expect(storage.length, 0);

        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        expect(storage.length, 1);
      });

      test('should reset for testing', () async {
        await storage.open();
        await storage.insert('prod-1', {'name': 'Widget', 'price': 10});
        await storage.beginTransaction();

        storage.reset();

        expect(storage.length, 0);
        expect(storage.inTransaction, isFalse);
      });
    });

    group('StorageRecord', () {
      test('should have correct id and data', () {
        const record = StorageRecord(id: 'test-id', data: {'key': 'value'});

        expect(record.id, 'test-id');
        expect(record.data, {'key': 'value'});
      });

      test('should have meaningful toString', () {
        const record = StorageRecord(id: 'test-id', data: {'key': 'value'});

        expect(record.toString(), contains('test-id'));
        expect(record.toString(), contains('key'));
      });
    });
  });

  group('BinarySerializer - Compression', () {
    test('should serialize and deserialize without compression', () async {
      final serializer = BinarySerializer();

      final data = {
        'name': 'Test Product',
        'price': 29.99,
        'tags': ['electronics', 'sale'],
      };

      final bytes = await serializer.serialize(data);
      final restored = await serializer.deserialize(bytes);

      expect(restored['name'], equals('Test Product'));
      expect(restored['price'], equals(29.99));
      expect(restored['tags'], equals(['electronics', 'sale']));
    });

    test('should serialize and deserialize with compression', () async {
      final serializer = BinarySerializer(
        config: SerializationConfig.compressed(level: 6),
      );

      final data = {
        'name': 'Test Product with a very long name for compression testing',
        'description': 'A long description that repeats many times: ' * 20,
        'price': 29.99,
        'tags': List.generate(50, (i) => 'tag$i'),
      };

      final bytes = await serializer.serialize(data);
      final restored = await serializer.deserialize(bytes);

      expect(restored['name'], equals(data['name']));
      expect(restored['description'], equals(data['description']));
      expect(restored['price'], equals(29.99));
      expect(restored['tags'], equals(data['tags']));
    });

    test(
      'should produce smaller output with compression for large data',
      () async {
        final uncompressedSerializer = BinarySerializer();
        final compressedSerializer = BinarySerializer(
          config: SerializationConfig.compressed(level: 9),
        );

        // Data that compresses well (repetitive content)
        final data = {
          'content': 'The quick brown fox jumps over the lazy dog. ' * 100,
          'metadata': {
            for (var i = 0; i < 50; i++)
              'field$i': 'value$i with repeated text',
          },
        };

        final uncompressed = await uncompressedSerializer.serialize(data);
        final compressed = await compressedSerializer.serialize(data);

        expect(
          compressed.length,
          lessThan(uncompressed.length),
          reason: 'Compressed data should be smaller than uncompressed',
        );

        // Both should deserialize correctly
        final restoredUncompressed = await uncompressedSerializer.deserialize(
          uncompressed,
        );
        final restoredCompressed = await compressedSerializer.deserialize(
          compressed,
        );

        expect(restoredUncompressed['content'], equals(data['content']));
        expect(restoredCompressed['content'], equals(data['content']));
      },
    );

    test('should skip compression for small data', () async {
      final serializer = BinarySerializer(
        config: SerializationConfig.compressed(),
      );

      // Small data below threshold (64 bytes)
      final data = {'x': 1, 'y': 2};

      final bytes = await serializer.serialize(data);

      // Check that compressed flag is not set (byte at position 3)
      expect(
        bytes[3] & 0x02,
        equals(0),
        reason: 'Compressed flag should not be set for small data',
      );
    });

    test(
      'should deserialize uncompressed data with compressed serializer',
      () async {
        final uncompressedSerializer = BinarySerializer();
        final compressedSerializer = BinarySerializer(
          config: SerializationConfig.compressed(),
        );

        final data = {'key': 'value', 'count': 42};

        // Serialize without compression
        final bytes = await uncompressedSerializer.serialize(data);

        // Deserialize with compressed serializer (should auto-detect)
        final restored = await compressedSerializer.deserialize(bytes);

        expect(restored['key'], equals('value'));
        expect(restored['count'], equals(42));
      },
    );

    test(
      'should deserialize compressed data with uncompressed serializer',
      () async {
        final compressedSerializer = BinarySerializer(
          config: SerializationConfig.compressed(),
        );
        final uncompressedSerializer = BinarySerializer();

        // Large data that will be compressed
        final data = {'content': 'Repeated text for compression. ' * 50};

        // Serialize with compression
        final bytes = await compressedSerializer.serialize(data);

        // Deserialize with uncompressed serializer (should auto-detect)
        final restored = await uncompressedSerializer.deserialize(bytes);

        expect(restored['content'], equals(data['content']));
      },
    );

    test('should handle various compression levels', () async {
      final data = {'content': 'Test data for compression levels. ' * 100};

      for (var level = 1; level <= 9; level++) {
        final serializer = BinarySerializer(
          config: SerializationConfig.compressed(level: level),
        );

        final bytes = await serializer.serialize(data);
        final restored = await serializer.deserialize(bytes);

        expect(restored['content'], equals(data['content']));
      }
    });

    test('should support copyWith for SerializationConfig', () {
      const original = SerializationConfig(
        compressionEnabled: true,
        compressionLevel: 6,
      );

      final modified = original.copyWith(compressionLevel: 9);

      expect(original.compressionEnabled, isTrue);
      expect(original.compressionLevel, equals(6));
      expect(modified.compressionEnabled, isTrue);
      expect(modified.compressionLevel, equals(9));
    });

    test('compressionEnabled getter should reflect config', () {
      final serializer1 = BinarySerializer();
      final serializer2 = BinarySerializer(
        config: SerializationConfig.compressed(),
      );

      expect(serializer1.compressionEnabled, isFalse);
      expect(serializer2.compressionEnabled, isTrue);
    });

    test('should handle empty data with compression', () async {
      final serializer = BinarySerializer(
        config: SerializationConfig.compressed(),
      );

      final data = <String, dynamic>{};

      final bytes = await serializer.serialize(data);
      final restored = await serializer.deserialize(bytes);

      expect(restored, isEmpty);
    });

    test('should handle nested maps with compression', () async {
      final serializer = BinarySerializer(
        config: SerializationConfig.compressed(),
      );

      final data = {
        'level1': {
          'level2': {
            'level3': {
              'value':
                  'deeply nested content that benefits from compression ' * 10,
            },
          },
        },
      };

      final bytes = await serializer.serialize(data);
      final restored = await serializer.deserialize(bytes);

      expect(
        (((restored['level1'] as Map)['level2'] as Map)['level3']
            as Map)['value'],
        equals(data['level1']!['level2']!['level3']!['value']),
      );
    });

    test('should handle DateTime with compression', () async {
      final serializer = BinarySerializer(
        config: SerializationConfig.compressed(),
      );

      // CBOR DateTime serialization uses second precision
      final now = DateTime.now();
      final data = {
        'timestamp': now,
        'padding': 'data to make it compressible ' * 10,
      };

      final bytes = await serializer.serialize(data);
      final restored = await serializer.deserialize(bytes);

      // Compare at second precision since CBOR DateTime uses epoch seconds
      final restoredTimestamp = restored['timestamp'] as DateTime;
      expect(
        restoredTimestamp.difference(now).inSeconds.abs(),
        lessThanOrEqualTo(1),
        reason: 'DateTime should be within 1 second of original',
      );
    });
  });
}
