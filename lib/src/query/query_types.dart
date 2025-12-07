/// Query type definitions for DocDB.
///
/// This module contains all query interface and implementation classes
/// for filtering entities based on field values.
library;

import 'package:meta/meta.dart';

/// Abstract interface for all query types.
///
/// Queries are used to filter entities based on field values. Each query
/// type implements the [matches] method to determine if a data map
/// satisfies the query criteria.
///
/// ## Usage
///
/// Queries are typically constructed using [QueryBuilder] rather than
/// instantiated directly:
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .whereGreaterThan('age', 18)
///     .build();
///
/// // Check if entity matches
/// final data = entity.toMap();
/// if (query.matches(data)) {
///   // Entity matches the query
/// }
/// ```
///
/// ## Serialization
///
/// All queries support serialization via [toMap] and deserialization via
/// [IQuery.fromMap], enabling query persistence and network transfer.
@immutable
abstract interface class IQuery {
  /// Determines if the given [data] map matches the query criteria.
  ///
  /// The [data] parameter is typically obtained from [Entity.toMap()].
  /// Returns `true` if the data matches, `false` otherwise.
  bool matches(Map<String, dynamic> data);

  /// Serializes the query to a map for persistence or network transfer.
  ///
  /// The resulting map can be deserialized using [IQuery.fromMap].
  Map<String, dynamic> toMap();

  /// Deserializes a query from a map.
  ///
  /// Throws [ArgumentError] if the map contains an invalid query type.
  static IQuery fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    if (type == null) {
      throw ArgumentError.value(map, 'map', 'Missing "type" field in query');
    }

    return switch (type) {
      'EqualsQuery' => EqualsQuery._fromMap(map),
      'NotEqualsQuery' => NotEqualsQuery._fromMap(map),
      'AndQuery' => AndQuery._fromMap(map),
      'OrQuery' => OrQuery._fromMap(map),
      'NotQuery' => NotQuery._fromMap(map),
      'GreaterThanQuery' => GreaterThanQuery._fromMap(map),
      'GreaterThanOrEqualsQuery' => GreaterThanOrEqualsQuery._fromMap(map),
      'LessThanQuery' => LessThanQuery._fromMap(map),
      'LessThanOrEqualsQuery' => LessThanOrEqualsQuery._fromMap(map),
      'BetweenQuery' => BetweenQuery._fromMap(map),
      'InQuery' => InQuery._fromMap(map),
      'NotInQuery' => NotInQuery._fromMap(map),
      'RegexQuery' => RegexQuery._fromMap(map),
      'ExistsQuery' => ExistsQuery._fromMap(map),
      'ContainsQuery' => ContainsQuery._fromMap(map),
      'StartsWithQuery' => StartsWithQuery._fromMap(map),
      'EndsWithQuery' => EndsWithQuery._fromMap(map),
      'IsNullQuery' => IsNullQuery._fromMap(map),
      'IsNotNullQuery' => IsNotNullQuery._fromMap(map),
      'AllQuery' => const AllQuery(),
      'FullTextQuery' => FullTextQuery._fromMap(map),
      'FullTextPhraseQuery' => FullTextPhraseQuery._fromMap(map),
      'FullTextAnyQuery' => FullTextAnyQuery._fromMap(map),
      'FullTextPrefixQuery' => FullTextPrefixQuery._fromMap(map),
      'FullTextProximityQuery' => FullTextProximityQuery._fromMap(map),
      _ => throw ArgumentError.value(type, 'type', 'Unknown query type'),
    };
  }
}

/// A query that matches all entities.
///
/// Useful as a default query or when you want to retrieve all entities
/// from a collection.
@immutable
class AllQuery implements IQuery {
  /// Creates an [AllQuery] that matches everything.
  const AllQuery();

  @override
  bool matches(Map<String, dynamic> data) => true;

  @override
  Map<String, dynamic> toMap() => {'type': 'AllQuery'};
}

/// Query to check if a field equals a specific value.
///
/// Supports deep equality for nested maps and lists.
///
/// ## Example
///
/// ```dart
/// final query = EqualsQuery('status', 'active');
/// query.matches({'status': 'active'}); // true
/// query.matches({'status': 'inactive'}); // false
/// ```
@immutable
class EqualsQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value to compare against.
  final dynamic value;

  /// Creates an [EqualsQuery] for the given [field] and [value].
  const EqualsQuery(this.field, this.value);

  factory EqualsQuery._fromMap(Map<String, dynamic> map) {
    return EqualsQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return _deepEquals(fieldValue, value);
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'EqualsQuery',
    'field': field,
    'value': value,
  };
}

/// Query to check if a field does not equal a specific value.
///
/// The logical negation of [EqualsQuery].
@immutable
class NotEqualsQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value that the field should not equal.
  final dynamic value;

  /// Creates a [NotEqualsQuery] for the given [field] and [value].
  const NotEqualsQuery(this.field, this.value);

  factory NotEqualsQuery._fromMap(Map<String, dynamic> map) {
    return NotEqualsQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return !_deepEquals(fieldValue, value);
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'NotEqualsQuery',
    'field': field,
    'value': value,
  };
}

/// Query to combine multiple queries with a logical AND.
///
/// All sub-queries must match for the overall query to match.
///
/// ## Example
///
/// ```dart
/// final query = AndQuery([
///   EqualsQuery('status', 'active'),
///   GreaterThanQuery('age', 18),
/// ]);
/// ```
@immutable
class AndQuery implements IQuery {
  /// The list of queries that must all match.
  final List<IQuery> queries;

  /// Creates an [AndQuery] with the given [queries].
  ///
  /// Throws [ArgumentError] if [queries] is empty.
  AndQuery(this.queries) {
    if (queries.isEmpty) {
      throw ArgumentError.value(queries, 'queries', 'Cannot be empty');
    }
  }

  factory AndQuery._fromMap(Map<String, dynamic> map) {
    final queriesList = map['queries'] as List;
    return AndQuery(
      queriesList
          .map((q) => IQuery.fromMap(q as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    return queries.every((query) => query.matches(data));
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'AndQuery',
    'queries': queries.map((q) => q.toMap()).toList(),
  };
}

/// Query to combine multiple queries with a logical OR.
///
/// At least one sub-query must match for the overall query to match.
///
/// ## Example
///
/// ```dart
/// final query = OrQuery([
///   EqualsQuery('status', 'active'),
///   EqualsQuery('status', 'pending'),
/// ]);
/// ```
@immutable
class OrQuery implements IQuery {
  /// The list of queries where at least one must match.
  final List<IQuery> queries;

  /// Creates an [OrQuery] with the given [queries].
  ///
  /// Throws [ArgumentError] if [queries] is empty.
  OrQuery(this.queries) {
    if (queries.isEmpty) {
      throw ArgumentError.value(queries, 'queries', 'Cannot be empty');
    }
  }

  factory OrQuery._fromMap(Map<String, dynamic> map) {
    final queriesList = map['queries'] as List;
    return OrQuery(
      queriesList
          .map((q) => IQuery.fromMap(q as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    return queries.any((query) => query.matches(data));
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'OrQuery',
    'queries': queries.map((q) => q.toMap()).toList(),
  };
}

/// Query to negate another query.
///
/// Matches when the wrapped query does not match.
///
/// ## Example
///
/// ```dart
/// final query = NotQuery(EqualsQuery('status', 'deleted'));
/// // Matches all entities where status is not 'deleted'
/// ```
@immutable
class NotQuery implements IQuery {
  /// The query to negate.
  final IQuery query;

  /// Creates a [NotQuery] that negates [query].
  const NotQuery(this.query);

  factory NotQuery._fromMap(Map<String, dynamic> map) {
    return NotQuery(IQuery.fromMap(map['query'] as Map<String, dynamic>));
  }

  @override
  bool matches(Map<String, dynamic> data) => !query.matches(data);

  @override
  Map<String, dynamic> toMap() => {'type': 'NotQuery', 'query': query.toMap()};
}

/// Query to check if a field's value is greater than a specified value.
///
/// Works with any [Comparable] type (numbers, strings, dates).
@immutable
class GreaterThanQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value to compare against.
  final dynamic value;

  /// Creates a [GreaterThanQuery] for the given [field] and [value].
  const GreaterThanQuery(this.field, this.value);

  factory GreaterThanQuery._fromMap(Map<String, dynamic> map) {
    return GreaterThanQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue == null) return false;
    return _compareValues(fieldValue, value) > 0;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'GreaterThanQuery',
    'field': field,
    'value': value,
  };
}

/// Query to check if a field's value is greater than or equal to a specified value.
@immutable
class GreaterThanOrEqualsQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value to compare against.
  final dynamic value;

  /// Creates a [GreaterThanOrEqualsQuery] for the given [field] and [value].
  const GreaterThanOrEqualsQuery(this.field, this.value);

  factory GreaterThanOrEqualsQuery._fromMap(Map<String, dynamic> map) {
    return GreaterThanOrEqualsQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue == null) return false;
    return _compareValues(fieldValue, value) >= 0;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'GreaterThanOrEqualsQuery',
    'field': field,
    'value': value,
  };
}

/// Query to check if a field's value is less than a specified value.
///
/// Works with any [Comparable] type (numbers, strings, dates).
@immutable
class LessThanQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value to compare against.
  final dynamic value;

  /// Creates a [LessThanQuery] for the given [field] and [value].
  const LessThanQuery(this.field, this.value);

  factory LessThanQuery._fromMap(Map<String, dynamic> map) {
    return LessThanQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue == null) return false;
    return _compareValues(fieldValue, value) < 0;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'LessThanQuery',
    'field': field,
    'value': value,
  };
}

/// Query to check if a field's value is less than or equal to a specified value.
@immutable
class LessThanOrEqualsQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The value to compare against.
  final dynamic value;

  /// Creates a [LessThanOrEqualsQuery] for the given [field] and [value].
  const LessThanOrEqualsQuery(this.field, this.value);

  factory LessThanOrEqualsQuery._fromMap(Map<String, dynamic> map) {
    return LessThanOrEqualsQuery(map['field'] as String, map['value']);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue == null) return false;
    return _compareValues(fieldValue, value) <= 0;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'LessThanOrEqualsQuery',
    'field': field,
    'value': value,
  };
}

/// Query to check if a field's value falls within a range.
///
/// By default, the range is inclusive on both ends.
///
/// ## Example
///
/// ```dart
/// final query = BetweenQuery('age', 18, 65);
/// // Matches entities where 18 <= age <= 65
/// ```
@immutable
class BetweenQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The lower bound of the range.
  final dynamic lowerBound;

  /// The upper bound of the range.
  final dynamic upperBound;

  /// Whether to include the lower bound in the range.
  final bool includeLower;

  /// Whether to include the upper bound in the range.
  final bool includeUpper;

  /// Creates a [BetweenQuery] for the given [field] and range.
  const BetweenQuery(
    this.field,
    this.lowerBound,
    this.upperBound, {
    this.includeLower = true,
    this.includeUpper = true,
  });

  factory BetweenQuery._fromMap(Map<String, dynamic> map) {
    return BetweenQuery(
      map['field'] as String,
      map['lowerBound'],
      map['upperBound'],
      includeLower: map['includeLower'] as bool? ?? true,
      includeUpper: map['includeUpper'] as bool? ?? true,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue == null) return false;

    final lowerComparison = _compareValues(fieldValue, lowerBound);
    final upperComparison = _compareValues(fieldValue, upperBound);

    final meetsLower = includeLower
        ? lowerComparison >= 0
        : lowerComparison > 0;
    final meetsUpper = includeUpper
        ? upperComparison <= 0
        : upperComparison < 0;

    return meetsLower && meetsUpper;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'BetweenQuery',
    'field': field,
    'lowerBound': lowerBound,
    'upperBound': upperBound,
    'includeLower': includeLower,
    'includeUpper': includeUpper,
  };
}

/// Query to check if a field's value exists within a list of values.
///
/// ## Example
///
/// ```dart
/// final query = InQuery('status', ['active', 'pending', 'review']);
/// ```
@immutable
class InQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The list of acceptable values.
  final List<dynamic> values;

  /// Creates an [InQuery] for the given [field] and [values].
  const InQuery(this.field, this.values);

  factory InQuery._fromMap(Map<String, dynamic> map) {
    return InQuery(
      map['field'] as String,
      List<dynamic>.from(map['values'] as List),
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return values.any((v) => _deepEquals(fieldValue, v));
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'InQuery',
    'field': field,
    'values': values,
  };
}

/// Query to check if a field's value does not exist within a list of values.
///
/// The logical negation of [InQuery].
@immutable
class NotInQuery implements IQuery {
  /// The field name to compare.
  final String field;

  /// The list of values that the field should not match.
  final List<dynamic> values;

  /// Creates a [NotInQuery] for the given [field] and [values].
  const NotInQuery(this.field, this.values);

  factory NotInQuery._fromMap(Map<String, dynamic> map) {
    return NotInQuery(
      map['field'] as String,
      List<dynamic>.from(map['values'] as List),
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return !values.any((v) => _deepEquals(fieldValue, v));
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'NotInQuery',
    'field': field,
    'values': values,
  };
}

/// Query to match a field's string value against a regular expression.
///
/// ## Example
///
/// ```dart
/// final query = RegexQuery('email', r'^[a-z]+@example\.com$');
/// ```
@immutable
class RegexQuery implements IQuery {
  /// The field name to match.
  final String field;

  /// The regular expression pattern.
  final RegExp pattern;

  /// Creates a [RegexQuery] for the given [field] and [pattern].
  RegexQuery(this.field, this.pattern);

  /// Creates a [RegexQuery] from a pattern string.
  factory RegexQuery.fromPattern(
    String field,
    String pattern, {
    bool caseSensitive = true,
    bool multiLine = false,
  }) {
    return RegexQuery(
      field,
      RegExp(pattern, caseSensitive: caseSensitive, multiLine: multiLine),
    );
  }

  factory RegexQuery._fromMap(Map<String, dynamic> map) {
    return RegexQuery(
      map['field'] as String,
      RegExp(
        map['pattern'] as String,
        caseSensitive: map['caseSensitive'] as bool? ?? true,
        multiLine: map['multiLine'] as bool? ?? false,
      ),
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;
    return pattern.hasMatch(fieldValue);
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'RegexQuery',
    'field': field,
    'pattern': pattern.pattern,
    'caseSensitive': pattern.isCaseSensitive,
    'multiLine': pattern.isMultiLine,
  };
}

/// Query to check if a field exists in the data map.
///
/// ## Example
///
/// ```dart
/// final query = ExistsQuery('email');
/// // Matches entities that have an 'email' field (even if null)
/// ```
@immutable
class ExistsQuery implements IQuery {
  /// The field name to check for existence.
  final String field;

  /// Creates an [ExistsQuery] for the given [field].
  const ExistsQuery(this.field);

  factory ExistsQuery._fromMap(Map<String, dynamic> map) {
    return ExistsQuery(map['field'] as String);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    return _fieldExists(data, field);
  }

  @override
  Map<String, dynamic> toMap() => {'type': 'ExistsQuery', 'field': field};
}

/// Query to check if a field's value is null.
@immutable
class IsNullQuery implements IQuery {
  /// The field name to check.
  final String field;

  /// Creates an [IsNullQuery] for the given [field].
  const IsNullQuery(this.field);

  factory IsNullQuery._fromMap(Map<String, dynamic> map) {
    return IsNullQuery(map['field'] as String);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return fieldValue == null;
  }

  @override
  Map<String, dynamic> toMap() => {'type': 'IsNullQuery', 'field': field};
}

/// Query to check if a field's value is not null.
@immutable
class IsNotNullQuery implements IQuery {
  /// The field name to check.
  final String field;

  /// Creates an [IsNotNullQuery] for the given [field].
  const IsNotNullQuery(this.field);

  factory IsNotNullQuery._fromMap(Map<String, dynamic> map) {
    return IsNotNullQuery(map['field'] as String);
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    return fieldValue != null;
  }

  @override
  Map<String, dynamic> toMap() => {'type': 'IsNotNullQuery', 'field': field};
}

/// Query to check if a string or list field contains a value.
///
/// For strings, checks if the value is a substring.
/// For lists, checks if the list contains the value.
///
/// ## Example
///
/// ```dart
/// // String containment
/// final query = ContainsQuery('description', 'important');
///
/// // List containment
/// final query = ContainsQuery('tags', 'featured');
/// ```
@immutable
class ContainsQuery implements IQuery {
  /// The field name to check.
  final String field;

  /// The value to search for.
  final dynamic value;

  /// Whether string matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [ContainsQuery] for the given [field] and [value].
  const ContainsQuery(this.field, this.value, {this.caseSensitive = true});

  factory ContainsQuery._fromMap(Map<String, dynamic> map) {
    return ContainsQuery(
      map['field'] as String,
      map['value'],
      caseSensitive: map['caseSensitive'] as bool? ?? true,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);

    if (fieldValue is String && value is String) {
      if (caseSensitive) {
        return fieldValue.contains(value);
      }
      return fieldValue.toLowerCase().contains((value as String).toLowerCase());
    }

    if (fieldValue is List) {
      return fieldValue.any((item) => _deepEquals(item, value));
    }

    return false;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'ContainsQuery',
    'field': field,
    'value': value,
    'caseSensitive': caseSensitive,
  };
}

/// Query to check if a string field starts with a prefix.
@immutable
class StartsWithQuery implements IQuery {
  /// The field name to check.
  final String field;

  /// The prefix to match.
  final String prefix;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [StartsWithQuery] for the given [field] and [prefix].
  const StartsWithQuery(this.field, this.prefix, {this.caseSensitive = true});

  factory StartsWithQuery._fromMap(Map<String, dynamic> map) {
    return StartsWithQuery(
      map['field'] as String,
      map['prefix'] as String,
      caseSensitive: map['caseSensitive'] as bool? ?? true,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    if (caseSensitive) {
      return fieldValue.startsWith(prefix);
    }
    return fieldValue.toLowerCase().startsWith(prefix.toLowerCase());
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'StartsWithQuery',
    'field': field,
    'prefix': prefix,
    'caseSensitive': caseSensitive,
  };
}

/// Query to check if a string field ends with a suffix.
@immutable
class EndsWithQuery implements IQuery {
  /// The field name to check.
  final String field;

  /// The suffix to match.
  final String suffix;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates an [EndsWithQuery] for the given [field] and [suffix].
  const EndsWithQuery(this.field, this.suffix, {this.caseSensitive = true});

  factory EndsWithQuery._fromMap(Map<String, dynamic> map) {
    return EndsWithQuery(
      map['field'] as String,
      map['suffix'] as String,
      caseSensitive: map['caseSensitive'] as bool? ?? true,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    if (caseSensitive) {
      return fieldValue.endsWith(suffix);
    }
    return fieldValue.toLowerCase().endsWith(suffix.toLowerCase());
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'EndsWithQuery',
    'field': field,
    'suffix': suffix,
    'caseSensitive': caseSensitive,
  };
}

// ---------------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------------

/// Gets a nested field value using dot notation.
///
/// Example: `_getNestedField(data, 'address.city')` returns `data['address']['city']`
dynamic _getNestedField(Map<String, dynamic> data, String field) {
  final parts = field.split('.');
  dynamic current = data;

  for (final part in parts) {
    if (current is! Map<String, dynamic>) {
      return null;
    }
    if (!current.containsKey(part)) {
      return null;
    }
    current = current[part];
  }

  return current;
}

/// Checks if a nested field exists using dot notation.
bool _fieldExists(Map<String, dynamic> data, String field) {
  final parts = field.split('.');
  dynamic current = data;

  for (int i = 0; i < parts.length; i++) {
    if (current is! Map<String, dynamic>) {
      return false;
    }
    if (!current.containsKey(parts[i])) {
      return false;
    }
    current = current[parts[i]];
  }

  return true;
}

/// Deep equality check that handles lists and maps.
bool _deepEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.runtimeType != b.runtimeType) return false;

  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }

  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }

  return a == b;
}

/// Compares two values for ordering.
///
/// Returns negative if a < b, zero if a == b, positive if a > b.
/// Handles numbers, strings, DateTime, and other Comparable types.
int _compareValues(dynamic a, dynamic b) {
  // Handle nulls
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;

  // Handle numbers (int and double can be compared)
  if (a is num && b is num) {
    return a.compareTo(b);
  }

  // Handle strings
  if (a is String && b is String) {
    return a.compareTo(b);
  }

  // Handle DateTime
  if (a is DateTime && b is DateTime) {
    return a.compareTo(b);
  }

  // Handle other Comparable types
  if (a is Comparable && b is Comparable) {
    try {
      return Comparable.compare(a, b);
    } catch (_) {
      // Types are not comparable
      return 0;
    }
  }

  // Cannot compare, treat as equal
  return 0;
}

// =============================================================================
// Full-Text Search Query Types
// =============================================================================

/// Query for full-text search matching all terms (AND semantics).
///
/// This query tokenizes the search text and matches documents containing
/// all the search terms. Designed to be used with [FullTextIndex].
///
/// ## Example
///
/// ```dart
/// final query = FullTextQuery('content', 'quick brown fox');
/// // Matches documents where 'content' contains all: quick, brown, fox
/// ```
@immutable
class FullTextQuery implements IQuery {
  /// The field name to search in.
  final String field;

  /// The search text (will be tokenized).
  final String searchText;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [FullTextQuery] for the given [field] and [searchText].
  const FullTextQuery(
    this.field,
    this.searchText, {
    this.caseSensitive = false,
  });

  factory FullTextQuery._fromMap(Map<String, dynamic> map) {
    return FullTextQuery(
      map['field'] as String,
      map['searchText'] as String,
      caseSensitive: map['caseSensitive'] as bool? ?? false,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    // Tokenize both field value and search text
    final normalizedField = caseSensitive
        ? fieldValue
        : fieldValue.toLowerCase();
    final normalizedSearch = caseSensitive
        ? searchText
        : searchText.toLowerCase();

    final searchTerms = _tokenize(normalizedSearch);
    if (searchTerms.isEmpty) return true;

    // Check if all search terms appear in the field
    for (final term in searchTerms) {
      if (!normalizedField.contains(term)) {
        return false;
      }
    }

    return true;
  }

  /// Simple tokenization by whitespace and punctuation.
  static List<String> _tokenize(String text) {
    return text
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .where((t) => t.length >= 2)
        .toList();
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'FullTextQuery',
    'field': field,
    'searchText': searchText,
    'caseSensitive': caseSensitive,
  };
}

/// Query for full-text phrase search (exact sequence of words).
///
/// Matches documents containing the exact phrase (words in sequence).
/// Designed to be used with [FullTextIndex] with position tracking enabled.
///
/// ## Example
///
/// ```dart
/// final query = FullTextPhraseQuery('content', 'quick brown');
/// // Matches "the quick brown fox" but not "brown quick fox"
/// ```
@immutable
class FullTextPhraseQuery implements IQuery {
  /// The field name to search in.
  final String field;

  /// The exact phrase to search for.
  final String phrase;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [FullTextPhraseQuery] for the given [field] and [phrase].
  const FullTextPhraseQuery(
    this.field,
    this.phrase, {
    this.caseSensitive = false,
  });

  factory FullTextPhraseQuery._fromMap(Map<String, dynamic> map) {
    return FullTextPhraseQuery(
      map['field'] as String,
      map['phrase'] as String,
      caseSensitive: map['caseSensitive'] as bool? ?? false,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    final normalizedField = caseSensitive
        ? fieldValue
        : fieldValue.toLowerCase();
    final normalizedPhrase = caseSensitive ? phrase : phrase.toLowerCase();

    return normalizedField.contains(normalizedPhrase);
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'FullTextPhraseQuery',
    'field': field,
    'phrase': phrase,
    'caseSensitive': caseSensitive,
  };
}

/// Query for full-text search matching any term (OR semantics).
///
/// Matches documents containing at least one of the search terms.
/// Designed to be used with [FullTextIndex].
///
/// ## Example
///
/// ```dart
/// final query = FullTextAnyQuery('content', ['quick', 'slow']);
/// // Matches documents containing 'quick' OR 'slow'
/// ```
@immutable
class FullTextAnyQuery implements IQuery {
  /// The field name to search in.
  final String field;

  /// The list of terms to search for.
  final List<String> terms;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [FullTextAnyQuery] for the given [field] and [terms].
  const FullTextAnyQuery(this.field, this.terms, {this.caseSensitive = false});

  factory FullTextAnyQuery._fromMap(Map<String, dynamic> map) {
    return FullTextAnyQuery(
      map['field'] as String,
      (map['terms'] as List).cast<String>(),
      caseSensitive: map['caseSensitive'] as bool? ?? false,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    if (terms.isEmpty) return true;

    final normalizedField = caseSensitive
        ? fieldValue
        : fieldValue.toLowerCase();

    for (final term in terms) {
      final normalizedTerm = caseSensitive ? term : term.toLowerCase();
      if (normalizedField.contains(normalizedTerm)) {
        return true;
      }
    }

    return false;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'FullTextAnyQuery',
    'field': field,
    'terms': terms,
    'caseSensitive': caseSensitive,
  };
}

/// Query for full-text prefix search.
///
/// Matches documents containing terms starting with the given prefix.
/// Designed to be used with [FullTextIndex].
///
/// ## Example
///
/// ```dart
/// final query = FullTextPrefixQuery('content', 'qui');
/// // Matches "quick", "quiet", "quintessential"
/// ```
@immutable
class FullTextPrefixQuery implements IQuery {
  /// The field name to search in.
  final String field;

  /// The prefix to search for.
  final String prefix;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [FullTextPrefixQuery] for the given [field] and [prefix].
  const FullTextPrefixQuery(
    this.field,
    this.prefix, {
    this.caseSensitive = false,
  });

  factory FullTextPrefixQuery._fromMap(Map<String, dynamic> map) {
    return FullTextPrefixQuery(
      map['field'] as String,
      map['prefix'] as String,
      caseSensitive: map['caseSensitive'] as bool? ?? false,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    final normalizedField = caseSensitive
        ? fieldValue
        : fieldValue.toLowerCase();
    final normalizedPrefix = caseSensitive ? prefix : prefix.toLowerCase();

    // Tokenize the field and check if any token starts with prefix
    final tokens = normalizedField.split(RegExp(r'[\s\p{P}]+', unicode: true));
    for (final token in tokens) {
      if (token.startsWith(normalizedPrefix)) {
        return true;
      }
    }

    return false;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'FullTextPrefixQuery',
    'field': field,
    'prefix': prefix,
    'caseSensitive': caseSensitive,
  };
}

/// Query for full-text proximity search.
///
/// Matches documents where specified terms appear within a certain
/// distance of each other. Designed to be used with [FullTextIndex]
/// with position tracking enabled.
///
/// ## Example
///
/// ```dart
/// final query = FullTextProximityQuery('content', ['quick', 'fox'], 3);
/// // Matches "quick brown fox" (distance 2) but not "quick lazy brown dog fox"
/// ```
@immutable
class FullTextProximityQuery implements IQuery {
  /// The field name to search in.
  final String field;

  /// The terms that should appear near each other.
  final List<String> terms;

  /// Maximum number of words between terms.
  final int maxDistance;

  /// Whether matching should be case-sensitive.
  final bool caseSensitive;

  /// Creates a [FullTextProximityQuery].
  const FullTextProximityQuery(
    this.field,
    this.terms,
    this.maxDistance, {
    this.caseSensitive = false,
  });

  factory FullTextProximityQuery._fromMap(Map<String, dynamic> map) {
    return FullTextProximityQuery(
      map['field'] as String,
      (map['terms'] as List).cast<String>(),
      map['maxDistance'] as int,
      caseSensitive: map['caseSensitive'] as bool? ?? false,
    );
  }

  @override
  bool matches(Map<String, dynamic> data) {
    final fieldValue = _getNestedField(data, field);
    if (fieldValue is! String) return false;

    if (terms.length < 2) {
      // Need at least 2 terms for proximity
      return terms.isEmpty ||
          fieldValue.toLowerCase().contains(terms.first.toLowerCase());
    }

    final normalizedField = caseSensitive
        ? fieldValue
        : fieldValue.toLowerCase();

    // Tokenize the field
    final tokens = normalizedField
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .toList();

    // Find positions of each term
    final positions = <int, List<int>>{};
    for (var i = 0; i < terms.length; i++) {
      final normalizedTerm = caseSensitive ? terms[i] : terms[i].toLowerCase();
      positions[i] = [];
      for (var j = 0; j < tokens.length; j++) {
        if (tokens[j] == normalizedTerm) {
          positions[i]!.add(j);
        }
      }
      // If any term is not found, no match
      if (positions[i]!.isEmpty) return false;
    }

    // Check if all terms can appear within maxDistance
    return _checkProximity(positions, maxDistance);
  }

  /// Checks if all terms can appear within the proximity window.
  bool _checkProximity(Map<int, List<int>> positions, int maxDist) {
    // Use sliding window to check proximity
    final pointers = List<int>.filled(positions.length, 0);

    while (true) {
      // Get current positions for each term
      int minPos = positions[0]![pointers[0]];
      int maxPos = minPos;
      int minIdx = 0;

      for (var i = 1; i < positions.length; i++) {
        final pos = positions[i]![pointers[i]];
        if (pos < minPos) {
          minPos = pos;
          minIdx = i;
        }
        if (pos > maxPos) {
          maxPos = pos;
        }
      }

      // Check if current window satisfies proximity
      if (maxPos - minPos <= maxDist) {
        return true;
      }

      // Advance the pointer at minimum position
      pointers[minIdx]++;
      if (pointers[minIdx] >= positions[minIdx]!.length) {
        break;
      }
    }

    return false;
  }

  @override
  Map<String, dynamic> toMap() => {
    'type': 'FullTextProximityQuery',
    'field': field,
    'terms': terms,
    'maxDistance': maxDistance,
    'caseSensitive': caseSensitive,
  };
}
