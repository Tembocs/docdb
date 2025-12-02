/// Query module for DocDB.
///
/// This module provides a comprehensive query system for filtering entities
/// based on field values. Queries are constructed using a fluent builder API
/// and can be serialized for persistence or network transfer.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/query/query.dart';
///
/// // Build a simple query
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .whereGreaterThan('age', 18)
///     .build();
///
/// // Check if entity matches
/// final data = entity.toMap();
/// if (query.matches(data)) {
///   print('Entity matches the query');
/// }
/// ```
///
/// ## Query Types
///
/// The module provides various query types for different comparison needs:
///
/// | Query Type | Description | Example |
/// |------------|-------------|---------|
/// | [EqualsQuery] | Exact match | `status == 'active'` |
/// | [NotEqualsQuery] | Not equal | `status != 'deleted'` |
/// | [GreaterThanQuery] | Greater than | `age > 18` |
/// | [LessThanQuery] | Less than | `price < 100` |
/// | [BetweenQuery] | Range check | `18 <= age <= 65` |
/// | [InQuery] | Value in list | `status in ['a', 'b']` |
/// | [RegexQuery] | Pattern match | `email matches /@.*\.com$/` |
/// | [ContainsQuery] | Substring/element | `name contains 'John'` |
/// | [ExistsQuery] | Field exists | `email exists` |
/// | [IsNullQuery] | Null check | `deletedAt is null` |
///
/// ## Combining Queries
///
/// Use [AndQuery] and [OrQuery] to combine multiple conditions:
///
/// ```dart
/// // Using builder (AND by default)
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .whereGreaterThan('priority', 5)
///     .build();
///
/// // OR conditions
/// final query = QueryBuilder()
///     .whereEquals('status', 'active')
///     .or(EqualsQuery('status', 'pending'))
///     .build();
///
/// // Complex logic
/// final query = OrQuery([
///   AndQuery([EqualsQuery('a', 1), EqualsQuery('b', 2)]),
///   AndQuery([EqualsQuery('c', 3), EqualsQuery('d', 4)]),
/// ]);
/// ```
///
/// ## Nested Fields
///
/// Use dot notation for nested field access:
///
/// ```dart
/// final query = QueryBuilder()
///     .whereEquals('address.city', 'London')
///     .whereEquals('address.country', 'UK')
///     .build();
/// ```
///
/// ## Serialization
///
/// Queries can be serialized and deserialized:
///
/// ```dart
/// // Serialize
/// final map = query.toMap();
///
/// // Deserialize
/// final restored = IQuery.fromMap(map);
/// ```
library;

export 'query_builder.dart' show QueryBuilder;
export 'query_types.dart'
    show
        IQuery,
        AllQuery,
        EqualsQuery,
        NotEqualsQuery,
        AndQuery,
        OrQuery,
        NotQuery,
        GreaterThanQuery,
        GreaterThanOrEqualsQuery,
        LessThanQuery,
        LessThanOrEqualsQuery,
        BetweenQuery,
        InQuery,
        NotInQuery,
        RegexQuery,
        ExistsQuery,
        IsNullQuery,
        IsNotNullQuery,
        ContainsQuery,
        StartsWithQuery,
        EndsWithQuery;
