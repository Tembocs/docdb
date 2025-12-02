import 'dart:collection';

/// A generic Least Recently Used (LRU) cache implementation.
///
/// The LRU cache maintains a fixed maximum capacity and automatically
/// evicts the least recently accessed entries when the cache is full.
///
/// ## Usage
///
/// ```dart
/// final cache = LruCache<int, String>(maxSize: 3);
///
/// cache.put(1, 'one');
/// cache.put(2, 'two');
/// cache.put(3, 'three');
///
/// // Access key 1 to make it recently used
/// cache.get(1); // Returns 'one'
///
/// // Adding a new entry evicts the LRU entry (key 2)
/// cache.put(4, 'four');
/// cache.get(2); // Returns null (evicted)
/// ```
///
/// ## Thread Safety
///
/// This implementation is NOT thread-safe. For concurrent access,
/// wrap operations in a [Lock] or use a synchronized wrapper.
class LruCache<K, V> {
  /// The maximum number of entries the cache can hold.
  final int maxSize;

  /// The internal storage using a [LinkedHashMap] for access-order iteration.
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  /// Optional callback invoked when an entry is evicted.
  ///
  /// Can be used to perform cleanup (e.g., releasing resources).
  final void Function(K key, V value)? onEvict;

  /// Creates a new LRU cache with the specified maximum size.
  ///
  /// - [maxSize]: Maximum number of entries (must be > 0)
  /// - [onEvict]: Optional callback for eviction notifications
  ///
  /// Throws [ArgumentError] if maxSize is less than 1.
  LruCache({required this.maxSize, this.onEvict}) {
    if (maxSize < 1) {
      throw ArgumentError.value(maxSize, 'maxSize', 'Must be at least 1');
    }
  }

  /// The current number of entries in the cache.
  int get length => _cache.length;

  /// Whether the cache is empty.
  bool get isEmpty => _cache.isEmpty;

  /// Whether the cache is not empty.
  bool get isNotEmpty => _cache.isNotEmpty;

  /// Whether the cache is at maximum capacity.
  bool get isFull => _cache.length >= maxSize;

  /// All keys in the cache, from least to most recently used.
  Iterable<K> get keys => _cache.keys;

  /// All values in the cache, from least to most recently used.
  Iterable<V> get values => _cache.values;

  /// All entries in the cache, from least to most recently used.
  Iterable<MapEntry<K, V>> get entries => _cache.entries;

  /// The least recently used key, or `null` if cache is empty.
  K? get lruKey => _cache.isEmpty ? null : _cache.keys.first;

  /// The most recently used key, or `null` if cache is empty.
  K? get mruKey => _cache.isEmpty ? null : _cache.keys.last;

  /// Returns the value for [key], or `null` if not present.
  ///
  /// Accessing a key marks it as recently used (moves it to the end).
  V? get(K key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value; // Re-insert at the end (most recently used)
    }
    return value;
  }

  /// Returns the value for [key] without updating its access order.
  ///
  /// Use this for read-only inspection that shouldn't affect eviction order.
  V? peek(K key) => _cache[key];

  /// Stores a [key]-[value] pair in the cache.
  ///
  /// If the key already exists, its value is updated and it becomes
  /// the most recently used entry.
  ///
  /// If the cache is full and the key is new, the least recently used
  /// entry is evicted to make room.
  ///
  /// Returns the previously associated value, or `null` if the key was new.
  V? put(K key, V value) {
    // Check if key exists - if so, remove it first (will re-add at end)
    final existing = _cache.remove(key);

    // If key was new and cache is full, evict LRU entry
    if (existing == null && _cache.length >= maxSize) {
      _evictLru();
    }

    _cache[key] = value;
    return existing;
  }

  /// Stores a [key]-[value] pair only if the key is not already present.
  ///
  /// Returns the existing value if present, otherwise stores and returns
  /// the new value.
  V putIfAbsent(K key, V Function() ifAbsent) {
    final existing = _cache[key];
    if (existing != null) {
      // Mark as recently used
      _cache.remove(key);
      _cache[key] = existing;
      return existing;
    }

    // Evict if necessary
    if (_cache.length >= maxSize) {
      _evictLru();
    }

    final value = ifAbsent();
    _cache[key] = value;
    return value;
  }

  /// Removes the entry for [key] from the cache.
  ///
  /// Returns the removed value, or `null` if the key was not present.
  ///
  /// Note: This does NOT call [onEvict] - use [evict] for that.
  V? remove(K key) => _cache.remove(key);

  /// Removes and returns the entry for [key], calling [onEvict] if present.
  ///
  /// Returns the evicted value, or `null` if the key was not present.
  V? evict(K key) {
    final value = _cache.remove(key);
    if (value != null) {
      onEvict?.call(key, value);
    }
    return value;
  }

  /// Returns `true` if the cache contains an entry for [key].
  bool containsKey(K key) => _cache.containsKey(key);

  /// Clears all entries from the cache.
  ///
  /// If [callOnEvict] is `true`, calls [onEvict] for each removed entry.
  void clear({bool callOnEvict = false}) {
    if (callOnEvict && onEvict != null) {
      for (final entry in _cache.entries.toList()) {
        onEvict!(entry.key, entry.value);
      }
    }
    _cache.clear();
  }

  /// Evicts the least recently used entry.
  ///
  /// Returns `true` if an entry was evicted, `false` if cache was empty.
  bool evictLru() {
    if (_cache.isEmpty) return false;
    _evictLru();
    return true;
  }

  /// Internal method to evict the LRU entry.
  void _evictLru() {
    final key = _cache.keys.first;
    final value = _cache.remove(key);
    if (value != null) {
      onEvict?.call(key, value);
    }
  }

  /// Evicts entries until the cache size is at most [targetSize].
  ///
  /// Returns the number of entries evicted.
  int evictUntil(int targetSize) {
    var evicted = 0;
    while (_cache.length > targetSize && _cache.isNotEmpty) {
      _evictLru();
      evicted++;
    }
    return evicted;
  }

  /// Applies [action] to each entry in the cache.
  ///
  /// Iteration order is from least to most recently used.
  void forEach(void Function(K key, V value) action) {
    _cache.forEach(action);
  }

  /// Updates the value for [key] using [update].
  ///
  /// If [key] is not present and [ifAbsent] is provided, inserts the
  /// result of [ifAbsent]. Otherwise throws [ArgumentError].
  ///
  /// The entry becomes the most recently used.
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    final existing = _cache.remove(key);

    if (existing != null) {
      final newValue = update(existing);
      _cache[key] = newValue;
      return newValue;
    }

    if (ifAbsent != null) {
      if (_cache.length >= maxSize) {
        _evictLru();
      }
      final value = ifAbsent();
      _cache[key] = value;
      return value;
    }

    throw ArgumentError('Key not in cache: $key');
  }

  /// Returns a list of keys that match the given [predicate].
  ///
  /// Does not modify access order.
  List<K> keysWhere(bool Function(K key, V value) predicate) {
    return _cache.entries
        .where((e) => predicate(e.key, e.value))
        .map((e) => e.key)
        .toList();
  }

  /// Evicts all entries matching the given [predicate].
  ///
  /// Returns the number of entries evicted.
  int evictWhere(bool Function(K key, V value) predicate) {
    final keysToEvict = keysWhere(predicate);
    for (final key in keysToEvict) {
      evict(key);
    }
    return keysToEvict.length;
  }

  @override
  String toString() {
    return 'LruCache(size: ${_cache.length}/$maxSize, '
        'lru: $lruKey, mru: $mruKey)';
  }
}
