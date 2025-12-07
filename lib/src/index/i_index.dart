/// Abstract interface for index implementations in DocDB.
///
/// This module defines the [IIndex] contract that all index implementations
/// must follow. Indexes provide efficient lookup of entities based on
/// field values.
///
/// ## Implementations
///
/// - [BTreeIndex]: Ordered index supporting range queries
/// - [HashIndex]: O(1) lookup for exact matches
///
/// ## Usage
///
/// Indexes are typically managed through [IndexManager] rather than
/// used directly:
///
/// ```dart
/// final manager = IndexManager();
/// manager.createIndex('email', IndexType.hash);
/// manager.createIndex('age', IndexType.btree);
/// ```
library;

/// The type of index to create.
///
/// Different index types provide different performance characteristics:
///
/// - [btree]: Balanced tree structure supporting range queries and ordering.
///   Best for fields that need range queries (e.g., dates, numbers).
///
/// - [hash]: Hash table structure for O(1) exact-match lookups.
///   Best for unique identifiers and equality comparisons.
///
/// - [fulltext]: Inverted index for full-text search.
///   Best for text fields requiring word-based search, phrase matching,
///   and relevance scoring.
enum IndexType {
  /// B-tree index for ordered data and range queries.
  btree,

  /// Hash index for fast exact-match lookups.
  hash,

  /// Full-text index for text search with tokenization.
  fulltext,
}

/// Abstract interface for index implementations.
///
/// All index implementations must provide methods for inserting,
/// removing, and searching entities based on indexed field values.
///
/// ## Implementation Notes
///
/// - Indexes store entity IDs, not the entities themselves
/// - A single key can map to multiple entity IDs (non-unique index)
/// - Null field values are not indexed
/// - Entity ID must not be null when indexing
///
/// ## Example Implementation
///
/// ```dart
/// class CustomIndex implements IIndex {
///   @override
///   final String field;
///
///   CustomIndex(this.field);
///
///   @override
///   void insert(String entityId, Map<String, dynamic> data) {
///     final key = data[field];
///     if (key != null) {
///       // Add entityId to index under key
///     }
///   }
///
///   // ... implement other methods
/// }
/// ```
abstract interface class IIndex {
  /// The field name on which this index is built.
  ///
  /// This corresponds to a key in the entity's [toMap()] result.
  String get field;

  /// Inserts an entity into the index.
  ///
  /// Extracts the value of [field] from [data] and associates
  /// it with the given [entityId].
  ///
  /// - [entityId]: The unique identifier of the entity (must not be null)
  /// - [data]: The entity's data map from [Entity.toMap()]
  ///
  /// If the field value is null, the entity is not indexed.
  void insert(String entityId, Map<String, dynamic> data);

  /// Removes an entity from the index.
  ///
  /// Looks up the value of [field] in [data] and removes the
  /// association with [entityId].
  ///
  /// - [entityId]: The unique identifier of the entity
  /// - [data]: The entity's data map from [Entity.toMap()]
  void remove(String entityId, Map<String, dynamic> data);

  /// Searches for entities matching the given [value].
  ///
  /// Returns a list of entity IDs whose indexed field equals [value].
  /// Returns an empty list if no matches are found.
  ///
  /// - [value]: The value to search for
  List<String> search(dynamic value);

  /// Clears all entries from the index.
  ///
  /// After calling this method, [search] will return empty results
  /// until new entries are inserted.
  void clear();
}
