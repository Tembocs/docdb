import 'query_types.dart';

/// A builder class for constructing complex queries using a fluent interface.
///
/// The [QueryBuilder] provides a convenient way to construct queries
/// programmatically by chaining method calls.
///
/// ## Basic Usage
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .whereGreaterThan('age', 18)
///     .build();
/// ```
///
/// ## Combining Queries
///
/// Multiple conditions are combined with AND by default:
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')    // AND
///     .whereGreaterThan('priority', 5)    // AND
///     .whereLessThan('age', 65)
///     .build();
/// ```
///
/// Use [or] for OR conditions:
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .or(EqualsQuery('status', 'pending'))
///     .build();
/// ```
///
/// ## Nested Field Queries
///
/// Use dot notation for nested fields:
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('address.city', 'London')
///     .build();
/// ```
///
/// ## Complex Queries
///
/// For complex logic, compose queries manually:
///
/// ```dart
/// final query = OrQuery([
///   AndQuery([
///     EqualsQuery('status', 'active'),
///     GreaterThanQuery('priority', 5),
///   ]),
///   AndQuery([
///     EqualsQuery('status', 'urgent'),
///     EqualsQuery('assigned', true),
///   ]),
/// ]);
/// ```
class QueryBuilder {
  IQuery? _currentQuery;

  /// Adds an equality condition: field == value.
  ///
  /// ```dart
  /// builder.whereEquals('name', 'Alice');
  /// ```
  QueryBuilder whereEquals(String field, dynamic value) {
    return _addQuery(EqualsQuery(field, value));
  }

  /// Adds a not-equal condition: field != value.
  ///
  /// ```dart
  /// builder.whereNotEquals('status', 'deleted');
  /// ```
  QueryBuilder whereNotEquals(String field, dynamic value) {
    return _addQuery(NotEqualsQuery(field, value));
  }

  /// Adds a greater-than condition: field > value.
  ///
  /// ```dart
  /// builder.whereGreaterThan('age', 18);
  /// ```
  QueryBuilder whereGreaterThan(String field, dynamic value) {
    return _addQuery(GreaterThanQuery(field, value));
  }

  /// Adds a greater-than-or-equal condition: field >= value.
  ///
  /// ```dart
  /// builder.whereGreaterThanOrEquals('age', 18);
  /// ```
  QueryBuilder whereGreaterThanOrEquals(String field, dynamic value) {
    return _addQuery(GreaterThanOrEqualsQuery(field, value));
  }

  /// Adds a less-than condition: field < value.
  ///
  /// ```dart
  /// builder.whereLessThan('price', 100);
  /// ```
  QueryBuilder whereLessThan(String field, dynamic value) {
    return _addQuery(LessThanQuery(field, value));
  }

  /// Adds a less-than-or-equal condition: field <= value.
  ///
  /// ```dart
  /// builder.whereLessThanOrEquals('price', 100);
  /// ```
  QueryBuilder whereLessThanOrEquals(String field, dynamic value) {
    return _addQuery(LessThanOrEqualsQuery(field, value));
  }

  /// Adds a between condition: lowerBound <= field <= upperBound.
  ///
  /// By default, both bounds are inclusive.
  ///
  /// ```dart
  /// builder.whereBetween('age', 18, 65);
  /// builder.whereBetween('price', 10, 100, includeLower: false);
  /// ```
  QueryBuilder whereBetween(
    String field,
    dynamic lowerBound,
    dynamic upperBound, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return _addQuery(
      BetweenQuery(
        field,
        lowerBound,
        upperBound,
        includeLower: includeLower,
        includeUpper: includeUpper,
      ),
    );
  }

  /// Adds an IN condition: field in [values].
  ///
  /// ```dart
  /// builder.whereIn('status', ['active', 'pending', 'review']);
  /// ```
  QueryBuilder whereIn(String field, List<dynamic> values) {
    return _addQuery(InQuery(field, values));
  }

  /// Adds a NOT IN condition: field not in [values].
  ///
  /// ```dart
  /// builder.whereNotIn('status', ['deleted', 'archived']);
  /// ```
  QueryBuilder whereNotIn(String field, List<dynamic> values) {
    return _addQuery(NotInQuery(field, values));
  }

  /// Adds a regex condition: field matches pattern.
  ///
  /// ```dart
  /// builder.whereRegex('email', r'^[a-z]+@example\.com$');
  /// ```
  QueryBuilder whereRegex(
    String field,
    String pattern, {
    bool caseSensitive = true,
    bool multiLine = false,
  }) {
    return _addQuery(
      RegexQuery(
        field,
        RegExp(pattern, caseSensitive: caseSensitive, multiLine: multiLine),
      ),
    );
  }

  /// Adds a condition checking if a field exists.
  ///
  /// ```dart
  /// builder.whereExists('email');
  /// ```
  QueryBuilder whereExists(String field) {
    return _addQuery(ExistsQuery(field));
  }

  /// Adds a condition checking if a field is null.
  ///
  /// ```dart
  /// builder.whereIsNull('deletedAt');
  /// ```
  QueryBuilder whereIsNull(String field) {
    return _addQuery(IsNullQuery(field));
  }

  /// Adds a condition checking if a field is not null.
  ///
  /// ```dart
  /// builder.whereIsNotNull('email');
  /// ```
  QueryBuilder whereIsNotNull(String field) {
    return _addQuery(IsNotNullQuery(field));
  }

  /// Adds a contains condition for strings or lists.
  ///
  /// For strings: checks if field contains the substring.
  /// For lists: checks if field list contains the value.
  ///
  /// ```dart
  /// builder.whereContains('description', 'important');
  /// builder.whereContains('tags', 'featured');
  /// ```
  QueryBuilder whereContains(
    String field,
    dynamic value, {
    bool caseSensitive = true,
  }) {
    return _addQuery(ContainsQuery(field, value, caseSensitive: caseSensitive));
  }

  /// Adds a starts-with condition for string fields.
  ///
  /// ```dart
  /// builder.whereStartsWith('name', 'Dr.');
  /// ```
  QueryBuilder whereStartsWith(
    String field,
    String prefix, {
    bool caseSensitive = true,
  }) {
    return _addQuery(
      StartsWithQuery(field, prefix, caseSensitive: caseSensitive),
    );
  }

  /// Adds an ends-with condition for string fields.
  ///
  /// ```dart
  /// builder.whereEndsWith('email', '@example.com');
  /// ```
  QueryBuilder whereEndsWith(
    String field,
    String suffix, {
    bool caseSensitive = true,
  }) {
    return _addQuery(
      EndsWithQuery(field, suffix, caseSensitive: caseSensitive),
    );
  }

  // ===========================================================================
  // Full-Text Search Methods
  // ===========================================================================

  /// Adds a full-text search condition matching ALL terms (AND semantics).
  ///
  /// The search text is tokenized, and documents must contain all terms.
  /// Best used with a full-text index on the field for optimal performance.
  ///
  /// ```dart
  /// builder.whereFullText('description', 'quick brown fox');
  /// // Matches documents containing all: quick, brown, fox
  /// ```
  QueryBuilder whereFullText(
    String field,
    String searchText, {
    bool caseSensitive = false,
  }) {
    return _addQuery(
      FullTextQuery(field, searchText, caseSensitive: caseSensitive),
    );
  }

  /// Adds a full-text phrase search condition (exact sequence).
  ///
  /// Matches documents containing the exact phrase.
  /// Best used with a full-text index with position tracking.
  ///
  /// ```dart
  /// builder.whereFullTextPhrase('content', 'quick brown');
  /// // Matches "the quick brown fox" but not "brown quick fox"
  /// ```
  QueryBuilder whereFullTextPhrase(
    String field,
    String phrase, {
    bool caseSensitive = false,
  }) {
    return _addQuery(
      FullTextPhraseQuery(field, phrase, caseSensitive: caseSensitive),
    );
  }

  /// Adds a full-text search condition matching ANY term (OR semantics).
  ///
  /// Matches documents containing at least one of the terms.
  /// Best used with a full-text index on the field.
  ///
  /// ```dart
  /// builder.whereFullTextAny('tags', ['urgent', 'important']);
  /// // Matches documents containing 'urgent' OR 'important'
  /// ```
  QueryBuilder whereFullTextAny(
    String field,
    List<String> terms, {
    bool caseSensitive = false,
  }) {
    return _addQuery(
      FullTextAnyQuery(field, terms, caseSensitive: caseSensitive),
    );
  }

  /// Adds a full-text prefix search condition.
  ///
  /// Matches documents containing terms starting with the prefix.
  /// Best used with a full-text index on the field.
  ///
  /// ```dart
  /// builder.whereFullTextPrefix('content', 'qui');
  /// // Matches documents with "quick", "quiet", "quintessential"
  /// ```
  QueryBuilder whereFullTextPrefix(
    String field,
    String prefix, {
    bool caseSensitive = false,
  }) {
    return _addQuery(
      FullTextPrefixQuery(field, prefix, caseSensitive: caseSensitive),
    );
  }

  /// Adds a full-text proximity search condition.
  ///
  /// Matches documents where terms appear within [maxDistance] of each other.
  /// Best used with a full-text index with position tracking.
  ///
  /// ```dart
  /// builder.whereFullTextProximity('content', ['quick', 'fox'], 3);
  /// // Matches "quick brown fox" but not "quick lazy brown dog fox"
  /// ```
  QueryBuilder whereFullTextProximity(
    String field,
    List<String> terms,
    int maxDistance, {
    bool caseSensitive = false,
  }) {
    return _addQuery(
      FullTextProximityQuery(
        field,
        terms,
        maxDistance,
        caseSensitive: caseSensitive,
      ),
    );
  }

  /// Negates a query.
  ///
  /// ```dart
  /// builder.whereNot(EqualsQuery('status', 'deleted'));
  /// ```
  QueryBuilder whereNot(IQuery query) {
    return _addQuery(NotQuery(query));
  }

  /// Combines the current query with another using AND.
  ///
  /// ```dart
  /// builder.whereEquals('active', true).and(customQuery);
  /// ```
  QueryBuilder and(IQuery query) {
    return _addQuery(query);
  }

  /// Combines the current query with another using OR.
  ///
  /// ```dart
  /// builder.whereEquals('status', 'active')
  ///        .or(EqualsQuery('status', 'pending'));
  /// ```
  QueryBuilder or(IQuery query) {
    if (_currentQuery == null) {
      _currentQuery = query;
    } else {
      _currentQuery = OrQuery([_currentQuery!, query]);
    }
    return this;
  }

  /// Combines the current query with multiple queries using OR.
  ///
  /// ```dart
  /// builder.orAll([
  ///   EqualsQuery('status', 'active'),
  ///   EqualsQuery('status', 'pending'),
  ///   EqualsQuery('status', 'review'),
  /// ]);
  /// ```
  QueryBuilder orAll(List<IQuery> queries) {
    if (queries.isEmpty) return this;

    final allQueries = _currentQuery != null
        ? [_currentQuery!, ...queries]
        : queries;

    if (allQueries.length == 1) {
      _currentQuery = allQueries.first;
    } else {
      _currentQuery = OrQuery(allQueries);
    }
    return this;
  }

  /// Builds and returns the final query.
  ///
  /// Throws [StateError] if no query conditions have been added.
  IQuery build() {
    if (_currentQuery == null) {
      throw StateError(
        'No query conditions have been added. '
        'Use whereEquals, whereGreaterThan, etc. to add conditions.',
      );
    }
    return _currentQuery!;
  }

  /// Builds the query or returns [AllQuery] if no conditions were added.
  ///
  /// Use this when you want to match all entities as a fallback.
  IQuery buildOrAll() {
    return _currentQuery ?? const AllQuery();
  }

  /// Resets the builder to its initial state.
  ///
  /// Returns this builder for chaining.
  QueryBuilder reset() {
    _currentQuery = null;
    return this;
  }

  /// Returns true if at least one condition has been added.
  bool get hasConditions => _currentQuery != null;

  /// Serializes the current query for debugging or logging.
  ///
  /// Throws [StateError] if no query conditions have been added.
  Map<String, dynamic> toMap() {
    if (_currentQuery == null) {
      throw StateError('No query conditions have been added.');
    }
    return _currentQuery!.toMap();
  }

  /// Internal helper to add a query with AND logic.
  QueryBuilder _addQuery(IQuery query) {
    if (_currentQuery == null) {
      _currentQuery = query;
    } else {
      _currentQuery = AndQuery([_currentQuery!, query]);
    }
    return this;
  }
}
