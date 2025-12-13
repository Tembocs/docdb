# EntiDB

An embedded, entity-based document database for Dart and Flutter applications.

[![Dart](https://img.shields.io/badge/Dart-%5E3.10.1-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/Tembocs/entidb/actions/workflows/ci.yml/badge.svg)](https://github.com/Tembocs/entidb/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/Tembocs/entidb/graph/badge.svg)](https://codecov.io/gh/Tembocs/entidb)

## Overview

EntiDB is a local, entity-based document database written in Dart. You define entity classes that implement a simple interface, and EntiDB handles serialization, storage, and retrieval. It provides typed collections, indexing, transactions, and optional encryption. It works with both Dart CLI applications and Flutter apps.

## Features

- **Document Storage** - Store and retrieve typed entities with automatic serialization
- **Collections** - Organize documents into typed collections
- **Indexing** - BTree, Hash, and Full-Text indexes for query performance
- **Query Builder** - Build queries with equality, comparison, and logical operators
- **Transactions** - ACID transactions with configurable isolation levels
- **Encryption** - Optional AES-GCM encryption for data at rest
- **Compression** - Reduce storage size with configurable compression
- **Migrations** - Schema versioning with forward and backward migrations
- **Backups** - Full, differential, and incremental backup support
- **Write-Ahead Log** - Crash recovery via WAL

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  entidb: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Define an Entity

```dart
import 'package:entidb/entidb.dart';

class Product implements Entity {
  @override
  final String? id;
  final String name;
  final double price;
  final int quantity;

  Product({
    this.id,
    required this.name,
    required this.price,
    required this.quantity,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'quantity': quantity,
  };

  static Product fromMap(String id, Map<String, dynamic> map) => Product(
    id: id,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    quantity: map['quantity'] as int,
  );
}
```

### Open Database and Use Collections

```dart
import 'package:entidb/entidb.dart';

Future<void> main() async {
  // Open database with file storage
  final db = await EntiDB.open(
    path: './data',
    config: EntiDBConfig.production(),
  );

  // Get a typed collection
  final products = await db.collection<Product>(
    'products',
    fromMap: Product.fromMap,
  );

  // Insert
  final id = await products.insert(
    Product(name: 'Widget', price: 29.99, quantity: 100),
  );

  // Query
  final results = await products.find(
    QueryBuilder().whereGreaterThan('price', 20.0).build(),
  );

  // Update
  final product = await products.get(id);
  if (product != null) {
    await products.update(product.copyWith(quantity: 90));
  }

  // Delete
  await products.delete(id);

  // Close
  await db.close();
}
```

### In-Memory Database

For testing or temporary data:

```dart
final db = await EntiDB.open(
  path: null,  // null path = in-memory
  config: EntiDBConfig.inMemory(),
);
```

## Queries

EntiDB provides a `QueryBuilder` for constructing queries:

```dart
// Equality
QueryBuilder().whereEquals('status', 'active').build();

// Comparison
QueryBuilder().whereGreaterThan('price', 100.0).build();
QueryBuilder().whereLessThan('quantity', 10).build();
QueryBuilder().whereBetween('price', 50.0, 200.0).build();

// String/List contains
QueryBuilder().whereContains('tags', 'electronics').build();

// Logical operators
QueryBuilder()
    .whereEquals('category', 'phones')
    .whereGreaterThan('price', 500.0)
    .build();

// Or conditions
QueryBuilder()
    .whereEquals('status', 'active')
    .or(QueryBuilder().whereEquals('featured', true).build())
    .build();
```

## Indexes

Create indexes to speed up queries:

```dart
// Hash index for equality lookups
await products.createIndex('category', IndexType.hash);

// BTree index for range queries
await products.createIndex('price', IndexType.btree);

// Full-text index for text search
await products.createIndex('description', IndexType.fullText);
```

## Transactions

```dart
await db.transaction((txn) async {
  final products = await txn.collection<Product>('products', fromMap: Product.fromMap);
  
  await products.insert(Product(name: 'Item 1', price: 10.0, quantity: 5));
  await products.insert(Product(name: 'Item 2', price: 20.0, quantity: 10));
  
  // Both inserts succeed or both fail
});
```

Isolation levels:

```dart
await db.transaction(
  (txn) async { /* ... */ },
  isolationLevel: IsolationLevel.serializable,
);
```

## Encryption

Enable encryption for sensitive data:

```dart
final db = await EntiDB.open(
  path: './secure_data',
  config: EntiDBConfig(
    encryption: EncryptionConfig(
      enabled: true,
      key: yourSecretKey,  // 32 bytes for AES-256
    ),
  ),
);
```

## Backups

```dart
// Create backup
final backup = db.backup;
await backup.createBackup('./backups/backup_2024.db');

// Restore from backup
await backup.restore('./backups/backup_2024.db');

// Differential backup (only changes since last backup)
await backup.createDifferentialBackup('./backups/diff.db', since: lastBackupTime);
```

## Migrations

Handle schema changes:

```dart
final migration = Migration(
  version: 2,
  name: 'add_email_field',
  up: (db) async {
    // Migration logic
  },
  down: (db) async {
    // Rollback logic
  },
);

final runner = MigrationRunner(db);
await runner.register(migration);
await runner.migrateToLatest();
```

## Configuration

```dart
final config = EntiDBConfig(
  // Storage settings
  pageSize: 4096,
  cacheSize: 1000,
  
  // Compression
  compression: CompressionConfig(enabled: true),
  
  // Query cache
  queryCache: QueryCacheConfig(
    enabled: true,
    maxSize: 100,
    ttl: Duration(minutes: 5),
  ),
  
  // Logging
  logLevel: LogLevel.info,
);
```

## Examples

See the [example/](example/) directory for complete examples:

- `basic_crud.dart` - Create, Read, Update, Delete operations
- `querying.dart` - Query builder usage
- `collections.dart` - Working with collections
- `persistence.dart` - File-based storage
- `configuration.dart` - Configuration options
- `benchmark.dart` - Performance benchmarks

Run an example:

```bash
dart run example/basic_crud.dart
```

## Documentation

- [API Documentation](doc/api/index.html)
- [Architecture Overview](doc/architecture/architecture.md)
- [API Examples](doc/architecture/API_examples.md)

## Limitations

- Single-process access only (no multi-process locking)
- No built-in replication or clustering
- Full-text search is basic (no stemming, fuzzy matching, or relevance ranking)
- Query optimizer handles simple cases; complex queries may need manual optimization

## Testing

```bash
# Run all tests
dart test

# Run with coverage
dart test --coverage=coverage
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.
