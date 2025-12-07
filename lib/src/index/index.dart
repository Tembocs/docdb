/// Index module for DocDB.
///
/// This module provides indexing capabilities for efficient entity lookups.
/// Indexes improve query performance by maintaining sorted or hashed
/// mappings of field values to entity IDs.
///
/// ## Index Types
///
/// - **B-Tree Index** ([BTreeIndex]): Ordered index supporting range queries.
///   Use for numeric fields, dates, or any field requiring range comparisons.
///
/// - **Hash Index** ([HashIndex]): O(1) lookup for exact matches.
///   Use for unique identifiers, email addresses, or foreign keys.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/index/index.dart';
///
/// // Create an index manager
/// final manager = IndexManager();
///
/// // Create indexes on fields
/// manager.createIndex('email', IndexType.hash);
/// manager.createIndex('createdAt', IndexType.btree);
///
/// // Index an entity
/// final user = User(id: 'user-1', email: 'alice@example.com');
/// manager.insert(user.id!, user.toMap());
///
/// // Query by indexed field
/// final results = manager.search('email', 'alice@example.com');
/// print(results); // ['user-1']
///
/// // Range query on B-tree index
/// final recent = manager.rangeSearch(
///   'createdAt',
///   DateTime(2024, 1, 1),
///   DateTime(2024, 12, 31),
/// );
/// ```
///
/// ## Performance Characteristics
///
/// | Index Type | Insert | Search | Range Query |
/// |------------|--------|--------|-------------|
/// | B-Tree     | O(log n) | O(log n) | O(log n + k) |
/// | Hash       | O(1)   | O(1)   | Not supported |
///
/// Where n is the number of unique keys and k is the number of results.
///
/// ## Best Practices
///
/// 1. **Choose the right index type**: Use hash for equality lookups,
///    B-tree for range queries and ordering.
///
/// 2. **Index selectively**: Each index adds overhead to write operations.
///    Only index fields that are frequently queried.
///
/// 3. **Consider cardinality**: High-cardinality fields (many unique values)
///    benefit more from indexing.
///
/// 4. **Keep indexes updated**: Always update indexes when entities change.
///    Use [IndexManager.update] for atomic updates.
library;

export 'btree.dart' show BTreeIndex;
export 'fulltext.dart'
    show FullTextIndex, FullTextConfig, TermPosting, ScoredResult;
export 'hash.dart' show HashIndex;
export 'i_index.dart' show IIndex, IndexType;
export 'index_manager.dart' show IndexManager;
export 'index_persistence.dart'
    show
        IndexPersistence,
        SerializedIndex,
        SerializedFullTextIndex,
        IndexMetadata;
