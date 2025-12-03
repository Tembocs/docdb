/// DocDB Backup Module Tests
///
/// Comprehensive tests for the backup module including:
/// - Snapshot: Point-in-time data capture with integrity verification
/// - BackupService: Backup creation, restoration, and retention policies
/// - BackupManager: Multi-storage backup coordination
/// - BackupMetadata: Backup metadata serialization
/// - BackupResult: Backup operation results
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:docdb/src/authentication/authentication.dart';
import 'package:docdb/src/backup/backup.dart';
import 'package:docdb/src/entity/entity.dart';
import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/storage/memory_storage.dart';

/// Test entity class representing a Product.
class Product implements Entity {
  /// Unique identifier for the product.
  @override
  final String? id;

  /// Product name.
  final String name;

  /// Product price.
  final double price;

  /// Product category.
  final String category;

  /// Stock quantity.
  final int stock;

  /// Creates a new Product instance.
  Product({
    this.id,
    required this.name,
    required this.price,
    required this.category,
    this.stock = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'price': price,
    'category': category,
    'stock': stock,
  };

  /// Creates a Product from a map.
  static Product fromMap(String id, Map<String, dynamic> map) => Product(
    id: id,
    name: map['name'] as String,
    price: (map['price'] as num).toDouble(),
    category: map['category'] as String,
    stock: map['stock'] as int? ?? 0,
  );
}

void main() {
  group('BackupType Enum', () {
    test('should have expected types', () {
      expect(
        BackupType.values,
        containsAll([
          BackupType.full,
          BackupType.incremental,
          BackupType.differential,
          BackupType.migration,
        ]),
      );
    });

    test('should have name property', () {
      expect(BackupType.full.name, equals('full'));
      expect(BackupType.incremental.name, equals('incremental'));
      expect(BackupType.migration.name, equals('migration'));
    });
  });

  group('BackupOperation Enum', () {
    test('should have expected operations', () {
      expect(
        BackupOperation.values,
        containsAll([
          BackupOperation.create,
          BackupOperation.restore,
          BackupOperation.verify,
          BackupOperation.delete,
          BackupOperation.list,
        ]),
      );
    });

    test('should have displayName', () {
      expect(BackupOperation.create.displayName, contains('Create'));
      expect(BackupOperation.restore.displayName, contains('Restore'));
    });
  });

  group('BackupMetadata Entity', () {
    test('should create with required fields', () {
      final metadata = BackupMetadata(
        filePath: '/backups/backup-123.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 5000,
        entityCount: 100,
        checksum: 'sha256-abc123',
      );

      expect(metadata.filePath, equals('/backups/backup-123.snap'));
      expect(metadata.entityCount, equals(100));
      expect(metadata.sizeInBytes, equals(5000));
      expect(metadata.checksum, equals('sha256-abc123'));
    });

    test('should create with all fields', () {
      final metadata = BackupMetadata(
        id: 'meta-1',
        filePath: '/backups/backup-456.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 2500,
        entityCount: 50,
        checksum: 'sha256-def456',
        schemaVersion: '2.0.0',
        name: 'Daily backup',
        description: 'Daily incremental backup',
        tags: ['daily', 'automated'],
        compressed: true,
        type: BackupType.incremental,
        sourceName: 'products',
      );

      expect(metadata.schemaVersion, equals('2.0.0'));
      expect(metadata.name, equals('Daily backup'));
      expect(metadata.description, equals('Daily incremental backup'));
      expect(metadata.tags, containsAll(['daily', 'automated']));
      expect(metadata.compressed, isTrue);
      expect(metadata.type, equals(BackupType.incremental));
      expect(metadata.sourceName, equals('products'));
    });

    test('should create using factory constructor', () {
      final metadata = BackupMetadata.create(
        filePath: '/backups/backup-789.snap',
        entityCount: 200,
        sizeInBytes: 10000,
        checksum: 'sha256-ghi789',
      );

      expect(metadata.filePath, equals('/backups/backup-789.snap'));
      expect(metadata.entityCount, equals(200));
      expect(metadata.createdAt, isNotNull);
    });

    test('should serialize to map', () {
      final metadata = BackupMetadata(
        filePath: '/backups/orders.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 10000,
        entityCount: 200,
        checksum: 'sha256-ghi789',
      );

      final map = metadata.toMap();

      expect(map['filePath'], equals('/backups/orders.snap'));
      expect(map['entityCount'], equals(200));
      expect(map['sizeInBytes'], equals(10000));
      expect(map['checksum'], equals('sha256-ghi789'));
    });

    test('should deserialize from map', () {
      final map = {
        'filePath': '/backups/inventory.snap',
        'createdAt': DateTime.now().toIso8601String(),
        'sizeInBytes': 3750,
        'entityCount': 75,
        'checksum': 'sha256-jkl012',
        'tags': ['manual'],
        'compressed': false,
        'type': 'full',
      };

      final metadata = BackupMetadata.fromMap('meta-id', map);

      expect(metadata.id, equals('meta-id'));
      expect(metadata.filePath, equals('/backups/inventory.snap'));
      expect(metadata.type, equals(BackupType.full));
    });

    test('should get file name from path', () {
      final metadata = BackupMetadata(
        filePath: '/path/to/backups/my_backup.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 1000,
        entityCount: 10,
        checksum: 'abc',
      );

      expect(metadata.fileName, equals('my_backup.snap'));
    });

    test('should get human readable size', () {
      final smallMetadata = BackupMetadata(
        filePath: 'test.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 500,
        entityCount: 1,
        checksum: 'abc',
      );
      expect(smallMetadata.humanReadableSize, contains('B'));

      final kbMetadata = BackupMetadata(
        filePath: 'test.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 1024 * 5,
        entityCount: 1,
        checksum: 'abc',
      );
      expect(kbMetadata.humanReadableSize, contains('KB'));

      final mbMetadata = BackupMetadata(
        filePath: 'test.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 1024 * 1024 * 5,
        entityCount: 1,
        checksum: 'abc',
      );
      expect(mbMetadata.humanReadableSize, contains('MB'));
    });

    test('should create copy with modifications', () {
      final original = BackupMetadata(
        filePath: '/path/orig.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 500,
        entityCount: 10,
        checksum: 'checksum',
      );

      final modified = original.copyWith(entityCount: 20, sizeInBytes: 1000);

      expect(modified.filePath, equals('/path/orig.snap'));
      expect(modified.entityCount, equals(20));
      expect(modified.sizeInBytes, equals(1000));
    });

    test('should compare metadata', () {
      final meta1 = BackupMetadata(
        id: 'meta-1',
        filePath: '/path/test.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 500,
        entityCount: 10,
        checksum: 'abc123',
      );

      final meta2 = BackupMetadata(
        id: 'meta-1',
        filePath: '/path/test.snap',
        createdAt: DateTime.now(),
        sizeInBytes: 500,
        entityCount: 10,
        checksum: 'abc123',
      );

      expect(meta1, equals(meta2));
    });
  });

  group('BackupResult', () {
    test('should create success result', () {
      final metadata = BackupMetadata.create(
        filePath: '/backup.snap',
        entityCount: 10,
        sizeInBytes: 500,
        checksum: 'abc',
      );

      final result = BackupResult.success(
        operation: BackupOperation.create,
        metadata: metadata,
        message: 'Backup created successfully',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.operation, equals(BackupOperation.create));
      expect(result.metadata, isNotNull);
      expect(result.error, isNull);
    });

    test('should create failure result', () {
      final result = BackupResult.failure(
        operation: BackupOperation.restore,
        error: 'Backup file not found',
        filePath: '/missing.snap',
      );

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.operation, equals(BackupOperation.restore));
      expect(result.error, equals('Backup file not found'));
    });

    test('should calculate duration', () {
      final startTime = DateTime.now().subtract(const Duration(seconds: 5));
      final result = BackupResult.success(
        operation: BackupOperation.create,
        startedAt: startTime,
      );

      expect(result.duration.inSeconds, greaterThanOrEqualTo(4));
    });

    test('should have summary representation', () {
      final result = BackupResult.success(
        operation: BackupOperation.create,
        entitiesAffected: 100,
      );

      expect(result.summary, contains('Create'));
      expect(result.summary, contains('SUCCESS'));
    });

    test('should convert to map', () {
      final result = BackupResult.success(
        operation: BackupOperation.verify,
        entitiesAffected: 50,
      );

      final map = result.toMap();

      expect(map['operation'], equals('verify'));
      expect(map['isSuccess'], isTrue);
      expect(map['entitiesAffected'], equals(50));
    });

    test('should create from map', () {
      final now = DateTime.now();
      final map = {
        'operation': 'restore',
        'isSuccess': true,
        'startedAt': now.toIso8601String(),
        'completedAt': now.toIso8601String(),
        'entitiesAffected': 25,
        'bytesProcessed': 1000,
      };

      final result = BackupResult.fromMap(map);

      expect(result.operation, equals(BackupOperation.restore));
      expect(result.isSuccess, isTrue);
      expect(result.entitiesAffected, equals(25));
    });
  });

  group('Snapshot', () {
    test('should create from entities', () {
      final entities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Product 1', 'price': 9.99},
        'doc-2': {'name': 'Product 2', 'price': 19.99},
      };

      final snapshot = Snapshot.fromEntities(entities: entities);

      expect(snapshot.entityCount, equals(2));
      expect(snapshot.checksum, isNotEmpty);
    });

    test('should create with version and description', () {
      final snapshot = Snapshot.fromEntities(
        entities: {
          'doc-1': {'key': 'value'},
        },
        version: '2.0.0',
        description: 'Test backup',
      );

      expect(snapshot.version, equals('2.0.0'));
      expect(snapshot.description, equals('Test backup'));
    });

    test('should create empty snapshot', () {
      final snapshot = Snapshot.empty(description: 'Empty storage');

      expect(snapshot.entityCount, equals(0));
      expect(snapshot.description, contains('Empty'));
    });

    test('should serialize to bytes', () {
      final entities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Test', 'value': 100},
      };

      final snapshot = Snapshot.fromEntities(entities: entities);

      final bytes = snapshot.toBytes();

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(0));
    });

    test('should deserialize from bytes', () {
      final originalEntities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Product 1', 'price': 9.99},
        'doc-2': {'name': 'Product 2', 'price': 19.99},
      };

      final original = Snapshot.fromEntities(
        entities: originalEntities,
        version: '1.0',
        description: 'Test snapshot',
      );

      final bytes = original.toBytes();
      final restored = Snapshot.fromBytes(bytes);

      expect(restored.entityCount, equals(2));
      expect(restored.checksum, equals(original.checksum));
      expect(restored.version, equals('1.0'));
    });

    test('should verify integrity', () {
      final entities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Valid', 'value': 42},
      };

      final snapshot = Snapshot.fromEntities(entities: entities);

      expect(snapshot.verifyIntegrity(), isTrue);
    });

    test('should extract entities', () {
      final originalEntities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Product 1', 'price': 9.99},
        'doc-2': {'name': 'Product 2', 'price': 19.99},
      };

      final snapshot = Snapshot.fromEntities(entities: originalEntities);

      final extracted = snapshot.toEntities();

      expect(extracted.length, equals(2));
      expect(extracted['doc-1']!['name'], equals('Product 1'));
      expect(extracted['doc-2']!['price'], equals(19.99));
    });

    test('should support compression', () {
      final entities = <String, Map<String, dynamic>>{};
      for (int i = 0; i < 100; i++) {
        entities['doc-$i'] = {
          'name': 'Product $i',
          'description':
              'A long description that repeats to test compression ' * 10,
          'price': i * 9.99,
        };
      }

      final uncompressed = Snapshot.fromEntities(
        entities: entities,
        compressed: false,
      );

      final compressed = Snapshot.fromEntities(
        entities: entities,
        compressed: true,
      );

      expect(compressed.compressed, isTrue);
      expect(compressed.sizeInBytes, lessThan(uncompressed.sizeInBytes));
    });

    test('should serialize and deserialize compressed snapshot', () {
      final entities = <String, Map<String, dynamic>>{
        'doc-1': {'name': 'Test', 'data': 'Some data ' * 100},
      };

      final original = Snapshot.fromEntities(
        entities: entities,
        compressed: true,
      );

      final bytes = original.toBytes();
      final restored = Snapshot.fromBytes(bytes);

      expect(restored.compressed, isTrue);
      expect(restored.verifyIntegrity(), isTrue);

      final restoredEntities = restored.toEntities();
      expect(restoredEntities['doc-1']!['name'], equals('Test'));
    });

    test('should have sizeInBytes property', () {
      final snapshot = Snapshot.fromEntities(
        entities: {
          'doc-1': {'key': 'value'},
        },
      );

      expect(snapshot.sizeInBytes, greaterThan(0));
    });

    test('should have meaningful string representation', () {
      final snapshot = Snapshot.fromEntities(
        entities: {
          'doc-1': {'key': 'value'},
        },
      );

      expect(snapshot.toString(), contains('Snapshot'));
      expect(snapshot.toString(), contains('1'));
    });

    test('should convert to map', () {
      final snapshot = Snapshot.fromEntities(
        entities: {
          'doc-1': {'key': 'value'},
        },
        version: '1.0',
        description: 'Test',
      );

      final map = snapshot.toMap();

      expect(map['checksum'], isNotNull);
      expect(map['entityCount'], equals(1));
      expect(map['version'], equals('1.0'));
    });
  });

  group('BackupConfig', () {
    test('should create with required directory', () {
      final config = BackupConfig(backupDirectory: '/backups');

      expect(config.backupDirectory, equals('/backups'));
      expect(config.compress, isFalse);
      expect(config.verifyAfterCreate, isTrue);
    });

    test('should create with all options', () {
      final config = BackupConfig(
        backupDirectory: '/backups',
        compress: true,
        verifyAfterCreate: true,
        verifyBeforeRestore: true,
        maxBackups: 10,
        maxAge: const Duration(days: 30),
        fileExtension: '.backup',
      );

      expect(config.compress, isTrue);
      expect(config.maxBackups, equals(10));
      expect(config.maxAge, equals(const Duration(days: 30)));
      expect(config.fileExtension, equals('.backup'));
    });

    test('should have development factory', () {
      final config = BackupConfig.development('/backups');

      expect(config.compress, isFalse);
      expect(config.verifyAfterCreate, isTrue);
    });

    test('should have production factory', () {
      final config = BackupConfig.production('/backups');

      expect(config.compress, isTrue);
      expect(config.verifyAfterCreate, isTrue);
      expect(config.maxBackups, isNotNull);
    });

    test('should have migration factory', () {
      final config = BackupConfig.migration('/backups');

      expect(config.fileExtension, contains('migration'));
    });
  });

  group('BackupService', () {
    late BackupService<Product> backupService;
    late MemoryStorage<Product> storage;
    late Directory tempDir;

    setUp(() async {
      storage = MemoryStorage<Product>(name: 'products');
      await storage.open();

      tempDir = await Directory.systemTemp.createTemp('docdb_backup_test_');

      backupService = BackupService<Product>(
        storage: storage,
        config: BackupConfig.development(tempDir.path),
      );
      await backupService.initialize();

      // Add test data
      await storage.upsert(
        'prod-1',
        Product(
          id: 'prod-1',
          name: 'Widget',
          price: 9.99,
          category: 'Electronics',
          stock: 100,
        ).toMap(),
      );
      await storage.upsert(
        'prod-2',
        Product(
          id: 'prod-2',
          name: 'Gadget',
          price: 19.99,
          category: 'Electronics',
          stock: 50,
        ).toMap(),
      );
    });

    tearDown(() async {
      await storage.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Initialization', () {
      test('should create backup directory if not exists', () async {
        final newDir = Directory('${tempDir.path}/new_backup_dir');
        expect(await newDir.exists(), isFalse);

        final newService = BackupService<Product>(
          storage: storage,
          config: BackupConfig(backupDirectory: newDir.path),
        );
        await newService.initialize();

        expect(await newDir.exists(), isTrue);
      });
    });

    group('Backup Creation', () {
      test('should create full backup', () async {
        final result = await backupService.createBackup(
          description: 'Test backup',
        );

        expect(result.isSuccess, isTrue);
        expect(result.operation, equals(BackupOperation.create));
        expect(result.metadata, isNotNull);
        expect(result.metadata!.entityCount, equals(2));
      });

      test('should create backup with schema version', () async {
        final result = await backupService.createBackup(schemaVersion: '2.0.0');

        expect(result.isSuccess, isTrue);
        expect(result.metadata!.schemaVersion, equals('2.0.0'));
      });

      test('should create migration backup', () async {
        final result = await backupService.createBackup(
          type: BackupType.migration,
          description: 'Pre-migration backup',
        );

        expect(result.isSuccess, isTrue);
        expect(result.metadata!.type, equals(BackupType.migration));
      });

      test('should create in-memory backup', () async {
        final snapshot = await backupService.createMemoryBackup(
          description: 'Memory backup',
        );

        expect(snapshot, isNotNull);
        expect(snapshot.entityCount, equals(2));
        expect(snapshot.verifyIntegrity(), isTrue);
      });
    });

    group('Backup Restoration', () {
      late String backupPath;

      setUp(() async {
        final result = await backupService.createBackup();
        backupPath = result.filePath!;
      });

      test('should restore from backup', () async {
        // Clear storage
        await storage.delete('prod-1');
        await storage.delete('prod-2');
        expect(await storage.count, equals(0));

        // Restore
        final result = await backupService.restore(backupPath);

        expect(result.isSuccess, isTrue);
        expect(result.operation, equals(BackupOperation.restore));
        expect(await storage.count, equals(2));
      });

      test('should restore from snapshot', () async {
        final snapshot = await backupService.createMemoryBackup();

        // Clear storage
        await storage.delete('prod-1');
        await storage.delete('prod-2');

        // Restore
        await backupService.restoreFromSnapshot(snapshot);

        expect(await storage.count, equals(2));
      });

      test('should fail on restoring non-existent backup', () async {
        final result = await backupService.restore('/non/existent/backup.snap');

        expect(result.isSuccess, isFalse);
        expect(result.error, isNotNull);
      });
    });

    group('Backup Verification', () {
      late String backupPath;

      setUp(() async {
        final result = await backupService.createBackup();
        backupPath = result.filePath!;
      });

      test('should verify valid backup', () async {
        final result = await backupService.verify(backupPath);

        expect(result.isSuccess, isTrue);
        expect(result.operation, equals(BackupOperation.verify));
      });

      test('should fail verification for non-existent backup', () async {
        final result = await backupService.verify('/invalid/path.snap');

        expect(result.isSuccess, isFalse);
      });
    });

    group('Backup Listing', () {
      setUp(() async {
        await backupService.createBackup(description: 'Backup 1');
        await backupService.createBackup(description: 'Backup 2');
      });

      test('should list all backups', () async {
        final backups = await backupService.listBackups();

        expect(backups.length, equals(2));
      });

      test('should sort backups by creation time (newest first)', () async {
        final backups = await backupService.listBackups();

        expect(backups.length, equals(2));
        expect(
          backups.first.createdAt.isAfter(backups.last.createdAt) ||
              backups.first.createdAt.isAtSameMomentAs(backups.last.createdAt),
          isTrue,
        );
      });

      test('should find latest backup', () async {
        final latest = await backupService.findLatestBackup();

        expect(latest, isNotNull);
      });
    });

    group('Backup Deletion', () {
      late String backupPath;

      setUp(() async {
        final result = await backupService.createBackup();
        backupPath = result.filePath!;
      });

      test('should delete backup', () async {
        final result = await backupService.deleteBackup(backupPath);

        expect(result.isSuccess, isTrue);
        expect(result.operation, equals(BackupOperation.delete));

        final backups = await backupService.listBackups();
        expect(backups.where((b) => b.filePath == backupPath), isEmpty);
      });

      test('should fail on deleting non-existent backup', () async {
        final result = await backupService.deleteBackup('/non/existent.snap');

        expect(result.isSuccess, isFalse);
      });
    });
  });

  group('BackupManager', () {
    late BackupManager<Product, User> backupManager;
    late MemoryStorage<Product> dataStorage;
    late MemoryStorage<User> userStorage;
    late Directory tempDir;

    setUp(() async {
      dataStorage = MemoryStorage<Product>(name: 'data');
      userStorage = MemoryStorage<User>(name: 'users');
      await dataStorage.open();
      await userStorage.open();

      tempDir = await Directory.systemTemp.createTemp(
        'docdb_backup_manager_test_',
      );

      backupManager = BackupManager<Product, User>(
        dataStorage: dataStorage,
        userStorage: userStorage,
        dataBackupPath: '${tempDir.path}/data',
        userBackupPath: '${tempDir.path}/users',
      );

      await backupManager.initialize();

      // Add test data
      await dataStorage.upsert(
        'prod-1',
        Product(
          id: 'prod-1',
          name: 'Test Product',
          price: 29.99,
          category: 'Test',
        ).toMap(),
      );
      await userStorage.upsert(
        'user-1',
        User(id: 'user-1', username: 'testuser', passwordHash: 'hash').toMap(),
      );
    });

    tearDown(() async {
      await dataStorage.close();
      await userStorage.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Initialization', () {
      test('should initialize successfully', () {
        expect(backupManager.isInitialized, isTrue);
      });

      test('should not reinitialize', () async {
        await backupManager.initialize();
        expect(backupManager.isInitialized, isTrue);
      });

      test('should provide access to backup services', () {
        expect(backupManager.dataBackupService, isNotNull);
        expect(backupManager.userBackupService, isNotNull);
      });
    });

    group('Data Backup Operations', () {
      test('should create data backup', () async {
        final result = await backupManager.createDataBackup(
          description: 'Test data backup',
        );

        expect(result.isSuccess, isTrue);
        expect(result.metadata!.entityCount, equals(1));
      });

      test('should restore data backup', () async {
        final createResult = await backupManager.createDataBackup();
        await dataStorage.delete('prod-1');

        final restoreResult = await backupManager.restoreDataBackup(
          createResult.filePath!,
        );

        expect(restoreResult.isSuccess, isTrue);
        expect(await dataStorage.count, equals(1));
      });

      test('should list data backups', () async {
        await backupManager.createDataBackup();
        await backupManager.createDataBackup();

        final backups = await backupManager.listDataBackups();

        expect(backups.length, equals(2));
      });

      test('should find latest data backup', () async {
        await backupManager.createDataBackup();

        final latest = await backupManager.findLatestDataBackup();

        expect(latest, isNotNull);
      });

      test('should verify data backup', () async {
        final createResult = await backupManager.createDataBackup();

        final verifyResult = await backupManager.verifyDataBackup(
          createResult.filePath!,
        );

        expect(verifyResult.isSuccess, isTrue);
      });

      test('should create data memory backup', () async {
        final snapshot = await backupManager.createDataMemoryBackup();

        expect(snapshot.entityCount, equals(1));
      });

      test('should restore data from snapshot', () async {
        final snapshot = await backupManager.createDataMemoryBackup();
        await dataStorage.delete('prod-1');

        await backupManager.restoreDataFromSnapshot(snapshot);

        expect(await dataStorage.count, equals(1));
      });
    });

    group('User Backup Operations', () {
      test('should create user backup', () async {
        final result = await backupManager.createUserBackup(
          description: 'Test user backup',
        );

        expect(result.isSuccess, isTrue);
        expect(result.metadata!.entityCount, equals(1));
      });

      test('should restore user backup', () async {
        final createResult = await backupManager.createUserBackup();
        await userStorage.delete('user-1');

        final restoreResult = await backupManager.restoreUserBackup(
          createResult.filePath!,
        );

        expect(restoreResult.isSuccess, isTrue);
        expect(await userStorage.count, equals(1));
      });

      test('should list user backups', () async {
        await backupManager.createUserBackup();

        final backups = await backupManager.listUserBackups();

        expect(backups.length, equals(1));
      });

      test('should find latest user backup', () async {
        await backupManager.createUserBackup();

        final latest = await backupManager.findLatestUserBackup();

        expect(latest, isNotNull);
      });

      test('should verify user backup', () async {
        final createResult = await backupManager.createUserBackup();

        final verifyResult = await backupManager.verifyUserBackup(
          createResult.filePath!,
        );

        expect(verifyResult.isSuccess, isTrue);
      });

      test('should create user memory backup', () async {
        final snapshot = await backupManager.createUserMemoryBackup();

        expect(snapshot.entityCount, equals(1));
      });

      test('should restore user from snapshot', () async {
        final snapshot = await backupManager.createUserMemoryBackup();
        await userStorage.delete('user-1');

        await backupManager.restoreUserFromSnapshot(snapshot);

        expect(await userStorage.count, equals(1));
      });
    });

    group('Combined Operations', () {
      test('should create full backup', () async {
        final result = await backupManager.createFullBackup(
          description: 'Full backup',
        );

        expect(result.isSuccess, isTrue);
        expect(result.dataResult.isSuccess, isTrue);
        expect(result.userResult.isSuccess, isTrue);
      });

      test('should create migration backups', () async {
        final result = await backupManager.createMigrationBackups(
          schemaVersion: '2.0.0',
        );

        expect(result.isSuccess, isTrue);
        expect(result.dataResult.metadata!.type, equals(BackupType.migration));
        expect(result.userResult.metadata!.type, equals(BackupType.migration));
      });

      test('should restore from latest', () async {
        await backupManager.createFullBackup();

        // Clear storages
        await dataStorage.delete('prod-1');
        await userStorage.delete('user-1');

        // Restore
        final result = await backupManager.restoreFromLatest();

        expect(result.isSuccess, isTrue);
        expect(await dataStorage.count, equals(1));
        expect(await userStorage.count, equals(1));
      });

      test('should handle restore when no backups exist', () async {
        // Don't create any backups
        final newManager = BackupManager<Product, User>(
          dataStorage: dataStorage,
          userStorage: userStorage,
          dataBackupPath: '${tempDir.path}/empty_data',
          userBackupPath: '${tempDir.path}/empty_users',
        );
        await newManager.initialize();

        final result = await newManager.restoreFromLatest();

        expect(result.isSuccess, isFalse);
        expect(result.dataResult.error, isNotNull);
        expect(result.userResult.error, isNotNull);
      });

      test('should create memory backups', () async {
        final backups = await backupManager.createMemoryBackups();

        expect(backups.dataSnapshot.entityCount, equals(1));
        expect(backups.userSnapshot.entityCount, equals(1));
        expect(backups.totalEntityCount, equals(2));
      });

      test('should restore from memory backups', () async {
        final backups = await backupManager.createMemoryBackups();

        // Clear storages
        await dataStorage.delete('prod-1');
        await userStorage.delete('user-1');

        // Restore
        await backupManager.restoreFromMemoryBackups(backups);

        expect(await dataStorage.count, equals(1));
        expect(await userStorage.count, equals(1));
      });
    });

    group('CombinedBackupResult', () {
      test('should check all success', () async {
        final result = await backupManager.createFullBackup();

        expect(result.isSuccess, isTrue);
        expect(result.isFailure, isFalse);
        expect(result.isPartialSuccess, isFalse);
      });

      test('should have summary', () async {
        final result = await backupManager.createFullBackup();

        expect(result.summary, contains('Data'));
        expect(result.summary, contains('User'));
      });

      test('should convert to map', () async {
        final result = await backupManager.createFullBackup();

        final map = result.toMap();

        expect(map['isSuccess'], isTrue);
        expect(map['dataResult'], isNotNull);
        expect(map['userResult'], isNotNull);
      });
    });

    group('CombinedMemoryBackup', () {
      test('should calculate total entity count', () async {
        final backups = await backupManager.createMemoryBackups();

        expect(backups.totalEntityCount, equals(2));
      });

      test('should calculate total size', () async {
        final backups = await backupManager.createMemoryBackups();

        expect(backups.totalSizeInBytes, greaterThan(0));
      });

      test('should have string representation', () async {
        final backups = await backupManager.createMemoryBackups();

        expect(backups.toString(), contains('data'));
        expect(backups.toString(), contains('user'));
      });
    });
  });

  group('BackupException', () {
    test('should create with message', () {
      final exception = BackupException('Backup failed');

      expect(exception.message, equals('Backup failed'));
      expect(exception.toString(), contains('Backup failed'));
    });

    test('should create with cause', () {
      final cause = FormatException('Invalid format');
      final exception = BackupException('Backup failed', cause: cause);

      expect(exception.cause, equals(cause));
    });

    test('should create with stack trace', () {
      try {
        throw FormatException('Test');
      } catch (e, stack) {
        final exception = BackupException(
          'Backup failed',
          cause: e,
          stackTrace: stack,
        );

        expect(exception.stackTrace, isNotNull);
      }
    });
  });

  group('DataBackupFileNotFoundException', () {
    test('should create with message', () {
      final exception = DataBackupFileNotFoundException('backup-123.snap');

      expect(exception.message, contains('backup-123.snap'));
    });
  });
}
