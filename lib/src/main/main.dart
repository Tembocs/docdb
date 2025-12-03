/// DocDB Main Module
///
/// This barrel file exports the core DocDB classes for database operations.
/// It provides the primary entry point for using DocDB.
///
/// ## Exported Classes
///
/// - [DocDB] - The main database class for opening and managing databases
/// - [DocDBConfig] - Configuration options for database instances
/// - [StorageBackend] - Enum for selecting storage type (paged/memory)
/// - [DocDBStats] - Database statistics and metrics
/// - [CollectionStats] - Per-collection statistics
///
/// ## Usage
///
/// ```dart
/// import 'package:docdb/docdb.dart';
///
/// final db = await DocDB.open(
///   path: './myapp.db',
///   config: DocDBConfig.production(),
/// );
///
/// final stats = await db.getStats();
/// print('Total entities: ${stats.totalEntityCount}');
///
/// await db.close();
/// ```
library;

// Main database class
export 'docdb.dart' show DocDB;

// Configuration and storage backend enum
export 'docdb_config.dart' show DocDBConfig, StorageBackend;

// Statistics classes
export 'docdb_stats.dart' show DocDBStats, CollectionStats;

// Note: CollectionEntry is intentionally not exported as it's internal
