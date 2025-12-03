/// DocDB Index Module Tests
///
/// Comprehensive tests for the index module including BTreeIndex and HashIndex
/// implementations for efficient data lookup and range queries.
library;

import 'package:test/test.dart';

import 'package:docdb/src/index/index.dart';

void main() {
  group('IIndex Interface', () {
    group('IndexType Enum', () {
      test('should have btree and hash types', () {
        expect(IndexType.values, contains(IndexType.btree));
        expect(IndexType.values, contains(IndexType.hash));
        expect(IndexType.values.length, equals(2));
      });

      test('should have correct string representations', () {
        expect(IndexType.btree.toString(), contains('btree'));
        expect(IndexType.hash.toString(), contains('hash'));
      });
    });
  });

  group('BTreeIndex', () {
    late BTreeIndex index;

    setUp(() {
      index = BTreeIndex('age');
    });

    group('Construction', () {
      test('should create index with field name', () {
        expect(index.field, equals('age'));
        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
      });

      test('should start empty', () {
        expect(index.minKey, isNull);
        expect(index.maxKey, isNull);
      });
    });

    group('Insert Operations', () {
      test('should insert single entity', () {
        index.insert('entity-1', {'age': 25});
        expect(index.keyCount, equals(1));
        expect(index.entryCount, equals(1));
      });

      test('should insert multiple entities with different keys', () {
        index.insert('entity-1', {'age': 25});
        index.insert('entity-2', {'age': 30});
        index.insert('entity-3', {'age': 35});
        expect(index.keyCount, equals(3));
        expect(index.entryCount, equals(3));
      });

      test('should insert multiple entities with same key', () {
        index.insert('entity-1', {'age': 25});
        index.insert('entity-2', {'age': 25});
        expect(index.keyCount, equals(1));
        expect(index.entryCount, equals(2));
      });

      test('should not insert entity with null field value', () {
        index.insert('entity-1', {'name': 'Alice'});
        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
      });

      test('should maintain sorted order for keys', () {
        index.insert('e5', {'age': 50});
        index.insert('e1', {'age': 10});
        index.insert('e3', {'age': 30});
        index.insert('e2', {'age': 20});
        index.insert('e4', {'age': 40});

        expect(index.minKey, equals(10));
        expect(index.maxKey, equals(50));
      });

      test('should handle negative numeric keys', () {
        index.insert('e1', {'age': -10});
        index.insert('e2', {'age': 0});
        index.insert('e3', {'age': 10});

        expect(index.minKey, equals(-10));
        expect(index.maxKey, equals(10));
      });
    });

    group('Search Operations', () {
      setUp(() {
        index.insert('entity-1', {'age': 25});
        index.insert('entity-2', {'age': 30});
        index.insert('entity-3', {'age': 25});
        index.insert('entity-4', {'age': 35});
      });

      test('should search for existing key and return all entity IDs', () {
        final results = index.search(25);
        expect(results, hasLength(2));
        expect(results, containsAll(['entity-1', 'entity-3']));
      });

      test('should return empty list for non-existent key', () {
        final results = index.search(99);
        expect(results, isEmpty);
      });

      test('should search for single-entity key correctly', () {
        final results = index.search(30);
        expect(results, equals(['entity-2']));
      });
    });

    group('Range Search', () {
      setUp(() {
        for (var i = 1; i <= 10; i++) {
          index.insert('entity-$i', {'age': i * 10});
        }
      });

      test('should perform inclusive lower bound range search', () {
        // Ages 30-70 inclusive lower, exclusive upper by default
        final results = index.rangeSearch(30, 80);
        expect(results, hasLength(5));
        expect(
          results,
          containsAll([
            'entity-3',
            'entity-4',
            'entity-5',
            'entity-6',
            'entity-7',
          ]),
        );
      });

      test('should perform exclusive upper bound range search', () {
        // Ages 30-60, upper exclusive
        final results = index.rangeSearch(30, 60);
        expect(results, hasLength(3));
        expect(results, containsAll(['entity-3', 'entity-4', 'entity-5']));
      });

      test('should perform inclusive upper bound when specified', () {
        final results = index.rangeSearch(30, 60, includeUpper: true);
        expect(results, hasLength(4));
        expect(
          results,
          containsAll(['entity-3', 'entity-4', 'entity-5', 'entity-6']),
        );
      });

      test('should perform exclusive lower bound when specified', () {
        final results = index.rangeSearch(30, 60, includeLower: false);
        expect(results, hasLength(2));
        expect(results, containsAll(['entity-4', 'entity-5']));
      });

      test('should return empty for out-of-range query', () {
        final results = index.rangeSearch(200, 300);
        expect(results, isEmpty);
      });

      test('should handle null lower bound (from minimum)', () {
        final results = index.rangeSearch(null, 40);
        expect(results, hasLength(3));
        expect(results, containsAll(['entity-1', 'entity-2', 'entity-3']));
      });

      test('should handle null upper bound (to maximum)', () {
        final results = index.rangeSearch(80, null);
        expect(results, hasLength(3));
        expect(results, containsAll(['entity-8', 'entity-9', 'entity-10']));
      });
    });

    group('Remove Operations', () {
      setUp(() {
        index.insert('entity-1', {'age': 25});
        index.insert('entity-2', {'age': 30});
        index.insert('entity-3', {'age': 25});
        index.insert('entity-4', {'age': 35});
      });

      test('should remove specific entity from key', () {
        index.remove('entity-1', {'age': 25});
        final results = index.search(25);
        expect(results, equals(['entity-3']));
        expect(index.keyCount, equals(3));
        expect(index.entryCount, equals(3));
      });

      test('should remove key entirely when last entity removed', () {
        index.remove('entity-2', {'age': 30});
        expect(index.search(30), isEmpty);
        expect(index.keyCount, equals(2));
      });

      test('should handle removing non-existent entity gracefully', () {
        // Should not throw
        index.remove('nonexistent', {'age': 25});
        expect(index.entryCount, equals(4));
      });

      test('should handle removing with non-indexed field', () {
        // Should not throw
        index.remove('entity-1', {'name': 'Alice'});
        expect(index.entryCount, equals(4));
      });
    });

    group('Min/Max Key Operations', () {
      test('should return null for minKey on empty index', () {
        expect(index.minKey, isNull);
      });

      test('should return null for maxKey on empty index', () {
        expect(index.maxKey, isNull);
      });

      test('should return correct minKey', () {
        index.insert('e1', {'age': 50});
        index.insert('e2', {'age': 10});
        index.insert('e3', {'age': 100});
        expect(index.minKey, equals(10));
      });

      test('should return correct maxKey', () {
        index.insert('e1', {'age': 50});
        index.insert('e2', {'age': 10});
        index.insert('e3', {'age': 100});
        expect(index.maxKey, equals(100));
      });

      test('should update min/max after removal', () {
        index.insert('e1', {'age': 10});
        index.insert('e2', {'age': 50});
        index.insert('e3', {'age': 100});

        index.remove('e1', {'age': 10});
        expect(index.minKey, equals(50));

        index.remove('e3', {'age': 100});
        expect(index.maxKey, equals(50));
      });
    });

    group('Clear', () {
      test('should clear all entries', () {
        index.insert('e1', {'age': 25});
        index.insert('e2', {'age': 30});
        index.insert('e3', {'age': 35});

        index.clear();

        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
        expect(index.minKey, isNull);
        expect(index.maxKey, isNull);
      });
    });

    group('String Field Values', () {
      late BTreeIndex nameIndex;

      setUp(() {
        nameIndex = BTreeIndex('name');
      });

      test('should handle string keys in sorted order', () {
        nameIndex.insert('e2', {'name': 'banana'});
        nameIndex.insert('e1', {'name': 'apple'});
        nameIndex.insert('e3', {'name': 'cherry'});

        expect(nameIndex.minKey, equals('apple'));
        expect(nameIndex.maxKey, equals('cherry'));
      });

      test('should perform range search on string keys', () {
        nameIndex.insert('e1', {'name': 'aaa'});
        nameIndex.insert('e2', {'name': 'bbb'});
        nameIndex.insert('e3', {'name': 'ccc'});
        nameIndex.insert('e4', {'name': 'ddd'});

        final results = nameIndex.rangeSearch('bbb', 'ddd');
        expect(results, containsAll(['e2', 'e3']));
      });
    });

    group('DateTime Field Values', () {
      late BTreeIndex dateIndex;

      setUp(() {
        dateIndex = BTreeIndex('createdAt');
      });

      test('should handle DateTime keys', () {
        dateIndex.insert('e1', {'createdAt': DateTime(2024, 1, 1)});
        dateIndex.insert('e2', {'createdAt': DateTime(2024, 6, 15)});
        dateIndex.insert('e3', {'createdAt': DateTime(2024, 12, 31)});

        expect(dateIndex.minKey, equals(DateTime(2024, 1, 1)));
        expect(dateIndex.maxKey, equals(DateTime(2024, 12, 31)));
      });

      test('should perform range search on DateTime keys', () {
        dateIndex.insert('e1', {'createdAt': DateTime(2024, 1, 1)});
        dateIndex.insert('e2', {'createdAt': DateTime(2024, 6, 15)});
        dateIndex.insert('e3', {'createdAt': DateTime(2024, 12, 31)});

        // First half of 2024
        final results = dateIndex.rangeSearch(
          DateTime(2024, 1, 1),
          DateTime(2024, 7, 1),
        );
        expect(results, containsAll(['e1', 'e2']));
      });
    });

    group('Large Dataset', () {
      test('should handle large number of entries', () {
        const count = 1000;
        for (var i = 0; i < count; i++) {
          index.insert('entity-$i', {'age': i});
        }

        expect(index.keyCount, equals(count));
        expect(index.entryCount, equals(count));
        expect(index.minKey, equals(0));
        expect(index.maxKey, equals(count - 1));

        // Verify random searches
        expect(index.search(500), equals(['entity-500']));
        expect(index.search(999), equals(['entity-999']));
      });

      test('should perform range search on large dataset', () {
        for (var i = 0; i < 1000; i++) {
          index.insert('entity-$i', {'age': i});
        }

        // Range 100-110 (exclusive upper)
        final results = index.rangeSearch(100, 110);
        expect(results, hasLength(10));
      });
    });
  });

  group('HashIndex', () {
    late HashIndex index;

    setUp(() {
      index = HashIndex('email');
    });

    group('Construction', () {
      test('should create index with field name', () {
        expect(index.field, equals('email'));
        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
      });
    });

    group('Insert Operations', () {
      test('should insert single entity', () {
        index.insert('user-1', {'email': 'alice@example.com'});
        expect(index.keyCount, equals(1));
        expect(index.entryCount, equals(1));
      });

      test('should insert multiple entities with different keys', () {
        index.insert('user-1', {'email': 'alice@example.com'});
        index.insert('user-2', {'email': 'bob@example.com'});
        index.insert('user-3', {'email': 'carol@example.com'});
        expect(index.keyCount, equals(3));
        expect(index.entryCount, equals(3));
      });

      test('should insert multiple entities with same key', () {
        index.insert('user-1', {'email': 'shared@example.com'});
        index.insert('user-2', {'email': 'shared@example.com'});
        expect(index.keyCount, equals(1));
        expect(index.entryCount, equals(2));
      });

      test('should not insert entity with null field value', () {
        index.insert('user-1', {'name': 'Alice'});
        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
      });

      test('should handle empty string key', () {
        index.insert('user-1', {'email': ''});
        expect(index.containsKey(''), isTrue);
        expect(index.search(''), equals(['user-1']));
      });
    });

    group('Search Operations', () {
      setUp(() {
        index.insert('user-1', {'email': 'alice@example.com'});
        index.insert('user-2', {'email': 'bob@example.com'});
        index.insert('user-3', {'email': 'alice@example.com'});
        index.insert('user-4', {'email': 'carol@example.com'});
      });

      test('should search for existing key and return all entity IDs', () {
        final results = index.search('alice@example.com');
        expect(results, hasLength(2));
        expect(results, containsAll(['user-1', 'user-3']));
      });

      test('should return empty list for non-existent key', () {
        final results = index.search('nonexistent@example.com');
        expect(results, isEmpty);
      });

      test('should search for single-entity key correctly', () {
        final results = index.search('bob@example.com');
        expect(results, equals(['user-2']));
      });

      test('should check if key exists', () {
        expect(index.containsKey('alice@example.com'), isTrue);
        expect(index.containsKey('nonexistent@example.com'), isFalse);
      });
    });

    group('Remove Operations', () {
      setUp(() {
        index.insert('user-1', {'email': 'alice@example.com'});
        index.insert('user-2', {'email': 'bob@example.com'});
        index.insert('user-3', {'email': 'alice@example.com'});
        index.insert('user-4', {'email': 'carol@example.com'});
      });

      test('should remove specific entity from key', () {
        index.remove('user-1', {'email': 'alice@example.com'});
        final results = index.search('alice@example.com');
        expect(results, equals(['user-3']));
        expect(index.keyCount, equals(3));
        expect(index.entryCount, equals(3));
      });

      test('should remove key entirely when last entity removed', () {
        index.remove('user-2', {'email': 'bob@example.com'});
        expect(index.search('bob@example.com'), isEmpty);
        expect(index.containsKey('bob@example.com'), isFalse);
        expect(index.keyCount, equals(2));
      });

      test('should handle removing non-existent entity gracefully', () {
        // Should not throw
        index.remove('nonexistent', {'email': 'alice@example.com'});
        expect(index.entryCount, equals(4));
      });

      test('should handle removing with non-indexed field', () {
        // Should not throw
        index.remove('user-1', {'name': 'Alice'});
        expect(index.entryCount, equals(4));
      });
    });

    group('Clear', () {
      test('should clear all entries', () {
        index.insert('user-1', {'email': 'alice@example.com'});
        index.insert('user-2', {'email': 'bob@example.com'});
        index.insert('user-3', {'email': 'carol@example.com'});

        index.clear();

        expect(index.keyCount, equals(0));
        expect(index.entryCount, equals(0));
      });
    });

    group('Integer Field Values', () {
      late HashIndex idIndex;

      setUp(() {
        idIndex = HashIndex('userId');
      });

      test('should handle integer keys', () {
        idIndex.insert('entity-1', {'userId': 1001});
        idIndex.insert('entity-2', {'userId': 1002});
        idIndex.insert('entity-3', {'userId': 1003});

        expect(idIndex.search(1002), equals(['entity-2']));
        expect(idIndex.keyCount, equals(3));
      });

      test('should handle negative integer keys', () {
        idIndex.insert('entity-1', {'userId': -1});
        idIndex.insert('entity-2', {'userId': 0});
        idIndex.insert('entity-3', {'userId': 1});

        expect(idIndex.search(-1), equals(['entity-1']));
        expect(idIndex.search(0), equals(['entity-2']));
      });
    });

    group('Large Dataset', () {
      test('should handle large number of entries efficiently', () {
        const count = 1000;
        for (var i = 0; i < count; i++) {
          index.insert('user-$i', {'email': 'user$i@example.com'});
        }

        expect(index.keyCount, equals(count));
        expect(index.entryCount, equals(count));

        // Verify random lookups are fast (O(1))
        expect(index.search('user500@example.com'), equals(['user-500']));
        expect(index.search('user999@example.com'), equals(['user-999']));
      });

      test('should handle many duplicates efficiently', () {
        const email = 'shared@example.com';
        const count = 100;

        for (var i = 0; i < count; i++) {
          index.insert('user-$i', {'email': email});
        }

        expect(index.keyCount, equals(1));
        expect(index.entryCount, equals(count));
        expect(index.search(email), hasLength(count));
      });
    });

    group('Comparison with BTreeIndex', () {
      late BTreeIndex btreeIndex;

      setUp(() {
        btreeIndex = BTreeIndex('category');
        index = HashIndex('category');
      });

      test('should have same basic behavior for insert/search', () {
        // Insert same data in both
        index.insert('e1', {'category': 'A'});
        index.insert('e2', {'category': 'B'});
        index.insert('e3', {'category': 'C'});

        btreeIndex.insert('e1', {'category': 'A'});
        btreeIndex.insert('e2', {'category': 'B'});
        btreeIndex.insert('e3', {'category': 'C'});

        // Verify same results
        expect(index.search('A'), equals(btreeIndex.search('A')));
        expect(index.search('B'), equals(btreeIndex.search('B')));
        expect(index.search('C'), equals(btreeIndex.search('C')));
        expect(index.keyCount, equals(btreeIndex.keyCount));
      });

      test('btree should support range search, hash should not', () {
        // BTree has rangeSearch
        btreeIndex.insert('e1', {'category': 'A'});
        btreeIndex.insert('e2', {'category': 'B'});
        btreeIndex.insert('e3', {'category': 'C'});

        final rangeResults = btreeIndex.rangeSearch('A', 'C');
        expect(rangeResults, containsAll(['e1', 'e2']));

        // HashIndex does not have rangeSearch method (by design)
        // This is a structural difference test
      });
    });
  });

  group('Index Factory Pattern', () {
    test('should be able to create and use multiple indexes', () {
      final ageIndex = BTreeIndex('age');
      final emailIndex = HashIndex('email');
      final nameIndex = BTreeIndex('name');

      // Verify they are independent
      final userData = {
        'age': 25,
        'email': 'alice@example.com',
        'name': 'Alice',
      };

      ageIndex.insert('user-1', userData);
      emailIndex.insert('user-1', userData);
      nameIndex.insert('user-1', userData);

      expect(ageIndex.search(25), equals(['user-1']));
      expect(emailIndex.search('alice@example.com'), equals(['user-1']));
      expect(nameIndex.search('Alice'), equals(['user-1']));
    });
  });

  group('IIndex Contract', () {
    test('BTreeIndex should implement IIndex', () {
      final index = BTreeIndex('field');
      expect(index, isA<IIndex>());
    });

    test('HashIndex should implement IIndex', () {
      final index = HashIndex('field');
      expect(index, isA<IIndex>());
    });

    test('both indexes should have required IIndex properties', () {
      final btree = BTreeIndex('testField');
      final hash = HashIndex('testField');

      expect(btree.field, equals('testField'));
      expect(hash.field, equals('testField'));
    });

    test('both indexes should support required IIndex methods', () {
      final btree = BTreeIndex('value');
      final hash = HashIndex('value');

      final data = {'value': 42};

      // Insert
      btree.insert('id-1', data);
      hash.insert('id-1', data);

      // Search
      expect(btree.search(42), equals(['id-1']));
      expect(hash.search(42), equals(['id-1']));

      // Remove
      btree.remove('id-1', data);
      hash.remove('id-1', data);

      expect(btree.search(42), isEmpty);
      expect(hash.search(42), isEmpty);

      // Clear
      btree.insert('id-2', data);
      hash.insert('id-2', data);

      btree.clear();
      hash.clear();

      expect(btree.keyCount, equals(0));
      expect(hash.keyCount, equals(0));
    });
  });
}
