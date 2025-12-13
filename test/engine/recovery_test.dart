/// Tests for WAL Recovery Integration.
///
/// Tests the integration between PagedStorage, Pager, and the WAL
/// recovery system.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:entidb/src/engine/storage/pager.dart';
import 'package:entidb/src/engine/storage/recovery.dart';
import 'package:entidb/src/engine/wal/wal_record.dart';
import 'package:entidb/src/engine/wal/wal_writer.dart';

void main() {
  group('RecoveryConfig', () {
    test('should have disabled as default', () {
      const config = RecoveryConfig.disabled;
      expect(config.isEnabled, isFalse);
      expect(config.walDirectory, isNull);
    });

    test('should enable with factory', () {
      final config = RecoveryConfig.enabled(walDirectory: '/tmp/wal');
      expect(config.isEnabled, isTrue);
      expect(config.walDirectory, '/tmp/wal');
    });

    test('should have default values', () {
      final config = RecoveryConfig.enabled(walDirectory: '/tmp/wal');
      expect(config.deleteWalAfterRecovery, isTrue);
      expect(config.throwOnRecoveryError, isTrue);
    });
  });

  group('StorageRecoveryHandler', () {
    test('should track insert operations', () async {
      final insertedEntities = <String, Map<String, dynamic>>{};

      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {
          insertedEntities[id] = data!;
        },
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      await handler.redoInsert(
        DataOperationPayload.insert(
          collectionName: 'test',
          entityId: 'entity-1',
          data: {'name': 'Test'},
        ),
      );

      expect(handler.insertCount, 1);
      expect(insertedEntities['entity-1'], {'name': 'Test'});
    });

    test('should track update operations', () async {
      final updatedEntities = <String, Map<String, dynamic>>{};

      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {
          updatedEntities[id] = data!;
        },
        onDelete: (collection, id, data) async {},
      );

      await handler.redoUpdate(
        DataOperationPayload.update(
          collectionName: 'test',
          entityId: 'entity-1',
          before: {'name': 'Old'},
          after: {'name': 'New'},
        ),
      );

      expect(handler.updateCount, 1);
      expect(updatedEntities['entity-1'], {'name': 'New'});
    });

    test('should track delete operations', () async {
      final deletedIds = <String>[];

      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {
          deletedIds.add(id);
        },
      );

      await handler.redoDelete(
        DataOperationPayload.delete(
          collectionName: 'test',
          entityId: 'entity-1',
          data: {'name': 'Test'},
        ),
      );

      expect(handler.deleteCount, 1);
      expect(deletedIds, contains('entity-1'));
    });

    test('should calculate total operations', () async {
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      await handler.redoInsert(
        DataOperationPayload.insert(
          collectionName: 'test',
          entityId: '1',
          data: {},
        ),
      );
      await handler.redoUpdate(
        DataOperationPayload.update(
          collectionName: 'test',
          entityId: '2',
          before: {},
          after: {},
        ),
      );
      await handler.redoDelete(
        DataOperationPayload.delete(
          collectionName: 'test',
          entityId: '3',
          data: {},
        ),
      );

      expect(handler.totalCount, 3);
    });

    test('should reset counters', () async {
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      await handler.redoInsert(
        DataOperationPayload.insert(
          collectionName: 'test',
          entityId: '1',
          data: {},
        ),
      );

      expect(handler.totalCount, 1);
      handler.reset();
      expect(handler.totalCount, 0);
    });
  });

  group('RecoveryResult', () {
    test('should indicate no recovery needed', () {
      const result = RecoveryResult.noRecoveryNeeded;
      expect(result.recoveryNeeded, isFalse);
      expect(result.success, isTrue);
    });

    test('should calculate total operations', () {
      const result = RecoveryResult(
        recoveryNeeded: true,
        success: true,
        insertCount: 5,
        updateCount: 3,
        deleteCount: 2,
      );
      expect(result.totalOperations, 10);
    });

    test('should have meaningful toString', () {
      const result = RecoveryResult.noRecoveryNeeded;
      expect(result.toString(), contains('no recovery needed'));

      const failedResult = RecoveryResult(
        recoveryNeeded: true,
        success: false,
        errorMessage: 'Test error',
      );
      expect(failedResult.toString(), contains('failed'));
      expect(failedResult.toString(), contains('Test error'));
    });
  });

  group('DatabaseRecovery', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('recovery_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should return no recovery needed for empty directory', () async {
      final config = RecoveryConfig.enabled(walDirectory: tempDir.path);
      final recovery = DatabaseRecovery(config: config);
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final result = await recovery.recover(handler);
      expect(result.recoveryNeeded, isFalse);
    });

    test('should return no recovery needed for disabled config', () async {
      const config = RecoveryConfig.disabled;
      final recovery = DatabaseRecovery(config: config);
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final result = await recovery.recover(handler);
      expect(result.recoveryNeeded, isFalse);
    });

    test('should recover committed transactions from WAL', () async {
      // Create a WAL with committed transactions
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
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

      // Perform recovery
      final recoveredEntities = <String, Map<String, dynamic>>{};
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {
          recoveredEntities[id] = data!;
        },
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final config = RecoveryConfig.enabled(
        walDirectory: tempDir.path,
        deleteWalAfterRecovery: false,
      );
      final recovery = DatabaseRecovery(config: config);
      final result = await recovery.recover(handler);

      expect(result.recoveryNeeded, isTrue);
      expect(result.success, isTrue);
      expect(result.insertCount, 1);
      expect(result.committedTransactions, 1);
      expect(recoveredEntities['user-1'], {'name': 'Alice'});
    });

    test('should not recover aborted transactions', () async {
      // Create a WAL with an aborted transaction
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.logInsert(
        transactionId: txnId,
        collectionName: 'users',
        entityId: 'user-aborted',
        data: {'name': 'Should Not Recover'},
      );
      await writer.abortTransaction(txnId);
      await writer.close();

      // Perform recovery
      final recoveredEntities = <String, Map<String, dynamic>>{};
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {
          recoveredEntities[id] = data!;
        },
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final config = RecoveryConfig.enabled(
        walDirectory: tempDir.path,
        deleteWalAfterRecovery: false,
      );
      final recovery = DatabaseRecovery(config: config);
      final result = await recovery.recover(handler);

      expect(result.recoveryNeeded, isTrue);
      expect(result.success, isTrue);
      expect(result.insertCount, 0);
      expect(result.abortedTransactions, 1);
      expect(recoveredEntities.containsKey('user-aborted'), isFalse);
    });

    test('should delete WAL after recovery when configured', () async {
      // Create a WAL
      final walConfig = WalConfig.development(tempDir.path);
      final writer = WalWriter(config: walConfig);
      await writer.open();

      final txnId = await writer.beginTransaction();
      await writer.commitTransaction(txnId);
      await writer.close();

      // Verify WAL exists
      final walFiles = tempDir.listSync().where(
        (f) => f.path.endsWith('.log') || f.path.endsWith('.wal'),
      );
      expect(walFiles, isNotEmpty);

      // Perform recovery with delete enabled
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final config = RecoveryConfig.enabled(
        walDirectory: tempDir.path,
        deleteWalAfterRecovery: true,
      );
      final recovery = DatabaseRecovery(config: config);
      await recovery.recover(handler);

      // Verify WAL was deleted
      final remainingWalFiles = tempDir.listSync().where(
        (f) => f.path.endsWith('.log') || f.path.endsWith('.wal'),
      );
      expect(remainingWalFiles, isEmpty);
    });
  });

  group('Pager Recovery Integration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pager_recovery_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should detect clean shutdown', () async {
      final dbPath = '${tempDir.path}/test.db';

      // Create and close pager cleanly
      final pager = await Pager.open(dbPath);
      await pager.close();

      // Reopen and check
      final pager2 = await Pager.open(dbPath);
      expect(pager2.recoveredFromDirtyShutdown, isFalse);
      await pager2.close();
    });

    test('should have recovery result after performRecovery', () async {
      final dbPath = '${tempDir.path}/test.db';
      final walPath = '${tempDir.path}/wal';
      await Directory(walPath).create();

      // Create pager
      final pager = await Pager.open(dbPath);

      // Perform recovery (even without dirty shutdown)
      final handler = StorageRecoveryHandler(
        onInsert: (collection, id, data) async {},
        onUpdate: (collection, id, data) async {},
        onDelete: (collection, id, data) async {},
      );

      final config = RecoveryConfig.enabled(walDirectory: walPath);
      final result = await pager.performRecovery(config, handler);

      expect(result, isNotNull);
      await pager.close();
    });
  });
}
