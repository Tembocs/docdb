/// DocDB Storage Engine.
///
/// This module provides the low-level storage infrastructure for DocDB,
/// including page-based storage, buffer management, disk I/O, and
/// write-ahead logging for durability.
///
/// ## Architecture Overview
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │                     Higher-Level APIs                       │
/// ├─────────────────────────────────────────────────────────────┤
/// │                     BufferManager                           │
/// │              (LRU Cache, Dirty Tracking)                    │
/// ├─────────────────────────────────────────────────────────────┤
/// │                        Pager                                │
/// │              (Page Allocation, Free List)                   │
/// ├─────────────────────────────────────────────────────────────┤
/// │                        Page                                 │
/// │              (Fixed-Size Data Blocks)                       │
/// ├─────────────────────────────────────────────────────────────┤
/// │                         WAL                                 │
/// │           (Write-Ahead Logging, Recovery)                   │
/// ├─────────────────────────────────────────────────────────────┤
/// │                    File System                              │
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/engine/engine.dart';
///
/// // Open or create a database file
/// final pager = await Pager.open('database.db');
///
/// // Create a buffer manager for caching
/// final bufferManager = BufferManager(pager: pager, poolSize: 1024);
///
/// // Allocate a new data page
/// final page = await bufferManager.allocatePage(PageType.data);
///
/// // Write data to the page
/// page.writeInt32(page.dataAreaStart, 42);
/// bufferManager.markDirty(page.pageId);
///
/// // Unpin the page when done
/// bufferManager.unpinPage(page.pageId);
///
/// // Flush and close
/// await bufferManager.flushAll();
/// await bufferManager.close();
/// await pager.close();
/// ```
///
/// ## Components
///
/// ### Page
///
/// A fixed-size block of data (default 4KB) that is the fundamental unit
/// of I/O. Pages contain a 16-byte header followed by a data area.
///
/// ### PageType
///
/// Enum identifying the purpose of a page (data, index, overflow, etc.).
///
/// ### Pager
///
/// The disk manager that handles reading/writing pages to the database
/// file, page allocation, and free list management.
///
/// ### BufferManager
///
/// An in-memory page cache with LRU eviction, dirty tracking, and
/// pin/unpin semantics for page protection.
///
/// ### LruCache
///
/// A generic least-recently-used cache used by the buffer manager.
///
/// ### WAL (Write-Ahead Log)
///
/// Provides durability guarantees through write-ahead logging. The WAL
/// records all modifications before they are applied, enabling crash
/// recovery.
///
/// ## Constants
///
/// Engine-wide constants are defined in [PageConstants], [BufferConstants],
/// [FileHeaderConstants], [WalConstants], etc. These control page sizes,
/// buffer pool settings, WAL sync modes, and file format details.
library;

// Storage components
export 'storage/page.dart';
export 'storage/page_type.dart';
export 'storage/pager.dart';
export 'storage/recovery.dart';

// Buffer management
export 'buffer/buffer_manager.dart';
export 'buffer/lru_cache.dart';

// Write-Ahead Log
export 'wal/wal.dart';

// Constants
export 'constants.dart';
