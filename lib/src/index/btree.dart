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
  /// Uses early termination for optimal performance - stops iterating once
  /// past the upper bound since keys are ordered.
  ///
  /// - [lowerBound]: The lower bound (inclusive). If null, starts from minimum.
  /// - [upperBound]: The upper bound (exclusive). If null, extends to maximum.
  /// - [includeLower]: Whether to include [lowerBound] in results (default: true).
  /// - [includeUpper]: Whether to include [upperBound] in results (default: false).
  ///
  /// Returns a list of matching entity IDs.
  ///
  /// ## Performance
  ///
  /// Time complexity is O(log n + k) where n is total keys and k is matching keys.
  /// Early termination ensures we don't scan keys beyond the upper bound.
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
    if (_index.isEmpty) {
      return const [];
    }

    final result = <String>{};

    for (final entry in _index.entries) {
      final key = entry.key;
      final entityIds = entry.value;

      // Check lower bound - skip keys below the lower bound
      if (lowerBound != null) {
        final comparison = Comparable.compare(key, lowerBound);
        if (includeLower ? comparison < 0 : comparison <= 0) {
          // Key is below lower bound, skip to next
          continue;
        }
      }

      // Check upper bound - stop iteration once past upper bound
      if (upperBound != null) {
        final comparison = Comparable.compare(key, upperBound);
        if (includeUpper ? comparison > 0 : comparison >= 0) {
          // Key is past upper bound, stop iteration (early termination)
          break;
        }
      }

      // Key is within range, add entity IDs
      result.addAll(entityIds);
    }

    return result.toList();
  }

  /// Finds all entity IDs where the indexed value is greater than [value].
  ///
  /// Uses early termination - skips keys until finding the first key greater
  /// than [value], then collects all remaining keys.
  ///
  /// Time complexity: O(log n + k) where k is the number of matching results.
  List<String> greaterThan(dynamic value) {
    if (_index.isEmpty) {
      return const [];
    }

    final result = <String>{};
    bool foundStart = false;

    for (final entry in _index.entries) {
      if (!foundStart) {
        if (Comparable.compare(entry.key, value) > 0) {
          foundStart = true;
          result.addAll(entry.value);
        }
      } else {
        // Once we've found the start, add all remaining entries
        result.addAll(entry.value);
      }
    }

    return result.toList();
  }

  /// Finds all entity IDs where the indexed value is greater than or equal to [value].
  ///
  /// Uses early termination - skips keys until finding the first key >= [value],
  /// then collects all remaining keys.
  ///
  /// Time complexity: O(log n + k) where k is the number of matching results.
  List<String> greaterThanOrEqual(dynamic value) {
    if (_index.isEmpty) {
      return const [];
    }

    final result = <String>{};
    bool foundStart = false;

    for (final entry in _index.entries) {
      if (!foundStart) {
        if (Comparable.compare(entry.key, value) >= 0) {
          foundStart = true;
          result.addAll(entry.value);
        }
      } else {
        result.addAll(entry.value);
      }
    }

    return result.toList();
  }

  /// Finds all entity IDs where the indexed value is less than [value].
  ///
  /// Uses early termination - collects keys until reaching [value], then stops.
  ///
  /// Time complexity: O(k) where k is the number of matching results.
  List<String> lessThan(dynamic value) {
    if (_index.isEmpty) {
      return const [];
    }

    final result = <String>{};

    for (final entry in _index.entries) {
      if (Comparable.compare(entry.key, value) >= 0) {
        // Reached the boundary, stop
        break;
      }
      result.addAll(entry.value);
    }

    return result.toList();
  }

  /// Finds all entity IDs where the indexed value is less than or equal to [value].
  ///
  /// Uses early termination - collects keys until passing [value], then stops.
  ///
  /// Time complexity: O(k) where k is the number of matching results.
  List<String> lessThanOrEqual(dynamic value) {
    if (_index.isEmpty) {
      return const [];
    }

    final result = <String>{};

    for (final entry in _index.entries) {
      if (Comparable.compare(entry.key, value) > 0) {
        // Passed the boundary, stop
        break;
      }
      result.addAll(entry.value);
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

  // ===========================================================================
  // Index-Only Count Methods
  // ===========================================================================
  // These methods return counts directly from the index without requiring
  // entity deserialization, providing O(1) to O(log n + k) performance.

  /// Counts entities where the indexed value equals [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(1)
  int countEquals(dynamic value) {
    final entityIds = _index[value];
    return entityIds?.length ?? 0;
  }

  /// Counts entities where the indexed value is greater than [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(log n + k) where k is matching keys.
  int countGreaterThan(dynamic value) {
    if (_index.isEmpty) return 0;

    int count = 0;
    bool foundStart = false;

    for (final entry in _index.entries) {
      if (!foundStart) {
        if (Comparable.compare(entry.key, value) > 0) {
          foundStart = true;
          count += entry.value.length;
        }
      } else {
        count += entry.value.length;
      }
    }

    return count;
  }

  /// Counts entities where the indexed value is greater than or equal to [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(log n + k) where k is matching keys.
  int countGreaterThanOrEqual(dynamic value) {
    if (_index.isEmpty) return 0;

    int count = 0;
    bool foundStart = false;

    for (final entry in _index.entries) {
      if (!foundStart) {
        if (Comparable.compare(entry.key, value) >= 0) {
          foundStart = true;
          count += entry.value.length;
        }
      } else {
        count += entry.value.length;
      }
    }

    return count;
  }

  /// Counts entities where the indexed value is less than [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(k) where k is matching keys.
  int countLessThan(dynamic value) {
    if (_index.isEmpty) return 0;

    int count = 0;

    for (final entry in _index.entries) {
      if (Comparable.compare(entry.key, value) >= 0) {
        break;
      }
      count += entry.value.length;
    }

    return count;
  }

  /// Counts entities where the indexed value is less than or equal to [value].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(k) where k is matching keys.
  int countLessThanOrEqual(dynamic value) {
    if (_index.isEmpty) return 0;

    int count = 0;

    for (final entry in _index.entries) {
      if (Comparable.compare(entry.key, value) > 0) {
        break;
      }
      count += entry.value.length;
    }

    return count;
  }

  /// Counts entities where the indexed value is between [lowerBound] and [upperBound].
  ///
  /// Returns the count directly from the index without loading entities.
  /// Time complexity: O(log n + k) where k is matching keys.
  int countRange(
    dynamic lowerBound,
    dynamic upperBound, {
    bool includeLower = true,
    bool includeUpper = false,
  }) {
    if (_index.isEmpty) return 0;

    int count = 0;

    for (final entry in _index.entries) {
      final key = entry.key;

      // Check lower bound
      if (lowerBound != null) {
        final comparison = Comparable.compare(key, lowerBound);
        if (includeLower ? comparison < 0 : comparison <= 0) {
          continue;
        }
      }

      // Check upper bound
      if (upperBound != null) {
        final comparison = Comparable.compare(key, upperBound);
        if (includeUpper ? comparison > 0 : comparison >= 0) {
          break;
        }
      }

      count += entry.value.length;
    }

    return count;
  }

  /// Checks if any entity exists where the indexed value equals [value].
  ///
  /// More efficient than search() when you only need to check existence.
  /// Time complexity: O(1)
  bool existsEquals(dynamic value) {
    return _index.containsKey(value);
  }

  /// Checks if any entity exists where the indexed value is greater than [value].
  ///
  /// Time complexity: O(1) - just checks if max key > value.
  bool existsGreaterThan(dynamic value) {
    if (_index.isEmpty) return false;
    return Comparable.compare(_index.lastKey()!, value) > 0;
  }

  /// Checks if any entity exists where the indexed value is less than [value].
  ///
  /// Time complexity: O(1) - just checks if min key < value.
  bool existsLessThan(dynamic value) {
    if (_index.isEmpty) return false;
    return Comparable.compare(_index.firstKey()!, value) < 0;
  }

  @override
  void clear() {
    _index.clear();
  }
}
