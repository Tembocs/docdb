/// EntiDB Backup Module
///
/// Provides comprehensive backup and restore capabilities for EntiDB storage
/// with integrity verification, compression, and flexible configuration.
///
/// ## Overview
///
/// The backup module offers multiple layers of backup functionality:
///
/// - **[Snapshot]**: Point-in-time capture of storage data with integrity
///   verification through SHA-256 checksums.
///
/// - **[BackupService]**: Generic backup service for a single storage instance
///   with file-based persistence and retention policies.
///
/// - **[BackupManager]**: High-level manager for coordinating backups across
///   multiple storage instances (data and user storage).
///
/// ## Quick Start
///
/// ### Single Storage Backup
///
/// ```dart
/// import 'package:entidb/src/backup/backup.dart';
///
/// final backupService = BackupService<Product>(
///   storage: productStorage,
///   config: BackupConfig(
///     backupDirectory: '/backups/products',
///     compress: true,
///     maxBackups: 10,
///   ),
/// );
///
/// await backupService.initialize();
///
/// // Create backup
/// final result = await backupService.createBackup(
///   description: 'Before price update',
/// );
///
/// if (result.isSuccess) {
///   print('Backup created: ${result.metadata?.filePath}');
/// }
///
/// // Restore from backup
/// await backupService.restore(result.filePath!);
/// ```
///
/// ### Multi-Storage Backup (Data + User)
///
/// ```dart
/// final manager = BackupManager<Product, User>(
///   dataStorage: productStorage,
///   userStorage: userStorage,
///   dataBackupPath: '/backups/data',
///   userBackupPath: '/backups/users',
/// );
///
/// await manager.initialize();
///
/// // Backup both storages
/// final results = await manager.createFullBackup(
///   description: 'Daily backup',
/// );
///
/// print('Data: ${results.dataResult.summary}');
/// print('User: ${results.userResult.summary}');
/// ```
///
/// ## Snapshot Format
///
/// Snapshots use a custom binary format with:
/// - Magic number for format identification
/// - Version byte for compatibility
/// - SHA-256 checksum for integrity
/// - Optional gzip compression
/// - JSON-serialized entity data
///
/// ```dart
/// // Create snapshot from entities
/// final snapshot = Snapshot.fromEntities(
///   entities: await storage.getAll(),
///   version: '2.0.0',
///   compressed: true,
/// );
///
/// // Verify integrity
/// if (snapshot.verifyIntegrity()) {
///   print('Snapshot is valid');
/// }
///
/// // Serialize to bytes
/// final bytes = snapshot.toBytes();
/// await File('backup.snap').writeAsBytes(bytes);
///
/// // Restore from bytes
/// final restored = Snapshot.fromBytes(bytes);
/// ```
///
/// ## Migration Integration
///
/// The backup module integrates seamlessly with the migration module:
///
/// ```dart
/// final runner = MigrationRunner<Product>(
///   storage: productStorage,
///   config: MigrationConfig(
///     currentVersion: '2.0.0',
///     migrations: [...],
///     createBackupBeforeMigration: true,
///   ),
///   backupService: BackupService<Product>(
///     storage: productStorage,
///     config: BackupConfig.migration('/backups/migrations'),
///   ),
/// );
/// ```
///
/// ## Backup Types
///
/// - **Full**: Complete backup of all entities
/// - **Migration**: Created before schema migrations for rollback
/// - **Differential**: Changes since last full backup (future)
/// - **Incremental**: Changes since any last backup (future)
///
/// ## Retention Policies
///
/// Configure automatic cleanup of old backups:
///
/// ```dart
/// final config = BackupConfig(
///   backupDirectory: '/backups',
///   maxBackups: 10,        // Keep max 10 backups
///   maxAge: Duration(days: 30),  // Delete backups older than 30 days
/// );
/// ```
///
/// ## Error Handling
///
/// ```dart
/// try {
///   await backupService.createBackup();
/// } on BackupException catch (e) {
///   print('Backup failed: ${e.message}');
/// }
///
/// final result = await backupService.restore(path);
/// if (result.isFailure) {
///   print('Restore failed: ${result.error}');
///   // Handle failure without throwing
/// }
/// ```
library;

// Core classes
export 'snapshot.dart' show Snapshot;
export 'backup_metadata.dart' show BackupMetadata, BackupType;
export 'backup_result.dart' show BackupResult, BackupOperation;
export 'storage_statistics.dart' show StorageStatistics, StorageStats;

// Differential and Incremental snapshots
export 'differential_snapshot.dart' show DifferentialSnapshot;
export 'incremental_snapshot.dart' show IncrementalSnapshot;

// Services
export 'backup_service.dart' show BackupService, BackupConfig;
export 'backup_manager.dart'
    show BackupManager, CombinedBackupResult, CombinedMemoryBackup;
