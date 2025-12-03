/// DocDB - A robust, embedded document database for Dart
///
/// DocDB provides a feature-rich document database with support for:
///
/// - **Entity Storage**: Generic, type-safe storage for any Entity
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
/// // Create storage and start using it
/// final storage = MemoryStorage<Product>();
/// await storage.set(product.id, product.toMap());
/// ```
///
/// See individual module documentation for detailed usage.
library;

// Core entity interface
export 'src/entity/entity.dart';

// Storage implementations
export 'src/storage/storage.dart';

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
