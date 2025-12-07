/// Query result cache for DocDB.
///
/// This module provides caching of query results with:
/// - Time-to-live (TTL) expiration
/// - LRU (Least Recently Used) eviction
/// - Automatic invalidation on collection mutations
/// - Field-based selective cache invalidation
/// - Configurable cache size
///
/// ## Overview
///
/// Query caching improves performance by storing results of expensive queries
/// and returning cached results for identical subsequent queries. The cache
/// automatically invalidates entries when underlying data changes.
///
/// ## Usage
///
/// ```dart
/// final cache = QueryCache<Product>(
///   maxSize: 100,
///   defaultTtl: Duration(minutes: 5),
/// );
///
/// // Cache a query result
/// cache.put(query, results);
///
/// // Get cached result (returns null if expired or not cached)
/// final cached = cache.get(query);
///
/// // Invalidate on mutation
/// cache.invalidateField('price'); // Invalidates queries using price field
/// cache.invalidateAll(); // Clears entire cache
/// ```
library;

import 'dart:collection';
import 'package:meta/meta.dart';

import '../entity/entity.dart';
import 'query_types.dart';

/// Configuration for query cache behavior.
@immutable
class QueryCacheConfig {
  /// Maximum number of cached query results.
  ///
  /// When exceeded, least recently used entries are evicted.
  final int maxSize;

  /// Default time-to-live for cached entries.
  ///
  /// Entries older than this duration are considered expired and
  /// will be removed on next access or cleanup.
  final Duration defaultTtl;

  /// Whether to track fields used by queries for selective invalidation.
  ///
  /// When true, mutations only invalidate queries that use affected fields.
  /// When false, all mutations invalidate the entire cache.
  final bool enableSelectiveInvalidation;

  /// Whether to collect cache statistics.
  final bool collectStatistics;

  /// Creates a query cache configuration.
  const QueryCacheConfig({
    this.maxSize = 100,
    this.defaultTtl = const Duration(minutes: 5),
    this.enableSelectiveInvalidation = true,
    this.collectStatistics = true,
  });

  /// Creates a copy with the specified values changed.
  QueryCacheConfig copyWith({
    int? maxSize,
    Duration? defaultTtl,
    bool? enableSelectiveInvalidation,
    bool? collectStatistics,
  }) {
    return QueryCacheConfig(
      maxSize: maxSize ?? this.maxSize,
      defaultTtl: defaultTtl ?? this.defaultTtl,
      enableSelectiveInvalidation:
          enableSelectiveInvalidation ?? this.enableSelectiveInvalidation,
      collectStatistics: collectStatistics ?? this.collectStatistics,
    );
  }

  @override
  String toString() {
    return 'QueryCacheConfig(maxSize: $maxSize, '
        'defaultTtl: $defaultTtl, '
        'selectiveInvalidation: $enableSelectiveInvalidation, '
        'collectStatistics: $collectStatistics)';
  }
}

/// Statistics about cache performance.
@immutable
class CacheStatistics {
  /// Number of cache hits (queries served from cache).
  final int hits;

  /// Number of cache misses (queries requiring execution).
  final int misses;

  /// Number of entries evicted due to size limits.
  final int evictions;

  /// Number of entries expired due to TTL.
  final int expirations;

  /// Number of invalidations triggered by mutations.
  final int invalidations;

  /// Current number of entries in cache.
  final int size;

  /// Cache hit ratio (0.0 to 1.0).
  double get hitRatio {
    final total = hits + misses;
    if (total == 0) return 0.0;
    return hits / total;
  }

  /// Creates cache statistics.
  const CacheStatistics({
    this.hits = 0,
    this.misses = 0,
    this.evictions = 0,
    this.expirations = 0,
    this.invalidations = 0,
    this.size = 0,
  });

  /// Creates a copy with incremented hit count.
  CacheStatistics incrementHits() => CacheStatistics(
    hits: hits + 1,
    misses: misses,
    evictions: evictions,
    expirations: expirations,
    invalidations: invalidations,
    size: size,
  );

  /// Creates a copy with incremented miss count.
  CacheStatistics incrementMisses() => CacheStatistics(
    hits: hits,
    misses: misses + 1,
    evictions: evictions,
    expirations: expirations,
    invalidations: invalidations,
    size: size,
  );

  /// Creates a copy with incremented eviction count.
  CacheStatistics incrementEvictions([int count = 1]) => CacheStatistics(
    hits: hits,
    misses: misses,
    evictions: evictions + count,
    expirations: expirations,
    invalidations: invalidations,
    size: size,
  );

  /// Creates a copy with incremented expiration count.
  CacheStatistics incrementExpirations([int count = 1]) => CacheStatistics(
    hits: hits,
    misses: misses,
    evictions: evictions,
    expirations: expirations + count,
    invalidations: invalidations,
    size: size,
  );

  /// Creates a copy with incremented invalidation count.
  CacheStatistics incrementInvalidations([int count = 1]) => CacheStatistics(
    hits: hits,
    misses: misses,
    evictions: evictions,
    expirations: expirations,
    invalidations: invalidations + count,
    size: size,
  );

  /// Creates a copy with updated size.
  CacheStatistics withSize(int newSize) => CacheStatistics(
    hits: hits,
    misses: misses,
    evictions: evictions,
    expirations: expirations,
    invalidations: invalidations,
    size: newSize,
  );

  @override
  String toString() {
    return 'CacheStatistics('
        'hits: $hits, misses: $misses, '
        'hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%, '
        'evictions: $evictions, expirations: $expirations, '
        'invalidations: $invalidations, size: $size)';
  }
}

/// A cached query result entry.
class _CacheEntry<T> {
  /// The cached entities.
  final List<T> results;

  /// When this entry was created.
  final DateTime createdAt;

  /// When this entry expires.
  final DateTime expiresAt;

  /// Fields used by the query (for selective invalidation).
  final Set<String> fields;

  /// Whether this entry has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Creates a cache entry.
  _CacheEntry({
    required this.results,
    required Duration ttl,
    required this.fields,
  }) : createdAt = DateTime.now(),
       expiresAt = DateTime.now().add(ttl);
}

/// A cache for query results with TTL and LRU eviction.
///
/// The cache stores results of previous queries and returns them
/// for identical subsequent queries, improving performance for
/// repeated or expensive queries.
///
/// ## Features
///
/// - **TTL Expiration**: Entries automatically expire after a configurable duration
/// - **LRU Eviction**: Least recently used entries are evicted when cache is full
/// - **Selective Invalidation**: Only invalidate queries affected by mutations
/// - **Field Tracking**: Track which fields each query depends on
/// - **Statistics**: Monitor cache performance with hit/miss ratios
///
/// ## Thread Safety
///
/// This class is NOT thread-safe. External synchronization is required
/// when accessed from multiple isolates or concurrent operations.
class QueryCache<T extends Entity> {
  /// The cache configuration.
  final QueryCacheConfig config;

  /// Cache entries, ordered by access time (most recent last).
  final LinkedHashMap<String, _CacheEntry<T>> _cache = LinkedHashMap();

  /// Index of queries by field for selective invalidation.
  final Map<String, Set<String>> _fieldToQueryKeys = {};

  /// Current cache statistics.
  CacheStatistics _statistics = const CacheStatistics();

  /// Creates a query cache with the given configuration.
  QueryCache({QueryCacheConfig? config})
    : config = config ?? const QueryCacheConfig();

  /// Creates a query cache with individual parameters.
  factory QueryCache.withParams({
    int maxSize = 100,
    Duration defaultTtl = const Duration(minutes: 5),
    bool enableSelectiveInvalidation = true,
    bool collectStatistics = true,
  }) {
    return QueryCache(
      config: QueryCacheConfig(
        maxSize: maxSize,
        defaultTtl: defaultTtl,
        enableSelectiveInvalidation: enableSelectiveInvalidation,
        collectStatistics: collectStatistics,
      ),
    );
  }

  /// Current cache statistics.
  CacheStatistics get statistics => _statistics.withSize(_cache.length);

  /// Number of entries currently in the cache.
  int get size => _cache.length;

  /// Whether the cache is empty.
  bool get isEmpty => _cache.isEmpty;

  /// Whether the cache is not empty.
  bool get isNotEmpty => _cache.isNotEmpty;

  /// Generates a cache key for a query.
  ///
  /// The key is based on the query's structure so that identical
  /// queries produce the same key.
  String _generateKey(IQuery query) {
    return query.toMap().toString().hashCode.toRadixString(16);
  }

  /// Extracts the fields used by a query for selective invalidation.
  Set<String> _extractFields(IQuery query) {
    final fields = <String>{};
    _collectFields(query, fields);
    return fields;
  }

  /// Recursively collects field names from a query.
  void _collectFields(IQuery query, Set<String> fields) {
    if (query is EqualsQuery) {
      fields.add(query.field);
    } else if (query is NotEqualsQuery) {
      fields.add(query.field);
    } else if (query is GreaterThanQuery) {
      fields.add(query.field);
    } else if (query is GreaterThanOrEqualsQuery) {
      fields.add(query.field);
    } else if (query is LessThanQuery) {
      fields.add(query.field);
    } else if (query is LessThanOrEqualsQuery) {
      fields.add(query.field);
    } else if (query is BetweenQuery) {
      fields.add(query.field);
    } else if (query is InQuery) {
      fields.add(query.field);
    } else if (query is NotInQuery) {
      fields.add(query.field);
    } else if (query is ContainsQuery) {
      fields.add(query.field);
    } else if (query is StartsWithQuery) {
      fields.add(query.field);
    } else if (query is EndsWithQuery) {
      fields.add(query.field);
    } else if (query is RegexQuery) {
      fields.add(query.field);
    } else if (query is ExistsQuery) {
      fields.add(query.field);
    } else if (query is IsNullQuery) {
      fields.add(query.field);
    } else if (query is FullTextQuery) {
      fields.add(query.field);
    } else if (query is FullTextAnyQuery) {
      fields.add(query.field);
    } else if (query is FullTextPhraseQuery) {
      fields.add(query.field);
    } else if (query is FullTextPrefixQuery) {
      fields.add(query.field);
    } else if (query is FullTextProximityQuery) {
      fields.add(query.field);
    } else if (query is AndQuery) {
      for (final subQuery in query.queries) {
        _collectFields(subQuery, fields);
      }
    } else if (query is OrQuery) {
      for (final subQuery in query.queries) {
        _collectFields(subQuery, fields);
      }
    } else if (query is NotQuery) {
      _collectFields(query.query, fields);
    }
    // AllQuery doesn't reference specific fields
  }

  /// Gets a cached result for the given query.
  ///
  /// Returns null if the query is not cached or has expired.
  /// Updates access time for LRU tracking on successful retrieval.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to look up.
  ///
  /// ## Returns
  ///
  /// A copy of the cached results, or null if not cached/expired.
  List<T>? get(IQuery query) {
    final key = _generateKey(query);
    final entry = _cache[key];

    if (entry == null) {
      if (config.collectStatistics) {
        _statistics = _statistics.incrementMisses();
      }
      return null;
    }

    // Check TTL expiration
    if (entry.isExpired) {
      _removeEntry(key);
      if (config.collectStatistics) {
        _statistics = _statistics.incrementExpirations();
        _statistics = _statistics.incrementMisses();
      }
      return null;
    }

    // Update access order for LRU (move to end)
    _cache.remove(key);
    _cache[key] = entry;

    if (config.collectStatistics) {
      _statistics = _statistics.incrementHits();
    }

    // Return a copy to prevent external modification
    return List.unmodifiable(entry.results);
  }

  /// Caches a query result.
  ///
  /// If the cache is full, the least recently used entry is evicted.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query whose results are being cached.
  /// - [results]: The query results to cache.
  /// - [ttl]: Optional TTL override. Uses default TTL if not specified.
  void put(IQuery query, List<T> results, {Duration? ttl}) {
    final key = _generateKey(query);
    final effectiveTtl = ttl ?? config.defaultTtl;

    // Extract fields for selective invalidation
    final fields = config.enableSelectiveInvalidation
        ? _extractFields(query)
        : <String>{};

    // Create new entry
    final entry = _CacheEntry<T>(
      results: List.unmodifiable(results),
      ttl: effectiveTtl,
      fields: fields,
    );

    // Remove existing entry if present (to update access order)
    if (_cache.containsKey(key)) {
      _removeEntry(key);
    }

    // Evict if at capacity
    while (_cache.length >= config.maxSize) {
      _evictLru();
    }

    // Add new entry
    _cache[key] = entry;

    // Register fields for selective invalidation
    if (config.enableSelectiveInvalidation) {
      for (final field in fields) {
        _fieldToQueryKeys.putIfAbsent(field, () => {}).add(key);
      }
    }
  }

  /// Evicts the least recently used entry.
  void _evictLru() {
    if (_cache.isEmpty) return;

    final key = _cache.keys.first;
    _removeEntry(key);

    if (config.collectStatistics) {
      _statistics = _statistics.incrementEvictions();
    }
  }

  /// Removes an entry and cleans up field indexes.
  void _removeEntry(String key) {
    final entry = _cache.remove(key);
    if (entry == null) return;

    // Clean up field index
    if (config.enableSelectiveInvalidation) {
      for (final field in entry.fields) {
        _fieldToQueryKeys[field]?.remove(key);
        if (_fieldToQueryKeys[field]?.isEmpty ?? false) {
          _fieldToQueryKeys.remove(field);
        }
      }
    }
  }

  /// Invalidates all cached entries for queries using the specified field.
  ///
  /// This should be called when a field's value changes due to
  /// insert, update, or delete operations.
  ///
  /// ## Parameters
  ///
  /// - [field]: The field that was modified.
  ///
  /// ## Returns
  ///
  /// The number of entries invalidated.
  int invalidateField(String field) {
    if (!config.enableSelectiveInvalidation) {
      return invalidateAll();
    }

    final keys = _fieldToQueryKeys[field];
    if (keys == null || keys.isEmpty) {
      return 0;
    }

    final keysToRemove = keys.toList();
    var count = 0;

    for (final key in keysToRemove) {
      if (_cache.containsKey(key)) {
        _removeEntry(key);
        count++;
      }
    }

    if (config.collectStatistics && count > 0) {
      _statistics = _statistics.incrementInvalidations(count);
    }

    return count;
  }

  /// Invalidates all cached entries for queries using any of the specified fields.
  ///
  /// ## Parameters
  ///
  /// - [fields]: The fields that were modified.
  ///
  /// ## Returns
  ///
  /// The number of entries invalidated.
  int invalidateFields(Set<String> fields) {
    if (!config.enableSelectiveInvalidation) {
      return invalidateAll();
    }

    final keysToRemove = <String>{};

    for (final field in fields) {
      final keys = _fieldToQueryKeys[field];
      if (keys != null) {
        keysToRemove.addAll(keys);
      }
    }

    var count = 0;
    for (final key in keysToRemove) {
      if (_cache.containsKey(key)) {
        _removeEntry(key);
        count++;
      }
    }

    if (config.collectStatistics && count > 0) {
      _statistics = _statistics.incrementInvalidations(count);
    }

    return count;
  }

  /// Invalidates a specific cached query.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to invalidate.
  ///
  /// ## Returns
  ///
  /// True if the query was cached and was removed.
  bool invalidateQuery(IQuery query) {
    final key = _generateKey(query);
    if (!_cache.containsKey(key)) {
      return false;
    }

    _removeEntry(key);

    if (config.collectStatistics) {
      _statistics = _statistics.incrementInvalidations();
    }

    return true;
  }

  /// Invalidates all cached entries.
  ///
  /// This is called when a mutation cannot be selectively traced
  /// to specific fields, or when the cache needs to be completely reset.
  ///
  /// ## Returns
  ///
  /// The number of entries that were invalidated.
  int invalidateAll() {
    final count = _cache.length;

    _cache.clear();
    _fieldToQueryKeys.clear();

    if (config.collectStatistics && count > 0) {
      _statistics = _statistics.incrementInvalidations(count);
    }

    return count;
  }

  /// Removes all expired entries from the cache.
  ///
  /// This is called periodically or on demand to clean up
  /// stale entries and free memory.
  ///
  /// ## Returns
  ///
  /// The number of expired entries removed.
  int removeExpired() {
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _removeEntry(key);
    }

    if (config.collectStatistics && keysToRemove.isNotEmpty) {
      _statistics = _statistics.incrementExpirations(keysToRemove.length);
    }

    return keysToRemove.length;
  }

  /// Checks if a query is currently cached and valid.
  ///
  /// ## Parameters
  ///
  /// - [query]: The query to check.
  ///
  /// ## Returns
  ///
  /// True if the query has a valid (non-expired) cache entry.
  bool containsQuery(IQuery query) {
    final key = _generateKey(query);
    final entry = _cache[key];
    return entry != null && !entry.isExpired;
  }

  /// Clears all entries and resets statistics.
  void clear() {
    _cache.clear();
    _fieldToQueryKeys.clear();
    _statistics = const CacheStatistics();
  }

  /// Resets statistics without clearing the cache.
  void resetStatistics() {
    _statistics = const CacheStatistics();
  }

  /// Gets the fields that currently have cached queries.
  Set<String> get cachedFields => _fieldToQueryKeys.keys.toSet();

  /// Gets the number of queries cached for a specific field.
  int queriesForField(String field) {
    return _fieldToQueryKeys[field]?.length ?? 0;
  }
}

/// Extension to provide query caching capabilities to queries.
extension QueryCachingExtension<T extends Entity> on IQuery {
  /// Executes the query with caching support.
  ///
  /// If a cached result exists and is valid, it is returned directly.
  /// Otherwise, the query is executed using [executeQuery] and the
  /// result is cached for future use.
  ///
  /// ## Parameters
  ///
  /// - [cache]: The query cache to use.
  /// - [executeQuery]: Function to execute the query if not cached.
  /// - [ttl]: Optional TTL override for this specific query.
  ///
  /// ## Returns
  ///
  /// The query results (from cache or fresh execution).
  Future<List<T>> executeWithCache(
    QueryCache<T> cache,
    Future<List<T>> Function() executeQuery, {
    Duration? ttl,
  }) async {
    // Check cache first
    final cached = cache.get(this);
    if (cached != null) {
      return cached;
    }

    // Execute query
    final results = await executeQuery();

    // Cache results
    cache.put(this, results, ttl: ttl);

    return results;
  }
}
