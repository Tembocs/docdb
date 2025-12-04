/// DocDB Performance Benchmark
///
/// Measures performance of core DocDB operations including:
/// - Insert operations (single and batch)
/// - Read operations (by ID and queries)
/// - Update operations
/// - Delete operations
/// - Index performance comparison
/// - Memory vs file-based storage
///
/// Run with: `dart run example/benchmark.dart`
import 'dart:io';

import 'package:docdb/docdb.dart';

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

  double get opsPerSecond =>
      operations / (duration.inMicroseconds / 1000000.0);

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
  print('╔════════════════════════════════════════════════════════════════════╗');
  print('║                    DocDB Performance Benchmark                     ║');
  print('╚════════════════════════════════════════════════════════════════════╝');
  print('');
  print('System: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('Dart:   ${Platform.version.split(' ').first}');
  print('');

  final results = <BenchmarkResult>[];

  // =========================================================================
  // In-Memory Benchmarks
  // =========================================================================
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  IN-MEMORY STORAGE BENCHMARKS');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  results.addAll(await _runStorageBenchmarks(
    config: DocDBConfig.inMemory(),
    prefix: 'Memory',
  ));

  // =========================================================================
  // File-Based Benchmarks
  // =========================================================================
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  FILE-BASED STORAGE BENCHMARKS');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  final tempDir = await Directory.systemTemp.createTemp('docdb_bench_');
  try {
    results.addAll(await _runStorageBenchmarks(
      config: DocDBConfig.production(),
      path: tempDir.path,
      prefix: 'File',
    ));
  } finally {
    await tempDir.delete(recursive: true);
  }

  // =========================================================================
  // Index Performance Comparison
  // =========================================================================
  print('');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('  INDEX PERFORMANCE COMPARISON');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('');

  results.addAll(await _runIndexBenchmarks());

  // =========================================================================
  // Summary
  // =========================================================================
  print('');
  print('╔════════════════════════════════════════════════════════════════════╗');
  print('║                         BENCHMARK SUMMARY                          ║');
  print('╚════════════════════════════════════════════════════════════════════╝');
  print('');
  print('${'Operation'.padRight(40)} ${'Total'.padLeft(6)}  ${'Per Op'.padLeft(8)}  ${'Throughput'.padLeft(10)}');
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
    results.add(await _benchmark(
      '$prefix: Insert $kMediumDataset (single)',
      kMediumDataset,
      () async {
        for (int i = 0; i < kMediumDataset; i++) {
          await products.insert(_createProduct(i));
        }
      },
    ));

    // Clear for next test
    await products.deleteAll();

    // Batch insert
    results.add(await _benchmark(
      '$prefix: Insert $kMediumDataset (batch)',
      kMediumDataset,
      () async {
        final batch = List.generate(kMediumDataset, _createProduct);
        await products.insertMany(batch);
      },
    ));

    // -------------------------------------------------------------------------
    // Read Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Read Operations:');

    // Get all IDs for read tests
    final allProducts = await products.getAll();
    final ids = allProducts.map((p) => p.id!).toList();

    // Read by ID
    results.add(await _benchmark(
      '$prefix: Read by ID ($kMediumDataset)',
      kMediumDataset,
      () async {
        for (final id in ids) {
          await products.get(id);
        }
      },
    ));

    // Get all
    results.add(await _benchmark(
      '$prefix: GetAll ($kMediumDataset entities)',
      1,
      () async {
        await products.getAll();
      },
    ));

    // Count
    results.add(await _benchmark(
      '$prefix: Count',
      100,
      () async {
        for (int i = 0; i < 100; i++) {
          await products.count;
        }
      },
    ));

    // -------------------------------------------------------------------------
    // Query Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Query Operations:');

    // Equals query
    results.add(await _benchmark(
      '$prefix: Query equals (100 queries)',
      100,
      () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 50).build(),
          );
        }
      },
    ));

    // Range query
    results.add(await _benchmark(
      '$prefix: Query range (100 queries)',
      100,
      () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 500.0).build(),
          );
        }
      },
    ));

    // Contains query
    results.add(await _benchmark(
      '$prefix: Query contains (100 queries)',
      100,
      () async {
        for (int i = 0; i < 100; i++) {
          await products.find(
            QueryBuilder().whereContains('name', 'Product').build(),
          );
        }
      },
    ));

    // -------------------------------------------------------------------------
    // Update Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Update Operations:');

    results.add(await _benchmark(
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
    ));

    // -------------------------------------------------------------------------
    // Delete Benchmarks
    // -------------------------------------------------------------------------
    print('');
    print('  Delete Operations:');

    results.add(await _benchmark(
      '$prefix: Delete ($kSmallDataset entities)',
      kSmallDataset,
      () async {
        for (int i = 0; i < kSmallDataset; i++) {
          await products.delete(ids[i]);
        }
      },
    ));

    // DeleteAll
    await products.insertMany(List.generate(kSmallDataset, _createProduct));
    results.add(await _benchmark(
      '$prefix: DeleteAll ($kSmallDataset entities)',
      1,
      () async {
        await products.deleteAll();
      },
    ));
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

    results.add(await _benchmark(
      'No Index: Equals query (50 queries)',
      50,
      () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      },
    ));

    results.add(await _benchmark(
      'No Index: Range query (50 queries)',
      50,
      () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 750.0).build(),
          );
        }
      },
    ));

    // -------------------------------------------------------------------------
    // Create Indexes
    // -------------------------------------------------------------------------
    print('');
    print('  Creating indexes...');

    results.add(await _benchmark(
      'Create Hash Index (quantity)',
      1,
      () async {
        await products.createIndex('quantity', IndexType.hash);
      },
      skipWarmup: true,
    ));

    results.add(await _benchmark(
      'Create BTree Index (price)',
      1,
      () async {
        await products.createIndex('price', IndexType.btree);
      },
      skipWarmup: true,
    ));

    // -------------------------------------------------------------------------
    // Query WITH Index
    // -------------------------------------------------------------------------
    print('');
    print('  With Index:');

    results.add(await _benchmark(
      'Hash Index: Equals query (50 queries)',
      50,
      () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereEquals('quantity', 25).build(),
          );
        }
      },
    ));

    results.add(await _benchmark(
      'BTree Index: Range query (50 queries)',
      50,
      () async {
        for (int i = 0; i < 50; i++) {
          await products.find(
            QueryBuilder().whereGreaterThan('price', 750.0).build(),
          );
        }
      },
    ));
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
