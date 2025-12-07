/// EntiDB Main Module
///
/// This barrel file exports the core EntiDB classes for database operations.
/// It provides the primary entry point for using EntiDB.
///
/// ## Exported Classes
///
/// - [EntiDB] - The main database class for opening and managing databases
/// - [EntiDBConfig] - Configuration options for database instances
/// - [StorageBackend] - Enum for selecting storage type (paged/memory)
/// - [EntiDBStats] - Database statistics and metrics
/// - [CollectionStats] - Per-collection statistics
///
/// ## Usage
///
/// ```dart
/// import 'package:entidb/entidb.dart';
///
/// final db = await EntiDB.open(
///   path: './myapp.db',
///   config: EntiDBConfig.production(),
/// );
///
/// final stats = await db.getStats();
/// print('Total entities: ${stats.totalEntityCount}');
///
/// await db.close();
/// ```
library;

// Main database class
export 'entidb.dart' show EntiDB;

// Configuration and storage backend enum
export 'entidb_config.dart' show EntiDBConfig, StorageBackend;

// Statistics classes
export 'entidb_stats.dart' show EntiDBStats, CollectionStats;

// Note: CollectionEntry is intentionally not exported as it's internal
