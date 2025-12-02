// lib/src/index/index_manager.dart

import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/logger/logger.dart';
import 'package:docdb/src/utils/constants.dart';

import 'btree.dart';
import 'hash.dart';
import 'i_index.dart';

/// Manages multiple indexes for a collection.
///
/// Provides a unified interface for creating, removing, and querying
/// indexes on entity fields. Handles automatic index updates when
/// entities are inserted, updated, or removed.
///
/// ## Usage
///
/// ```dart
/// final manager = IndexManager();
///
/// // Create indexes
/// manager.createIndex('email', IndexType.hash);
/// manager.createIndex('createdAt', IndexType.btree);
///
/// // Index an entity
/// final entity = User(id: 'user-1', email: 'alice@example.com');
/// manager.insert(entity.id!, entity.toMap());
///
/// // Query by indexed field
/// final results = manager.search('email', 'alice@example.com');
/// // results: ['user-1']
///
/// // Range query (btree only)
/// final recent = manager.rangeSearch('createdAt', startDate, endDate);
/// ```
///
/// ## Thread Safety
///
/// This class is not thread-safe. If concurrent access is required,
/// external synchronization must be provided.
class IndexManager {
  /// Internal map of field name to index.
  final Map<String, IIndex> _indices = {};

  /// Logger instance for this manager.
  final DocDBLogger _logger = DocDBLogger(LoggerNameConstants.index);

  /// Creates a new [IndexManager] instance.
  IndexManager();

  /// Creates an index on the specified [field] using the given [indexType].
  ///
  /// - [field]: The entity field name to index
  /// - [indexType]: The type of index to create
  ///
  /// Throws [IndexAlreadyExistsException] if an index on [field] already exists.
  ///
  /// ## Example
  ///
  /// ```dart
  /// manager.createIndex('email', IndexType.hash);
  /// manager.createIndex('age', IndexType.btree);
  /// ```
  void createIndex(String field, IndexType indexType) {
    if (_indices.containsKey(field)) {
      throw IndexAlreadyExistsException(
        'Index on field "$field" already exists.',
      );
    }

    final IIndex index = switch (indexType) {
      IndexType.btree => BTreeIndex(field),
      IndexType.hash => HashIndex(field),
    };

    _indices[field] = index;
    _logger.info('Created ${indexType.name} index on field "$field".');
  }

  /// Removes the index on the specified [field].
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  void removeIndex(String field) {
    final index = _indices.remove(field);
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }
    index.clear();
    _logger.info('Removed index on field "$field".');
  }

  /// Inserts an entity into all relevant indexes.
  ///
  /// - [entityId]: The unique identifier of the entity
  /// - [data]: The entity's data map from [Entity.toMap()]
  ///
  /// This method should be called whenever an entity is inserted
  /// or updated in the collection.
  void insert(String entityId, Map<String, dynamic> data) {
    for (final index in _indices.values) {
      index.insert(entityId, data);
    }
  }

  /// Removes an entity from all relevant indexes.
  ///
  /// - [entityId]: The unique identifier of the entity
  /// - [data]: The entity's data map from [Entity.toMap()]
  ///
  /// This method should be called whenever an entity is removed
  /// from the collection.
  void remove(String entityId, Map<String, dynamic> data) {
    for (final index in _indices.values) {
      index.remove(entityId, data);
    }
  }

  /// Updates an entity in all relevant indexes.
  ///
  /// Removes the old data and inserts the new data to handle
  /// field value changes correctly.
  ///
  /// - [entityId]: The unique identifier of the entity
  /// - [oldData]: The entity's previous data map
  /// - [newData]: The entity's new data map
  void update(
    String entityId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) {
    remove(entityId, oldData);
    insert(entityId, newData);
  }

  /// Searches for entity IDs matching [field] = [value].
  ///
  /// Returns a list of matching entity IDs.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  List<String> search(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }
    return index.search(value);
  }

  /// Performs a range search on the specified [field].
  ///
  /// Only supported for B-tree indexes.
  ///
  /// - [field]: The indexed field to search
  /// - [lowerBound]: The lower bound (inclusive by default)
  /// - [upperBound]: The upper bound (exclusive by default)
  /// - [includeLower]: Whether to include [lowerBound] in results
  /// - [includeUpper]: Whether to include [upperBound] in results
  ///
  /// Returns a list of matching entity IDs.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index doesn't support
  /// range queries.
  List<String> rangeSearch(
    String field,
    dynamic lowerBound,
    dynamic upperBound, {
    bool includeLower = true,
    bool includeUpper = false,
  }) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'Range search not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.rangeSearch(
      lowerBound,
      upperBound,
      includeLower: includeLower,
      includeUpper: includeUpper,
    );
  }

  /// Checks if an index exists on the specified [field].
  bool hasIndex(String field) => _indices.containsKey(field);

  /// Checks if an index of the specified [indexType] exists on [field].
  bool hasIndexOfType(String field, IndexType indexType) {
    final index = _indices[field];
    if (index == null) return false;

    return switch (indexType) {
      IndexType.btree => index is BTreeIndex,
      IndexType.hash => index is HashIndex,
    };
  }

  /// Returns the type of index on [field], or null if no index exists.
  IndexType? getIndexType(String field) {
    final index = _indices[field];
    if (index == null) return null;

    if (index is BTreeIndex) return IndexType.btree;
    if (index is HashIndex) return IndexType.hash;

    return null;
  }

  /// Returns a list of all indexed field names.
  List<String> get indexedFields => _indices.keys.toList();

  /// Returns a list of all indexes.
  List<IIndex> get indexes => _indices.values.toList();

  /// Returns the number of indexes.
  int get indexCount => _indices.length;

  /// Clears all indexes without removing them.
  ///
  /// The index structure is preserved, but all entries are removed.
  /// Use this when clearing all entities from a collection.
  void clearAllEntries() {
    for (final index in _indices.values) {
      index.clear();
    }
    _logger.info('Cleared all index entries.');
  }

  /// Removes all indexes.
  ///
  /// After calling this method, no indexes will exist.
  void removeAllIndexes() {
    for (final index in _indices.values) {
      index.clear();
    }
    _indices.clear();
    _logger.info('Removed all indexes.');
  }
}
