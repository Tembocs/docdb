/// EntiDB Migration Module Tests
///
/// Comprehensive tests for the migration module including MigrationStrategy,
/// SingleEntityMigrationStrategy, NoOpMigrationStrategy, MigrationConfig,
/// MigrationRunner, MigrationManager, MigrationLog, and MigrationStep.
library;

import 'package:test/test.dart';

import 'package:entidb/src/entity/entity.dart';
import 'package:entidb/src/exceptions/migration_exceptions.dart';
import 'package:entidb/src/storage/memory_storage.dart';
import 'package:entidb/src/migration/migration.dart';

// =============================================================================
// Test Entity
// =============================================================================

/// Simple test entity for migration tests.
class TestEntity implements Entity {
  @override
  final String? id;
  final String name;
  final int version;
  final String? email;
  final String? username;

  const TestEntity({
    this.id,
    required this.name,
    required this.version,
    this.email,
    this.username,
  });

  factory TestEntity.fromMap(String id, Map<String, dynamic> map) {
    return TestEntity(
      id: id,
      name: map['name'] as String,
      version: map['version'] as int? ?? 1,
      email: map['email'] as String?,
      username: map['username'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'version': version,
    if (email != null) 'email': email,
    if (username != null) 'username': username,
  };
}

// =============================================================================
// Test Migration Strategies
// =============================================================================

/// Adds email field with default value.
class AddEmailFieldMigration extends SingleEntityMigrationStrategy {
  @override
  String get description => 'Add email field with default value';

  @override
  String get fromVersion => '1.0.0';

  @override
  String get toVersion => '1.1.0';

  @override
  Map<String, dynamic> transformUp(String id, Map<String, dynamic> data) {
    return {...data, 'email': data['email'] ?? 'unknown@example.com'};
  }

  @override
  Map<String, dynamic> transformDown(String id, Map<String, dynamic> data) {
    final newData = Map<String, dynamic>.from(data);
    newData.remove('email');
    return newData;
  }
}

/// Renames userName to username.
class RenameFieldMigration extends SingleEntityMigrationStrategy {
  @override
  String get description => 'Rename userName to username';

  @override
  String get fromVersion => '1.1.0';

  @override
  String get toVersion => '1.2.0';

  @override
  Map<String, dynamic> transformUp(String id, Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    if (result.containsKey('userName')) {
      result['username'] = result.remove('userName');
    }
    return result;
  }

  @override
  Map<String, dynamic> transformDown(String id, Map<String, dynamic> data) {
    final result = Map<String, dynamic>.from(data);
    if (result.containsKey('username')) {
      result['userName'] = result.remove('username');
    }
    return result;
  }
}

/// A batch migration that computes statistics.
class ComputeStatsMigration implements MigrationStrategy {
  @override
  String get description => 'Compute aggregate statistics';

  @override
  String get fromVersion => '1.2.0';

  @override
  String get toVersion => '2.0.0';

  @override
  Future<Map<String, Map<String, dynamic>>> up(
    Map<String, Map<String, dynamic>> entities,
  ) async {
    final totalCount = entities.length;
    return entities.map(
      (id, data) => MapEntry(id, {...data, 'totalPeers': totalCount - 1}),
    );
  }

  @override
  Future<Map<String, Map<String, dynamic>>> down(
    Map<String, Map<String, dynamic>> entities,
  ) async {
    return entities.map((id, data) {
      final result = Map<String, dynamic>.from(data);
      result.remove('totalPeers');
      return MapEntry(id, result);
    });
  }
}

void main() {
  group('MigrationOutcome Enum', () {
    test('should have all expected outcomes', () {
      expect(MigrationOutcome.values, contains(MigrationOutcome.success));
      expect(MigrationOutcome.values, contains(MigrationOutcome.failed));
      expect(MigrationOutcome.values, contains(MigrationOutcome.skipped));
      expect(MigrationOutcome.values, contains(MigrationOutcome.rolledBack));
    });

    test('should have 4 outcomes total', () {
      expect(MigrationOutcome.values.length, equals(4));
    });
  });

  group('NoOpMigrationStrategy', () {
    test('should create with required parameters', () {
      final strategy = NoOpMigrationStrategy(
        fromVersion: '1.0.0',
        toVersion: '1.0.1',
      );

      expect(strategy.fromVersion, equals('1.0.0'));
      expect(strategy.toVersion, equals('1.0.1'));
      expect(strategy.description, equals('No data changes required'));
    });

    test('should accept custom description', () {
      final strategy = NoOpMigrationStrategy(
        fromVersion: '1.0.0',
        toVersion: '1.0.1',
        description: 'Metadata only update',
      );

      expect(strategy.description, equals('Metadata only update'));
    });

    test('should pass entities unchanged on up', () async {
      final strategy = NoOpMigrationStrategy(
        fromVersion: '1.0.0',
        toVersion: '1.0.1',
      );

      final entities = {
        'e1': {'name': 'Entity 1', 'value': 1},
        'e2': {'name': 'Entity 2', 'value': 2},
      };

      final result = await strategy.up(entities);

      expect(result, equals(entities));
    });

    test('should pass entities unchanged on down', () async {
      final strategy = NoOpMigrationStrategy(
        fromVersion: '1.0.0',
        toVersion: '1.0.1',
      );

      final entities = {
        'e1': {'name': 'Entity 1', 'value': 1},
        'e2': {'name': 'Entity 2', 'value': 2},
      };

      final result = await strategy.down(entities);

      expect(result, equals(entities));
    });

    test('should handle empty entities', () async {
      final strategy = NoOpMigrationStrategy(
        fromVersion: '1.0.0',
        toVersion: '1.0.1',
      );

      final entities = <String, Map<String, dynamic>>{};

      final resultUp = await strategy.up(entities);
      final resultDown = await strategy.down(entities);

      expect(resultUp, isEmpty);
      expect(resultDown, isEmpty);
    });
  });

  group('SingleEntityMigrationStrategy', () {
    late AddEmailFieldMigration migration;

    setUp(() {
      migration = AddEmailFieldMigration();
    });

    test('should have correct version properties', () {
      expect(migration.fromVersion, equals('1.0.0'));
      expect(migration.toVersion, equals('1.1.0'));
      expect(
        migration.description,
        equals('Add email field with default value'),
      );
    });

    test('should add email field on up', () async {
      final entities = {
        'e1': {'name': 'Entity 1'},
        'e2': {'name': 'Entity 2'},
      };

      final result = await migration.up(entities);

      expect(result['e1']!['email'], equals('unknown@example.com'));
      expect(result['e2']!['email'], equals('unknown@example.com'));
    });

    test('should preserve existing email on up', () async {
      final entities = {
        'e1': {'name': 'Entity 1', 'email': 'test@example.com'},
      };

      final result = await migration.up(entities);

      expect(result['e1']!['email'], equals('test@example.com'));
    });

    test('should remove email field on down', () async {
      final entities = {
        'e1': {'name': 'Entity 1', 'email': 'test@example.com'},
        'e2': {'name': 'Entity 2', 'email': 'another@example.com'},
      };

      final result = await migration.down(entities);

      expect(result['e1']!.containsKey('email'), isFalse);
      expect(result['e2']!.containsKey('email'), isFalse);
    });

    test('should handle empty entities', () async {
      final entities = <String, Map<String, dynamic>>{};

      final resultUp = await migration.up(entities);
      final resultDown = await migration.down(entities);

      expect(resultUp, isEmpty);
      expect(resultDown, isEmpty);
    });
  });

  group('RenameFieldMigration', () {
    late RenameFieldMigration migration;

    setUp(() {
      migration = RenameFieldMigration();
    });

    test('should have correct version properties', () {
      expect(migration.fromVersion, equals('1.1.0'));
      expect(migration.toVersion, equals('1.2.0'));
    });

    test('should rename userName to username on up', () async {
      final entities = {
        'e1': {'name': 'Entity 1', 'userName': 'john_doe'},
      };

      final result = await migration.up(entities);

      expect(result['e1']!.containsKey('userName'), isFalse);
      expect(result['e1']!['username'], equals('john_doe'));
    });

    test('should rename username to userName on down', () async {
      final entities = {
        'e1': {'name': 'Entity 1', 'username': 'john_doe'},
      };

      final result = await migration.down(entities);

      expect(result['e1']!.containsKey('username'), isFalse);
      expect(result['e1']!['userName'], equals('john_doe'));
    });

    test('should handle entities without the field', () async {
      final entities = {
        'e1': {'name': 'Entity 1'},
      };

      final resultUp = await migration.up(entities);
      final resultDown = await migration.down(entities);

      expect(resultUp['e1']!.containsKey('userName'), isFalse);
      expect(resultUp['e1']!.containsKey('username'), isFalse);
      expect(resultDown['e1']!.containsKey('userName'), isFalse);
    });
  });

  group('Batch MigrationStrategy (ComputeStatsMigration)', () {
    late ComputeStatsMigration migration;

    setUp(() {
      migration = ComputeStatsMigration();
    });

    test('should have correct version properties', () {
      expect(migration.fromVersion, equals('1.2.0'));
      expect(migration.toVersion, equals('2.0.0'));
    });

    test('should compute totalPeers on up', () async {
      final entities = {
        'e1': {'name': 'Entity 1'},
        'e2': {'name': 'Entity 2'},
        'e3': {'name': 'Entity 3'},
      };

      final result = await migration.up(entities);

      expect(result['e1']!['totalPeers'], equals(2));
      expect(result['e2']!['totalPeers'], equals(2));
      expect(result['e3']!['totalPeers'], equals(2));
    });

    test('should remove totalPeers on down', () async {
      final entities = {
        'e1': {'name': 'Entity 1', 'totalPeers': 2},
        'e2': {'name': 'Entity 2', 'totalPeers': 2},
      };

      final result = await migration.down(entities);

      expect(result['e1']!.containsKey('totalPeers'), isFalse);
      expect(result['e2']!.containsKey('totalPeers'), isFalse);
    });

    test('should handle single entity', () async {
      final entities = {
        'e1': {'name': 'Entity 1'},
      };

      final result = await migration.up(entities);

      expect(result['e1']!['totalPeers'], equals(0));
    });
  });

  group('MigrationConfig', () {
    test('should create with required parameters', () {
      final config = MigrationConfig(currentVersion: '2.0.0');

      expect(config.currentVersion, equals('2.0.0'));
      expect(config.migrations, isEmpty);
      expect(config.autoMigrate, isTrue);
      expect(config.createBackupBeforeMigration, isTrue);
      expect(config.maxLogEntries, equals(100));
      expect(config.validateAfterEachStep, isFalse);
    });

    test('should create with custom migrations', () {
      final migrations = [AddEmailFieldMigration(), RenameFieldMigration()];

      final config = MigrationConfig(
        currentVersion: '1.2.0',
        migrations: migrations,
      );

      expect(config.migrations.length, equals(2));
      expect(config.migrations[0], isA<AddEmailFieldMigration>());
      expect(config.migrations[1], isA<RenameFieldMigration>());
    });

    test('should create with all custom parameters', () {
      final config = MigrationConfig(
        currentVersion: '2.0.0',
        migrations: [AddEmailFieldMigration()],
        autoMigrate: false,
        createBackupBeforeMigration: false,
        maxLogEntries: 50,
        validateAfterEachStep: true,
      );

      expect(config.autoMigrate, isFalse);
      expect(config.createBackupBeforeMigration, isFalse);
      expect(config.maxLogEntries, equals(50));
      expect(config.validateAfterEachStep, isTrue);
    });

    test('should create development config', () {
      final config = MigrationConfig.development(
        currentVersion: '1.0.0',
        migrations: [AddEmailFieldMigration()],
      );

      expect(config.currentVersion, equals('1.0.0'));
      expect(config.autoMigrate, isFalse);
      expect(config.createBackupBeforeMigration, isFalse);
      expect(config.validateAfterEachStep, isTrue);
    });

    test('should create production config', () {
      final config = MigrationConfig.production(
        currentVersion: '2.0.0',
        migrations: [AddEmailFieldMigration()],
      );

      expect(config.currentVersion, equals('2.0.0'));
      expect(config.autoMigrate, isTrue);
      expect(config.createBackupBeforeMigration, isTrue);
      expect(config.validateAfterEachStep, isFalse);
    });

    test('should copy with modifications', () {
      final original = MigrationConfig(currentVersion: '1.0.0');

      final modified = original.copyWith(
        currentVersion: '2.0.0',
        autoMigrate: false,
        maxLogEntries: 200,
      );

      expect(modified.currentVersion, equals('2.0.0'));
      expect(modified.autoMigrate, isFalse);
      expect(modified.maxLogEntries, equals(200));
      expect(
        modified.createBackupBeforeMigration,
        equals(original.createBackupBeforeMigration),
      );
    });
  });

  group('MigrationStep', () {
    late AddEmailFieldMigration strategy;

    setUp(() {
      strategy = AddEmailFieldMigration();
    });

    test('should create upgrade step', () {
      final step = MigrationStep(
        strategy: strategy,
        isUpgrade: true,
        sequenceNumber: 1,
      );

      expect(step.strategy, equals(strategy));
      expect(step.isUpgrade, isTrue);
      expect(step.sequenceNumber, equals(1));
    });

    test('should create downgrade step', () {
      final step = MigrationStep(
        strategy: strategy,
        isUpgrade: false,
        sequenceNumber: 1,
      );

      expect(step.isUpgrade, isFalse);
    });

    test('should compute correct source/target versions for upgrade', () {
      final step = MigrationStep(strategy: strategy, isUpgrade: true);

      expect(step.sourceVersion, equals('1.0.0'));
      expect(step.targetVersion, equals('1.1.0'));
    });

    test('should compute correct source/target versions for downgrade', () {
      final step = MigrationStep(strategy: strategy, isUpgrade: false);

      expect(step.sourceVersion, equals('1.1.0'));
      expect(step.targetVersion, equals('1.0.0'));
    });

    test('should get description from strategy', () {
      final step = MigrationStep(strategy: strategy, isUpgrade: true);

      expect(step.description, equals('Add email field with default value'));
    });

    test('should execute upgrade transformation', () async {
      final step = MigrationStep(strategy: strategy, isUpgrade: true);

      final entities = {
        'e1': {'name': 'Entity 1'},
      };

      final result = await step.execute(entities);

      expect(result['e1']!['email'], equals('unknown@example.com'));
    });

    test('should execute downgrade transformation', () async {
      final step = MigrationStep(strategy: strategy, isUpgrade: false);

      final entities = {
        'e1': {'name': 'Entity 1', 'email': 'test@example.com'},
      };

      final result = await step.execute(entities);

      expect(result['e1']!.containsKey('email'), isFalse);
    });

    test('should have informative toString', () {
      final upgradeStep = MigrationStep(strategy: strategy, isUpgrade: true);

      final downgradeStep = MigrationStep(strategy: strategy, isUpgrade: false);

      expect(upgradeStep.toString(), contains('upgrade'));
      expect(upgradeStep.toString(), contains('1.0.0'));
      expect(upgradeStep.toString(), contains('1.1.0'));

      expect(downgradeStep.toString(), contains('downgrade'));
    });
  });

  group('MigrationLog', () {
    test('should create with required parameters', () {
      final log = MigrationLog(
        timestamp: DateTime(2024, 1, 15),
        fromVersion: '1.0.0',
        toVersion: '1.1.0',
        outcome: MigrationOutcome.success,
      );

      expect(log.timestamp, equals(DateTime(2024, 1, 15)));
      expect(log.fromVersion, equals('1.0.0'));
      expect(log.toVersion, equals('1.1.0'));
      expect(log.outcome, equals(MigrationOutcome.success));
      expect(log.isUpgrade, isTrue);
    });

    test('should create success log', () {
      final log = MigrationLog.success(
        fromVersion: '1.0.0',
        toVersion: '1.1.0',
        durationMs: 1500,
        entitiesAffected: 100,
      );

      expect(log.outcome, equals(MigrationOutcome.success));
      expect(log.durationMs, equals(1500));
      expect(log.entitiesAffected, equals(100));
      expect(log.error, isNull);
      expect(log.isSuccess, isTrue);
    });

    test('should create failed log', () {
      final log = MigrationLog.failed(
        fromVersion: '1.0.0',
        toVersion: '1.1.0',
        error: 'Migration failed due to schema error',
        stackTrace: 'at line 42',
        durationMs: 500,
      );

      expect(log.outcome, equals(MigrationOutcome.failed));
      expect(log.error, equals('Migration failed due to schema error'));
      expect(log.stackTrace, equals('at line 42'));
      expect(log.durationMs, equals(500));
      expect(log.isSuccess, isFalse);
    });

    test('should create skipped log', () {
      final log = MigrationLog.skipped(
        fromVersion: '1.0.0',
        toVersion: '1.0.0',
        reason: 'Already at target version',
      );

      expect(log.outcome, equals(MigrationOutcome.skipped));
      expect(log.metadata?['reason'], equals('Already at target version'));
      expect(log.isSuccess, isFalse);
    });

    test('should support metadata', () {
      final log = MigrationLog.success(
        fromVersion: '1.0.0',
        toVersion: '1.1.0',
        durationMs: 1000,
        metadata: {'stepsExecuted': 3, 'backupCreated': true},
      );

      expect(log.metadata?['stepsExecuted'], equals(3));
      expect(log.metadata?['backupCreated'], isTrue);
    });

    test('should support downgrade flag', () {
      final log = MigrationLog.success(
        fromVersion: '1.1.0',
        toVersion: '1.0.0',
        durationMs: 1000,
        isUpgrade: false,
      );

      expect(log.isUpgrade, isFalse);
    });
  });

  group('MigrationRunner', () {
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

    test('should create runner with storage and config', () {
      final config = MigrationConfig(
        currentVersion: '1.0.0',
        migrations: [AddEmailFieldMigration()],
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      expect(runner.storage, equals(storage));
      expect(runner.config, equals(config));
      expect(runner.targetVersion, equals('1.0.0'));
    });

    test('should initialize and load current version', () async {
      final config = MigrationConfig(
        currentVersion: '1.0.0',
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();

      // Should have set initial version to 0.0.0
      expect(runner.currentVersion, equals('0.0.0'));
    });

    test('should detect need for migration', () async {
      final config = MigrationConfig(
        currentVersion: '1.1.0',
        migrations: [AddEmailFieldMigration()],
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();

      expect(await runner.needsMigration(), isTrue);
    });

    test('should not need migration when at target version', () async {
      // First, set up storage with the target version
      await storage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final config = MigrationConfig(
        currentVersion: '1.0.0',
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();

      expect(await runner.needsMigration(), isFalse);
    });

    test('should skip migration when already at target version', () async {
      await storage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final config = MigrationConfig(
        currentVersion: '1.0.0',
        migrations: [AddEmailFieldMigration()],
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();

      final log = await runner.migrate();

      expect(log.outcome, equals(MigrationOutcome.skipped));
    });

    test('should maintain history', () async {
      await storage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final config = MigrationConfig(
        currentVersion: '1.0.0',
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();
      await runner.migrate();

      expect(runner.history, isNotEmpty);
    });

    test('should handle closed storage gracefully on initialize', () async {
      await storage.close();

      final config = MigrationConfig(
        currentVersion: '1.0.0',
        autoMigrate: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      // The runner initializes but falls back to default version
      // because it catches storage errors gracefully
      await runner.initialize();
      expect(runner.currentVersion, equals('0.0.0'));
    });

    test('should throw on migrate with closed storage', () async {
      final config = MigrationConfig(
        currentVersion: '1.1.0',
        migrations: [AddEmailFieldMigration()],
        autoMigrate: false,
        createBackupBeforeMigration: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();
      await storage.close();

      expect(() => runner.migrate(), throwsA(isA<MigrationException>()));
    });
  });

  group('MigrationManager', () {
    late MemoryStorage<TestEntity> dataStorage;
    late MemoryStorage<TestEntity> userStorage;

    setUp(() async {
      dataStorage = MemoryStorage<TestEntity>(name: 'data_storage');
      userStorage = MemoryStorage<TestEntity>(name: 'user_storage');
      await dataStorage.open();
      await userStorage.open();
    });

    tearDown(() async {
      if (dataStorage.isOpen) {
        await dataStorage.close();
      }
      if (userStorage.isOpen) {
        await userStorage.close();
      }
    });

    test('should require at least one runner', () {
      expect(
        () => MigrationManager<TestEntity, TestEntity>(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should create with data runner only', () {
      final dataRunner = MigrationRunner<TestEntity>(
        storage: dataStorage,
        config: MigrationConfig(currentVersion: '1.0.0', autoMigrate: false),
      );

      final manager = MigrationManager<TestEntity, TestEntity>(
        dataRunner: dataRunner,
      );

      expect(manager.dataRunner, equals(dataRunner));
      expect(manager.userRunner, isNull);
    });

    test('should create with user runner only', () {
      final userRunner = MigrationRunner<TestEntity>(
        storage: userStorage,
        config: MigrationConfig(currentVersion: '1.0.0', autoMigrate: false),
      );

      final manager = MigrationManager<TestEntity, TestEntity>(
        userRunner: userRunner,
      );

      expect(manager.dataRunner, isNull);
      expect(manager.userRunner, equals(userRunner));
    });

    test('should create with both runners', () {
      final dataRunner = MigrationRunner<TestEntity>(
        storage: dataStorage,
        config: MigrationConfig(currentVersion: '1.0.0', autoMigrate: false),
      );

      final userRunner = MigrationRunner<TestEntity>(
        storage: userStorage,
        config: MigrationConfig(currentVersion: '1.0.0', autoMigrate: false),
      );

      final manager = MigrationManager<TestEntity, TestEntity>(
        dataRunner: dataRunner,
        userRunner: userRunner,
      );

      expect(manager.dataRunner, equals(dataRunner));
      expect(manager.userRunner, equals(userRunner));
    });

    test('should create from storage', () {
      final manager = MigrationManager<TestEntity, TestEntity>.fromStorage(
        dataStorage: dataStorage,
        dataConfig: MigrationConfig(
          currentVersion: '1.0.0',
          autoMigrate: false,
        ),
        userStorage: userStorage,
        userConfig: MigrationConfig(
          currentVersion: '1.0.0',
          autoMigrate: false,
        ),
      );

      expect(manager.dataRunner, isNotNull);
      expect(manager.userRunner, isNotNull);
    });

    test('should initialize both runners', () async {
      final manager = MigrationManager<TestEntity, TestEntity>.fromStorage(
        dataStorage: dataStorage,
        dataConfig: MigrationConfig(
          currentVersion: '1.0.0',
          autoMigrate: false,
        ),
        userStorage: userStorage,
        userConfig: MigrationConfig(
          currentVersion: '1.0.0',
          autoMigrate: false,
        ),
      );

      expect(manager.isInitialized, isFalse);

      await manager.initialize();

      expect(manager.isInitialized, isTrue);
    });

    test('should get migration status', () async {
      final manager = MigrationManager<TestEntity, TestEntity>.fromStorage(
        dataStorage: dataStorage,
        dataConfig: MigrationConfig(
          currentVersion: '1.1.0',
          autoMigrate: false,
        ),
        userStorage: userStorage,
        userConfig: MigrationConfig(
          currentVersion: '1.0.0',
          autoMigrate: false,
        ),
      );

      await manager.initialize();

      final status = await manager.getMigrationStatus();

      expect(status, isNotNull);
    });
  });

  group('MigrationStatus', () {
    late MemoryStorage<TestEntity> dataStorage;
    late MemoryStorage<TestEntity> userStorage;

    setUp(() async {
      dataStorage = MemoryStorage<TestEntity>(name: 'data_storage');
      userStorage = MemoryStorage<TestEntity>(name: 'user_storage');
      await dataStorage.open();
      await userStorage.open();
    });

    tearDown(() async {
      if (dataStorage.isOpen) {
        await dataStorage.close();
      }
      if (userStorage.isOpen) {
        await userStorage.close();
      }
    });

    test('should track data and user migration need separately', () async {
      // Set up different versions
      await dataStorage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await userStorage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final manager = MigrationManager<TestEntity, TestEntity>.fromStorage(
        dataStorage: dataStorage,
        dataConfig: MigrationConfig(
          currentVersion: '1.1.0', // Needs migration
          migrations: [AddEmailFieldMigration()],
          autoMigrate: false,
        ),
        userStorage: userStorage,
        userConfig: MigrationConfig(
          currentVersion: '1.0.0', // Already at target
          autoMigrate: false,
        ),
      );

      await manager.initialize();

      final status = await manager.getMigrationStatus();

      expect(status.dataNeedsMigration, isTrue);
      expect(status.userNeedsMigration, isFalse);
    });
  });

  group('VersionedData', () {
    test('should create SchemaVersion', () {
      final schema = SchemaVersion.now(
        id: '__schema_version__',
        version: '1.0.0',
      );

      expect(schema.id, equals('__schema_version__'));
      expect(schema.version, equals('1.0.0'));
      expect(schema.updatedAt, isNotNull);
    });

    test('should serialize SchemaVersion to map', () {
      final schema = SchemaVersion.now(
        id: '__schema_version__',
        version: '1.0.0',
      );

      final map = schema.toMap();

      expect(map['version'], equals('1.0.0'));
      expect(map.containsKey('updatedAt'), isTrue);
    });

    test('should deserialize SchemaVersion from map', () {
      final map = {'version': '2.0.0', 'updatedAt': '2024-01-15T12:00:00.000Z'};

      final schema = SchemaVersion.fromMap('__schema_version__', map);

      expect(schema.version, equals('2.0.0'));
      expect(schema.id, equals('__schema_version__'));
    });
  });

  group('Integration Tests', () {
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

    test('should execute full migration chain', () async {
      // Insert initial data at version 1.0.0
      await storage.insert('e1', {'name': 'Entity 1', 'version': 1});
      await storage.insert('e2', {'name': 'Entity 2', 'version': 1});
      await storage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final config = MigrationConfig(
        currentVersion: '1.1.0',
        migrations: [AddEmailFieldMigration()],
        autoMigrate: false,
        createBackupBeforeMigration: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();

      expect(await runner.needsMigration(), isTrue);

      final log = await runner.migrate();

      expect(log.outcome, equals(MigrationOutcome.success));
      expect(log.fromVersion, equals('1.0.0'));
      expect(log.toVersion, equals('1.1.0'));

      // Verify data was migrated
      final e1 = await storage.get('e1');
      final e2 = await storage.get('e2');

      expect(e1!['email'], equals('unknown@example.com'));
      expect(e2!['email'], equals('unknown@example.com'));
    });

    test('should handle multi-step migration', () async {
      // Insert initial data at version 1.0.0
      await storage.insert('e1', {'name': 'Entity 1', 'userName': 'john'});
      await storage.upsert('__schema_version__', {
        'version': '1.0.0',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      final config = MigrationConfig(
        currentVersion: '1.2.0',
        migrations: [
          AddEmailFieldMigration(), // 1.0.0 -> 1.1.0
          RenameFieldMigration(), // 1.1.0 -> 1.2.0
        ],
        autoMigrate: false,
        createBackupBeforeMigration: false,
      );

      final runner = MigrationRunner<TestEntity>(
        storage: storage,
        config: config,
      );

      await runner.initialize();
      final log = await runner.migrate();

      expect(log.outcome, equals(MigrationOutcome.success));

      // Verify both migrations were applied
      final e1 = await storage.get('e1');
      expect(e1!['email'], equals('unknown@example.com'));
      expect(e1.containsKey('userName'), isFalse);
      expect(e1['username'], equals('john'));
    });
  });
}
