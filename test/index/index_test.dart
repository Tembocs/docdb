/// DocDB Index Module Tests
///
/// Comprehensive tests for the index module including BTreeIndex and HashIndex
/// implementations for efficient data lookup and range queries.
library;

import 'package:test/test.dart';

import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/index/index.dart';
import 'package:docdb/src/query/query_types.dart';

void main() {
  group('IIndex Interface', () {
    group('IndexType Enum', () {
      test('should have btree, hash, and fulltext types', () {
        expect(IndexType.values, contains(IndexType.btree));
        expect(IndexType.values, contains(IndexType.hash));
        expect(IndexType.values, contains(IndexType.fulltext));
        expect(IndexType.values.length, equals(3));
      });

      test('should have correct string representations', () {
        expect(IndexType.btree.toString(), contains('btree'));
        expect(IndexType.hash.toString(), contains('hash'));
        expect(IndexType.fulltext.toString(), contains('fulltext'));
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

  // ===========================================================================
  // FullTextIndex Tests
  // ===========================================================================
  group('FullTextIndex', () {
    late FullTextIndex index;

    setUp(() {
      index = FullTextIndex('content');
    });

    group('Construction', () {
      test('should create index with field name', () {
        expect(index.field, equals('content'));
        expect(index.termCount, equals(0));
        expect(index.entryCount, equals(0));
      });

      test('should create index with custom config', () {
        final customIndex = FullTextIndex(
          'body',
          config: const FullTextConfig(minTokenLength: 3, caseSensitive: true),
        );
        expect(customIndex.field, equals('body'));
        expect(customIndex.config.minTokenLength, equals(3));
        expect(customIndex.config.caseSensitive, isTrue);
      });

      test('should create index with no stop words config', () {
        final noStopIndex = FullTextIndex(
          'text',
          config: const FullTextConfig.noStopWords(),
        );
        expect(noStopIndex.config.stopWords, isEmpty);
      });
    });

    group('Insert Operations', () {
      test('should insert and tokenize document', () {
        index.insert('doc-1', {'content': 'The quick brown fox'});
        expect(index.documentCount, equals(1));
        expect(index.termCount, greaterThan(0));
      });

      test('should not insert null content', () {
        index.insert('doc-1', {'other': 'value'});
        expect(index.documentCount, equals(0));
      });

      test('should filter stop words', () {
        index.insert('doc-1', {'content': 'the and or is'});
        // All stop words, nothing should be indexed
        expect(index.termCount, equals(0));
      });

      test('should filter short tokens', () {
        index.insert('doc-1', {'content': 'a b c de'});
        // Only 'de' is >= 2 chars
        expect(index.termCount, equals(1));
      });

      test('should track term positions', () {
        index.insert('doc-1', {'content': 'quick brown quick'});
        // 'quick' appears at positions 0 and 2
        expect(index.documentCount, equals(1));
      });

      test('should handle multiple documents', () {
        index.insert('doc-1', {'content': 'The quick brown fox'});
        index.insert('doc-2', {'content': 'A lazy brown dog'});
        index.insert('doc-3', {'content': 'Fast red rabbit'});
        expect(index.documentCount, equals(3));
      });
    });

    group('Remove Operations', () {
      test('should remove document from index', () {
        index.insert('doc-1', {'content': 'quick brown fox'});
        expect(index.documentCount, equals(1));

        index.remove('doc-1', {'content': 'quick brown fox'});
        expect(index.documentCount, equals(0));
      });

      test('should remove terms when document is removed', () {
        index.insert('doc-1', {'content': 'unique term here'});
        expect(index.termCount, equals(3));

        index.remove('doc-1', {'content': 'unique term here'});
        expect(index.termCount, equals(0));
      });

      test('should not remove terms used by other documents', () {
        index.insert('doc-1', {'content': 'shared term'});
        index.insert('doc-2', {'content': 'shared word'});

        index.remove('doc-1', {'content': 'shared term'});
        expect(index.documentCount, equals(1));
        expect(index.getDocumentFrequency('shared'), equals(1));
      });
    });

    group('Basic Search', () {
      setUp(() {
        index.insert('doc-1', {'content': 'The quick brown fox jumps'});
        index.insert('doc-2', {'content': 'A lazy brown dog sleeps'});
        index.insert('doc-3', {'content': 'Fast red rabbit runs'});
      });

      test('should find single term', () {
        final results = index.search('brown');
        expect(results, containsAll(['doc-1', 'doc-2']));
        expect(results.length, equals(2));
      });

      test('should find documents with all terms (AND)', () {
        final results = index.search('brown fox');
        expect(results, equals(['doc-1']));
      });

      test('should be case-insensitive by default', () {
        final results = index.search('BROWN');
        expect(results, containsAll(['doc-1', 'doc-2']));
      });

      test('should return empty for non-existent term', () {
        final results = index.search('nonexistent');
        expect(results, isEmpty);
      });

      test('should return empty for null search', () {
        final results = index.search(null);
        expect(results, isEmpty);
      });
    });

    group('searchAll (AND semantics)', () {
      setUp(() {
        index.insert('doc-1', {'content': 'quick brown fox'});
        index.insert('doc-2', {'content': 'lazy brown dog'});
        index.insert('doc-3', {'content': 'quick red rabbit'});
      });

      test('should find documents containing all terms', () {
        final results = index.searchAll(['quick', 'brown']);
        expect(results, equals(['doc-1']));
      });

      test('should return empty if any term is missing', () {
        final results = index.searchAll(['quick', 'zebra']);
        expect(results, isEmpty);
      });

      test('should handle empty terms list', () {
        final results = index.searchAll([]);
        expect(results, isEmpty);
      });
    });

    group('searchAny (OR semantics)', () {
      setUp(() {
        index.insert('doc-1', {'content': 'quick brown fox'});
        index.insert('doc-2', {'content': 'lazy brown dog'});
        index.insert('doc-3', {'content': 'fast red rabbit'});
      });

      test('should find documents containing any term', () {
        final results = index.searchAny(['quick', 'fast']);
        expect(results, containsAll(['doc-1', 'doc-3']));
        expect(results.length, equals(2));
      });

      test('should return empty if no terms match', () {
        final results = index.searchAny(['zebra', 'elephant']);
        expect(results, isEmpty);
      });
    });

    group('Phrase Search', () {
      setUp(() {
        index.insert('doc-1', {'content': 'the quick brown fox'});
        index.insert('doc-2', {'content': 'brown quick fox'});
        index.insert('doc-3', {'content': 'quick red fox'});
      });

      test('should find exact phrase', () {
        final results = index.searchPhrase('quick brown');
        expect(results, equals(['doc-1']));
      });

      test('should not match wrong order', () {
        final results = index.searchPhrase('brown quick');
        expect(results, equals(['doc-2']));
      });

      test('should find single word phrase', () {
        final results = index.searchPhrase('quick');
        expect(results.length, equals(3));
      });

      test('should return empty for non-matching phrase', () {
        final results = index.searchPhrase('lazy dog');
        expect(results, isEmpty);
      });
    });

    group('Proximity Search', () {
      setUp(() {
        index.insert('doc-1', {'content': 'quick brown fox'});
        index.insert('doc-2', {'content': 'quick lazy brown sleepy fox'});
      });

      test('should find terms within distance', () {
        final results = index.searchProximity(['quick', 'fox'], 2);
        expect(results, equals(['doc-1']));
      });

      test('should find terms within larger distance', () {
        final results = index.searchProximity(['quick', 'fox'], 5);
        expect(results, containsAll(['doc-1', 'doc-2']));
      });

      test('should not find terms beyond distance', () {
        final results = index.searchProximity(['quick', 'fox'], 1);
        expect(results, isEmpty);
      });
    });

    group('Prefix Search', () {
      setUp(() {
        index.insert('doc-1', {'content': 'quicksand quickly quote'});
        index.insert('doc-2', {'content': 'slow steady'});
      });

      test('should find terms with matching prefix', () {
        final results = index.searchPrefix('qui');
        expect(results, equals(['doc-1']));
      });

      test('should return empty for non-matching prefix', () {
        final results = index.searchPrefix('xyz');
        expect(results, isEmpty);
      });

      test('should handle empty prefix', () {
        final results = index.searchPrefix('');
        expect(results, isEmpty);
      });
    });

    group('Ranked Search (TF-IDF)', () {
      setUp(() {
        // doc-1 has 'brown' once
        index.insert('doc-1', {'content': 'quick brown fox'});
        // doc-2 has 'brown' multiple times (higher TF)
        index.insert('doc-2', {'content': 'brown brown brown dog'});
        // doc-3 has different terms
        index.insert('doc-3', {'content': 'red blue green'});
      });

      test('should return scored results', () {
        final results = index.searchRanked('brown');
        expect(results.length, equals(2));
        expect(results.first.entityId, isIn(['doc-1', 'doc-2']));
        expect(results.first.score, greaterThan(0));
      });

      test('should rank higher TF documents higher', () {
        final results = index.searchRanked('brown');
        // doc-2 has 'brown' 3 times, should have higher TF score
        expect(results.first.entityId, equals('doc-2'));
      });

      test('should return empty for no matches', () {
        final results = index.searchRanked('nonexistent');
        expect(results, isEmpty);
      });
    });

    group('Document Frequency', () {
      setUp(() {
        index.insert('doc-1', {'content': 'quick brown fox'});
        index.insert('doc-2', {'content': 'lazy brown dog'});
        index.insert('doc-3', {'content': 'fast red rabbit'});
      });

      test('should return correct document frequency', () {
        expect(index.getDocumentFrequency('brown'), equals(2));
        expect(index.getDocumentFrequency('quick'), equals(1));
        expect(index.getDocumentFrequency('nonexistent'), equals(0));
      });
    });

    group('Clear', () {
      test('should clear all entries', () {
        index.insert('doc-1', {'content': 'quick brown fox'});
        index.insert('doc-2', {'content': 'lazy brown dog'});

        index.clear();

        expect(index.documentCount, equals(0));
        expect(index.termCount, equals(0));
      });
    });

    group('Serialization', () {
      test('should export to map', () {
        index.insert('doc-1', {'content': 'quick brown fox'});

        final map = index.toMap();

        expect(map.containsKey('inverted'), isTrue);
        expect(map.containsKey('forward'), isTrue);
        expect(map.containsKey('config'), isTrue);
      });

      test('should restore from map', () {
        index.insert('doc-1', {'content': 'quick brown fox'});

        final map = index.toMap();

        final newIndex = FullTextIndex('content');
        newIndex.restoreFromMap(map);

        expect(newIndex.documentCount, equals(1));
        expect(newIndex.search('quick'), equals(['doc-1']));
      });
    });

    group('FullTextConfig', () {
      test('case-sensitive config should respect case', () {
        final csIndex = FullTextIndex(
          'content',
          config: const FullTextConfig(caseSensitive: true),
        );

        csIndex.insert('doc-1', {'content': 'Quick BROWN fox'});

        expect(csIndex.search('Quick'), equals(['doc-1']));
        expect(csIndex.search('quick'), isEmpty);
      });

      test('custom min token length should filter short tokens', () {
        final longIndex = FullTextIndex(
          'content',
          config: const FullTextConfig(minTokenLength: 5),
        );

        longIndex.insert('doc-1', {'content': 'hi there friend'});

        // 'hi' (2), 'there' (5), 'friend' (6)
        expect(longIndex.termCount, equals(2));
        expect(longIndex.search('there'), equals(['doc-1']));
        expect(longIndex.search('hi'), isEmpty);
      });
    });
  });

  // ===========================================================================
  // Full-Text Query Types Tests
  // ===========================================================================
  group('Full-Text Query Types', () {
    group('FullTextQuery', () {
      test('should match documents containing all terms', () {
        final query = FullTextQuery('content', 'quick brown');
        expect(query.matches({'content': 'The quick brown fox'}), isTrue);
        expect(query.matches({'content': 'Only quick fox'}), isFalse);
      });

      test('should be case-insensitive by default', () {
        final query = FullTextQuery('content', 'QUICK');
        expect(query.matches({'content': 'quick fox'}), isTrue);
      });

      test('should serialize and deserialize', () {
        final query = FullTextQuery('content', 'test search');
        final map = query.toMap();
        expect(map['type'], equals('FullTextQuery'));
        expect(map['field'], equals('content'));
        expect(map['searchText'], equals('test search'));
      });
    });

    group('FullTextPhraseQuery', () {
      test('should match exact phrase', () {
        final query = FullTextPhraseQuery('content', 'quick brown');
        expect(query.matches({'content': 'The quick brown fox'}), isTrue);
        expect(query.matches({'content': 'The brown quick fox'}), isFalse);
      });

      test('should serialize correctly', () {
        final query = FullTextPhraseQuery('content', 'exact phrase');
        final map = query.toMap();
        expect(map['type'], equals('FullTextPhraseQuery'));
        expect(map['phrase'], equals('exact phrase'));
      });
    });

    group('FullTextAnyQuery', () {
      test('should match documents with any term', () {
        final query = FullTextAnyQuery('content', ['quick', 'slow']);
        expect(query.matches({'content': 'quick fox'}), isTrue);
        expect(query.matches({'content': 'slow dog'}), isTrue);
        expect(query.matches({'content': 'fast rabbit'}), isFalse);
      });

      test('should serialize correctly', () {
        final query = FullTextAnyQuery('content', ['a', 'b']);
        final map = query.toMap();
        expect(map['type'], equals('FullTextAnyQuery'));
        expect(map['terms'], equals(['a', 'b']));
      });
    });

    group('FullTextPrefixQuery', () {
      test('should match terms with prefix', () {
        final query = FullTextPrefixQuery('content', 'qui');
        expect(query.matches({'content': 'quick fox'}), isTrue);
        expect(query.matches({'content': 'slow dog'}), isFalse);
      });
    });

    group('FullTextProximityQuery', () {
      test('should match terms within distance', () {
        final query = FullTextProximityQuery('content', ['quick', 'fox'], 2);
        expect(query.matches({'content': 'quick brown fox'}), isTrue);
        expect(query.matches({'content': 'quick a b c d e fox'}), isFalse);
      });
    });
  });

  // ===========================================================================
  // IndexManager Full-Text Support Tests
  // ===========================================================================
  group('IndexManager FullText Support', () {
    late IndexManager manager;

    setUp(() {
      manager = IndexManager();
    });

    test('should create fulltext index', () {
      manager.createIndex('content', IndexType.fulltext);
      expect(manager.hasIndex('content'), isTrue);
      expect(manager.hasIndexOfType('content', IndexType.fulltext), isTrue);
    });

    test('should return correct index type', () {
      manager.createIndex('content', IndexType.fulltext);
      expect(manager.getIndexType('content'), equals(IndexType.fulltext));
    });

    test('should insert and search fulltext', () {
      manager.createIndex('content', IndexType.fulltext);
      manager.insert('doc-1', {'content': 'quick brown fox'});
      manager.insert('doc-2', {'content': 'lazy brown dog'});

      final results = manager.fullTextSearch('content', 'brown');
      expect(results, containsAll(['doc-1', 'doc-2']));
    });

    test('should perform phrase search', () {
      manager.createIndex('content', IndexType.fulltext);
      manager.insert('doc-1', {'content': 'quick brown fox'});
      manager.insert('doc-2', {'content': 'brown quick fox'});

      final results = manager.fullTextSearchPhrase('content', 'quick brown');
      expect(results, equals(['doc-1']));
    });

    test('should perform prefix search', () {
      manager.createIndex('content', IndexType.fulltext);
      manager.insert('doc-1', {'content': 'quicksand quickly'});
      manager.insert('doc-2', {'content': 'slow steady'});

      final results = manager.fullTextSearchPrefix('content', 'qui');
      expect(results, equals(['doc-1']));
    });

    test('should perform ranked search', () {
      manager.createIndex('content', IndexType.fulltext);
      manager.insert('doc-1', {'content': 'brown fox'});
      manager.insert('doc-2', {'content': 'brown brown brown'});

      final results = manager.fullTextSearchRanked('content', 'brown');
      expect(results.length, equals(2));
      // Both documents should be present with scores
      expect(
        results.map((r) => r.entityId).toList(),
        containsAll(['doc-1', 'doc-2']),
      );
      expect(results.first.score, greaterThanOrEqualTo(results.last.score));
    });

    test('should return cardinality for fulltext index', () {
      manager.createIndex('content', IndexType.fulltext);
      manager.insert('doc-1', {'content': 'quick brown fox'});

      expect(manager.getCardinality('content'), greaterThan(0));
    });

    test('should throw on fulltext search for non-fulltext index', () {
      manager.createIndex('value', IndexType.hash);
      expect(
        () => manager.fullTextSearch('value', 'test'),
        throwsA(isA<UnsupportedIndexTypeException>()),
      );
    });
  });
}
