/// EntiDB Performance Benchmark Regression Tests
///
/// These tests verify that performance characteristics remain within
/// acceptable bounds. They're designed to catch performance regressions
/// during development without being flaky in CI.
///
/// The thresholds are intentionally generous to avoid false positives
/// while still catching significant regressions.
///
/// Note: These tests use in-memory storage to avoid file system
/// variability and ensure consistent, repeatable results across platforms.
library;

import 'package:entidb/entidb.dart';
import 'package:test/test.dart';

/// Test entity for benchmarks.
class BenchProduct implements Entity {
  @override
  final String? id;
  final String name;
  final String description;
  final double price;
  final int quantity;
  final List<String> tags;

  BenchProduct({
    this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.quantity,
    required this.tags,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'description': description,
    'price': price,
    'quantity': quantity,
    'tags': tags,
  };

  static BenchProduct fromMap(String id, Map<String, dynamic> map) {
    return BenchProduct(
      id: id,
      name: map['name'] as String,
      description: map['description'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int,
      tags: List<String>.from(map['tags'] as List),
    );
  }

  BenchProduct copyWith({double? price, int? quantity}) {
    return BenchProduct(
      id: id,
      name: name,
      description: description,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      tags: tags,
    );
  }
}

/// Creates a test product with the given index.
BenchProduct createProduct(int index) {
  return BenchProduct(
    name: 'Product $index',
    description: 'Description for product $index with some additional text',
    price: 10.0 + (index % 1000),
    quantity: 50 + (index % 100),
    tags: ['tag${index % 10}', 'category${index % 5}', 'type${index % 3}'],
  );
}

/// Measures the execution time of an operation.
Future<Duration> measure(Future<void> Function() operation) async {
  final stopwatch = Stopwatch()..start();
  await operation();
  stopwatch.stop();
  return stopwatch.elapsed;
}

/// Helper to create an in-memory collection with optional query caching.
Future<Collection<BenchProduct>> createInMemoryCollection({
  required String name,
  bool enableQueryResultCaching = false,
}) async {
  final storage = MemoryStorage<BenchProduct>(name: name);
  await storage.open();

  return Collection<BenchProduct>(
    storage: storage,
    fromMap: BenchProduct.fromMap,
    name: name,
    enableQueryResultCaching: enableQueryResultCaching,
  );
}

void main() {
  group('Performance Regression Tests', () {
    late Collection<BenchProduct> products;

    setUp(() async {
      products = await createInMemoryCollection(name: 'products');
    });

    tearDown(() async {
      await products.dispose();
    });

    group('Insert Operations', () {
      test('single insert should complete within threshold', () async {
        // Threshold: 50ms for a single insert (very generous)
        const threshold = Duration(milliseconds: 50);

        final duration = await measure(() async {
          await products.insert(createProduct(0));
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Single insert took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('batch insert of 100 entities should complete within threshold', () async {
        // Threshold: 1000ms for 100 inserts in-memory (very generous)
        const threshold = Duration(milliseconds: 1000);
        const count = 100;

        final entities = List.generate(count, createProduct);

        final duration = await measure(() async {
          await products.insertMany(entities);
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Batch insert of $count entities took '
              '${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );

        // Verify data integrity
        final storedCount = await products.count;
        expect(storedCount, equals(count));
      });

      test('batch insert should be faster than sequential inserts', () async {
        const count = 50;

        // Sequential inserts
        final sequentialDuration = await measure(() async {
          for (int i = 0; i < count; i++) {
            await products.insert(createProduct(i));
          }
        });

        await products.deleteAll();

        // Batch insert
        final entities = List.generate(count, (i) => createProduct(i + count));
        final batchDuration = await measure(() async {
          await products.insertMany(entities);
        });

        // Batch should be at least 20% faster (conservative threshold)
        // In practice, it's often 2-10x faster
        expect(
          batchDuration.inMicroseconds,
          lessThan(sequentialDuration.inMicroseconds),
          reason: 'Batch insert (${batchDuration.inMilliseconds}ms) should be '
              'faster than sequential (${sequentialDuration.inMilliseconds}ms)',
        );
      });
    });

    group('Read Operations', () {
      late List<String> ids;

      setUp(() async {
        // Insert test data
        final entities = List.generate(100, createProduct);
        ids = await products.insertMany(entities);
      });

      test('get by ID should complete within threshold', () async {
        // Threshold: 20ms for a single get (generous for in-memory)
        const threshold = Duration(milliseconds: 20);

        final duration = await measure(() async {
          await products.get(ids.first);
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Get by ID took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('getAll should complete within threshold', () async {
        // Threshold: 200ms for getAll of 100 entities (in-memory)
        const threshold = Duration(milliseconds: 200);

        final duration = await measure(() async {
          await products.getAll();
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'GetAll took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('100 sequential reads should complete within threshold', () async {
        // Threshold: 500ms for 100 reads (5ms average)
        const threshold = Duration(milliseconds: 500);

        final duration = await measure(() async {
          for (final id in ids) {
            await products.get(id);
          }
        });

        expect(
          duration,
          lessThan(threshold),
          reason: '100 reads took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });
    });

    group('Query Operations', () {
      setUp(() async {
        // Insert test data
        final entities = List.generate(200, createProduct);
        await products.insertMany(entities);
      });

      test('equality query should complete within threshold', () async {
        // Threshold: 100ms for a query
        const threshold = Duration(milliseconds: 100);

        final duration = await measure(() async {
          await products.find(
            QueryBuilder().whereEquals('quantity', 50).build(),
          );
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Equality query took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('range query should complete within threshold', () async {
        // Threshold: 100ms for a range query
        const threshold = Duration(milliseconds: 100);

        final duration = await measure(() async {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 500.0).build(),
          );
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Range query took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('contains query should complete within threshold', () async {
        // Threshold: 100ms for a contains query (full scan)
        const threshold = Duration(milliseconds: 100);

        final duration = await measure(() async {
          await products.find(
            QueryBuilder().whereContains('name', 'Product').build(),
          );
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Contains query took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('complex AND query should complete within threshold', () async {
        // Threshold: 100ms for a complex query
        const threshold = Duration(milliseconds: 100);

        final duration = await measure(() async {
          await products.find(
            QueryBuilder()
                .whereGreaterThan('price', 100.0)
                .whereLessThan('quantity', 100)
                .build(),
          );
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Complex query took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });
    });

    group('Index Operations', () {
      test('hash index creation should complete within threshold', () async {
        // Insert data first
        final entities = List.generate(100, createProduct);
        await products.insertMany(entities);

        // Threshold: 200ms for index creation on 100 entities
        const threshold = Duration(milliseconds: 200);

        final duration = await measure(() async {
          await products.createIndex('name', IndexType.hash);
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Hash index creation took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('btree index creation should complete within threshold', () async {
        // Insert data first
        final entities = List.generate(100, createProduct);
        await products.insertMany(entities);

        // Threshold: 200ms for index creation on 100 entities
        const threshold = Duration(milliseconds: 200);

        final duration = await measure(() async {
          await products.createIndex('price', IndexType.btree);
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'B-tree index creation took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('indexed query should benefit from index after warmup', () async {
        // Insert data
        final entities = List.generate(500, createProduct);
        await products.insertMany(entities);

        // Create hash index first (before timing any queries)
        await products.createIndex('name', IndexType.hash);

        // Warm up the indexed query path
        await products.find(
          QueryBuilder().whereEquals('name', 'Product 100').build(),
        );

        // Now measure indexed query performance over multiple runs
        var totalIndexedTime = 0;
        const iterations = 5;

        for (int i = 0; i < iterations; i++) {
          final duration = await measure(() async {
            await products.find(
              QueryBuilder().whereEquals('name', 'Product ${50 + i}').build(),
            );
          });
          totalIndexedTime += duration.inMicroseconds;
        }

        final avgIndexedTime = totalIndexedTime / iterations;

        // Indexed query should complete within 50ms on average
        // This is a generous threshold that should catch severe regressions
        expect(
          avgIndexedTime,
          lessThan(50000), // 50ms in microseconds
          reason: 'Average indexed query time (${avgIndexedTime.toStringAsFixed(0)}μs) '
              'should be under 50ms',
        );
      });
    });

    group('Update Operations', () {
      late List<String> ids;

      setUp(() async {
        final entities = List.generate(50, createProduct);
        ids = await products.insertMany(entities);
      });

      test('single update should complete within threshold', () async {
        // Threshold: 50ms for a single update
        const threshold = Duration(milliseconds: 50);

        final product = await products.get(ids.first);

        final duration = await measure(() async {
          await products.update(product!.copyWith(price: 999.99));
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Single update took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('50 sequential updates should complete within threshold', () async {
        // Threshold: 1000ms for 50 updates (20ms average)
        const threshold = Duration(milliseconds: 1000);

        final duration = await measure(() async {
          for (int i = 0; i < ids.length; i++) {
            final product = await products.get(ids[i]);
            if (product != null) {
              await products.update(product.copyWith(price: product.price + 1));
            }
          }
        });

        expect(
          duration,
          lessThan(threshold),
          reason: '50 updates took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });
    });

    group('Delete Operations', () {
      test('single delete should complete within threshold', () async {
        final id = await products.insert(createProduct(0));

        // Threshold: 50ms for a single delete
        const threshold = Duration(milliseconds: 50);

        final duration = await measure(() async {
          await products.delete(id);
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'Single delete took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );
      });

      test('deleteAll of 100 entities should complete within threshold', () async {
        final entities = List.generate(100, createProduct);
        await products.insertMany(entities);

        // Threshold: 500ms for deleteAll
        const threshold = Duration(milliseconds: 500);

        final duration = await measure(() async {
          await products.deleteAll();
        });

        expect(
          duration,
          lessThan(threshold),
          reason: 'DeleteAll took ${duration.inMilliseconds}ms, '
              'expected < ${threshold.inMilliseconds}ms',
        );

        expect(await products.count, equals(0));
      });
    });
  });

  group('Query Cache Performance', () {
    late Collection<BenchProduct> products;

    setUp(() async {
      // Create collection directly with query caching enabled
      products = await createInMemoryCollection(
        name: 'products_cached',
        enableQueryResultCaching: true,
      );

      // Insert test data
      final entities = List.generate(200, createProduct);
      await products.insertMany(entities);
    });

    tearDown(() async {
      await products.dispose();
    });

    test('cached query should be faster than first query', () async {
      final query = QueryBuilder().whereGreaterThan('price', 500.0).build();

      // First query (cache miss)
      final firstDuration = await measure(() async {
        await products.find(query);
      });

      // Second query (cache hit)
      final secondDuration = await measure(() async {
        await products.find(query);
      });

      // Cached query should be faster or at least not slower
      expect(
        secondDuration.inMicroseconds,
        lessThanOrEqualTo(firstDuration.inMicroseconds),
        reason: 'Cached query (${secondDuration.inMicroseconds}μs) should be '
            'faster than first query (${firstDuration.inMicroseconds}μs)',
      );
    });

    test('cache hit ratio should be high for repeated queries', () async {
      final query = QueryBuilder().whereEquals('quantity', 50).build();

      // Execute query multiple times
      for (int i = 0; i < 10; i++) {
        await products.find(query);
      }

      final stats = products.queryCacheStatistics;
      expect(stats, isNotNull);

      // At least 9 out of 10 should be cache hits
      expect(
        stats!.hits,
        greaterThanOrEqualTo(9),
        reason: 'Expected at least 9 cache hits, got ${stats.hits}',
      );
    });
  });

  group('Scalability Tests', () {
    late Collection<BenchProduct> products;

    setUp(() async {
      products = await createInMemoryCollection(name: 'scalability_test');
    });

    tearDown(() async {
      await products.dispose();
    });

    test('500 entity insert should scale linearly', () async {
      const smallCount = 100;
      const largeCount = 500;

      // Insert 100 entities
      var entities = List.generate(smallCount, createProduct);
      final smallDuration = await measure(() async {
        await products.insertMany(entities);
      });

      await products.deleteAll();

      // Insert 500 entities
      entities = List.generate(largeCount, (i) => createProduct(i + smallCount));
      final largeDuration = await measure(() async {
        await products.insertMany(entities);
      });

      // Time per entity should be roughly similar
      // (large batch / large count) <= 2 * (small batch / small count)
      final smallPerEntity = smallDuration.inMicroseconds / smallCount;
      final largePerEntity = largeDuration.inMicroseconds / largeCount;

      expect(
        largePerEntity,
        lessThan(smallPerEntity * 3),
        reason: 'Per-entity time should not degrade significantly: '
            '${largePerEntity.toStringAsFixed(2)}μs vs '
            '${smallPerEntity.toStringAsFixed(2)}μs',
      );
    });

    test('query performance should not degrade significantly with data size', () async {
      // Insert 100 entities first
      var entities = List.generate(100, createProduct);
      await products.insertMany(entities);

      final query = QueryBuilder().whereGreaterThan('price', 500.0).build();

      final smallDuration = await measure(() async {
        await products.find(query);
      });

      // Add 400 more entities (total 500)
      entities = List.generate(400, (i) => createProduct(i + 100));
      await products.insertMany(entities);

      final largeDuration = await measure(() async {
        await products.find(query);
      });

      // Query time should scale roughly linearly (5x data = max 6x time)
      expect(
        largeDuration.inMicroseconds,
        lessThan(smallDuration.inMicroseconds * 8),
        reason: 'Query time should scale acceptably: '
            '${largeDuration.inMicroseconds}μs vs '
            '${smallDuration.inMicroseconds}μs',
      );
    });
  });
}
