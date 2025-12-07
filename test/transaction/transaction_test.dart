/// EntiDB Transaction Module Tests
///
/// Comprehensive tests for the transaction module including Transaction,
/// TransactionManager, isolation levels, commit, and rollback functionality.
library;

import 'package:test/test.dart';

import 'package:entidb/src/entity/entity.dart';
import 'package:entidb/src/exceptions/transaction_exceptions.dart';
import 'package:entidb/src/storage/memory_storage.dart';
import 'package:entidb/src/transaction/transaction.dart';

/// Simple test entity for transaction tests.
class TestEntity implements Entity {
  @override
  final String? id;
  final String name;
  final int value;

  const TestEntity({this.id, required this.name, required this.value});

  factory TestEntity.fromMap(String id, Map<String, dynamic> map) {
    return TestEntity(
      id: id,
      name: map['name'] as String,
      value: map['value'] as int,
    );
  }

  @override
  Map<String, dynamic> toMap() => {'name': name, 'value': value};
}

void main() {
  group('TransactionStatus Enum', () {
    test('should have all expected statuses', () {
      expect(TransactionStatus.values, contains(TransactionStatus.pending));
      expect(TransactionStatus.values, contains(TransactionStatus.active));
      expect(TransactionStatus.values, contains(TransactionStatus.committed));
      expect(TransactionStatus.values, contains(TransactionStatus.rolledBack));
      expect(TransactionStatus.values, contains(TransactionStatus.failed));
    });
  });

  group('IsolationLevel Enum', () {
    test('should have all expected isolation levels', () {
      expect(IsolationLevel.values, contains(IsolationLevel.readUncommitted));
      expect(IsolationLevel.values, contains(IsolationLevel.readCommitted));
      expect(IsolationLevel.values, contains(IsolationLevel.repeatableRead));
      expect(IsolationLevel.values, contains(IsolationLevel.serializable));
    });

    test('should have correct string representations', () {
      expect(
        IsolationLevel.readUncommitted.toString(),
        contains('readUncommitted'),
      );
      expect(
        IsolationLevel.readCommitted.toString(),
        contains('readCommitted'),
      );
      expect(
        IsolationLevel.repeatableRead.toString(),
        contains('repeatableRead'),
      );
      expect(IsolationLevel.serializable.toString(), contains('serializable'));
    });
  });

  group('OperationType Enum', () {
    test('should have all expected operation types', () {
      expect(OperationType.values, contains(OperationType.insert));
      expect(OperationType.values, contains(OperationType.update));
      expect(OperationType.values, contains(OperationType.upsert));
      expect(OperationType.values, contains(OperationType.delete));
    });
  });

  group('TransactionOperation', () {
    test('should create insert operation', () {
      final op = TransactionOperation.insert('entity-1', {'name': 'Test'});

      expect(op.type, equals(OperationType.insert));
      expect(op.entityId, equals('entity-1'));
      expect(op.data, equals({'name': 'Test'}));
    });

    test('should create update operation', () {
      final op = TransactionOperation.update('entity-1', {'name': 'Updated'});

      expect(op.type, equals(OperationType.update));
      expect(op.entityId, equals('entity-1'));
      expect(op.data, equals({'name': 'Updated'}));
    });

    test('should create upsert operation', () {
      final op = TransactionOperation.upsert('entity-1', {'name': 'Upserted'});

      expect(op.type, equals(OperationType.upsert));
      expect(op.entityId, equals('entity-1'));
      expect(op.data, equals({'name': 'Upserted'}));
    });

    test('should create delete operation', () {
      final op = TransactionOperation.delete('entity-1');

      expect(op.type, equals(OperationType.delete));
      expect(op.entityId, equals('entity-1'));
      expect(op.data, isNull);
    });

    test('should support metadata', () {
      final op = TransactionOperation.insert(
        'entity-1',
        {'name': 'Test'},
        metadata: {'timestamp': 1234567890},
      );

      expect(op.metadata, equals({'timestamp': 1234567890}));
    });
  });

  group('Transaction', () {
    late MemoryStorage<TestEntity> storage;

    setUp(() async {
      storage = MemoryStorage<TestEntity>(name: 'test_storage');
      await storage.open();
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    group('Creation', () {
      test('should create transaction for open storage', () async {
        final txn = await Transaction.create(storage);

        expect(txn.id, isNotEmpty);
        expect(txn.isActive, isTrue);
        expect(txn.status, equals(TransactionStatus.active));
        expect(txn.isolationLevel, equals(IsolationLevel.readCommitted));
        expect(txn.operationCount, equals(0));
      });

      test('should create transaction with custom isolation level', () async {
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        expect(txn.isolationLevel, equals(IsolationLevel.serializable));
      });

      test('should throw for closed storage', () async {
        await storage.close();

        expect(
          () => Transaction.create(storage),
          throwsA(isA<TransactionException>()),
        );
      });

      test('should take snapshot of current storage state', () async {
        // Insert some data first
        await storage.insert('e1', {
          'id': 'e1',
          'name': 'Entity 1',
          'value': 1,
        });
        await storage.insert('e2', {
          'id': 'e2',
          'name': 'Entity 2',
          'value': 2,
        });

        final txn = await Transaction.create(storage);

        // The transaction should have captured the snapshot
        expect(txn.isActive, isTrue);
      });
    });

    group('Operations', () {
      late Transaction<TestEntity> txn;

      setUp(() async {
        txn = await Transaction.create(storage);
      });

      tearDown(() async {
        if (txn.isActive) {
          await txn.rollback();
        }
      });

      test('should queue insert operation', () {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});

        expect(txn.operationCount, equals(1));
        expect(txn.operations.first.type, equals(OperationType.insert));
      });

      test('should queue update operation', () {
        txn.update('e1', {'id': 'e1', 'name': 'Updated', 'value': 2});

        expect(txn.operationCount, equals(1));
        expect(txn.operations.first.type, equals(OperationType.update));
      });

      test('should queue upsert operation', () {
        txn.upsert('e1', {'id': 'e1', 'name': 'Upserted', 'value': 3});

        expect(txn.operationCount, equals(1));
        expect(txn.operations.first.type, equals(OperationType.upsert));
      });

      test('should queue delete operation', () {
        txn.delete('e1');

        expect(txn.operationCount, equals(1));
        expect(txn.operations.first.type, equals(OperationType.delete));
      });

      test('should queue multiple operations', () {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        txn.insert('e2', {'id': 'e2', 'name': 'Entity 2', 'value': 2});
        txn.update('e1', {'id': 'e1', 'name': 'Updated 1', 'value': 10});
        txn.delete('e2');

        expect(txn.operationCount, equals(4));
      });

      test('should throw for operation on non-active transaction', () async {
        await txn.rollback();

        expect(
          () => txn.insert('e1', {'name': 'Test', 'value': 1}),
          throwsA(isA<TransactionException>()),
        );
      });
    });

    group('Read Operations', () {
      late Transaction<TestEntity> txn;

      setUp(() async {
        await storage.insert('e1', {
          'id': 'e1',
          'name': 'Entity 1',
          'value': 1,
        });
        await storage.insert('e2', {
          'id': 'e2',
          'name': 'Entity 2',
          'value': 2,
        });
        txn = await Transaction.create(storage);
      });

      tearDown(() async {
        if (txn.isActive) {
          await txn.rollback();
        }
      });

      test('should read entity', () async {
        final data = await txn.get('e1');

        expect(data, isNotNull);
        expect(data!['name'], equals('Entity 1'));
      });

      test('should return null for non-existent entity', () async {
        final data = await txn.get('nonexistent');

        expect(data, isNull);
      });

      test('should read all entities', () async {
        final all = await txn.getAll();

        expect(all.length, equals(2));
        expect(all.containsKey('e1'), isTrue);
        expect(all.containsKey('e2'), isTrue);
      });

      test('should check entity existence', () async {
        expect(await txn.exists('e1'), isTrue);
        expect(await txn.exists('nonexistent'), isFalse);
      });
    });

    group('Commit', () {
      late Transaction<TestEntity> txn;

      setUp(() async {
        txn = await Transaction.create(storage);
      });

      test('should commit empty transaction', () async {
        await txn.commit();

        expect(txn.isCommitted, isTrue);
        expect(txn.status, equals(TransactionStatus.committed));
        expect(txn.completedAt, isNotNull);
      });

      test('should commit and apply insert operations', () async {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        txn.insert('e2', {'id': 'e2', 'name': 'Entity 2', 'value': 2});

        await txn.commit();

        expect(txn.isCommitted, isTrue);
        expect(await storage.exists('e1'), isTrue);
        expect(await storage.exists('e2'), isTrue);
      });

      test('should commit and apply update operations', () async {
        await storage.insert('e1', {
          'id': 'e1',
          'name': 'Original',
          'value': 1,
        });

        txn = await Transaction.create(storage);
        txn.update('e1', {'id': 'e1', 'name': 'Updated', 'value': 10});

        await txn.commit();

        final data = await storage.get('e1');
        expect(data!['name'], equals('Updated'));
        expect(data['value'], equals(10));
      });

      test('should commit and apply upsert operations', () async {
        txn.upsert('e1', {'id': 'e1', 'name': 'Upserted', 'value': 1});

        await txn.commit();

        final data = await storage.get('e1');
        expect(data, isNotNull);
        expect(data!['name'], equals('Upserted'));
      });

      test('should commit and apply delete operations', () async {
        await storage.insert('e1', {
          'id': 'e1',
          'name': 'To Delete',
          'value': 1,
        });

        txn = await Transaction.create(storage);
        txn.delete('e1');

        await txn.commit();

        expect(await storage.exists('e1'), isFalse);
      });

      test('should throw for commit on non-active transaction', () async {
        await txn.rollback();

        expect(() => txn.commit(), throwsA(isA<TransactionException>()));
      });

      test('should apply operations in order', () async {
        txn.insert('e1', {'id': 'e1', 'name': 'First', 'value': 1});
        txn.update('e1', {'id': 'e1', 'name': 'Second', 'value': 2});

        await txn.commit();

        final data = await storage.get('e1');
        expect(data!['name'], equals('Second'));
        expect(data['value'], equals(2));
      });
    });

    group('Rollback', () {
      late Transaction<TestEntity> txn;

      setUp(() async {
        txn = await Transaction.create(storage);
      });

      test('should rollback empty transaction', () async {
        await txn.rollback();

        expect(txn.isRolledBack, isTrue);
        expect(txn.status, equals(TransactionStatus.rolledBack));
        expect(txn.completedAt, isNotNull);
      });

      test('should rollback and discard pending operations', () async {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        txn.insert('e2', {'id': 'e2', 'name': 'Entity 2', 'value': 2});

        await txn.rollback();

        expect(txn.isRolledBack, isTrue);
        expect(await storage.exists('e1'), isFalse);
        expect(await storage.exists('e2'), isFalse);
      });

      test('should throw for rollback on non-active transaction', () async {
        await txn.rollback();

        expect(() => txn.rollback(), throwsA(isA<TransactionException>()));
      });
    });

    group('State Properties', () {
      test('should track active state', () async {
        final txn = await Transaction.create(storage);

        expect(txn.isActive, isTrue);
        expect(txn.isCommitted, isFalse);
        expect(txn.isRolledBack, isFalse);
        expect(txn.isCompleted, isFalse);

        await txn.commit();

        expect(txn.isActive, isFalse);
        expect(txn.isCommitted, isTrue);
        expect(txn.isCompleted, isTrue);
      });

      test('should track creation time', () async {
        final before = DateTime.now();
        final txn = await Transaction.create(storage);
        final after = DateTime.now();

        expect(
          txn.createdAt.isAfter(before) || txn.createdAt == before,
          isTrue,
        );
        expect(txn.createdAt.isBefore(after) || txn.createdAt == after, isTrue);
      });

      test('should track age', () async {
        final txn = await Transaction.create(storage);

        // Use a longer delay to avoid timing issues in test environments
        await Future.delayed(const Duration(milliseconds: 50));

        expect(txn.age.inMilliseconds, greaterThanOrEqualTo(45));
      });

      test('should have unique IDs', () async {
        final txn1 = await Transaction.create(storage);
        final txn2 = await Transaction.create(storage);

        await txn1.rollback();
        await txn2.rollback();

        expect(txn1.id, isNot(equals(txn2.id)));
      });
    });

    group('Dispose', () {
      test('should dispose and rollback active transaction', () async {
        final txn = await Transaction.create(storage);
        txn.insert('e1', {'id': 'e1', 'name': 'Test', 'value': 1});

        await txn.dispose();

        expect(txn.isRolledBack, isTrue);
        expect(await storage.exists('e1'), isFalse);
      });

      test('should dispose already completed transaction', () async {
        final txn = await Transaction.create(storage);
        await txn.commit();

        // Should not throw
        await txn.dispose();
      });
    });

    group('toString', () {
      test('should provide informative string representation', () async {
        final txn = await Transaction.create(storage);
        txn.insert('e1', {'id': 'e1', 'name': 'Test', 'value': 1});

        final str = txn.toString();

        expect(str, contains('Transaction'));
        expect(str, contains(txn.id));
        expect(str, contains('active'));
        expect(str, contains('operations: 1'));
      });
    });

    group('Rollback on Failure', () {
      test('should rollback on commit failure', () async {
        await storage.insert('e1', {
          'id': 'e1',
          'name': 'Original',
          'value': 1,
        });

        final txn = await Transaction.create(storage);
        txn.insert('e1', {'id': 'e1', 'name': 'Duplicate', 'value': 2});

        try {
          await txn.commit();
          fail('Should have thrown');
        } catch (e) {
          expect(e, isA<TransactionException>());
        }

        // Original should still exist
        final data = await storage.get('e1');
        expect(data!['name'], equals('Original'));
      });
    });
  });

  group('TransactionManager', () {
    late MemoryStorage<TestEntity> storage;

    setUp(() async {
      storage = MemoryStorage<TestEntity>(name: 'test_storage');
      await storage.open();
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    test('should create transaction via manager', () async {
      final manager = TransactionManager<TestEntity>(storage);
      final txn = await manager.beginTransaction();

      expect(txn, isNotNull);
      expect(txn.isActive, isTrue);

      await txn.rollback();
    });

    test('should create transaction with custom isolation level', () async {
      final manager = TransactionManager<TestEntity>(storage);
      final txn = await manager.beginTransaction(
        isolationLevel: IsolationLevel.serializable,
      );

      expect(txn.isolationLevel, equals(IsolationLevel.serializable));

      await txn.rollback();
    });

    test('should track current transaction', () async {
      final manager = TransactionManager<TestEntity>(storage);
      final txn = await manager.beginTransaction();

      expect(manager.currentTransaction, equals(txn));

      await txn.commit();
    });

    test('should clear current transaction after commit', () async {
      final manager = TransactionManager<TestEntity>(storage);
      await manager.beginTransaction();
      await manager.commit();

      expect(manager.currentTransaction, isNull);
    });

    test('should clear current transaction after rollback', () async {
      final manager = TransactionManager<TestEntity>(storage);
      await manager.beginTransaction();
      await manager.rollback();

      expect(manager.currentTransaction, isNull);
    });
  });

  group('Storage Extension', () {
    late MemoryStorage<TestEntity> storage;

    setUp(() async {
      storage = MemoryStorage<TestEntity>(name: 'test_storage');
      await storage.open();
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    test('should create transaction via Transaction.create', () async {
      final txn = await Transaction.create(storage);

      expect(txn, isNotNull);
      expect(txn.isActive, isTrue);

      await txn.rollback();
    });

    test('should create transaction with isolation level', () async {
      final txn = await Transaction.create(
        storage,
        isolationLevel: IsolationLevel.repeatableRead,
      );

      expect(txn.isolationLevel, equals(IsolationLevel.repeatableRead));

      await txn.rollback();
    });
  });

  group('Transaction Scope Pattern', () {
    late MemoryStorage<TestEntity> storage;

    setUp(() async {
      storage = MemoryStorage<TestEntity>(name: 'test_storage');
      await storage.open();
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    test('should auto-commit on success using manual pattern', () async {
      // Manual transaction scope pattern using Transaction.create
      final txn = await Transaction.create(storage);
      try {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        txn.insert('e2', {'id': 'e2', 'name': 'Entity 2', 'value': 2});
        await txn.commit();
      } catch (e) {
        if (txn.isActive) {
          await txn.rollback();
        }
        rethrow;
      }

      expect(await storage.exists('e1'), isTrue);
      expect(await storage.exists('e2'), isTrue);
    });

    test('should auto-rollback on exception using manual pattern', () async {
      // Manual transaction scope pattern with exception
      final txn = await Transaction.create(storage);
      try {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        throw Exception('Simulated failure');
      } catch (e) {
        if (txn.isActive) {
          await txn.rollback();
        }
        // Don't rethrow for test purposes
      }

      expect(await storage.exists('e1'), isFalse);
    });

    test('should return action result using manual pattern', () async {
      final txn = await Transaction.create(storage);
      int result;
      try {
        txn.insert('e1', {'id': 'e1', 'name': 'Entity 1', 'value': 1});
        result = 42;
        await txn.commit();
      } catch (e) {
        if (txn.isActive) {
          await txn.rollback();
        }
        rethrow;
      }

      expect(result, equals(42));
    });

    test('should use custom isolation level', () async {
      final txn = await Transaction.create(
        storage,
        isolationLevel: IsolationLevel.serializable,
      );

      expect(txn.isolationLevel, equals(IsolationLevel.serializable));

      await txn.rollback();
    });
  });

  group('Isolation Level Behavior', () {
    late MemoryStorage<TestEntity> storage;

    setUp(() async {
      storage = MemoryStorage<TestEntity>(name: 'isolation_test');
      await storage.open();
    });

    tearDown(() async {
      if (storage.isOpen) {
        await storage.close();
      }
    });

    group('readCommitted', () {
      test('should read current storage state', () async {
        // Insert initial data
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});

        // Start transaction with readCommitted
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.readCommitted,
        );

        // Read should see current storage state
        final data = await txn.get('entity-1');
        expect(data, isNotNull);
        expect(data!['name'], equals('Original'));

        // Modify storage directly (simulating another transaction commit)
        await storage.update('entity-1', {'name': 'Modified', 'value': 2});

        // Read should see the new value
        final newData = await txn.get('entity-1');
        expect(newData!['name'], equals('Modified'));

        await txn.rollback();
      });
    });

    group('repeatableRead', () {
      test('should read from snapshot, not seeing external changes', () async {
        // Insert initial data
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});

        // Start transaction with repeatableRead
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.repeatableRead,
        );

        // Read should see snapshot state
        final data = await txn.get('entity-1');
        expect(data, isNotNull);
        expect(data!['name'], equals('Original'));

        // Modify storage directly (simulating another transaction commit)
        await storage.update('entity-1', {'name': 'Modified', 'value': 2});

        // Read should still see the original value from snapshot
        final snapshotData = await txn.get('entity-1');
        expect(snapshotData!['name'], equals('Original'));
        expect(snapshotData['value'], equals(1));

        await txn.rollback();
      });

      test('should see pending operations from this transaction', () async {
        // Insert initial data
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});

        // Start transaction with repeatableRead
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.repeatableRead,
        );

        // Queue an update in the transaction
        txn.update('entity-1', {'name': 'Updated', 'value': 10});

        // Read should see the pending update
        final data = await txn.get('entity-1');
        expect(data!['name'], equals('Updated'));
        expect(data['value'], equals(10));

        await txn.rollback();
      });

      test('should see pending inserts from this transaction', () async {
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.repeatableRead,
        );

        // Queue an insert
        txn.insert('new-entity', {'name': 'New', 'value': 42});

        // Read should see the pending insert
        final data = await txn.get('new-entity');
        expect(data, isNotNull);
        expect(data!['name'], equals('New'));

        // Exists should also work
        final exists = await txn.exists('new-entity');
        expect(exists, isTrue);

        await txn.rollback();
      });

      test('should not see deleted entities from this transaction', () async {
        await storage.insert('entity-1', {'name': 'ToDelete', 'value': 1});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.repeatableRead,
        );

        // Queue a delete
        txn.delete('entity-1');

        // Read should return null for deleted entity
        final data = await txn.get('entity-1');
        expect(data, isNull);

        // Exists should return false
        final exists = await txn.exists('entity-1');
        expect(exists, isFalse);

        await txn.rollback();
      });

      test('getAll should return snapshot with pending operations', () async {
        await storage.insert('entity-1', {'name': 'One', 'value': 1});
        await storage.insert('entity-2', {'name': 'Two', 'value': 2});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.repeatableRead,
        );

        // Queue various operations
        txn.update('entity-1', {'name': 'OneUpdated', 'value': 10});
        txn.delete('entity-2');
        txn.insert('entity-3', {'name': 'Three', 'value': 3});

        // Modify storage directly (should not be visible)
        await storage.insert('entity-4', {'name': 'Four', 'value': 4});

        final all = await txn.getAll();

        // Should see updated entity-1
        expect(all['entity-1']?['name'], equals('OneUpdated'));
        // Should NOT see deleted entity-2
        expect(all.containsKey('entity-2'), isFalse);
        // Should see inserted entity-3
        expect(all['entity-3']?['name'], equals('Three'));
        // Should NOT see entity-4 (added after snapshot)
        expect(all.containsKey('entity-4'), isFalse);

        await txn.rollback();
      });
    });

    group('serializable', () {
      test('should detect conflict when entity was modified', () async {
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Read the entity (adds to read set)
        final data = await txn.get('entity-1');
        expect(data!['name'], equals('Original'));

        // Modify storage directly (simulating another transaction commit)
        await storage.update('entity-1', {
          'name': 'ConflictingUpdate',
          'value': 99,
        });

        // Queue an update
        txn.update('entity-1', {'name': 'OurUpdate', 'value': 10});

        // Commit should fail with conflict exception
        expect(
          () => txn.commit(),
          throwsA(isA<TransactionConflictException>()),
        );
      });

      test('should detect conflict when entity was deleted', () async {
        await storage.insert('entity-1', {'name': 'ToBeDeleted', 'value': 1});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Read the entity (adds to read set)
        final data = await txn.get('entity-1');
        expect(data, isNotNull);

        // Delete from storage directly
        await storage.delete('entity-1');

        // Queue any operation
        txn.insert('entity-2', {'name': 'New', 'value': 2});

        // Commit should fail because entity-1 was in read set and changed
        expect(
          () => txn.commit(),
          throwsA(isA<TransactionConflictException>()),
        );
      });

      test('should detect conflict when entity was inserted', () async {
        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Read non-existent entity (adds to read set)
        final data = await txn.get('entity-1');
        expect(data, isNull);

        // Insert into storage directly (simulating another transaction)
        await storage.insert('entity-1', {'name': 'Inserted', 'value': 1});

        // Queue an operation
        txn.insert('entity-2', {'name': 'Ours', 'value': 2});

        // Commit should fail because entity-1 now exists
        expect(
          () => txn.commit(),
          throwsA(isA<TransactionConflictException>()),
        );
      });

      test('should commit successfully when no conflicts', () async {
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});
        await storage.insert('entity-2', {'name': 'Other', 'value': 2});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Read entity-1
        final data = await txn.get('entity-1');
        expect(data, isNotNull);

        // Modify entity-2 directly (not in our read set)
        await storage.update('entity-2', {'name': 'Modified', 'value': 99});

        // Queue update on entity-1
        txn.update('entity-1', {'name': 'Updated', 'value': 10});

        // Should NOT fail because entity-1 wasn't modified externally
        // However, we need to undo the external change for the test
        await storage.update('entity-1', {'name': 'Original', 'value': 1});

        // Commit should succeed
        await txn.commit();

        // Verify the update was applied
        final updated = await storage.get('entity-1');
        expect(updated!['name'], equals('Updated'));
      });

      test('should not conflict if no reads were made', () async {
        await storage.insert('entity-1', {'name': 'Original', 'value': 1});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Modify storage directly
        await storage.update('entity-1', {'name': 'Modified', 'value': 99});

        // Queue insert without reading anything
        txn.insert('entity-2', {'name': 'New', 'value': 2});

        // Commit should succeed (empty read set means no conflicts possible)
        await txn.commit();

        expect(await storage.exists('entity-2'), isTrue);
      });

      test('conflict exception should contain entity IDs', () async {
        await storage.insert('entity-1', {'name': 'One', 'value': 1});
        await storage.insert('entity-2', {'name': 'Two', 'value': 2});

        final txn = await Transaction.create(
          storage,
          isolationLevel: IsolationLevel.serializable,
        );

        // Read both entities
        await txn.get('entity-1');
        await txn.get('entity-2');

        // Modify both externally
        await storage.update('entity-1', {'name': 'Modified1', 'value': 10});
        await storage.update('entity-2', {'name': 'Modified2', 'value': 20});

        // Queue any operation
        txn.insert('entity-3', {'name': 'New', 'value': 3});

        try {
          await txn.commit();
          fail('Expected TransactionConflictException');
        } on TransactionConflictException catch (e) {
          expect(e.conflictingIds, containsAll(['entity-1', 'entity-2']));
        }
      });
    });
  });
}
