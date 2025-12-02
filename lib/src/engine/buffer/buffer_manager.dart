import 'dart:async';

import 'package:synchronized/synchronized.dart';

import '../../exceptions/storage_exceptions.dart';
import '../constants.dart';
import '../storage/page.dart';
import '../storage/page_type.dart';
import '../storage/pager.dart';
import 'lru_cache.dart';

/// A page descriptor holding metadata for a cached page.
///
/// Used internally by [BufferManager] to track page state and
/// enable proper resource management.
class PageDescriptor {
  /// The cached page.
  final Page page;

  /// Number of active references (pins) to this page.
  int pinCount;

  /// Whether the page has been modified since last flush.
  bool isDirty;

  /// Timestamp of last access (for statistics).
  DateTime lastAccess;

  /// Creates a new page descriptor.
  PageDescriptor({
    required this.page,
    this.pinCount = 0,
    this.isDirty = false,
    DateTime? lastAccess,
  }) : lastAccess = lastAccess ?? DateTime.now();

  /// Updates the last access timestamp.
  void touch() {
    lastAccess = DateTime.now();
  }

  @override
  String toString() {
    return 'PageDescriptor(pageId: ${page.pageId}, pinCount: $pinCount, '
        'isDirty: $isDirty)';
  }
}

/// Manages an in-memory cache of database pages.
///
/// The BufferManager provides a high-level interface for accessing pages,
/// automatically handling:
/// - Page caching with LRU eviction
/// - Dirty page tracking and flushing
/// - Pin/unpin semantics for page protection
/// - Concurrency control via synchronization
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │                      BufferManager                          │
/// ├─────────────────────────────────────────────────────────────┤
/// │  ┌─────────────────────────────────────────────────────┐    │
/// │  │              LRU Cache (Page Descriptors)           │    │
/// │  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐       │    │
/// │  │  │ P1  │──│ P5  │──│ P3  │──│ P7  │──│ P2  │       │    │
/// │  │  └─────┘  └─────┘  └─────┘  └─────┘  └─────┘       │    │
/// │  │   LRU                                     MRU       │    │
/// │  └─────────────────────────────────────────────────────┘    │
/// │                           │                                  │
/// │                           ▼                                  │
/// │  ┌─────────────────────────────────────────────────────┐    │
/// │  │                      Pager                           │    │
/// │  │              (Disk I/O Abstraction)                  │    │
/// │  └─────────────────────────────────────────────────────┘    │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```dart
/// final pager = await Pager.open('database.db');
/// final bufferManager = BufferManager(pager: pager, poolSize: 1024);
///
/// // Fetch a page (loads from disk if not cached)
/// final page = await bufferManager.fetchPage(pageId);
///
/// // Modify the page
/// page.writeInt32(offset, value);
/// bufferManager.markDirty(pageId);
///
/// // Unpin when done (allows eviction)
/// bufferManager.unpinPage(pageId);
///
/// // Flush all dirty pages to disk
/// await bufferManager.flushAll();
///
/// // Close the buffer manager
/// await bufferManager.close();
/// ```
///
/// ## Pin Semantics
///
/// Pages are automatically pinned when fetched. Pinned pages cannot be
/// evicted from the cache. Always call [unpinPage] when you're done
/// with a page to allow proper cache management.
class BufferManager {
  /// The underlying pager for disk I/O.
  final Pager _pager;

  /// The LRU cache holding page descriptors.
  late final LruCache<int, PageDescriptor> _cache;

  /// Lock for thread-safe access.
  final Lock _lock = Lock();

  /// The maximum number of pages in the buffer pool.
  final int poolSize;

  /// Statistics: total page fetches.
  int _fetchCount = 0;

  /// Statistics: cache hits.
  int _hitCount = 0;

  /// Statistics: cache misses (disk reads).
  int _missCount = 0;

  /// Statistics: pages written to disk.
  int _writeCount = 0;

  /// Whether the buffer manager is open.
  bool _isOpen = true;

  /// Creates a new buffer manager.
  ///
  /// - [pager]: The pager for disk I/O (must be open)
  /// - [poolSize]: Maximum number of pages to cache
  ///
  /// Throws [ArgumentError] if poolSize is invalid.
  BufferManager({
    required Pager pager,
    this.poolSize = BufferConstants.defaultPoolSize,
  }) : _pager = pager {
    if (poolSize < BufferConstants.minPoolSize) {
      throw ArgumentError.value(
        poolSize,
        'poolSize',
        'Must be at least ${BufferConstants.minPoolSize}',
      );
    }

    _cache = LruCache<int, PageDescriptor>(
      maxSize: poolSize,
      onEvict: _onPageEvicted,
    );
  }

  /// The page size used by the underlying pager.
  int get pageSize => _pager.pageSize;

  /// The number of pages currently in the cache.
  int get cachedPageCount => _cache.length;

  /// The number of dirty pages in the cache.
  int get dirtyPageCount {
    var count = 0;
    _cache.forEach((_, descriptor) {
      if (descriptor.isDirty) count++;
    });
    return count;
  }

  /// Cache hit ratio (0.0 to 1.0).
  double get hitRatio {
    final total = _hitCount + _missCount;
    return total == 0 ? 0.0 : _hitCount / total;
  }

  /// Statistics snapshot.
  BufferStatistics get statistics => BufferStatistics(
    fetchCount: _fetchCount,
    hitCount: _hitCount,
    missCount: _missCount,
    writeCount: _writeCount,
    cachedPages: _cache.length,
    dirtyPages: dirtyPageCount,
    poolSize: poolSize,
  );

  // ============================================================
  // Page Access
  // ============================================================

  /// Fetches a page from the cache or disk.
  ///
  /// The page is automatically pinned and must be unpinned when no longer
  /// needed. If the page is already in the cache, it's marked as recently
  /// used.
  ///
  /// - [pageId]: The ID of the page to fetch
  ///
  /// Returns the requested page (pinned).
  ///
  /// Throws [StorageException] if the page cannot be read.
  Future<Page> fetchPage(int pageId) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      _fetchCount++;

      // Check cache first
      final cached = _cache.get(pageId);
      if (cached != null) {
        _hitCount++;
        cached.pinCount++;
        cached.touch();
        return cached.page;
      }

      // Cache miss - read from disk
      _missCount++;
      await _ensureSpace();

      final page = await _pager.readPage(pageId);
      final descriptor = PageDescriptor(page: page, pinCount: 1);
      _cache.put(pageId, descriptor);

      return page;
    });
  }

  /// Fetches a page without pinning it.
  ///
  /// Use this for read-only access where you won't hold the page
  /// across async boundaries.
  ///
  /// **Warning**: The page may be evicted at any time if unpinned.
  Future<Page> peekPage(int pageId) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      _fetchCount++;

      final cached = _cache.peek(pageId);
      if (cached != null) {
        _hitCount++;
        return cached.page;
      }

      _missCount++;
      await _ensureSpace();

      final page = await _pager.readPage(pageId);
      final descriptor = PageDescriptor(page: page, pinCount: 0);
      _cache.put(pageId, descriptor);

      return page;
    });
  }

  /// Allocates a new page of the given type.
  ///
  /// The page is automatically added to the cache and pinned.
  ///
  /// - [type]: The type of page to allocate
  ///
  /// Returns the newly allocated page (pinned).
  Future<Page> allocatePage(PageType type) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      await _ensureSpace();

      final page = await _pager.allocatePage(type);
      final descriptor = PageDescriptor(page: page, pinCount: 1, isDirty: true);
      _cache.put(page.pageId, descriptor);

      return page;
    });
  }

  /// Ensures there's space in the cache for a new page.
  ///
  /// Evicts unpinned pages if necessary.
  Future<void> _ensureSpace() async {
    if (!_cache.isFull) return;

    // Find and evict unpinned pages
    final unpinnedKeys = _cache.keysWhere((_, d) => d.pinCount == 0);

    if (unpinnedKeys.isEmpty) {
      throw StorageOperationException(
        'Buffer pool exhausted: all ${_cache.length} pages are pinned',
        path: _pager.filePath,
      );
    }

    // Evict the LRU unpinned page
    for (final key in unpinnedKeys) {
      if (_cache.length < poolSize) break;
      final descriptor = _cache.peek(key);
      if (descriptor != null && descriptor.pinCount == 0) {
        await _flushIfDirty(key, descriptor);
        _cache.remove(key);
      }
    }
  }

  /// Callback when a page is evicted from the cache.
  void _onPageEvicted(int pageId, PageDescriptor descriptor) {
    // This is called during cache operations, so we can't do async I/O here.
    // Dirty pages should be flushed before eviction via _ensureSpace.
    if (descriptor.isDirty) {
      // Log a warning - this shouldn't happen with proper usage
      // In production, we'd use a logger here
    }
  }

  // ============================================================
  // Pin Management
  // ============================================================

  /// Pins a page, preventing it from being evicted.
  ///
  /// Returns `true` if the page was found and pinned, `false` if not cached.
  bool pinPage(int pageId) {
    final descriptor = _cache.peek(pageId);
    if (descriptor != null) {
      descriptor.pinCount++;
      return true;
    }
    return false;
  }

  /// Unpins a page, allowing it to be evicted.
  ///
  /// Returns `true` if the page was found and unpinned, `false` if not cached.
  ///
  /// Throws [StateError] if the page is not currently pinned.
  bool unpinPage(int pageId) {
    final descriptor = _cache.peek(pageId);
    if (descriptor != null) {
      if (descriptor.pinCount <= 0) {
        throw StateError('Page $pageId is not pinned');
      }
      descriptor.pinCount--;
      return true;
    }
    return false;
  }

  /// Returns the pin count for a page, or -1 if not cached.
  int getPinCount(int pageId) {
    final descriptor = _cache.peek(pageId);
    return descriptor?.pinCount ?? -1;
  }

  /// Returns `true` if the page is currently pinned.
  bool isPagePinned(int pageId) {
    final descriptor = _cache.peek(pageId);
    return descriptor != null && descriptor.pinCount > 0;
  }

  // ============================================================
  // Dirty Page Management
  // ============================================================

  /// Marks a page as dirty (modified).
  ///
  /// Dirty pages will be written to disk during flush operations.
  ///
  /// Returns `true` if the page was found and marked, `false` if not cached.
  bool markDirty(int pageId) {
    final descriptor = _cache.peek(pageId);
    if (descriptor != null) {
      descriptor.isDirty = true;
      descriptor.page.markDirty();
      return true;
    }
    return false;
  }

  /// Returns `true` if the page is marked as dirty.
  bool isPageDirty(int pageId) {
    final descriptor = _cache.peek(pageId);
    return descriptor?.isDirty ?? false;
  }

  /// Flushes a specific page to disk if it's dirty.
  ///
  /// Returns `true` if the page was flushed, `false` if clean or not cached.
  Future<bool> flushPage(int pageId) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      final descriptor = _cache.peek(pageId);
      if (descriptor != null && descriptor.isDirty) {
        await _flushDescriptor(pageId, descriptor);
        return true;
      }
      return false;
    });
  }

  /// Flushes all dirty pages to disk.
  ///
  /// Returns the number of pages flushed.
  Future<int> flushAll() async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      var flushed = 0;

      for (final entry in _cache.entries.toList()) {
        if (entry.value.isDirty) {
          await _flushDescriptor(entry.key, entry.value);
          flushed++;
        }
      }

      await _pager.flush();
      return flushed;
    });
  }

  /// Flushes a page descriptor to disk.
  Future<void> _flushDescriptor(int pageId, PageDescriptor descriptor) async {
    await _pager.writePage(descriptor.page);
    descriptor.isDirty = false;
    descriptor.page.markClean();
    _writeCount++;
  }

  /// Flushes a descriptor if dirty (used during eviction).
  Future<void> _flushIfDirty(int pageId, PageDescriptor descriptor) async {
    if (descriptor.isDirty) {
      await _flushDescriptor(pageId, descriptor);
    }
  }

  // ============================================================
  // Cache Management
  // ============================================================

  /// Removes a page from the cache without flushing.
  ///
  /// **Warning**: This discards any unflushed changes!
  ///
  /// Returns `true` if the page was found and removed.
  bool discardPage(int pageId) {
    return _cache.remove(pageId) != null;
  }

  /// Removes a page from the cache, flushing if dirty.
  ///
  /// Returns `true` if the page was found and evicted.
  Future<bool> evictPage(int pageId) async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      final descriptor = _cache.peek(pageId);
      if (descriptor == null) return false;

      if (descriptor.pinCount > 0) {
        throw StorageOperationException(
          'Cannot evict pinned page $pageId (pinCount: ${descriptor.pinCount})',
          path: _pager.filePath,
        );
      }

      await _flushIfDirty(pageId, descriptor);
      _cache.remove(pageId);
      return true;
    });
  }

  /// Clears the entire cache, flushing all dirty pages first.
  ///
  /// Returns the number of pages that were flushed.
  Future<int> clearCache() async {
    _ensureOpen();

    return await _lock.synchronized(() async {
      // Check for pinned pages
      final pinnedCount = _cache.keysWhere((_, d) => d.pinCount > 0).length;
      if (pinnedCount > 0) {
        throw StorageOperationException(
          'Cannot clear cache: $pinnedCount pages are still pinned',
          path: _pager.filePath,
        );
      }

      // Flush all dirty pages
      final flushed = await flushAll();

      // Clear the cache
      _cache.clear();

      return flushed;
    });
  }

  /// Prefetches pages into the cache.
  ///
  /// Useful for warming the cache with pages likely to be accessed.
  /// Pages are not pinned.
  ///
  /// - [pageIds]: List of page IDs to prefetch
  ///
  /// Returns the number of pages actually loaded (excluding already cached).
  Future<int> prefetch(List<int> pageIds) async {
    _ensureOpen();

    var loaded = 0;
    for (final pageId in pageIds) {
      if (!_cache.containsKey(pageId)) {
        await peekPage(pageId);
        loaded++;
      }
    }
    return loaded;
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  /// Closes the buffer manager.
  ///
  /// Flushes all dirty pages before closing. Does not close the
  /// underlying pager.
  Future<void> close() async {
    if (!_isOpen) return;

    await _lock.synchronized(() async {
      // Flush all dirty pages
      for (final entry in _cache.entries) {
        if (entry.value.isDirty) {
          await _flushDescriptor(entry.key, entry.value);
        }
      }

      _cache.clear();
      _isOpen = false;
    });
  }

  /// Ensures the buffer manager is open.
  void _ensureOpen() {
    if (!_isOpen) {
      throw StorageNotOpenException.withMessage(
        'BufferManager is closed',
        path: _pager.filePath,
      );
    }
  }

  /// Resets statistics counters.
  void resetStatistics() {
    _fetchCount = 0;
    _hitCount = 0;
    _missCount = 0;
    _writeCount = 0;
  }

  @override
  String toString() {
    return 'BufferManager(cached: ${_cache.length}/$poolSize, '
        'dirty: $dirtyPageCount, hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}

/// Statistics for the buffer manager.
class BufferStatistics {
  /// Total number of page fetches.
  final int fetchCount;

  /// Number of cache hits.
  final int hitCount;

  /// Number of cache misses.
  final int missCount;

  /// Number of pages written to disk.
  final int writeCount;

  /// Number of pages currently cached.
  final int cachedPages;

  /// Number of dirty pages in cache.
  final int dirtyPages;

  /// Maximum pool size.
  final int poolSize;

  const BufferStatistics({
    required this.fetchCount,
    required this.hitCount,
    required this.missCount,
    required this.writeCount,
    required this.cachedPages,
    required this.dirtyPages,
    required this.poolSize,
  });

  /// Cache hit ratio (0.0 to 1.0).
  double get hitRatio {
    final total = hitCount + missCount;
    return total == 0 ? 0.0 : hitCount / total;
  }

  /// Cache utilization ratio (0.0 to 1.0).
  double get utilizationRatio => cachedPages / poolSize;

  @override
  String toString() {
    return 'BufferStatistics(fetches: $fetchCount, hits: $hitCount, '
        'misses: $missCount, writes: $writeCount, '
        'cached: $cachedPages/$poolSize, dirty: $dirtyPages, '
        'hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}
