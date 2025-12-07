// lib/src/index/index_manager.dart

import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/logger/logger.dart';
import 'package:docdb/src/utils/constants.dart';

import 'btree.dart';
import 'fulltext.dart';
import 'hash.dart';
import 'i_index.dart';
import 'index_persistence.dart';

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
      IndexType.fulltext => FullTextIndex(field),
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

  /// Finds entity IDs where the indexed value is greater than [value].
  ///
  /// Uses optimized early termination for better performance.
  /// Only supported for B-tree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a B-tree.
  List<String> greaterThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'greaterThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.greaterThan(value);
  }

  /// Finds entity IDs where the indexed value is greater than or equal to [value].
  ///
  /// Uses optimized early termination for better performance.
  /// Only supported for B-tree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a B-tree.
  List<String> greaterThanOrEqual(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'greaterThanOrEqual not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.greaterThanOrEqual(value);
  }

  /// Finds entity IDs where the indexed value is less than [value].
  ///
  /// Uses optimized early termination for better performance.
  /// Only supported for B-tree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a B-tree.
  List<String> lessThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'lessThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.lessThan(value);
  }

  /// Finds entity IDs where the indexed value is less than or equal to [value].
  ///
  /// Uses optimized early termination for better performance.
  /// Only supported for B-tree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a B-tree.
  List<String> lessThanOrEqual(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'lessThanOrEqual not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.lessThanOrEqual(value);
  }

  // ===========================================================================
  // Full-Text Search Methods
  // ===========================================================================
  // These methods provide full-text search capabilities on text fields.

  /// Performs a full-text search for the specified [query] on [field].
  ///
  /// Returns entity IDs of documents containing all query terms (AND semantics).
  /// Only supported for full-text indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<String> fullTextSearch(String field, String query) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Full-text search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for text search.',
      );
    }

    return index.search(query);
  }

  /// Performs a full-text search with OR semantics.
  ///
  /// Returns entity IDs of documents containing any query term.
  /// Only supported for full-text indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<String> fullTextSearchAny(String field, List<String> terms) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Full-text search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for text search.',
      );
    }

    return index.searchAny(terms);
  }

  /// Performs a phrase search (exact sequence of words).
  ///
  /// Returns entity IDs of documents containing the exact phrase.
  /// Requires position tracking to be enabled in the index config.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<String> fullTextSearchPhrase(String field, String phrase) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Phrase search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for phrase search.',
      );
    }

    return index.searchPhrase(phrase);
  }

  /// Performs a proximity search (terms within a certain distance).
  ///
  /// Returns entity IDs where all terms appear within [maxDistance] of each other.
  /// Requires position tracking to be enabled in the index config.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<String> fullTextSearchProximity(
    String field,
    List<String> terms,
    int maxDistance,
  ) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Proximity search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for proximity search.',
      );
    }

    return index.searchProximity(terms, maxDistance);
  }

  /// Performs a prefix search for terms starting with the given prefix.
  ///
  /// Returns entity IDs containing any term starting with [prefix].
  /// Only supported for full-text indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<String> fullTextSearchPrefix(String field, String prefix) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Prefix search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for prefix search.',
      );
    }

    return index.searchPrefix(prefix);
  }

  /// Performs a ranked full-text search using TF-IDF scoring.
  ///
  /// Returns a list of [ScoredResult] sorted by relevance (highest first).
  /// Only supported for full-text indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a full-text index.
  List<ScoredResult> fullTextSearchRanked(String field, String query) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! FullTextIndex) {
      throw UnsupportedIndexTypeException(
        'Ranked search not supported for non-fulltext index on field "$field". '
        'Use a fulltext index for ranked search.',
      );
    }

    return index.searchRanked(query);
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
      IndexType.fulltext => index is FullTextIndex,
    };
  }

  /// Returns the type of index on [field], or null if no index exists.
  IndexType? getIndexType(String field) {
    final index = _indices[field];
    if (index == null) return null;

    if (index is BTreeIndex) return IndexType.btree;
    if (index is HashIndex) return IndexType.hash;
    if (index is FullTextIndex) return IndexType.fulltext;

    return null;
  }

  // ===========================================================================
  // Index Statistics Methods
  // ===========================================================================
  // These methods provide statistics for query optimization.

  /// Returns the cardinality (number of unique keys) for the index on [field].
  ///
  /// Cardinality indicates how many distinct values exist in the index.
  /// Higher cardinality generally means better selectivity.
  /// For full-text indexes, returns the number of unique terms.
  ///
  /// Returns 0 if no index exists on [field].
  int getCardinality(String field) {
    final index = _indices[field];
    if (index == null) return 0;

    if (index is BTreeIndex) return index.keyCount;
    if (index is HashIndex) return index.keyCount;
    if (index is FullTextIndex) return index.termCount;

    return 0;
  }

  /// Returns the total number of entries (entity references) in the index.
  ///
  /// This may be greater than cardinality if multiple entities share keys.
  /// For full-text indexes, returns the number of indexed documents.
  ///
  /// Returns 0 if no index exists on [field].
  int getTotalEntries(String field) {
    final index = _indices[field];
    if (index == null) return 0;

    if (index is BTreeIndex) return index.entryCount;
    if (index is HashIndex) return index.entryCount;
    if (index is FullTextIndex) return index.entryCount;

    return 0;
  }

  /// Returns a list of all indexed field names.
  List<String> get indexedFields => _indices.keys.toList();

  /// Returns a list of all indexes.
  List<IIndex> get indexes => _indices.values.toList();

  /// Returns the number of indexes.
  int get indexCount => _indices.length;

  // ===========================================================================
  // Index-Only Count Methods
  // ===========================================================================
  // These methods return counts directly from the index without requiring
  // entity deserialization. Use these for optimal performance when you only
  // need counts, not actual entities.

  /// Counts entities where [field] equals [value] using the index.
  ///
  /// Returns the count directly from the index without loading entities.
  /// Works with both hash and btree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  int countEquals(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is HashIndex) {
      return index.countEquals(value);
    } else if (index is BTreeIndex) {
      return index.countEquals(value);
    }

    // Fallback to search and count
    return index.search(value).length;
  }

  /// Counts entities where [field] is greater than [value] using a btree index.
  ///
  /// Returns the count directly from the index without loading entities.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  int countGreaterThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'countGreaterThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.countGreaterThan(value);
  }

  /// Counts entities where [field] is greater than or equal to [value].
  ///
  /// Returns the count directly from the index without loading entities.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  int countGreaterThanOrEqual(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'countGreaterThanOrEqual not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.countGreaterThanOrEqual(value);
  }

  /// Counts entities where [field] is less than [value] using a btree index.
  ///
  /// Returns the count directly from the index without loading entities.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  int countLessThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'countLessThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.countLessThan(value);
  }

  /// Counts entities where [field] is less than or equal to [value].
  ///
  /// Returns the count directly from the index without loading entities.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  int countLessThanOrEqual(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'countLessThanOrEqual not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.countLessThanOrEqual(value);
  }

  /// Counts entities where [field] is between [lowerBound] and [upperBound].
  ///
  /// Returns the count directly from the index without loading entities.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  int countRange(
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
        'countRange not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.countRange(
      lowerBound,
      upperBound,
      includeLower: includeLower,
      includeUpper: includeUpper,
    );
  }

  // ===========================================================================
  // Index-Only Existence Checks
  // ===========================================================================
  // These methods check for existence directly from the index without
  // loading entities from storage.

  /// Checks if any entity exists where [field] equals [value].
  ///
  /// Returns true if at least one entity matches, without loading entities.
  /// Works with both hash and btree indexes.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  bool existsEquals(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is HashIndex) {
      return index.existsEquals(value);
    } else if (index is BTreeIndex) {
      return index.existsEquals(value);
    }

    // Fallback to search
    return index.search(value).isNotEmpty;
  }

  /// Checks if any entity exists where [field] is greater than [value].
  ///
  /// Uses O(1) check against index bounds.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  bool existsGreaterThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'existsGreaterThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.existsGreaterThan(value);
  }

  /// Checks if any entity exists where [field] is less than [value].
  ///
  /// Uses O(1) check against index bounds.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  /// Throws [UnsupportedIndexTypeException] if the index is not a btree.
  bool existsLessThan(String field, dynamic value) {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }

    if (index is! BTreeIndex) {
      throw UnsupportedIndexTypeException(
        'existsLessThan not supported for hash index on field "$field". '
        'Use a btree index for range queries.',
      );
    }

    return index.existsLessThan(value);
  }

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

  // ===========================================================================
  // Persistence Support
  // ===========================================================================

  /// Gets an index by field name for direct access.
  ///
  /// Returns null if no index exists on the field.
  IIndex? getIndex(String field) => _indices[field];

  /// Gets all indexes as field-to-index entries for iteration.
  Iterable<MapEntry<String, IIndex>> get allIndexes => _indices.entries;

  /// Registers a pre-existing index (used during restoration).
  ///
  /// This bypasses normal creation and directly registers an index.
  /// Typically used when loading persisted indexes from disk.
  ///
  /// Throws [IndexAlreadyExistsException] if an index on [field] already exists.
  void registerIndex(String field, IIndex index) {
    if (_indices.containsKey(field)) {
      throw IndexAlreadyExistsException(
        'Index on field "$field" already exists.',
      );
    }
    _indices[field] = index;
    _logger.info('Registered restored index on field "$field".');
  }

  /// Saves all indexes to disk using the provided persistence manager.
  ///
  /// - [collectionName]: The collection these indexes belong to.
  /// - [persistence]: The persistence manager to use.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final persistence = IndexPersistence(directory: './data/indexes');
  /// await manager.saveAllIndexes('users', persistence);
  /// ```
  Future<void> saveAllIndexes(
    String collectionName,
    IndexPersistence persistence,
  ) async {
    for (final entry in _indices.entries) {
      await persistence.saveIndex(collectionName, entry.key, entry.value);
      _logger.info(
        'Saved index on field "${entry.key}" for collection "$collectionName".',
      );
    }
  }

  /// Loads all persisted indexes for a collection.
  ///
  /// Clears existing indexes and loads from disk.
  ///
  /// - [collectionName]: The collection to load indexes for.
  /// - [persistence]: The persistence manager to use.
  ///
  /// Returns the number of indexes loaded.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final persistence = IndexPersistence(directory: './data/indexes');
  /// final count = await manager.loadAllIndexes('users', persistence);
  /// print('Loaded $count indexes');
  /// ```
  Future<int> loadAllIndexes(
    String collectionName,
    IndexPersistence persistence,
  ) async {
    final fields = await persistence.listIndexes(collectionName);
    var loadedCount = 0;

    for (final field in fields) {
      final data = await persistence.loadIndex(collectionName, field);
      if (data == null) continue;

      // Handle full-text indexes separately
      if (data is SerializedFullTextIndex) {
        final index = FullTextIndex(field);
        index.restoreFromMap(data.data);

        if (!_indices.containsKey(field)) {
          _indices[field] = index;
          loadedCount++;
          _logger.info(
            'Loaded fulltext index on field "$field" for collection "$collectionName".',
          );
        }
        continue;
      }

      // Handle btree and hash indexes
      final serializedIndex = data as SerializedIndex;

      // Create the appropriate index type
      final IIndex index = switch (serializedIndex.type) {
        IndexType.btree => BTreeIndex(field),
        IndexType.hash => HashIndex(field),
        IndexType.fulltext => FullTextIndex(field),
      };

      // Restore the data
      switch (index) {
        case BTreeIndex btree:
          btree.restoreFromMap(serializedIndex.entries);
        case HashIndex hash:
          hash.restoreFromMap(serializedIndex.entries);
        case FullTextIndex _:
          // Already handled above
          continue;
      }

      // Register without overwriting
      if (!_indices.containsKey(field)) {
        _indices[field] = index;
        loadedCount++;
        _logger.info(
          'Loaded index on field "$field" for collection "$collectionName".',
        );
      }
    }

    return loadedCount;
  }

  /// Saves a single index to disk.
  ///
  /// - [collectionName]: The collection this index belongs to.
  /// - [field]: The field name of the index to save.
  /// - [persistence]: The persistence manager to use.
  ///
  /// Throws [IndexNotFoundException] if no index exists on [field].
  Future<void> saveIndex(
    String collectionName,
    String field,
    IndexPersistence persistence,
  ) async {
    final index = _indices[field];
    if (index == null) {
      throw IndexNotFoundException('No index exists on field "$field".');
    }
    await persistence.saveIndex(collectionName, field, index);
    _logger.info(
      'Saved index on field "$field" for collection "$collectionName".',
    );
  }

  /// Loads a single index from disk.
  ///
  /// - [collectionName]: The collection this index belongs to.
  /// - [field]: The field name of the index to load.
  /// - [persistence]: The persistence manager to use.
  ///
  /// Returns true if the index was loaded, false if it doesn't exist on disk.
  Future<bool> loadIndex(
    String collectionName,
    String field,
    IndexPersistence persistence,
  ) async {
    final data = await persistence.loadIndex(collectionName, field);
    if (data == null) return false;

    // Handle full-text indexes separately
    if (data is SerializedFullTextIndex) {
      final index = FullTextIndex(field);
      index.restoreFromMap(data.data);
      _indices[field] = index;
      _logger.info(
        'Loaded fulltext index on field "$field" for collection "$collectionName".',
      );
      return true;
    }

    // Handle btree and hash indexes
    final serializedIndex = data as SerializedIndex;

    // Create the appropriate index type
    final IIndex index = switch (serializedIndex.type) {
      IndexType.btree => BTreeIndex(field),
      IndexType.hash => HashIndex(field),
      IndexType.fulltext => FullTextIndex(field),
    };

    // Restore the data
    switch (index) {
      case BTreeIndex btree:
        btree.restoreFromMap(serializedIndex.entries);
      case HashIndex hash:
        hash.restoreFromMap(serializedIndex.entries);
      case FullTextIndex _:
        // Already handled above
        return false;
    }

    // Register (or replace existing)
    _indices[field] = index;
    _logger.info(
      'Loaded index on field "$field" for collection "$collectionName".',
    );
    return true;
  }
}
