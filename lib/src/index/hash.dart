import 'i_index.dart';

/// Hash-based index implementation for O(1) exact-match lookups.
///
/// Uses a hash table to provide constant-time lookups for equality
/// comparisons. Does not support range queries or ordering.
///
/// ## Performance Characteristics
///
/// | Operation | Time Complexity |
/// |-----------|-----------------|
/// | Insert    | O(1) average    |
/// | Remove    | O(1) average    |
/// | Search    | O(1) average    |
///
/// ## Use Cases
///
/// Best suited for fields that:
/// - Have high cardinality (many unique values)
/// - Are only queried for exact matches
/// - Serve as unique identifiers or foreign keys
///
/// ## Example
///
/// ```dart
/// final index = HashIndex('email');
///
/// // Insert entities
/// index.insert('user-1', {'email': 'alice@example.com'});
/// index.insert('user-2', {'email': 'bob@example.com'});
///
/// // O(1) lookup
/// final results = index.search('alice@example.com');
/// // results: ['user-1']
/// ```
///
/// ## Limitations
///
/// - Does not support range queries (use [BTreeIndex] instead)
/// - Does not maintain insertion order
/// - Hash collisions may degrade performance for very large datasets
class HashIndex implements IIndex {
  @override
  final String field;

  /// Internal hash map storing key -> entity IDs mapping.
  final Map<dynamic, Set<String>> _index = {};

  /// Creates a new hash index on the specified [field].
  HashIndex(this.field);

  @override
  void insert(String entityId, Map<String, dynamic> data) {
    final key = data[field];
    if (key == null) {
      return;
    }
    _index.putIfAbsent(key, () => <String>{}).add(entityId);
  }

  @override
  void remove(String entityId, Map<String, dynamic> data) {
    final key = data[field];
    if (key == null) {
      return;
    }

    final entityIds = _index[key];
    if (entityIds == null) {
      return;
    }

    entityIds.remove(entityId);

    // Clean up empty sets to prevent memory leaks
    if (entityIds.isEmpty) {
      _index.remove(key);
    }
  }

  @override
  List<String> search(dynamic value) {
    final entityIds = _index[value];
    if (entityIds == null) {
      return const [];
    }
    return entityIds.toList();
  }

  /// Returns the number of unique keys in the index.
  int get keyCount => _index.length;

  /// Returns the total number of indexed entity references.
  int get entryCount => _index.values.fold(0, (sum, set) => sum + set.length);

  /// Checks if a specific key exists in the index.
  bool containsKey(dynamic key) => _index.containsKey(key);

  // ===========================================================================
  // Index-Only Count Methods
  // ===========================================================================
  // These methods return counts directly from the index without requiring
  // entity deserialization, providing O(1) performance.

  /// Counts entities where the indexed value equals [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(1)
  int countEquals(dynamic value) {
    final entityIds = _index[value];
    return entityIds?.length ?? 0;
  }

  /// Checks if any entity exists where the indexed value equals [value].
  ///
  /// More efficient than search() when you only need to check existence.
  /// Time complexity: O(1)
  bool existsEquals(dynamic value) {
    return _index.containsKey(value);
  }

  @override
  void clear() {
    _index.clear();
  }

  // ===========================================================================
  // Serialization Support
  // ===========================================================================

  /// Exports the index state as a map for persistence.
  ///
  /// Returns a copy of the internal index structure suitable for
  /// serialization. Each key maps to a set of entity IDs.
  ///
  /// See also: [restoreFromMap] for restoring state.
  Map<dynamic, Set<String>> toMap() {
    // Create a deep copy to prevent external modifications
    return Map.fromEntries(
      _index.entries.map((e) => MapEntry(e.key, Set<String>.from(e.value))),
    );
  }

  /// Restores the index state from a serialized map.
  ///
  /// Clears existing entries and populates from the provided [data].
  /// This is used during index recovery from disk.
  ///
  /// - [data]: Map of indexed values to entity ID sets.
  ///
  /// See also: [toMap] for exporting state.
  void restoreFromMap(Map<dynamic, Set<String>> data) {
    _index.clear();
    for (final entry in data.entries) {
      // Ensure we use a fresh set copy for safety
      _index[entry.key] = Set<String>.from(entry.value);
    }
  }
}
