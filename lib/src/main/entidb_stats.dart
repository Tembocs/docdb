/// EntiDB Statistics
///
/// Provides statistics and metrics for EntiDB database instances
/// and their collections.
library;

import 'package:meta/meta.dart';

import 'entidb_config.dart';

/// Database statistics.
///
/// Provides an overview of the database state including collection counts,
/// entity totals, and configuration status.
///
/// ## Usage
///
/// ```dart
/// final stats = await db.getStats();
/// print('Total entities: ${stats.totalEntityCount}');
/// print('Collections: ${stats.collectionCount}');
/// ```
@immutable
class EntiDBStats {
  /// Database path (null for in-memory).
  final String? path;

  /// Whether the database is open.
  final bool isOpen;

  /// Number of registered collections.
  final int collectionCount;

  /// Statistics for each collection.
  final Map<String, CollectionStats> collections;

  /// Whether encryption is enabled.
  final bool encryptionEnabled;

  /// The storage backend type.
  final StorageBackend storageBackend;

  /// Creates database statistics.
  const EntiDBStats({
    required this.path,
    required this.isOpen,
    required this.collectionCount,
    required this.collections,
    required this.encryptionEnabled,
    required this.storageBackend,
  });

  /// Total entity count across all collections.
  int get totalEntityCount =>
      collections.values.fold(0, (sum, c) => sum + c.entityCount);

  /// Total index count across all collections.
  int get totalIndexCount =>
      collections.values.fold(0, (sum, c) => sum + c.indexCount);

  @override
  String toString() {
    return 'EntiDBStats('
        'path: ${path ?? "in-memory"}, '
        'collections: $collectionCount, '
        'entities: $totalEntityCount, '
        'indexes: $totalIndexCount, '
        'encrypted: $encryptionEnabled)';
  }
}

/// Statistics for a single collection.
///
/// Provides metrics about a specific collection including entity count
/// and index information.
@immutable
class CollectionStats {
  /// Collection name.
  final String name;

  /// Number of entities.
  final int entityCount;

  /// Number of indexes.
  final int indexCount;

  /// Creates collection statistics.
  const CollectionStats({
    required this.name,
    required this.entityCount,
    required this.indexCount,
  });

  @override
  String toString() {
    return 'CollectionStats($name: $entityCount entities, $indexCount indexes)';
  }
}
