/// DocDB Performance Benchmark
///
/// Measures performance of core DocDB operations including:
/// - Insert operations (single and batch)
/// - Read operations (by ID and queries)
/// - Update operations
/// - Delete operations
/// - Index performance comparison (Hash, B-tree, Full-text)
/// - Query caching (hit vs miss)
/// - Data compression overhead
/// - Query optimizer plan generation
/// - Index persistence (save/load)
/// - Memory vs file-based storage
///
/// Run with: `dart run example/benchmark.dart`
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:docdb/docdb.dart';
// ignore: implementation_imports
import 'package:docdb/src/storage/serialization.dart';

import 'models/models.dart';

/// Number of entities for benchmarks.
const int kSmallDataset = 100;
const int kMediumDataset = 1000;
const int kLargeDataset = 5000;

/// Benchmark results container.
class BenchmarkResult {
  final String name;
  final int operations;
  final Duration duration;

  BenchmarkResult(this.name, this.operations, this.duration);

  double get opsPerSecond => operations / (duration.inMicroseconds / 1000000.0);

  double get msPerOp => duration.inMicroseconds / 1000.0 / operations;

  @override
  String toString() {
    final ops = opsPerSecond.toStringAsFixed(0).padLeft(10);
    final ms = msPerOp.toStringAsFixed(3).padLeft(8);
    final total = duration.inMilliseconds.toString().padLeft(6);
    return '${name.padRight(40)} ${total}ms  ${ms}ms/op  $ops ops/sec';
  }
}

Future<void> main() async {
  print(
    '╔════════════════════════════════════════════════════════════════════╗',
  );
  print(
    '║                    DocDB Performance Benchmark                     ║',
  );
  print(
    '╚════════════════════════════════════════════════════════════════════╝',
  );
  print('');
  print(
    'System: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
  print('Dart:   ${Platform.version.split(' ').first}');
  print('');

  final results = <BenchmarkResult>[];

  // =========================================================================
  // In-Memory Benchmarks
  // =========================================================================
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  IN-MEMORY STORAGE BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(
    await _runStorageBenchmarks(
      config: DocDBConfig.inMemory(),
      prefix: 'Memory',
    ),
  );

  // =========================================================================
  // File-Based Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  FILE-BASED STORAGE BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  final tempDir = await Directory.systemTemp.createTemp('docdb_bench_');
  try {
    results.addAll(
      await _runStorageBenchmarks(
        config: DocDBConfig.production(),
        path: tempDir.path,
        prefix: 'File',
      ),
    );
  } finally {
    await tempDir.delete(recursive: true);
  }

  // =========================================================================
  // Index Performance Comparison
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  INDEX PERFORMANCE COMPARISON');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runIndexBenchmarks());

  // =========================================================================
  // Full-Text Search Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  FULL-TEXT SEARCH BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runFullTextBenchmarks());

  // =========================================================================
  // Query Cache Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  QUERY CACHE BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runQueryCacheBenchmarks());

  // =========================================================================
  // Compression Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  DATA COMPRESSION BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runCompressionBenchmarks());

  // =========================================================================
  // Query Optimizer Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  QUERY OPTIMIZER BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runQueryOptimizerBenchmarks());

  // =========================================================================
  // Index Persistence Benchmarks
  // =========================================================================
  print('');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('  INDEX PERSISTENCE BENCHMARKS');
  print(
    '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
  );
  print('');

  results.addAll(await _runIndexPersistenceBenchmarks());

  // =========================================================================
  // Summary
  // =========================================================================
  print('');
  print(
    '╔════════════════════════════════════════════════════════════════════╗',
  );
  print(
    '║                         BENCHMARK SUMMARY                          ║',
  );
  print(
    '╚════════════════════════════════════════════════════════════════════╝',
  );
  print('');
  print(
    '${'Operation'.padRight(40)} ${'Total'.padLeft(6)}  ${'Per Op'.padLeft(8)}  ${'Throughput'.padLeft(10)}',
  );
  print('─' * 72);

  for (final result in results) {
    print(result);
  }

  print('');
  print('Benchmark complete.');
}

/// Runs storage benchmarks for a given configuration.
Future<List<BenchmarkResult>> _runStorageBenchmarks({
  required DocDBConfig config,
  String? path,
  required String prefix,
}) async {
  final results = <BenchmarkResult>[];

  final db = await DocDB.open(path: path, config: config);

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // -------------------------------------------------------------------------
    // Insert Benchmarks
    // -------------------------------------------------------------------------
    print('  Insert Operations:');

    // Single inserts
    results.add(
      await _benchmark(
        '$prefix: Insert $kMediumDataset (single)',
        kMediumDataset,
        () async {
          for (int i = 0; i < kMediumDataset; i++) {
            await products.insert(_createProduct(i));
          }
        },
      ),
    );

    // Clear for next test
    await products.deleteAll();

    // Batch insert
    results.add(
      await _benchmark(
        '$prefix: Insert $kMediumDataset (batch)',
        kMediumDataset,
        () async {
          final batch = List.generate(kMediumDataset, _createProduct);
          await products.insertMany(batch);
        },
      ),
    );

    // -------------------------------------------------------------------------
    // Read Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Read Operations:');

    // Get all IDs for read tests
    final allProducts = await products.getAll();
    final ids = allProducts.map((p) => p.id!).toList();

    // Read by ID
    results.add(
      await _benchmark(
        '$prefix: Read by ID ($kMediumDataset)',
        kMediumDataset,
        () async {
          for (final id in ids) {
            await products.get(id);
          }
        },
      ),
    );

    // Get all
    results.add(
      await _benchmark(
        '$prefix: GetAll ($kMediumDataset entities)',
        1,
        () async {
          await products.getAll();
        },
      ),
    );

    // Count
    results.add(
      await _benchmark('$prefix: Count', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.count;
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Query Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Query Operations:');

    // Equals query
    results.add(
      await _benchmark('$prefix: Query equals (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 50).build(),
          );
        }
      }),
    );

    // Range query
    results.add(
      await _benchmark('$prefix: Query range (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 500.0).build(),
          );
        }
      }),
    );

    // Contains query
    results.add(
      await _benchmark('$prefix: Query contains (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereContains('name', 'Product').build(),
          );
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Update Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Update Operations:');

    results.add(
      await _benchmark(
        '$prefix: Update ($kSmallDataset entities)',
        kSmallDataset,
        () async {
          final fresh = await products.getAll();
          for (int i = 0; i < kSmallDataset; i++) {
            final product = fresh[i];
            final updated = product.copyWith(price: product.price + 1.0);
            await products.update(updated);
          }
        },
        skipWarmup: true,
      ),
    );

    // -------------------------------------------------------------------------
    // Delete Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Delete Operations:');

    results.add(
      await _benchmark(
        '$prefix: Delete ($kSmallDataset entities)',
        kSmallDataset,
        () async {
          for (int i = 0; i < kSmallDataset; i++) {
            await products.delete(ids[i]);
          }
        },
      ),
    );

    // DeleteAll
    await products.insertMany(List.generate(kSmallDataset, _createProduct));
    results.add(
      await _benchmark(
        '$prefix: DeleteAll ($kSmallDataset entities)',
        1,
        () async {
          await products.deleteAll();
        },
      ),
    );
  } finally {
    await db.close();
  }

  return results;
}

/// Runs index performance comparison benchmarks.
Future<List<BenchmarkResult>> _runIndexBenchmarks() async {
  final results = <BenchmarkResult>[];
  final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert test data
    print('  Preparing $kLargeDataset entities for index tests...');
    await products.insertMany(List.generate(kLargeDataset, _createProduct));
    print('');

    // -------------------------------------------------------------------------
    // Query WITHOUT Index
    // -------------------------------------------------------------------------
    print('  Without Index:');

    results.add(
      await _benchmark('No Index: Equals query (50 queries)', 50, () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      }),
    );

    results.add(
      await _benchmark('No Index: Range query (50 queries)', 50, () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 750.0).build(),
          );
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Create Indexes
    // -------------------------------------------------------------------------
    print('');
    print('  Creating indexes...');

    results.add(
      await _benchmark('Create Hash Index (quantity)', 1, () async {
        await products.createIndex('quantity', IndexType.hash);
      }, skipWarmup: true),
    );

    results.add(
      await _benchmark('Create BTree Index (price)', 1, () async {
        await products.createIndex('price', IndexType.btree);
      }, skipWarmup: true),
    );

    // -------------------------------------------------------------------------
    // Query WITH Index
    // -------------------------------------------------------------------------
    print('');
    print('  With Index:');

    results.add(
      await _benchmark('Hash Index: Equals query (50 queries)', 50, () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      }),
    );

    results.add(
      await _benchmark('BTree Index: Range query (50 queries)', 50, () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 750.0).build(),
          );
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Index-Only Count Benchmarks (No Deserialization)
    // -------------------------------------------------------------------------
    print('');
    print('  Index-Only Count (no deserialization):');

    results.add(
      await _benchmark('Index Count: Equals (100 counts)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.countWhere(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      }),
    );

    results.add(
      await _benchmark('Index Count: Range (100 counts)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.countWhere(
            QueryBuilder().whereGreaterThan('price', 750.0).build(),
          );
        }
      }),
    );

    results.add(
      await _benchmark('Index Count: Between (100 counts)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.countWhere(
            QueryBuilder().whereBetween('price', 200.0, 800.0).build(),
          );
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Index-Only Exists Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Index-Only Exists (no deserialization):');

    results.add(
      await _benchmark('Index Exists: Equals (100 checks)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.existsWhere(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      }),
    );

    results.add(
      await _benchmark('Index Exists: Range (100 checks)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.existsWhere(
            QueryBuilder().whereGreaterThan('price', 999.0).build(),
          );
        }
      }),
    );
  } finally {
    await db.close();
  }

  return results;
}

/// Runs a benchmark and returns the result.
Future<BenchmarkResult> _benchmark(
  String name,
  int operations,
  Future<void> Function() fn, {
  bool skipWarmup = false,
}) async {
  // Warm-up run (not measured)
  if (!skipWarmup) {
    try {
      await fn();
    } catch (_) {
      // Ignore warm-up errors
    }
  }

  // Actual measurement
  final stopwatch = Stopwatch()..start();
  await fn();
  stopwatch.stop();

  final result = BenchmarkResult(name, operations, stopwatch.elapsed);
  print('    ${result.toString()}');

  return result;
}

/// Creates a product for benchmarking.
Product _createProduct(int index) {
  return Product(
    name: 'Product $index',
    description: 'Description for product $index with some additional text',
    price: (index % 1000) + 0.99,
    quantity: index % 100,
    tags: ['tag${index % 10}', 'category${index % 5}'],
  );
}

/// Creates a product with rich text content for full-text search benchmarks.
Product _createProductWithContent(int index) {
  // Generate varied text content for full-text indexing
  final adjectives = [
    'premium',
    'quality',
    'affordable',
    'luxury',
    'durable',
    'lightweight',
    'portable',
    'professional',
    'innovative',
    'reliable',
  ];
  final categories = [
    'electronics',
    'clothing',
    'furniture',
    'sports',
    'kitchen',
    'garden',
    'automotive',
    'office',
    'toys',
    'health',
  ];

  final adj1 = adjectives[index % adjectives.length];
  final adj2 = adjectives[(index + 3) % adjectives.length];
  final cat = categories[index % categories.length];

  return Product(
    name: 'Product $index - $adj1 $cat item',
    description:
        'This $adj1 and $adj2 product is perfect for $cat enthusiasts. '
        'Features include high performance, excellent build quality, and great value. '
        'Our customers love this item for its durability and style. '
        'Item number $index in our catalog of premium $cat products.',
    price: (index % 1000) + 0.99,
    quantity: index % 100,
    tags: ['tag${index % 10}', cat, adj1],
  );
}

/// Runs full-text search benchmarks.
Future<List<BenchmarkResult>> _runFullTextBenchmarks() async {
  final results = <BenchmarkResult>[];
  final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert test data with rich text content
    print('  Preparing $kMediumDataset entities for full-text tests...');
    await products.insertMany(
      List.generate(kMediumDataset, _createProductWithContent),
    );
    print('');

    // -------------------------------------------------------------------------
    // Full-Text Index Creation
    // -------------------------------------------------------------------------
    print('  Full-Text Index Creation:');

    results.add(
      await _benchmark('Create Full-Text Index (description)', 1, () async {
        await products.createIndex('description', IndexType.fulltext);
      }, skipWarmup: true),
    );

    results.add(
      await _benchmark('Create Full-Text Index (name)', 1, () async {
        await products.createIndex('name', IndexType.fulltext);
      }, skipWarmup: true),
    );

    // -------------------------------------------------------------------------
    // Full-Text Search Operations
    // -------------------------------------------------------------------------
    print('');
    print('  Full-Text Search Operations:');

    // Single term search
    results.add(
      await _benchmark('Full-Text: Single term (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereFullText('description', 'premium').build(),
          );
        }
      }),
    );

    // Multi-term search (AND)
    results.add(
      await _benchmark(
        'Full-Text: Multi-term AND (100 queries)',
        100,
        () async {
          for (int i = 0; i < 100; i++) {
            await products.find(
              QueryBuilder()
                  .whereFullText('description', 'premium quality')
                  .build(),
            );
          }
        },
      ),
    );

    // Multi-term search (OR)
    results.add(
      await _benchmark('Full-Text: Multi-term OR (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereFullTextAny('description', [
              'premium',
              'luxury',
            ]).build(),
          );
        }
      }),
    );

    // Phrase search
    results.add(
      await _benchmark('Full-Text: Phrase search (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder()
                .whereFullTextPhrase('description', 'high performance')
                .build(),
          );
        }
      }),
    );

    // Prefix search
    results.add(
      await _benchmark('Full-Text: Prefix search (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereFullTextPrefix('description', 'prem').build(),
          );
        }
      }),
    );
  } finally {
    await db.close();
  }

  return results;
}

/// Runs query cache performance benchmarks.
Future<List<BenchmarkResult>> _runQueryCacheBenchmarks() async {
  final results = <BenchmarkResult>[];
  final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert test data
    print('  Preparing $kMediumDataset entities for cache tests...');
    await products.insertMany(List.generate(kMediumDataset, _createProduct));

    // Create indexes for consistent query behavior
    await products.createIndex('quantity', IndexType.hash);
    await products.createIndex('price', IndexType.btree);
    print('');

    // -------------------------------------------------------------------------
    // Without Cache (Baseline)
    // -------------------------------------------------------------------------
    print('  Without Query Cache (baseline):');

    results.add(
      await _benchmark(
        'No Cache: Repeated equals (100 queries)',
        100,
        () async {
          for (int i = 0; i < 100; i++) {
            await products.find(
              QueryBuilder().whereEquals('quantity', 50).build(),
            );
          }
        },
      ),
    );

    results.add(
      await _benchmark('No Cache: Repeated range (100 queries)', 100, () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereBetween('price', 200.0, 500.0).build(),
          );
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Enable Cache
    // -------------------------------------------------------------------------
    print('');
    print('  With Query Cache:');

    products.enableQueryCache(
      config: QueryCacheConfig(
        maxSize: 100,
        defaultTtl: Duration(minutes: 5),
        enableSelectiveInvalidation: true,
      ),
    );

    // Warm up the cache with one query each
    await products.find(QueryBuilder().whereEquals('quantity', 50).build());
    await products.find(
      QueryBuilder().whereBetween('price', 200.0, 500.0).build(),
    );

    // Cache hits
    results.add(
      await _benchmark(
        'Cache Hit: Repeated equals (100 queries)',
        100,
        () async {
          for (int i = 0; i < 100; i++) {
            await products.find(
              QueryBuilder().whereEquals('quantity', 50).build(),
            );
          }
        },
      ),
    );

    results.add(
      await _benchmark(
        'Cache Hit: Repeated range (100 queries)',
        100,
        () async {
          for (int i = 0; i < 100; i++) {
            await products.find(
              QueryBuilder().whereBetween('price', 200.0, 500.0).build(),
            );
          }
        },
      ),
    );

    // Cache misses (varying queries)
    results.add(
      await _benchmark(
        'Cache Miss: Varying equals (100 queries)',
        100,
        () async {
          for (int i = 0; i < 100; i++) {
            await products.find(
              QueryBuilder().whereEquals('quantity', i % 100).build(),
            );
          }
        },
      ),
    );

    // Print cache statistics
    final stats = products.queryCacheStatistics;
    if (stats != null) {
      print('');
      print('  Cache Statistics:');
      print('    Hits: ${stats.hits}, Misses: ${stats.misses}');
      print('    Hit Ratio: ${(stats.hitRatio * 100).toStringAsFixed(1)}%');
      print('    Evictions: ${stats.evictions}');
    }
  } finally {
    await db.close();
  }

  return results;
}

/// Runs data compression benchmarks.
///
/// Note: This benchmarks the BinarySerializer compression directly,
/// as compression is configured at the serializer level.
Future<List<BenchmarkResult>> _runCompressionBenchmarks() async {
  final results = <BenchmarkResult>[];

  // Create test data with content that compresses well
  final testData = <Map<String, dynamic>>[];
  for (int i = 0; i < kMediumDataset; i++) {
    testData.add({
      'id': 'product-$i',
      'name': 'Product $i - premium quality item',
      'description':
          'This premium and reliable product is perfect for enthusiasts. '
              'Features include high performance, excellent build quality. ' *
          3,
      'price': (i % 1000) + 0.99,
      'quantity': i % 100,
      'tags': ['tag${i % 10}', 'category${i % 5}', 'featured'],
    });
  }

  // -------------------------------------------------------------------------
  // Uncompressed Serialization
  // -------------------------------------------------------------------------
  print('  Without Compression (BinarySerializer):');

  final uncompressedSerializer = BinarySerializer();

  results.add(
    await _benchmark(
      'Uncompressed: Serialize $kMediumDataset',
      kMediumDataset,
      () async {
        for (final data in testData) {
          await uncompressedSerializer.serialize(data);
        }
      },
    ),
  );

  // Serialize once for size comparison
  final uncompressedBytes = <Uint8List>[];
  for (final data in testData) {
    uncompressedBytes.add(await uncompressedSerializer.serialize(data));
  }
  final uncompressedSize = uncompressedBytes.fold<int>(
    0,
    (sum, bytes) => sum + bytes.length,
  );

  results.add(
    await _benchmark(
      'Uncompressed: Deserialize $kMediumDataset',
      kMediumDataset,
      () async {
        for (final bytes in uncompressedBytes) {
          await uncompressedSerializer.deserialize(bytes);
        }
      },
    ),
  );

  // -------------------------------------------------------------------------
  // Compressed Serialization
  // -------------------------------------------------------------------------
  print('');
  print('  With Compression (BinarySerializer):');

  final compressedSerializer = BinarySerializer(
    config: SerializationConfig.compressed(level: 6),
  );

  results.add(
    await _benchmark(
      'Compressed: Serialize $kMediumDataset',
      kMediumDataset,
      () async {
        for (final data in testData) {
          await compressedSerializer.serialize(data);
        }
      },
    ),
  );

  // Serialize once for size comparison
  final compressedBytes = <Uint8List>[];
  for (final data in testData) {
    compressedBytes.add(await compressedSerializer.serialize(data));
  }
  final compressedSize = compressedBytes.fold<int>(
    0,
    (sum, bytes) => sum + bytes.length,
  );

  results.add(
    await _benchmark(
      'Compressed: Deserialize $kMediumDataset',
      kMediumDataset,
      () async {
        for (final bytes in compressedBytes) {
          await compressedSerializer.deserialize(bytes);
        }
      },
    ),
  );

  // Print size comparison
  print('');
  print('  Serialization Size Comparison ($kMediumDataset entities):');
  print('    Uncompressed: ${(uncompressedSize / 1024).toStringAsFixed(1)} KB');
  print('    Compressed: ${(compressedSize / 1024).toStringAsFixed(1)} KB');
  if (uncompressedSize > 0) {
    final ratio = (1 - compressedSize / uncompressedSize) * 100;
    print('    Space Savings: ${ratio.toStringAsFixed(1)}%');
  }

  return results;
}

/// Runs query optimizer benchmarks.
Future<List<BenchmarkResult>> _runQueryOptimizerBenchmarks() async {
  final results = <BenchmarkResult>[];
  final db = await DocDB.open(path: null, config: DocDBConfig.inMemory());

  try {
    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert test data
    print('  Preparing $kLargeDataset entities for optimizer tests...');
    await products.insertMany(List.generate(kLargeDataset, _createProduct));

    // Create multiple indexes for optimizer choices
    await products.createIndex('quantity', IndexType.hash);
    await products.createIndex('price', IndexType.btree);
    await products.createIndex('name', IndexType.hash);
    print('');

    // -------------------------------------------------------------------------
    // Query Plan Generation
    // -------------------------------------------------------------------------
    print('  Query Plan Generation:');

    // Simple query plan
    results.add(
      await _benchmark('Plan Generation: Simple equals (1000)', 1000, () async {
        for (int i = 0; i < 1000; i++) {
          await products.explain(
            QueryBuilder().whereEquals('quantity', 50).build(),
          );
        }
      }),
    );

    // Range query plan
    results.add(
      await _benchmark('Plan Generation: Range query (1000)', 1000, () async {
        for (int i = 0; i < 1000; i++) {
          await products.explain(
            QueryBuilder().whereGreaterThan('price', 500.0).build(),
          );
        }
      }),
    );

    // Compound query plan (using AndQuery for compound queries)
    final compoundQuery = AndQuery([
      EqualsQuery('quantity', 50),
      GreaterThanQuery('price', 500.0),
    ]);
    results.add(
      await _benchmark('Plan Generation: Compound AND (1000)', 1000, () async {
        for (int i = 0; i < 1000; i++) {
          await products.explain(compoundQuery);
        }
      }),
    );

    // -------------------------------------------------------------------------
    // Optimized vs Unoptimized Execution
    // -------------------------------------------------------------------------
    print('');
    print('  Optimized Query Execution:');

    // Show example query plan
    final examplePlan = await products.explain(compoundQuery);
    print('    Example Plan Strategy: ${examplePlan.strategy.name}');
    print(
      '    Estimated Cost: ${examplePlan.estimatedCost.toStringAsFixed(2)}',
    );

    // Optimized compound query execution
    final execQuery = AndQuery([
      EqualsQuery('quantity', 25),
      GreaterThanQuery('price', 500.0),
    ]);
    results.add(
      await _benchmark('Optimized: Compound query (50 queries)', 50, () async {
        for (int i = 0; i < 50; i++) {
          await products.find(execQuery);
        }
      }),
    );
  } finally {
    await db.close();
  }

  return results;
}

/// Runs index persistence benchmarks.
Future<List<BenchmarkResult>> _runIndexPersistenceBenchmarks() async {
  final results = <BenchmarkResult>[];

  final tempDir = await Directory.systemTemp.createTemp('docdb_idx_persist_');
  try {
    final db = await DocDB.open(
      path: '${tempDir.path}/db',
      config: DocDBConfig.production(),
    );

    final products = await db.collection<Product>(
      'products',
      fromMap: Product.fromMap,
    );

    // Insert test data
    print('  Preparing $kLargeDataset entities for persistence tests...');
    await products.insertMany(List.generate(kLargeDataset, _createProduct));
    print('');

    // -------------------------------------------------------------------------
    // Index Creation (for persistence)
    // -------------------------------------------------------------------------
    print('  Index Creation (to persist):');

    results.add(
      await _benchmark(
        'Create Hash Index ($kLargeDataset entries)',
        1,
        () async {
          await products.createIndex('quantity', IndexType.hash);
        },
        skipWarmup: true,
      ),
    );

    results.add(
      await _benchmark(
        'Create BTree Index ($kLargeDataset entries)',
        1,
        () async {
          await products.createIndex('price', IndexType.btree);
        },
        skipWarmup: true,
      ),
    );

    // Save indexes to disk via close
    await db.close();

    // -------------------------------------------------------------------------
    // Index Loading on Startup
    // -------------------------------------------------------------------------
    print('');
    print('  Index Loading (simulated via re-open):');

    // Re-open database to trigger index load
    results.add(
      await _benchmark('Re-open DB with persisted indexes', 1, () async {
        final db2 = await DocDB.open(
          path: '${tempDir.path}/db',
          config: DocDBConfig.production(),
        );
        await db2.collection<Product>('products', fromMap: Product.fromMap);
        await db2.close();
      }, skipWarmup: true),
    );

    // -------------------------------------------------------------------------
    // Cold Start Comparison
    // -------------------------------------------------------------------------
    print('');
    print('  Cold Start Comparison:');

    // Fresh database without existing indexes
    results.add(
      await _benchmark('Cold Start: Fresh DB + index creation', 1, () async {
        final freshDir = await Directory.systemTemp.createTemp('docdb_cold_');
        try {
          final freshDb = await DocDB.open(
            path: freshDir.path,
            config: DocDBConfig.production(),
          );
          final coll = await freshDb.collection<Product>(
            'products',
            fromMap: Product.fromMap,
          );
          await coll.insertMany(List.generate(kMediumDataset, _createProduct));
          await coll.createIndex('quantity', IndexType.hash);
          await coll.createIndex('price', IndexType.btree);
          await freshDb.close();
        } finally {
          await freshDir.delete(recursive: true);
        }
      }, skipWarmup: true),
    );
  } finally {
    await tempDir.delete(recursive: true);
  }

  return results;
}
