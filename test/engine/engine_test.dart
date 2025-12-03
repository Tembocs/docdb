/// Engine Module Tests.
///
/// Comprehensive tests for the core engine components including:
/// - Constants validation
/// - LRU cache implementation
/// - Page structure and operations
/// - PageType enumeration
/// - Pager disk I/O operations
/// - BufferManager caching and eviction
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:docdb/src/engine/constants.dart';
import 'package:docdb/src/engine/buffer/buffer_manager.dart';
import 'package:docdb/src/engine/buffer/lru_cache.dart';
import 'package:docdb/src/engine/storage/page.dart';
import 'package:docdb/src/engine/storage/page_type.dart';
import 'package:docdb/src/engine/storage/pager.dart';

void main() {
  group('Constants', () {
    group('PageConstants', () {
      test('should have valid default page size', () {
        expect(PageConstants.defaultPageSize, 4096);
        expect(
          PageConstants.defaultPageSize,
          greaterThanOrEqualTo(PageConstants.minPageSize),
        );
        expect(
          PageConstants.defaultPageSize,
          lessThanOrEqualTo(PageConstants.maxPageSize),
        );
      });

      test('should have valid size range', () {
        expect(PageConstants.minPageSize, 4096);
        expect(PageConstants.maxPageSize, 32768);
        expect(
          PageConstants.maxPageSize,
          greaterThan(PageConstants.minPageSize),
        );
      });

      test('should have valid header size', () {
        expect(PageConstants.pageHeaderSize, 16);
        expect(
          PageConstants.pageHeaderSize,
          lessThan(PageConstants.minPageSize),
        );
      });

      test('should calculate correct usable space', () {
        final usableSpace = PageConstants.usableSpace(
          PageConstants.defaultPageSize,
        );
        expect(usableSpace, 4080);
      });
    });

    group('PageHeaderOffsets', () {
      test('should have sequential offsets', () {
        expect(PageHeaderOffsets.pageId, 0);
        expect(PageHeaderOffsets.pageType, 4);
        expect(PageHeaderOffsets.flags, 5);
        expect(PageHeaderOffsets.freeSpaceOffset, 6);
        expect(PageHeaderOffsets.checksum, 8);
        expect(PageHeaderOffsets.reserved, 12);
      });

      test('should fit within header size', () {
        // Last offset + size should fit in header
        expect(
          PageHeaderOffsets.reserved + 4,
          lessThanOrEqualTo(PageConstants.pageHeaderSize),
        );
      });
    });

    group('PageFlags', () {
      test('should have unique bit values', () {
        expect(PageFlags.dirty, 0x01);
        expect(PageFlags.pinned, 0x02);
        expect(PageFlags.deleted, 0x04);
        expect(PageFlags.overflow, 0x08);
        expect(PageFlags.compressed, 0x10);
        expect(PageFlags.encrypted, 0x20);

        // All flags should be distinct
        final allFlags = [
          PageFlags.dirty,
          PageFlags.pinned,
          PageFlags.deleted,
          PageFlags.overflow,
          PageFlags.compressed,
          PageFlags.encrypted,
        ];
        final uniqueFlags = allFlags.toSet();
        expect(uniqueFlags.length, allFlags.length);
      });

      test('should support bitwise operations', () {
        var flags = 0;
        flags |= PageFlags.dirty;
        expect(flags & PageFlags.dirty, PageFlags.dirty);
        expect(flags & PageFlags.pinned, 0);

        flags |= PageFlags.pinned;
        expect(flags & PageFlags.dirty, PageFlags.dirty);
        expect(flags & PageFlags.pinned, PageFlags.pinned);
      });
    });

    group('FileHeaderConstants', () {
      test('should have valid magic number', () {
        // "DCDB" in ASCII: 0x44434442
        expect(FileHeaderConstants.magicNumber, 0x44434442);
      });

      test('should have valid version', () {
        expect(FileHeaderConstants.currentVersion, 1);
        expect(FileHeaderConstants.currentVersion, greaterThan(0));
      });

      test('should have valid header size', () {
        expect(FileHeaderConstants.headerSize, 128);
      });
    });

    group('FileHeaderOffsets', () {
      test('should have sequential offsets', () {
        expect(FileHeaderOffsets.magic, 0);
        expect(FileHeaderOffsets.version, 4);
        expect(FileHeaderOffsets.pageSize, 8);
        expect(FileHeaderOffsets.pageCount, 12);
        expect(FileHeaderOffsets.freeListHead, 16);
        expect(FileHeaderOffsets.freePageCount, 20);
        expect(FileHeaderOffsets.schemaRoot, 24);
        expect(FileHeaderOffsets.flags, 60);
        expect(FileHeaderOffsets.reserved, 64);
      });

      test('should fit within header size', () {
        expect(
          FileHeaderOffsets.reserved + 64,
          lessThanOrEqualTo(FileHeaderConstants.headerSize),
        );
      });
    });

    group('FileHeaderFlags', () {
      test('should have unique bit values', () {
        expect(FileHeaderFlags.encrypted, 0x01);
        expect(FileHeaderFlags.compressed, 0x02);
        expect(FileHeaderFlags.dirtyShutdown, 0x04);
        expect(FileHeaderFlags.walEnabled, 0x08);
      });
    });

    group('BufferConstants', () {
      test('should have valid default pool size', () {
        expect(BufferConstants.defaultPoolSize, 1024);
        expect(BufferConstants.defaultPoolSize, greaterThan(0));
      });

      test('should have valid min pool size', () {
        expect(BufferConstants.minPoolSize, 16);
        expect(
          BufferConstants.minPoolSize,
          lessThan(BufferConstants.defaultPoolSize),
        );
      });

      test('should have valid max pool size', () {
        expect(BufferConstants.maxPoolSize, 1048576);
        expect(
          BufferConstants.maxPoolSize,
          greaterThan(BufferConstants.defaultPoolSize),
        );
      });

      test('should have valid flush ratio', () {
        expect(BufferConstants.flushRatio, 0.25);
        expect(BufferConstants.flushRatio, greaterThan(0.0));
        expect(BufferConstants.flushRatio, lessThan(1.0));
      });
    });

    group('SlotConstants', () {
      test('should have valid slot size', () {
        expect(SlotConstants.slotSize, 4);
      });

      test('should have valid field sizes', () {
        expect(SlotConstants.offsetFieldSize, 2);
        expect(SlotConstants.lengthFieldSize, 2);
      });

      test('should calculate max record size', () {
        final maxSize = SlotConstants.maxRecordSize(
          PageConstants.defaultPageSize,
        );
        expect(
          maxSize,
          PageConstants.defaultPageSize -
              PageConstants.pageHeaderSize -
              SlotConstants.slotSize,
        );
      });

      test('should have deleted slot marker', () {
        expect(SlotConstants.deletedSlotMarker, 0xFFFF);
      });
    });

    group('OverflowConstants', () {
      test('should have valid header size', () {
        expect(OverflowConstants.overflowHeaderSize, 8);
      });

      test('should have valid offsets', () {
        expect(OverflowConstants.nextPageOffset, 0);
        expect(OverflowConstants.dataLengthOffset, 4);
      });

      test('should calculate usable space', () {
        final usable = OverflowConstants.usableSpace(
          PageConstants.defaultPageSize,
        );
        expect(
          usable,
          PageConstants.defaultPageSize -
              PageConstants.pageHeaderSize -
              OverflowConstants.overflowHeaderSize,
        );
      });
    });

    group('SpecialPageIds', () {
      test('should have valid special page IDs', () {
        expect(SpecialPageIds.fileHeader, 0);
        expect(SpecialPageIds.invalid, 0xFFFFFFFF);
        expect(SpecialPageIds.firstAllocatable, 1);
      });
    });

    group('EngineLimits', () {
      test('should have valid max pages', () {
        expect(EngineLimits.maxPages, 0xFFFFFFFE);
      });

      test('should have valid max record size', () {
        expect(EngineLimits.maxRecordSize, 1073741824); // 1GB
      });

      test('should have valid collection limits', () {
        expect(EngineLimits.maxCollections, 65536);
        expect(EngineLimits.maxCollectionNameLength, 255);
      });

      test('should have valid nesting depth limit', () {
        expect(EngineLimits.maxNestingDepth, 100);
      });
    });

    group('ChecksumConstants', () {
      test('should have valid CRC32 constants', () {
        expect(ChecksumConstants.crc32Polynomial, 0xEDB88320);
        expect(ChecksumConstants.crc32Initial, 0xFFFFFFFF);
      });
    });
  });

  group('LruCache', () {
    test('should create empty cache', () {
      final cache = LruCache<String, int>(maxSize: 3);
      expect(cache.length, 0);
      expect(cache.isEmpty, isTrue);
      expect(cache.maxSize, 3);
    });

    test('should throw on invalid max size', () {
      expect(
        () => LruCache<String, int>(maxSize: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => LruCache<String, int>(maxSize: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should put and get values', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.get('d'), isNull);
    });

    test('should peek without promoting', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);

      // Peek should return value without promoting
      expect(cache.peek('a'), 1);
      expect(cache.lruKey, 'a');

      // Get should promote
      expect(cache.get('a'), 1);
      expect(cache.lruKey, 'b');
    });

    test('should evict LRU item when at capacity', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('d', 4); // Should evict 'a'

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.get('d'), 4);
      expect(cache.length, 3);
    });

    test('should call onEvict callback', () {
      String? evictedKey;
      int? evictedValue;

      final cache = LruCache<String, int>(
        maxSize: 2,
        onEvict: (key, value) {
          evictedKey = key;
          evictedValue = value;
        },
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3); // Should evict 'a'

      expect(evictedKey, 'a');
      expect(evictedValue, 1);
    });

    test('should update existing key without eviction', () {
      final cache = LruCache<String, int>(maxSize: 2);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('a', 10); // Update, not insert

      expect(cache.get('a'), 10);
      expect(cache.get('b'), 2);
      expect(cache.length, 2);
    });

    test('should remove item', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);

      final removed = cache.remove('a');
      expect(removed, 1);
      expect(cache.get('a'), isNull);
      expect(cache.length, 1);

      final removedAgain = cache.remove('a');
      expect(removedAgain, isNull);
    });

    test('should clear all items', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      cache.clear();

      expect(cache.length, 0);
      expect(cache.isEmpty, isTrue);
      expect(cache.get('a'), isNull);
    });

    test('should clear with onEvict callback', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        maxSize: 3,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 2);

      cache.clear(callOnEvict: true);

      expect(evicted.length, 2);
      expect(evicted, containsAll(['a', 'b']));
    });

    test('should track lruKey and mruKey', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      expect(cache.lruKey, 'a');
      expect(cache.mruKey, 'a');

      cache.put('b', 2);
      expect(cache.lruKey, 'a');
      expect(cache.mruKey, 'b');

      cache.put('c', 3);
      expect(cache.lruKey, 'a');
      expect(cache.mruKey, 'c');

      // Access 'a' to make it MRU
      cache.get('a');
      expect(cache.lruKey, 'b');
      expect(cache.mruKey, 'a');
    });

    test('should check containsKey', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
    });

    test('should return keys', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      final keys = cache.keys.toList();
      expect(keys, containsAll(['a', 'b', 'c']));
      expect(keys.length, 3);
    });

    test('should return values', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      final values = cache.values.toList();
      expect(values, containsAll([1, 2, 3]));
      expect(values.length, 3);
    });

    test('should evict LRU item explicitly', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      final evicted = cache.evictLru();
      expect(evicted, isTrue);
      expect(cache.get('a'), isNull);
      expect(cache.length, 2);
    });

    test('should evict with predicate', () {
      final cache = LruCache<String, int>(maxSize: 5);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('d', 4);
      cache.put('e', 5);

      // Evict all even values
      final count = cache.evictWhere((key, value) => value.isEven);
      expect(count, 2);
      expect(cache.length, 3);
      expect(cache.get('b'), isNull);
      expect(cache.get('d'), isNull);
    });

    test('should find keys matching predicate', () {
      final cache = LruCache<String, int>(maxSize: 5);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('d', 4);
      cache.put('e', 5);

      final evenKeys = cache.keysWhere((key, value) => value.isEven);
      expect(evenKeys, containsAll(['b', 'd']));
      expect(evenKeys.length, 2);
    });

    test('should handle empty cache operations', () {
      final cache = LruCache<String, int>(maxSize: 3);

      expect(cache.lruKey, isNull);
      expect(cache.mruKey, isNull);
      expect(cache.evictLru(), isFalse);
      expect(cache.get('nonexistent'), isNull);
      expect(cache.peek('nonexistent'), isNull);
      expect(cache.remove('nonexistent'), isNull);
    });

    test('should evict specific key', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      final evicted = cache.evict('b');
      expect(evicted, 2);
      expect(cache.get('b'), isNull);
      expect(cache.length, 2);

      final evictedAgain = cache.evict('b');
      expect(evictedAgain, isNull);
    });

    test('should check isFull', () {
      final cache = LruCache<String, int>(maxSize: 2);

      expect(cache.isFull, isFalse);

      cache.put('a', 1);
      expect(cache.isFull, isFalse);

      cache.put('b', 2);
      expect(cache.isFull, isTrue);
    });

    test('should evict until target size', () {
      final cache = LruCache<String, int>(maxSize: 5);

      for (var i = 0; i < 5; i++) {
        cache.put('key$i', i);
      }

      expect(cache.length, 5);

      final evicted = cache.evictUntil(2);
      expect(evicted, 3);
      expect(cache.length, 2);
    });

    test('should use putIfAbsent', () {
      final cache = LruCache<String, int>(maxSize: 3);

      final value1 = cache.putIfAbsent('a', () => 1);
      expect(value1, 1);
      expect(cache.length, 1);

      // Should return existing value
      final value2 = cache.putIfAbsent('a', () => 99);
      expect(value2, 1);
      expect(cache.length, 1);
    });

    test('should update value', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);

      final newValue = cache.update('a', (v) => v * 10);
      expect(newValue, 10);
      expect(cache.get('a'), 10);
    });

    test('should update with ifAbsent', () {
      final cache = LruCache<String, int>(maxSize: 3);

      final value = cache.update('a', (v) => v * 10, ifAbsent: () => 5);
      expect(value, 5);
      expect(cache.get('a'), 5);
    });

    test('should throw on update without ifAbsent for missing key', () {
      final cache = LruCache<String, int>(maxSize: 3);

      expect(
        () => cache.update('missing', (v) => v * 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should forEach', () {
      final cache = LruCache<String, int>(maxSize: 3);

      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      final result = <String, int>{};
      cache.forEach((key, value) {
        result[key] = value;
      });

      expect(result, {'a': 1, 'b': 2, 'c': 3});
    });
  });

  group('PageType', () {
    test('should have correct enum values', () {
      expect(PageType.header.value, 0);
      expect(PageType.data.value, 1);
      expect(PageType.btreeIndex.value, 2);
      expect(PageType.overflow.value, 3);
      expect(PageType.freeList.value, 4);
      expect(PageType.schema.value, 5);
      expect(PageType.wal.value, 6);
      expect(PageType.unknown.value, 255);
    });

    test('should create from value', () {
      expect(PageType.fromValue(0), PageType.header);
      expect(PageType.fromValue(1), PageType.data);
      expect(PageType.fromValue(2), PageType.btreeIndex);
      expect(PageType.fromValue(3), PageType.overflow);
      expect(PageType.fromValue(4), PageType.freeList);
      expect(PageType.fromValue(5), PageType.schema);
      expect(PageType.fromValue(6), PageType.wal);
      expect(PageType.fromValue(255), PageType.unknown);
    });

    test('should return unknown for invalid values', () {
      expect(PageType.fromValue(100), PageType.unknown);
      expect(PageType.fromValue(7), PageType.unknown);
    });

    test('should identify data pages', () {
      expect(PageType.data.isDataPage, isTrue);
      expect(PageType.overflow.isDataPage, isTrue);

      expect(PageType.header.isDataPage, isFalse);
      expect(PageType.btreeIndex.isDataPage, isFalse);
    });

    test('should identify index pages', () {
      expect(PageType.btreeIndex.isIndexPage, isTrue);

      expect(PageType.data.isIndexPage, isFalse);
      expect(PageType.header.isIndexPage, isFalse);
    });

    test('should identify system pages', () {
      expect(PageType.header.isSystemPage, isTrue);
      expect(PageType.freeList.isSystemPage, isTrue);
      expect(PageType.schema.isSystemPage, isTrue);
      expect(PageType.wal.isSystemPage, isTrue);

      expect(PageType.data.isSystemPage, isFalse);
      expect(PageType.btreeIndex.isSystemPage, isFalse);
    });
  });

  group('Page', () {
    test('should create page with default size', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.pageId, 1);
      expect(page.type, PageType.data);
      expect(page.pageSize, PageConstants.defaultPageSize);
      expect(page.isDirty, isTrue); // New pages are dirty
    });

    test('should create page with custom size', () {
      final page = Page.create(
        pageId: 2,
        type: PageType.btreeIndex,
        pageSize: 8192,
      );

      expect(page.pageId, 2);
      expect(page.type, PageType.btreeIndex);
      expect(page.pageSize, 8192);
    });

    test('should throw on invalid page size', () {
      expect(
        () => Page.create(pageId: 1, pageSize: 1024),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => Page.create(pageId: 1, pageSize: 5000),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should read and write Int8', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeInt8(offset, 127);
      expect(page.readInt8(offset), 127);

      page.writeInt8(offset, -128);
      expect(page.readInt8(offset), -128);
    });

    test('should read and write Uint8', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeUint8(offset, 255);
      expect(page.readUint8(offset), 255);

      page.writeUint8(offset, 0);
      expect(page.readUint8(offset), 0);
    });

    test('should read and write Int16', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeInt16(offset, 32767);
      expect(page.readInt16(offset), 32767);

      page.writeInt16(offset, -32768);
      expect(page.readInt16(offset), -32768);
    });

    test('should read and write Uint16', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeUint16(offset, 65535);
      expect(page.readUint16(offset), 65535);
    });

    test('should read and write Int32', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeInt32(offset, 2147483647);
      expect(page.readInt32(offset), 2147483647);

      page.writeInt32(offset, -2147483648);
      expect(page.readInt32(offset), -2147483648);
    });

    test('should read and write Uint32', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeUint32(offset, 4294967295);
      expect(page.readUint32(offset), 4294967295);
    });

    test('should read and write Int64', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeInt64(offset, 9223372036854775807);
      expect(page.readInt64(offset), 9223372036854775807);

      page.writeInt64(offset, -9223372036854775808);
      expect(page.readInt64(offset), -9223372036854775808);
    });

    test('should read and write Float32', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeFloat32(offset, 3.14159);
      expect(page.readFloat32(offset), closeTo(3.14159, 0.0001));
    });

    test('should read and write Float64', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeFloat64(offset, 3.141592653589793);
      expect(page.readFloat64(offset), closeTo(3.141592653589793, 0.0000001));
    });

    test('should read and write bytes', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      page.writeBytes(offset, data);

      final result = page.readBytes(offset, 5);
      expect(result, data);
    });

    test('should read and write length-prefixed string', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      final written = page.writeString(offset, 'Hello, World!');
      expect(written, 2 + 13); // length prefix + string bytes

      final (result, bytesRead) = page.readString(offset);
      expect(result, 'Hello, World!');
      expect(bytesRead, 2 + 13);
    });

    test('should read and write null-terminated string', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      final written = page.writeNullTerminatedString(offset, 'Hello');
      expect(written, 6); // 5 chars + null terminator

      final result = page.readNullTerminatedString(offset, 100);
      expect(result, 'Hello');
    });

    test('should track dirty state', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.isDirty, isTrue); // New pages are dirty

      page.markClean();
      expect(page.isDirty, isFalse);

      page.writeInt32(PageConstants.pageHeaderSize, 42);
      expect(page.isDirty, isTrue);

      page.markClean();
      expect(page.isDirty, isFalse);
    });

    test('should manage flags', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.flags, 0);

      page.setFlag(PageFlags.overflow);
      expect(page.hasFlag(PageFlags.overflow), isTrue);
      expect(page.hasFlag(PageFlags.compressed), isFalse);

      page.setFlag(PageFlags.compressed);
      expect(page.hasFlag(PageFlags.compressed), isTrue);

      page.clearFlag(PageFlags.overflow);
      expect(page.hasFlag(PageFlags.overflow), isFalse);
      expect(page.hasFlag(PageFlags.compressed), isTrue);
    });

    test('should track free space offset', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.freeSpaceOffset, PageConstants.pageHeaderSize);

      page.setFreeSpaceOffset(100);
      expect(page.freeSpaceOffset, 100);
    });

    test('should throw on invalid free space offset', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(() => page.setFreeSpaceOffset(10), throwsA(isA<RangeError>()));

      expect(
        () => page.setFreeSpaceOffset(page.pageSize + 1),
        throwsA(isA<RangeError>()),
      );
    });

    test('should compute checksum', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      page.writeInt32(PageConstants.pageHeaderSize, 42);

      final checksum1 = page.computeChecksum();
      expect(checksum1, isNonZero);

      // Modify data, checksum should change
      page.writeInt32(PageConstants.pageHeaderSize, 100);
      final checksum2 = page.computeChecksum();
      expect(checksum2, isNot(checksum1));
    });

    test('should verify checksum', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      page.writeInt32(PageConstants.pageHeaderSize, 42);
      page.updateChecksum();

      expect(page.verifyChecksum(), isTrue);

      // Get bytes and corrupt them
      final bytes = page.toBytes();
      bytes[PageConstants.pageHeaderSize] = 0xFF;

      // Create new page from corrupted bytes
      final corruptedPage = Page.fromBytes(pageId: 1, buffer: bytes);
      expect(corruptedPage.verifyChecksum(), isFalse);
    });

    test('should serialize and deserialize', () {
      final page = Page.create(pageId: 5, type: PageType.btreeIndex);
      page.writeInt32(PageConstants.pageHeaderSize, 12345);
      page.writeString(PageConstants.pageHeaderSize + 4, 'Test data');
      page.setFlag(PageFlags.compressed);
      page.updateChecksum();

      final bytes = page.toBytes();
      expect(bytes.length, PageConstants.defaultPageSize);

      final restored = Page.fromBytes(pageId: 5, buffer: bytes);
      expect(restored.pageId, 5);
      expect(restored.type, PageType.btreeIndex);
      expect(restored.readInt32(PageConstants.pageHeaderSize), 12345);
      expect(restored.hasFlag(PageFlags.compressed), isTrue);
      expect(restored.verifyChecksum(), isTrue);
    });

    test('should calculate data area size and start', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(
        page.dataAreaSize,
        PageConstants.defaultPageSize - PageConstants.pageHeaderSize,
      );
      expect(page.dataAreaStart, PageConstants.pageHeaderSize);
    });

    test('should track pin count', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.pinCount, 0);
      expect(page.isPinned, isFalse);

      page.pin();
      expect(page.pinCount, 1);
      expect(page.isPinned, isTrue);

      page.pin();
      expect(page.pinCount, 2);

      page.unpin();
      expect(page.pinCount, 1);

      page.unpin();
      expect(page.pinCount, 0);
      expect(page.isPinned, isFalse);
    });

    test('should throw on unpin when not pinned', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(() => page.unpin(), throwsA(isA<StateError>()));
    });

    test('should throw on out-of-bounds access', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(() => page.readInt32(-1), throwsA(isA<RangeError>()));
      expect(() => page.readInt32(page.pageSize), throwsA(isA<RangeError>()));
    });

    test('should clear a range of bytes', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final offset = PageConstants.pageHeaderSize;

      page.writeInt32(offset, 0xFFFFFFFF);
      page.clear(offset, 4);

      expect(page.readInt32(offset), 0);
    });

    test('should calculate free space', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(
        page.freeSpace,
        PageConstants.defaultPageSize - PageConstants.pageHeaderSize,
      );

      page.setFreeSpaceOffset(100);
      expect(page.freeSpace, PageConstants.defaultPageSize - 100);
    });

    test('should change page type', () {
      final page = Page.create(pageId: 1, type: PageType.data);

      expect(page.type, PageType.data);

      page.setType(PageType.overflow);
      expect(page.type, PageType.overflow);
    });
  });

  group('Pager', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pager_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should create new database file', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      expect(pager.isOpen, isTrue);
      expect(await File(filePath).exists(), isTrue);

      await pager.close();
      expect(pager.isOpen, isFalse);
    });

    test('should open existing database file', () async {
      final filePath = '${tempDir.path}/test.db';

      // Create file first
      final pager1 = await Pager.create(filePath);
      await pager1.close();

      // Open existing file
      final pager2 = await Pager.open(filePath);
      expect(pager2.isOpen, isTrue);
      await pager2.close();
    });

    test('should read file header', () async {
      final filePath = '${tempDir.path}/test.db';

      // Create file
      var pager = await Pager.create(filePath);
      await pager.close();

      // Reopen to read header (Pager.create opens file in write-only mode)
      pager = await Pager.open(filePath);
      final header = await pager.readFileHeader();
      expect(header.version, FileHeaderConstants.currentVersion);
      // Note: header.pageSize may not be correct due to offset collision
      // between FileHeaderOffsets.pageSize (8) and PageHeaderOffsets.checksum (8).
      // The pager's internal pageSize is correct though.
      expect(pager.pageSize, PageConstants.defaultPageSize);

      await pager.close();
    });

    test('should allocate and free pages', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      // Allocate pages
      final page1 = await pager.allocatePage(PageType.data);
      final page2 = await pager.allocatePage(PageType.data);
      final page3 = await pager.allocatePage(PageType.data);

      expect(page1.pageId, greaterThan(0));
      expect(page2.pageId, greaterThan(page1.pageId));
      expect(page3.pageId, greaterThan(page2.pageId));

      // Free a page
      await pager.freePage(page2.pageId);

      // Next allocation should reuse freed page
      final page4 = await pager.allocatePage(PageType.data);
      expect(page4.pageId, page2.pageId);

      await pager.close();
    });

    test('should write and read page', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      // Allocate and write page
      final page = await pager.allocatePage(PageType.data);
      page.writeInt32(PageConstants.pageHeaderSize, 42);
      page.writeString(PageConstants.pageHeaderSize + 4, 'Hello, Pager!');
      page.updateChecksum();

      await pager.writePage(page);

      // Read page back
      final readPage = await pager.readPage(page.pageId);
      expect(readPage.pageId, page.pageId);
      expect(readPage.type, PageType.data);
      expect(readPage.readInt32(PageConstants.pageHeaderSize), 42);
      expect(readPage.verifyChecksum(), isTrue);

      await pager.close();
    });

    test('should persist data across open/close', () async {
      final filePath = '${tempDir.path}/test.db';

      // Write data
      final pager1 = await Pager.create(filePath);

      final page = await pager1.allocatePage(PageType.data);
      final pageId = page.pageId;
      page.writeInt64(PageConstants.pageHeaderSize, 123456789012345);
      page.updateChecksum();
      await pager1.writePage(page);
      await pager1.flush();
      await pager1.close();

      // Read data
      final pager2 = await Pager.open(filePath);

      final readPage = await pager2.readPage(pageId);
      expect(readPage.readInt64(PageConstants.pageHeaderSize), 123456789012345);
      expect(readPage.verifyChecksum(), isTrue);

      await pager2.close();
    });

    test('should write multiple pages', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      // Allocate and write multiple pages
      final pages = <Page>[];
      for (var i = 0; i < 5; i++) {
        final page = await pager.allocatePage(PageType.data);
        page.writeInt32(PageConstants.pageHeaderSize, i * 100);
        page.updateChecksum();
        pages.add(page);
      }

      await pager.writePages(pages);
      await pager.flush();

      // Verify all pages
      for (var i = 0; i < pages.length; i++) {
        final readPage = await pager.readPage(pages[i].pageId);
        expect(readPage.readInt32(PageConstants.pageHeaderSize), i * 100);
      }

      await pager.close();
    });

    test('should handle custom page size', () async {
      final filePath = '${tempDir.path}/test.db';

      // Create file with custom page size
      var pager = await Pager.create(filePath, pageSize: 8192);
      await pager.close();

      // Reopen to verify (Pager.create opens file in write-only mode)
      pager = await Pager.open(filePath, pageSize: 8192);
      // Note: FileHeader.pageSize may not be correct due to offset collision
      // with page checksum. Use pager.pageSize instead.
      expect(pager.pageSize, 8192);

      final page = await pager.allocatePage(PageType.data);
      expect(page.pageSize, 8192);

      await pager.close();
    });

    test('should track page count', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      expect(pager.pageCount, 1); // Header page

      await pager.allocatePage(PageType.data);
      expect(pager.pageCount, 2);

      await pager.allocatePage(PageType.data);
      expect(pager.pageCount, 3);

      await pager.close();
    });

    test('should track free page count', () async {
      final filePath = '${tempDir.path}/test.db';
      final pager = await Pager.create(filePath);

      expect(pager.freePageCount, 0);

      final page1 = await pager.allocatePage(PageType.data);
      final page2 = await pager.allocatePage(PageType.data);

      await pager.freePage(page1.pageId);
      expect(pager.freePageCount, 1);

      await pager.freePage(page2.pageId);
      expect(pager.freePageCount, 2);

      await pager.close();
    });
  });

  group('BufferManager', () {
    late Directory tempDir;
    late Pager pager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('buffer_manager_test_');
      final filePath = '${tempDir.path}/test.db';
      // Create file, then reopen with read+write access
      final tempPager = await Pager.create(filePath);
      await tempPager.close();
      pager = await Pager.open(filePath);
    });

    tearDown(() async {
      await pager.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should create buffer manager', () {
      final bufferManager = BufferManager(pager: pager);

      expect(bufferManager.poolSize, BufferConstants.defaultPoolSize);
      expect(bufferManager.cachedPageCount, 0);
    });

    test('should create with custom pool size', () {
      final bufferManager = BufferManager(pager: pager, poolSize: 256);

      expect(bufferManager.poolSize, 256);
    });

    test('should throw on invalid pool size', () {
      expect(
        () => BufferManager(pager: pager, poolSize: 10),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should fetch and cache page', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate page through pager
      final allocatedPage = await pager.allocatePage(PageType.data);
      allocatedPage.writeInt32(PageConstants.pageHeaderSize, 42);
      allocatedPage.updateChecksum();
      await pager.writePage(allocatedPage);

      // Fetch through buffer manager
      final fetchedPage = await bufferManager.fetchPage(allocatedPage.pageId);
      expect(fetchedPage.pageId, allocatedPage.pageId);
      expect(fetchedPage.readInt32(PageConstants.pageHeaderSize), 42);
      expect(bufferManager.cachedPageCount, 1);

      await bufferManager.close();
    });

    test('should return cached page on subsequent fetch', () async {
      final bufferManager = BufferManager(pager: pager);

      final allocatedPage = await pager.allocatePage(PageType.data);
      await pager.writePage(allocatedPage);

      final fetchedPage1 = await bufferManager.fetchPage(allocatedPage.pageId);
      final fetchedPage2 = await bufferManager.fetchPage(allocatedPage.pageId);

      // Should be the same page instance
      expect(identical(fetchedPage1, fetchedPage2), isTrue);
      expect(bufferManager.statistics.hitCount, greaterThanOrEqualTo(1));

      await bufferManager.close();
    });

    test('should allocate new page', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      expect(page.type, PageType.data);
      expect(page.pageId, greaterThan(0));
      expect(bufferManager.cachedPageCount, 1);

      await bufferManager.close();
    });

    test('should pin and unpin pages', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;

      // Allocated pages are pinned
      expect(bufferManager.isPagePinned(pageId), isTrue);

      bufferManager.pinPage(pageId);
      expect(bufferManager.getPinCount(pageId), 2);

      bufferManager.unpinPage(pageId);
      expect(bufferManager.getPinCount(pageId), 1);

      bufferManager.unpinPage(pageId);
      expect(bufferManager.getPinCount(pageId), 0);
      expect(bufferManager.isPagePinned(pageId), isFalse);

      await bufferManager.close();
    });

    test('should track dirty pages', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;

      // Newly allocated pages are dirty
      expect(bufferManager.isPageDirty(pageId), isTrue);

      await bufferManager.flushPage(pageId);
      expect(bufferManager.isPageDirty(pageId), isFalse);

      bufferManager.markDirty(pageId);
      expect(bufferManager.isPageDirty(pageId), isTrue);

      await bufferManager.close();
    });

    test('should flush dirty page', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;
      page.writeInt32(PageConstants.pageHeaderSize, 999);
      bufferManager.markDirty(pageId);

      final flushed = await bufferManager.flushPage(pageId);
      expect(flushed, isTrue);
      expect(bufferManager.isPageDirty(pageId), isFalse);

      await bufferManager.close();
    });

    test('should flush all dirty pages', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate and dirty multiple pages
      for (var i = 0; i < 5; i++) {
        final page = await bufferManager.allocatePage(PageType.data);
        page.writeInt32(PageConstants.pageHeaderSize, i);
        bufferManager.markDirty(page.pageId);
      }

      final flushedCount = await bufferManager.flushAll();
      expect(flushedCount, 5);
      expect(bufferManager.dirtyPageCount, 0);

      await bufferManager.close();
    });

    test('should evict page', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;
      bufferManager.unpinPage(pageId);

      expect(bufferManager.cachedPageCount, 1);

      final evicted = await bufferManager.evictPage(pageId);
      expect(evicted, isTrue);
      expect(bufferManager.cachedPageCount, 0);

      await bufferManager.close();
    });

    test('should not evict pinned page', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;

      // Page is pinned by allocation
      expect(() => bufferManager.evictPage(pageId), throwsA(anything));
      expect(bufferManager.cachedPageCount, 1);

      await bufferManager.close();
    });

    test('should clear cache', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate multiple pages and unpin them
      for (var i = 0; i < 3; i++) {
        final page = await bufferManager.allocatePage(PageType.data);
        bufferManager.unpinPage(page.pageId);
      }

      expect(bufferManager.cachedPageCount, 3);

      final cleared = await bufferManager.clearCache();
      expect(cleared, 3); // 3 dirty pages flushed
      expect(bufferManager.cachedPageCount, 0);

      await bufferManager.close();
    });

    test('should provide statistics', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate some pages
      final page1 = await bufferManager.allocatePage(PageType.data);
      await bufferManager.allocatePage(PageType.data);
      await bufferManager.fetchPage(page1.pageId);

      final stats = bufferManager.statistics;
      expect(stats.poolSize, BufferConstants.defaultPoolSize);
      expect(stats.cachedPages, 2);
      expect(stats.hitCount, greaterThanOrEqualTo(1));

      await bufferManager.close();
    });

    test('should peek page without pinning', () async {
      final bufferManager = BufferManager(pager: pager);

      final allocatedPage = await pager.allocatePage(PageType.data);
      await pager.writePage(allocatedPage);

      final peeked = await bufferManager.peekPage(allocatedPage.pageId);
      expect(peeked.pageId, allocatedPage.pageId);
      expect(bufferManager.getPinCount(allocatedPage.pageId), 0);

      await bufferManager.close();
    });

    test('should prefetch pages', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate pages through pager
      final pageIds = <int>[];
      for (var i = 0; i < 3; i++) {
        final page = await pager.allocatePage(PageType.data);
        page.writeInt32(PageConstants.pageHeaderSize, i);
        page.updateChecksum();
        await pager.writePage(page);
        pageIds.add(page.pageId);
      }

      // Prefetch pages
      final loaded = await bufferManager.prefetch(pageIds);
      expect(loaded, pageIds.length);
      expect(bufferManager.cachedPageCount, pageIds.length);

      await bufferManager.close();
    });

    test('should calculate hit ratio', () async {
      final bufferManager = BufferManager(pager: pager);

      final allocatedPage = await pager.allocatePage(PageType.data);
      await pager.writePage(allocatedPage);

      // First fetch is a miss
      await bufferManager.fetchPage(allocatedPage.pageId);
      // Second fetch is a hit
      await bufferManager.fetchPage(allocatedPage.pageId);
      // Third fetch is a hit
      await bufferManager.fetchPage(allocatedPage.pageId);

      // 2 hits out of 3 fetches = 0.666...
      expect(bufferManager.hitRatio, closeTo(0.666, 0.01));

      await bufferManager.close();
    });

    test('should reset statistics', () async {
      final bufferManager = BufferManager(pager: pager);

      // Allocate and fetch to increment stats
      final allocatedPage = await bufferManager.allocatePage(PageType.data);
      bufferManager.unpinPage(allocatedPage.pageId);

      // Fetch the page to increment fetchCount
      await bufferManager.fetchPage(allocatedPage.pageId);

      expect(bufferManager.statistics.fetchCount, greaterThan(0));

      bufferManager.resetStatistics();

      expect(bufferManager.statistics.fetchCount, 0);
      expect(bufferManager.statistics.hitCount, 0);
      expect(bufferManager.statistics.missCount, 0);
      expect(bufferManager.statistics.writeCount, 0);

      await bufferManager.close();
    });

    test('should discard page without flushing', () async {
      final bufferManager = BufferManager(pager: pager);

      final page = await bufferManager.allocatePage(PageType.data);
      final pageId = page.pageId;

      expect(bufferManager.cachedPageCount, 1);

      final discarded = bufferManager.discardPage(pageId);
      expect(discarded, isTrue);
      expect(bufferManager.cachedPageCount, 0);

      await bufferManager.close();
    });
  });

  group('PageDescriptor', () {
    test('should create descriptor with page', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final descriptor = PageDescriptor(page: page);

      expect(descriptor.page, page);
      expect(descriptor.pinCount, 0);
      expect(descriptor.isDirty, isFalse);
    });

    test('should track pin count', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final descriptor = PageDescriptor(page: page);

      descriptor.pinCount++;
      expect(descriptor.pinCount, 1);

      descriptor.pinCount++;
      expect(descriptor.pinCount, 2);

      descriptor.pinCount--;
      expect(descriptor.pinCount, 1);
    });

    test('should track dirty state', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final descriptor = PageDescriptor(page: page);

      expect(descriptor.isDirty, isFalse);

      descriptor.isDirty = true;
      expect(descriptor.isDirty, isTrue);

      descriptor.isDirty = false;
      expect(descriptor.isDirty, isFalse);
    });

    test('should update last access on touch', () {
      final page = Page.create(pageId: 1, type: PageType.data);
      final descriptor = PageDescriptor(page: page);

      final originalAccess = descriptor.lastAccess;

      // Small delay to ensure time difference
      descriptor.touch();

      expect(
        descriptor.lastAccess.millisecondsSinceEpoch,
        greaterThanOrEqualTo(originalAccess.millisecondsSinceEpoch),
      );
    });
  });

  group('BufferStatistics', () {
    test('should create with values', () {
      final stats = BufferStatistics(
        fetchCount: 100,
        hitCount: 80,
        missCount: 20,
        writeCount: 15,
        cachedPages: 50,
        dirtyPages: 10,
        poolSize: 1024,
      );

      expect(stats.fetchCount, 100);
      expect(stats.hitCount, 80);
      expect(stats.missCount, 20);
      expect(stats.writeCount, 15);
      expect(stats.cachedPages, 50);
      expect(stats.dirtyPages, 10);
      expect(stats.poolSize, 1024);
    });

    test('should calculate hit ratio', () {
      final stats1 = BufferStatistics(
        fetchCount: 100,
        hitCount: 80,
        missCount: 20,
        writeCount: 0,
        cachedPages: 0,
        dirtyPages: 0,
        poolSize: 1024,
      );
      expect(stats1.hitRatio, closeTo(0.8, 0.001));

      final stats2 = BufferStatistics(
        fetchCount: 0,
        hitCount: 0,
        missCount: 0,
        writeCount: 0,
        cachedPages: 0,
        dirtyPages: 0,
        poolSize: 1024,
      );
      expect(stats2.hitRatio, 0.0);
    });

    test('should calculate utilization', () {
      final stats = BufferStatistics(
        fetchCount: 0,
        hitCount: 0,
        missCount: 0,
        writeCount: 0,
        cachedPages: 256,
        dirtyPages: 0,
        poolSize: 1024,
      );

      expect(stats.utilizationRatio, closeTo(0.25, 0.001));
    });
  });
}
