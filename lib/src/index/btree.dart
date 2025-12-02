import 'dart:collection';

import 'i_index.dart';

/// B-tree index implementation using a self-balancing tree structure.
///
/// Provides ordered storage of indexed values, enabling both exact-match
/// lookups and efficient range queries.
///
/// ## Performance Characteristics
///
/// | Operation | Time Complexity |
/// |-----------|-----------------|
/// | Insert    | O(log n)        |
/// | Remove    | O(log n)        |
/// | Search    | O(log n)        |
/// | Range     | O(log n + k)    |
///
/// Where n is the number of unique keys and k is the number of results.
///
/// ## Use Cases
///
/// Best suited for fields that require:
/// - Range queries (e.g., `age > 18 AND age < 65`)
/// - Ordered iteration (e.g., sorting by date)
/// - Min/max lookups
///
/// ## Example
///
/// ```dart
/// final index = BTreeIndex('createdAt');
///
/// // Insert entities
/// index.insert('entity-1', {'createdAt': DateTime(2024, 1, 1)});
/// index.insert('entity-2', {'createdAt': DateTime(2024, 6, 15)});
///
/// // Range query for first half of 2024
/// final results = index.rangeSearch(
///   DateTime(2024, 1, 1),
///   DateTime(2024, 7, 1),
/// );
/// ```
class BTreeIndex implements IIndex {
  @override
  final String field;

  /// Internal sorted map storing key -> entity IDs mapping.
  ///
  /// Uses [SplayTreeMap] for self-balancing tree properties.
  final SplayTreeMap<dynamic, Set<String>> _index = SplayTreeMap();

  /// Creates a new B-tree index on the specified [field].
  BTreeIndex(this.field);

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

  /// Performs a range search between [lowerBound] and [upperBound].
  ///
  /// Returns entity IDs whose indexed values fall within the specified range.
  ///
  /// - [lowerBound]: The lower bound (inclusive). If null, starts from minimum.
  /// - [upperBound]: The upper bound (exclusive). If null, extends to maximum.
  /// - [includeLower]: Whether to include [lowerBound] in results (default: true).
  /// - [includeUpper]: Whether to include [upperBound] in results (default: false).
  ///
  /// Returns a list of matching entity IDs.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Find entities with age between 18 (inclusive) and 65 (exclusive)
  /// final adults = index.rangeSearch(18, 65);
  ///
  /// // Find entities with age >= 21
  /// final over21 = index.rangeSearch(21, null);
  ///
  /// // Find entities with age < 18
  /// final minors = index.rangeSearch(null, 18);
  /// ```
  List<String> rangeSearch(
    dynamic lowerBound,
    dynamic upperBound, {
    bool includeLower = true,
    bool includeUpper = false,
  }) {
    final result = <String>{};

    for (final entry in _index.entries) {
      final key = entry.key;
      final entityIds = entry.value;

      // Check lower bound
      bool withinLower;
      if (lowerBound == null) {
        withinLower = true;
      } else {
        final comparison = Comparable.compare(key, lowerBound);
        withinLower = includeLower ? comparison >= 0 : comparison > 0;
      }

      // Check upper bound
      bool withinUpper;
      if (upperBound == null) {
        withinUpper = true;
      } else {
        final comparison = Comparable.compare(key, upperBound);
        withinUpper = includeUpper ? comparison <= 0 : comparison < 0;
      }

      if (withinLower && withinUpper) {
        result.addAll(entityIds);
      }
    }

    return result.toList();
  }

  /// Returns the minimum key in the index, or null if empty.
  dynamic get minKey => _index.isEmpty ? null : _index.firstKey();

  /// Returns the maximum key in the index, or null if empty.
  dynamic get maxKey => _index.isEmpty ? null : _index.lastKey();

  /// Returns the number of unique keys in the index.
  int get keyCount => _index.length;

  /// Returns the total number of indexed entity references.
  int get entryCount => _index.values.fold(0, (sum, set) => sum + set.length);

  @override
  void clear() {
    _index.clear();
  }
}
