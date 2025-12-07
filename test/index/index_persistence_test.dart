// Index Persistence Tests
//
// Tests for the IndexPersistence module which provides disk-based
// persistence for BTree and Hash indexes.

import 'dart:io';

import 'package:docdb/docdb.dart';
import 'package:test/test.dart';

void main() {
  group('SerializedIndex', () {
    group('BTreeIndex serialization', () {
      test('serializes and deserializes empty index', () {
        final index = BTreeIndex('name');
        final serialized = SerializedIndex(
          field: 'name',
          type: IndexType.btree,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        expect(bytes, isNotEmpty);

        final restored = SerializedIndex.fromBytes(bytes);
        expect(restored.field, equals('name'));
        expect(restored.type, equals(IndexType.btree));
        expect(restored.entries, isEmpty);
      });

      test('serializes and deserializes index with string keys', () {
        final index = BTreeIndex('name');
        index.insert('entity-1', {'name': 'Alice'});
        index.insert('entity-2', {'name': 'Bob'});
        index.insert('entity-3', {'name': 'Alice'});

        final serialized = SerializedIndex(
          field: 'name',
          type: IndexType.btree,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.field, equals('name'));
        expect(restored.type, equals(IndexType.btree));
        expect(
          restored.entries['Alice'],
          containsAll(['entity-1', 'entity-3']),
        );
        expect(restored.entries['Bob'], contains('entity-2'));
      });

      test('serializes and deserializes index with integer keys', () {
        final index = BTreeIndex('age');
        index.insert('entity-1', {'age': 25});
        index.insert('entity-2', {'age': 30});
        index.insert('entity-3', {'age': 25});

        final serialized = SerializedIndex(
          field: 'age',
          type: IndexType.btree,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.entries[25], containsAll(['entity-1', 'entity-3']));
        expect(restored.entries[30], contains('entity-2'));
      });

      test('serializes and deserializes index with double keys', () {
        final index = BTreeIndex('price');
        index.insert('product-1', {'price': 29.99});
        index.insert('product-2', {'price': 49.99});

        final serialized = SerializedIndex(
          field: 'price',
          type: IndexType.btree,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.entries[29.99], contains('product-1'));
        expect(restored.entries[49.99], contains('product-2'));
      });

      test('serializes and deserializes index with boolean keys', () {
        // Note: BTreeIndex uses SplayTreeMap which requires Comparable keys.
        // Booleans are not Comparable, so we use HashIndex for boolean fields.
        final index = HashIndex('active');
        index.insert('entity-1', {'active': true});
        index.insert('entity-2', {'active': false});

        final serialized = SerializedIndex(
          field: 'active',
          type: IndexType.hash,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.entries[true], contains('entity-1'));
        expect(restored.entries[false], contains('entity-2'));
      });

      test('serializes and deserializes index with DateTime keys', () {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));

        final index = BTreeIndex('createdAt');
        index.insert('entity-1', {'createdAt': now});
        index.insert('entity-2', {'createdAt': yesterday});

        final serialized = SerializedIndex(
          field: 'createdAt',
          type: IndexType.btree,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        // DateTime should be restored (though as string if not specially handled)
        expect(restored.entries.length, equals(2));
      });
    });

    group('HashIndex serialization', () {
      test('serializes and deserializes empty hash index', () {
        final index = HashIndex('email');
        final serialized = SerializedIndex(
          field: 'email',
          type: IndexType.hash,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.field, equals('email'));
        expect(restored.type, equals(IndexType.hash));
        expect(restored.entries, isEmpty);
      });

      test('serializes and deserializes hash index with data', () {
        final index = HashIndex('email');
        index.insert('user-1', {'email': 'alice@example.com'});
        index.insert('user-2', {'email': 'bob@example.com'});

        final serialized = SerializedIndex(
          field: 'email',
          type: IndexType.hash,
          entries: index.toMap(),
        );

        final bytes = serialized.toBytes();
        final restored = SerializedIndex.fromBytes(bytes);

        expect(restored.entries['alice@example.com'], contains('user-1'));
        expect(restored.entries['bob@example.com'], contains('user-2'));
      });
    });
  });

  group('BTreeIndex toMap/restoreFromMap', () {
    test('toMap creates deep copy', () {
      final index = BTreeIndex('name');
      index.insert('entity-1', {'name': 'Alice'});

      final map = index.toMap();

      // Modify the returned map
      map['Alice']!.add('entity-extra');

      // Original index should be unchanged
      expect(index.search('Alice'), equals(['entity-1']));
    });

    test('restoreFromMap clears existing data', () {
      final index = BTreeIndex('name');
      index.insert('entity-1', {'name': 'Alice'});

      index.restoreFromMap({
        'Bob': {'entity-2'},
      });

      expect(index.search('Alice'), isEmpty);
      expect(index.search('Bob'), equals(['entity-2']));
    });

    test('restoreFromMap preserves order for range queries', () {
      final index = BTreeIndex('age');

      index.restoreFromMap({
        30: {'entity-3'},
        10: {'entity-1'},
        20: {'entity-2'},
      });

      // Range query should work correctly
      final results = index.rangeSearch(15, 25);
      expect(results, equals(['entity-2']));
    });
  });

  group('HashIndex toMap/restoreFromMap', () {
    test('toMap creates deep copy', () {
      final index = HashIndex('email');
      index.insert('user-1', {'email': 'alice@example.com'});

      final map = index.toMap();

      // Modify the returned map
      map['alice@example.com']!.add('user-extra');

      // Original index should be unchanged
      expect(index.search('alice@example.com'), equals(['user-1']));
    });

    test('restoreFromMap clears existing data', () {
      final index = HashIndex('email');
      index.insert('user-1', {'email': 'alice@example.com'});

      index.restoreFromMap({
        'bob@example.com': {'user-2'},
      });

      expect(index.search('alice@example.com'), isEmpty);
      expect(index.search('bob@example.com'), equals(['user-2']));
    });
  });

  group('IndexPersistence', () {
    late Directory tempDir;
    late IndexPersistence persistence;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docdb_index_test_');
      persistence = IndexPersistence(directory: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves and loads BTreeIndex', () async {
      final index = BTreeIndex('name');
      index.insert('entity-1', {'name': 'Alice'});
      index.insert('entity-2', {'name': 'Bob'});
      index.insert('entity-3', {'name': 'Alice'});

      await persistence.saveIndex('users', 'name', index);

      // Verify file exists
      expect(await persistence.indexExists('users', 'name'), isTrue);

      // Load the index
      final data = await persistence.loadIndex('users', 'name');
      expect(data, isNotNull);
      expect(data!.field, equals('name'));
      expect(data.type, equals(IndexType.btree));

      // Restore to a new index
      final restoredIndex = BTreeIndex('name');
      restoredIndex.restoreFromMap(data.entries);

      expect(
        restoredIndex.search('Alice'),
        containsAll(['entity-1', 'entity-3']),
      );
      expect(restoredIndex.search('Bob'), contains('entity-2'));
    });

    test('saves and loads HashIndex', () async {
      final index = HashIndex('email');
      index.insert('user-1', {'email': 'alice@example.com'});
      index.insert('user-2', {'email': 'bob@example.com'});

      await persistence.saveIndex('users', 'email', index);

      final data = await persistence.loadIndex('users', 'email');
      expect(data, isNotNull);
      expect(data!.type, equals(IndexType.hash));

      final restoredIndex = HashIndex('email');
      restoredIndex.restoreFromMap(data.entries);

      expect(restoredIndex.search('alice@example.com'), contains('user-1'));
      expect(restoredIndex.search('bob@example.com'), contains('user-2'));
    });

    test('loadIndex returns null for non-existent index', () async {
      final data = await persistence.loadIndex('users', 'nonexistent');
      expect(data, isNull);
    });

    test('deleteIndex removes the index file', () async {
      final index = BTreeIndex('name');
      index.insert('entity-1', {'name': 'Alice'});

      await persistence.saveIndex('users', 'name', index);
      expect(await persistence.indexExists('users', 'name'), isTrue);

      await persistence.deleteIndex('users', 'name');
      expect(await persistence.indexExists('users', 'name'), isFalse);
    });

    test(
      'listIndexes returns all persisted indexes for a collection',
      () async {
        final nameIndex = BTreeIndex('name');
        nameIndex.insert('entity-1', {'name': 'Alice'});

        final emailIndex = HashIndex('email');
        emailIndex.insert('user-1', {'email': 'test@example.com'});

        await persistence.saveIndex('users', 'name', nameIndex);
        await persistence.saveIndex('users', 'email', emailIndex);

        final indexes = await persistence.listIndexes('users');
        expect(indexes, containsAll(['name', 'email']));
      },
    );

    test('clearCollection removes all indexes for a collection', () async {
      final nameIndex = BTreeIndex('name');
      final emailIndex = HashIndex('email');

      await persistence.saveIndex('users', 'name', nameIndex);
      await persistence.saveIndex('users', 'email', emailIndex);

      await persistence.clearCollection('users');

      expect(await persistence.indexExists('users', 'name'), isFalse);
      expect(await persistence.indexExists('users', 'email'), isFalse);
    });
  });

  group('IndexManager persistence integration', () {
    late Directory tempDir;
    late IndexPersistence persistence;
    late IndexManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docdb_index_mgr_test_');
      persistence = IndexPersistence(directory: tempDir.path);
      manager = IndexManager();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveAllIndexes persists all indexes', () async {
      manager.createIndex('name', IndexType.btree);
      manager.createIndex('email', IndexType.hash);

      manager.insert('entity-1', {
        'name': 'Alice',
        'email': 'alice@example.com',
      });
      manager.insert('entity-2', {'name': 'Bob', 'email': 'bob@example.com'});

      await manager.saveAllIndexes('users', persistence);

      expect(await persistence.indexExists('users', 'name'), isTrue);
      expect(await persistence.indexExists('users', 'email'), isTrue);
    });

    test('loadAllIndexes restores all indexes', () async {
      // Create and save indexes
      final originalManager = IndexManager();
      originalManager.createIndex('name', IndexType.btree);
      originalManager.createIndex('email', IndexType.hash);
      originalManager.insert('entity-1', {
        'name': 'Alice',
        'email': 'alice@example.com',
      });

      await originalManager.saveAllIndexes('users', persistence);

      // Load into a new manager
      final newManager = IndexManager();
      final count = await newManager.loadAllIndexes('users', persistence);

      expect(count, equals(2));
      expect(newManager.search('name', 'Alice'), contains('entity-1'));
      expect(
        newManager.search('email', 'alice@example.com'),
        contains('entity-1'),
      );
    });

    test('saveIndex and loadIndex work for single index', () async {
      manager.createIndex('name', IndexType.btree);
      manager.insert('entity-1', {'name': 'Alice'});

      await manager.saveIndex('users', 'name', persistence);

      final newManager = IndexManager();
      final loaded = await newManager.loadIndex('users', 'name', persistence);

      expect(loaded, isTrue);
      expect(newManager.search('name', 'Alice'), contains('entity-1'));
    });

    test('loadIndex returns false for non-existent index', () async {
      final loaded = await manager.loadIndex(
        'users',
        'nonexistent',
        persistence,
      );
      expect(loaded, isFalse);
    });

    test('getIndex returns the index for direct access', () {
      manager.createIndex('name', IndexType.btree);

      final index = manager.getIndex('name');
      expect(index, isNotNull);
      expect(index, isA<BTreeIndex>());
    });

    test('allIndexes returns all index entries', () {
      manager.createIndex('name', IndexType.btree);
      manager.createIndex('email', IndexType.hash);

      final entries = manager.allIndexes.toList();
      expect(entries.length, equals(2));
      expect(entries.map((e) => e.key), containsAll(['name', 'email']));
    });

    test('registerIndex adds pre-built index', () {
      final index = BTreeIndex('name');
      index.insert('entity-1', {'name': 'Alice'});

      manager.registerIndex('name', index);

      expect(manager.search('name', 'Alice'), contains('entity-1'));
    });

    test('registerIndex throws on duplicate', () {
      manager.createIndex('name', IndexType.btree);

      final index = BTreeIndex('name');
      expect(
        () => manager.registerIndex('name', index),
        throwsA(isA<IndexAlreadyExistsException>()),
      );
    });
  });

  group('Index persistence with large data', () {
    late Directory tempDir;
    late IndexPersistence persistence;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docdb_large_idx_test_');
      persistence = IndexPersistence(directory: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('handles large number of entries', () async {
      final index = BTreeIndex('counter');

      // Insert 10,000 entries
      for (var i = 0; i < 10000; i++) {
        index.insert('entity-$i', {'counter': i % 100});
      }

      await persistence.saveIndex('large', 'counter', index);

      final data = await persistence.loadIndex('large', 'counter');
      expect(data, isNotNull);
      expect(data!.entries.length, equals(100)); // 100 unique keys

      final restoredIndex = BTreeIndex('counter');
      restoredIndex.restoreFromMap(data.entries);

      // Each key should have 100 entities (10000 / 100 unique keys)
      expect(restoredIndex.search(0).length, equals(100));
      expect(restoredIndex.search(50).length, equals(100));
    });

    test('handles many unique keys', () async {
      final index = HashIndex('uuid');

      // Insert 5,000 entries with unique keys
      for (var i = 0; i < 5000; i++) {
        index.insert('entity-$i', {'uuid': 'uuid-$i'});
      }

      await persistence.saveIndex('unique', 'uuid', index);

      final data = await persistence.loadIndex('unique', 'uuid');
      expect(data, isNotNull);
      expect(data!.entries.length, equals(5000));

      final restoredIndex = HashIndex('uuid');
      restoredIndex.restoreFromMap(data.entries);

      // Verify some random lookups
      expect(restoredIndex.search('uuid-0'), contains('entity-0'));
      expect(restoredIndex.search('uuid-2500'), contains('entity-2500'));
      expect(restoredIndex.search('uuid-4999'), contains('entity-4999'));
    });
  });
}
