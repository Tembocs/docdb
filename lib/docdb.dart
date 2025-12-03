/// DocDB - A robust, embedded document database for Dart
///
/// DocDB provides a feature-rich document database with support for:
///
/// - **Entity Storage**: Generic, type-safe storage for any Entity
/// - **Collections**: Type-safe collections with indexing and queries
/// - **Transactions**: ACID-compliant transactions with isolation levels
/// - **Indexing**: BTree and Hash indexes for fast queries
/// - **Encryption**: Optional AES-GCM encryption at rest
/// - **Migrations**: Bidirectional schema migrations with rollback support
/// - **Backup**: Point-in-time snapshots with integrity verification
/// - **Logging**: Structured logging with configurable levels
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/docdb.dart';
///
/// // Define your entity
/// class Product implements Entity {
///   @override
///   final String? id;
///   final String name;
///   final double price;
///
///   Product({this.id, required this.name, required this.price});
///
///   @override
///   Map<String, dynamic> toMap() => {'name': name, 'price': price};
///
///   static Product fromMap(String id, Map<String, dynamic> map) =>
///     Product(id: id, name: map['name'], price: map['price']);
/// }
///
/// // Open database
/// final db = await DocDB.open(
///   path: './myapp_data',
///   config: DocDBConfig.production(),
/// );
///
/// // Get a collection
/// final products = await db.collection<Product>(
///   'products',
///   fromMap: Product.fromMap,
/// );
///
/// // Insert and query
/// await products.insert(Product(name: 'Widget', price: 29.99));
/// final results = await products.find(
///   QueryBuilder().whereGreaterThan('price', 20.0).build(),
/// );
///
/// // Close when done
/// await db.close();
/// ```
///
/// See individual module documentation for detailed usage.
library;

// Main DocDB class - primary entry point
export 'src/docdb.dart';

// Core entity interface
export 'src/entity/entity.dart';

// Storage implementations
export 'src/storage/storage.dart';
export 'src/storage/memory_storage.dart';
export 'src/storage/paged_storage.dart';

// Collection module - type-safe entity collections with indexing
export 'src/collection/collection.dart';

// Backup module - point-in-time snapshots, integrity verification
export 'src/backup/backup.dart';

// Migration module - schema versioning and data transformation
export 'src/migration/migration.dart';

// Exception hierarchy
export 'src/exceptions/exceptions.dart';

// Logging utilities
export 'src/logger/logger.dart';

// Query builder
export 'src/query/query.dart';

// Transaction support
export 'src/transaction/transaction.dart';

// Index management
export 'src/index/index.dart';

// Encryption
export 'src/encryption/encryption.dart';

// Type registry for serialization
export 'src/type_registry/type_registry.dart';

// Authentication module - user management, login, tokens
export 'src/authentication/authentication.dart';

// Authorization module - roles, permissions, access control
export 'src/authorization/authorization.dart';
