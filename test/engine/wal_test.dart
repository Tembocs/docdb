/// Write-Ahead Log (WAL) Tests.
///
/// Comprehensive tests for the WAL module including:
/// - WAL record serialization/deserialization
/// - WAL writer operations
/// - WAL reader operations
/// - Crash recovery scenarios
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:entidb/src/engine/wal/wal_constants.dart';
import 'package:entidb/src/engine/wal/wal_record.dart';
import 'package:entidb/src/engine/wal/wal_reader.dart';
import 'package:entidb/src/engine/wal/wal_writer.dart';

void main() {
  group('WalRecordType', () {
    test('should have correct values', () {
      expect(WalRecordType.beginTransaction.value, 1);
      expect(WalRecordType.commitTransaction.value, 2);
      expect(WalRecordType.abortTransaction.value, 3);
      expect(WalRecordType.insert.value, 4);
      expect(WalRecordType.update.value, 5);
      expect(WalRecordType.delete.value, 6);
      expect(WalRecordType.checkpoint.value, 7);
      expect(WalRecordType.endOfLog.value, 255);
    });

    test('should convert from value', () {
      expect(WalRecordType.fromValue(1), WalRecordType.beginTransaction);
      expect(WalRecordType.fromValue(2), WalRecordType.commitTransaction);
      expect(WalRecordType.fromValue(7), WalRecordType.checkpoint);
    });

    test('should throw for invalid value', () {
      expect(() => WalRecordType.fromValue(0), throwsA(isA<ArgumentError>()));
      expect(() => WalRecordType.fromValue(99), throwsA(isA<ArgumentError>()));
    });
  });

  group('Lsn', () {
    test('should create with value', () {
      final lsn = Lsn(1000);
      expect(lsn.value, 1000);
    });

    test('should have first LSN constant', () {
      expect(Lsn.first.value, WalHeaderConstants.headerSize);
    });

    test('should support comparison', () {
      final lsn1 = Lsn(100);
      final lsn2 = Lsn(200);
      final lsn3 = Lsn(100);

      expect(lsn1 < lsn2, isTrue);
      expect(lsn2 > lsn1, isTrue);
      expect(lsn1 == lsn3, isTrue);
      expect(lsn1 <= lsn3, isTrue);
      expect(lsn2 >= lsn1, isTrue);
    });

    test('should advance by offset', () {
      final lsn = Lsn(100);
      final advanced = lsn.advance(50);
      expect(advanced.value, 150);
    });
  });

  group('WalRecord', () {
    test('should serialize and deserialize transaction record', () {
      final record = WalRecord(
        type: WalRecordType.beginTransaction,
        transactionId: 1,
        lsn: Lsn(100),
        prevLsn: Lsn.invalid,
        payload: Uint8List(0),
      );

      expect(record.type, WalRecordType.beginTransaction);
      expect(record.lsn.value, 100);
      expect(record.transactionId, 1);

      final bytes = record.toBytes();
      final restored = WalRecord.fromBytes(bytes);

      expect(restored.type, WalRecordType.beginTransaction);
      expect(restored.transactionId, 1);
    });

    test('should serialize and deserialize commit record', () {
      final record = WalRecord(
        type: WalRecordType.commitTransaction,
        transactionId: 5,
        lsn: Lsn(200),
        prevLsn: Lsn(100),
        payload: Uint8List(0),
      );

      final bytes = record.toBytes();
      final restored = WalRecord.fromBytes(bytes);

      expect(restored.type, WalRecordType.commitTransaction);
      expect(restored.transactionId, 5);
    });

    test('should serialize and deserialize insert operation', () {
      final payload = DataOperationPayload.insert(
        collectionName: 'users',
        entityId: 'user-123',
        data: {'name': 'Alice', 'age': 30},
      );

      final record = WalRecord(
        type: WalRecordType.insert,
        transactionId: 10,
        lsn: Lsn(300),
        prevLsn: Lsn(250),
        payload: payload.toBytes(),
      );

      final bytes = record.toBytes();
      final restored = WalRecord.fromBytes(bytes);

      expect(restored.type, WalRecordType.insert);
      expect(restored.transactionId, 10);

      final restoredPayload = DataOperationPayload.fromBytes(restored.payload);
      expect(restoredPayload.collectionName, 'users');
      expect(restoredPayload.entityId, 'user-123');
      expect(restoredPayload.afterImage, {'name': 'Alice', 'age': 30});
    });

    test('should serialize and deserialize update operation', () {
      final payload = DataOperationPayload.update(
        collectionName: 'products',
        entityId: 'prod-1',
        before: {'price': 10},
        after: {'price': 20},
      );

      final record = WalRecord(
        type: WalRecordType.update,
        transactionId: 20,
        lsn: Lsn(400),
        prevLsn: Lsn(350),
        payload: payload.toBytes(),
      );

      final bytes = record.toBytes();
      final restored = WalRecord.fromBytes(bytes);

      expect(restored.type, WalRecordType.update);

      final restoredPayload = DataOperationPayload.fromBytes(restored.payload);
      expect(restoredPayload.collectionName, 'products');
      expect(restoredPayload.beforeImage, {'price': 10});
      expect(restoredPayload.afterImage, {'price': 20});
    });

    test('should serialize and deserialize delete operation', () {
      final payload = DataOperationPayload.delete(
        collectionName: 'orders',
        entityId: 'order-999',
        data: {'status': 'pending'},
      );

      final record = WalRecord(
        type: WalRecordType.delete,
        transactionId: 30,
        lsn: Lsn(500),
        prevLsn: Lsn(450),
        payload: payload.toBytes(),
      );

      final bytes = record.toBytes();
      final restored = WalRecord.fromBytes(bytes);

      expect(restored.type, WalRecordType.delete);

      final restoredPayload = DataOperationPayload.fromBytes(restored.payload);
      expect(restoredPayload.entityId, 'order-999');
      expect(restoredPayload.beforeImage, {'status': 'pending'});
      expect(restoredPayload.afterImage, isNull);
    });

    test('should detect corrupted checksum', () {
      final record = WalRecord(
        type: WalRecordType.beginTransaction,
        transactionId: 1,
        lsn: Lsn(100),
        prevLsn: Lsn.invalid,
        payload: Uint8List(0),
      );
      final bytes = record.toBytes();

      // Corrupt the checksum
      bytes[WalRecordOffsets.checksum] ^= 0xFF;

      expect(
        () => WalRecord.fromBytes(bytes),
        throwsA(isA<WalCorruptedException>()),
      );
    });
  });

  group('DataOperationPayload', () {
    test('should serialize with all fields', () {
      final payload = DataOperationPayload(
        collectionName: 'test_collection',
        entityId: 'doc-abc',
        beforeImage: {'old': 'value'},
        afterImage: {'new': 'value'},
      );

      final bytes = payload.toBytes();
      final restored = DataOperationPayload.fromBytes(bytes);

      expect(restored.collectionName, 'test_collection');
      expect(restored.entityId, 'doc-abc');
      expect(restored.beforeImage, {'old': 'value'});
      expect(restored.afterImage, {'new': 'value'});
    });

    test('should serialize with only collection and id', () {
      final payload = DataOperationPayload(
        collectionName: 'minimal',
        entityId: 'min-1',
      );

      final bytes = payload.toBytes();
      final restored = DataOperationPayload.fromBytes(bytes);

      expect(restored.collectionName, 'minimal');
      expect(restored.entityId, 'min-1');
      expect(restored.beforeImage, isNull);
      expect(restored.afterImage, isNull);
    });
  });

  group('WalWriter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wal_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should create WAL file on open', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();
      expect(writer.isOpen, isTrue);

      // Check that WAL file was created
      final files = await tempDir.list().toList();
      expect(files.any((f) => f.path.endsWith('.log')), isTrue);

      await writer.close();
      expect(writer.isOpen, isFalse);
    });

    test('should handle transaction lifecycle', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      // Begin transaction
      final txnId = await writer.beginTransaction();
      expect(txnId, greaterThan(0));
      expect(writer.activeTransactionCount, 1);

      // Log insert
      final insertLsn = await writer.logInsert(
        transactionId: txnId,
        collectionName: 'users',
        entityId: 'user-1',
        data: {'name': 'Alice'},
      );
      expect(insertLsn.value, greaterThan(0));

      // Commit transaction
      await writer.commitTransaction(txnId);
      expect(writer.activeTransactionCount, 0);

      await writer.close();
    });

    test('should handle multiple transactions', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      // Transaction 1: insert and commit
      final txn1 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn1,
        collectionName: 'products',
        entityId: 'prod-1',
        data: {'name': 'Widget', 'price': 10},
      );
      await writer.commitTransaction(txn1);

      // Transaction 2: update and abort
      final txn2 = await writer.beginTransaction();
      await writer.logUpdate(
        transactionId: txn2,
        collectionName: 'products',
        entityId: 'prod-1',
        before: {'name': 'Widget', 'price': 10},
        after: {'name': 'Widget', 'price': 20},
      );
      await writer.abortTransaction(txn2);

      // Transaction 3: delete and commit
      final txn3 = await writer.beginTransaction();
      await writer.logDelete(
        transactionId: txn3,
        collectionName: 'products',
        entityId: 'prod-1',
        data: {'name': 'Widget', 'price': 10},
      );
      await writer.commitTransaction(txn3);

      expect(writer.activeTransactionCount, 0);
      expect(writer.statistics.totalRecordsWritten, greaterThan(0));

      await writer.close();
    });

    test('should write checkpoint', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.commitTransaction(txnId);

      final checkpointLsn = await writer.checkpoint();
      expect(checkpointLsn.value, greaterThan(0));
      expect(writer.statistics.totalCheckpoints, 1);

      await writer.close();
    });

    test('should throw when operating after close', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();
      await writer.close();

      expect(() => writer.beginTransaction(), throwsA(isA<StateError>()));
    });

    test('should track statistics', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      final stats1 = writer.statistics;
      expect(stats1.totalRecordsWritten, 0);

      final txnId = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txnId,
        collectionName: 'test',
        entityId: 'id-1',
        data: {'value': 42},
      );
      await writer.commitTransaction(txnId);

      final stats2 = writer.statistics;
      expect(stats2.totalRecordsWritten, 3); // begin, insert, commit
      expect(stats2.totalBytesWritten, greaterThan(0));

      await writer.close();
    });
  });

  group('WalReader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wal_reader_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should read written records', () async {
      // First write some records
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txnId,
        collectionName: 'users',
        entityId: 'user-1',
        data: {'name': 'Alice'},
      );
      await writer.commitTransaction(txnId);

      await writer.close();

      // Now read the records
      final walFile = Directory(
        tempDir.path,
      ).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.log'));

      final reader = WalReader(filePath: walFile.path);
      final header = await reader.open();

      expect(header.version, WalHeaderConstants.currentVersion);
      expect(header.isClean, isTrue);

      final records = await reader.readAll();
      expect(records.length, 3); // begin, insert, commit

      expect(records[0].type, WalRecordType.beginTransaction);
      expect(records[1].type, WalRecordType.insert);
      expect(records[2].type, WalRecordType.commitTransaction);

      await reader.close();
    });

    test('should iterate with forEach', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      for (var i = 0; i < 5; i++) {
        final txnId = await writer.beginTransaction();
        await writer.commitTransaction(txnId);
      }

      await writer.close();

      final walFile = Directory(
        tempDir.path,
      ).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.log'));

      final reader = WalReader(filePath: walFile.path);
      await reader.open();

      var count = 0;
      await reader.forEach((record) async {
        count++;
        return true;
      });

      expect(count, 10); // 5 begin + 5 commit

      await reader.close();
    });
  });

  group('WalRecovery', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wal_recovery_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should recover committed transactions', () async {
      final config = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: config);

      await writer.open();

      // Committed transaction
      final txn1 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn1,
        collectionName: 'users',
        entityId: 'user-1',
        data: {'name': 'Alice'},
      );
      await writer.commitTransaction(txn1);

      // Aborted transaction
      final txn2 = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txn2,
        collectionName: 'users',
        entityId: 'user-2',
        data: {'name': 'Bob'},
      );
      await writer.abortTransaction(txn2);

      await writer.close();

      // Recovery
      final walFile = Directory(
        tempDir.path,
      ).listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.log'));

      final redoHandler = _TestRedoHandler();
      final recovery = WalRecovery(
        walFilePath: walFile.path,
        redoHandler: redoHandler,
      );

      final stats = await recovery.recover();

      expect(stats.committedTransactions, 1);
      expect(stats.abortedTransactions, 1);
      expect(stats.uncommittedTransactions, 0);
      expect(stats.redoOperations, 1);

      expect(redoHandler.insertedEntityIds, ['user-1']);
      expect(redoHandler.insertedEntityIds, isNot(contains('user-2')));
    });
  });
}

/// Test implementation of WalRedoHandler.
class _TestRedoHandler implements WalRedoHandler {
  final List<String> insertedEntityIds = [];
  final List<String> updatedEntityIds = [];
  final List<String> deletedEntityIds = [];

  @override
  Future<void> redoInsert(DataOperationPayload payload) async {
    insertedEntityIds.add(payload.entityId);
  }

  @override
  Future<void> redoUpdate(DataOperationPayload payload) async {
    updatedEntityIds.add(payload.entityId);
  }

  @override
  Future<void> redoDelete(DataOperationPayload payload) async {
    deletedEntityIds.add(payload.entityId);
  }
}
