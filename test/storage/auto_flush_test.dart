/// Test to verify automatic flushing behavior
///
/// This test verifies that data is automatically persisted without requiring
/// manual flush() calls from the user.
library;

import 'dart:io';

import 'package:entidb/entidb.dart';
import 'package:test/test.dart';

/// Test entity for persistence verification
class TestEntity implements Entity {
  @override
  final String? id;

  final String name;
  final int value;

  TestEntity({this.id, required this.name, required this.value});

  @override
  Map<String, dynamic> toMap() => {'name': name, 'value': value};

  factory TestEntity.fromMap(String id, Map<String, dynamic> map) => TestEntity(
    id: id,
    name: map['name'] as String,
    value: map['value'] as int,
  );
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('entidb_autoflush_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Automatic Flushing', () {
    test(
      'data persists without manual flush() when autoFlushOnClose is true',
      () async {
        final dbPath = tempDir.path;
        String entityId;

        // Session 1: Insert data and close WITHOUT manual flush
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development().copyWith(autoFlushOnClose: true),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          entityId = await collection.insert(
            TestEntity(name: 'AutoFlush Test', value: 42),
          );

          expect(await collection.count, 1);

          // Close WITHOUT calling flush() manually
          await db.close();
        }

        // Session 2: Reopen and verify data was persisted
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development(),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          expect(await collection.count, 1);

          final entity = await collection.get(entityId);
          expect(entity, isNotNull);
          expect(entity!.name, 'AutoFlush Test');
          expect(entity.value, 42);

          await db.close();
        }
      },
    );

    test(
      'data STILL persists when autoFlushOnClose is false because storage layer always flushes on close',
      () async {
        final dbPath = tempDir.path;
        String entityId;

        // Session 1: Insert data and close WITHOUT flush
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development().copyWith(
              autoFlushOnClose: false,
            ),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          entityId = await collection.insert(
            TestEntity(name: 'No AutoFlush', value: 99),
          );

          expect(await collection.count, 1);

          // Close WITHOUT calling flush() manually
          await db.close();
        }

        // Session 2: Reopen and verify data WAS persisted
        // The PagedStorage.close() always flushes, so data is persisted
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development(),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          // Data IS persisted because PagedStorage.close() always calls flush()
          expect(await collection.count, 1);

          final entity = await collection.get(entityId);
          expect(entity, isNotNull);
          expect(entity!.name, 'No AutoFlush');
          expect(entity.value, 99);

          await db.close();
        }
      },
    );

    test(
      'data persists with manual flush() even when autoFlushOnClose is false',
      () async {
        final dbPath = tempDir.path;
        String entityId;

        // Session 1: Insert data, call flush() manually, then close
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development().copyWith(
              autoFlushOnClose: false,
            ),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          entityId = await collection.insert(
            TestEntity(name: 'Manual Flush', value: 77),
          );

          expect(await collection.count, 1);

          // Manual flush ensures data is written
          await db.flush();

          await db.close();
        }

        // Session 2: Reopen and verify data was persisted
        {
          final db = await EntiDB.open(
            path: dbPath,
            config: EntiDBConfig.development(),
          );

          final collection = await db.collection<TestEntity>(
            'test',
            fromMap: TestEntity.fromMap,
          );

          expect(await collection.count, 1);

          final entity = await collection.get(entityId);
          expect(entity, isNotNull);
          expect(entity!.name, 'Manual Flush');
          expect(entity.value, 77);

          await db.close();
        }
      },
    );

    test('production config has autoFlushOnClose enabled by default', () {
      final config = EntiDBConfig.production();
      expect(config.autoFlushOnClose, isTrue);
    });

    test('development config has autoFlushOnClose enabled by default', () {
      final config = EntiDBConfig.development();
      expect(config.autoFlushOnClose, isTrue);
    });

    test('multiple writes persist correctly with autoFlushOnClose', () async {
      final dbPath = tempDir.path;
      final entityIds = <String>[];

      // Session 1: Insert multiple entities
      {
        final db = await EntiDB.open(
          path: dbPath,
          config: EntiDBConfig.development().copyWith(autoFlushOnClose: true),
        );

        final collection = await db.collection<TestEntity>(
          'test',
          fromMap: TestEntity.fromMap,
        );

        for (int i = 0; i < 10; i++) {
          final id = await collection.insert(
            TestEntity(name: 'Entity $i', value: i * 10),
          );
          entityIds.add(id);
        }

        expect(await collection.count, 10);

        await db.close();
      }

      // Session 2: Verify all entities persisted
      {
        final db = await EntiDB.open(
          path: dbPath,
          config: EntiDBConfig.development(),
        );

        final collection = await db.collection<TestEntity>(
          'test',
          fromMap: TestEntity.fromMap,
        );

        expect(await collection.count, 10);

        for (int i = 0; i < 10; i++) {
          final entity = await collection.get(entityIds[i]);
          expect(entity, isNotNull);
          expect(entity!.name, 'Entity $i');
          expect(entity.value, i * 10);
        }

        await db.close();
      }
    });

    test('multiple insert persist with autoFlushOnClose', () async {
      final dbPath = tempDir.path;
      final entityIds = <String>[];

      // Session 1: Insert entities within a transaction
      {
        final db = await EntiDB.open(
          path: dbPath,
          config: EntiDBConfig.development().copyWith(autoFlushOnClose: true),
        );

        final collection = await db.collection<TestEntity>(
          'test',
          fromMap: TestEntity.fromMap,
        );

        // Insert entities directly (no transaction needed for this test)
        for (int i = 0; i < 5; i++) {
          final id = await collection.insert(
            TestEntity(name: 'Txn Entity $i', value: i * 100),
          );
          entityIds.add(id);
        }

        expect(await collection.count, 5);

        await db.close();
      }

      // Session 2: Verify transactional entities persisted
      {
        final db = await EntiDB.open(
          path: dbPath,
          config: EntiDBConfig.development(),
        );

        final collection = await db.collection<TestEntity>(
          'test',
          fromMap: TestEntity.fromMap,
        );

        expect(await collection.count, 5);

        for (int i = 0; i < 5; i++) {
          final entity = await collection.get(entityIds[i]);
          expect(entity, isNotNull);
          expect(entity!.name, 'Txn Entity $i');
          expect(entity.value, i * 100);
        }

        await db.close();
      }
    });
  });
}
