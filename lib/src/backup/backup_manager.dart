// lib/src/backup_restore/backup_manager.dart

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:docdb/src/exceptions/exceptions.dart';
import 'package:docdb/src/storage/data_storage/data_storage.dart';
import 'package:docdb/src/storage/user_storage/user_storage.dart';
import 'package:docdb/src/backup/snapshot.dart';
import 'package:docdb/src/logger/docdb_logger.dart';
import 'package:docdb/src/utils/constants.dart';

/// A manager that handles both backup and restoration operations for data and user storage.
class BackupManager {
  final DataStorage _dataStorage;
  final UserStorage _userStorage;
  final Directory _dataBackupDirectory;
  final Directory _userBackupDirectory;
  final DocDbLogger _logger = DocDbLogger(LoggerNameConstants.backup);

  /// Creates an instance of [BackupManager].
  ///
  /// - [_dataStorage]: The data storage engine to back up and restore.
  /// - [_userStorage]: The user storage engine to back up and restore.
  /// - [dataBackupPath]: The directory where data backups will be stored.
  /// - [userBackupPath]: The directory where user backups will be stored.
  /// - [logger]: The logger instance for logging operations.
  BackupManager({
    required DataStorage dataStorage,
    required UserStorage userStorage,
    required String dataBackupPath,
    required String userBackupPath,
  })  : _dataStorage = dataStorage,
        _userStorage = userStorage,
        _dataBackupDirectory = Directory(dataBackupPath),
        _userBackupDirectory = Directory(userBackupPath) {
    if (!_dataBackupDirectory.existsSync()) {
      try {
        _dataBackupDirectory.createSync(recursive: true);
        _logger.info(
            'BackupManager: Created data backup directory at ${_dataBackupDirectory.path}');
      } catch (e, stackTrace) {
        _logger.error(
            'BackupManager: Failed to create data backup directory: $e',
            e,
            stackTrace);
        throw BackupException('Failed to create data backup directory.');
      }
    } else {
      _logger.info(
          'BackupManager: Data backup directory exists at ${_dataBackupDirectory.path}');
    }

    // Ensure user backup directory exists
    if (!_userBackupDirectory.existsSync()) {
      try {
        _userBackupDirectory.createSync(recursive: true);
        _logger.info(
            'BackupManager: Created user backup directory at ${_userBackupDirectory.path}');
      } catch (e, stackTrace) {
        _logger.error(
            'BackupManager: Failed to create user backup directory: $e',
            e,
            stackTrace);
        throw BackupException('Failed to create user backup directory.');
      }
    } else {
      _logger.info(
          'BackupManager: User backup directory exists at ${_userBackupDirectory.path}');
    }
  }

  // -------------------
  // Data Storage Backup Methods
  // -------------------

  Future<String> createDataBackup() async {
    try {
      _logger.info('BackupManager: Starting data backup creation.');

      // Generate a snapshot from the data storage engine
      final snapshot = await _dataStorage.getSnapshot();

      // Define the backup file name and path
      final backupFileName =
          'data_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip';
      final backupFilePath = p.join(_dataBackupDirectory.path, backupFileName);

      // Write the snapshot to the file
      final backupFile = File(backupFilePath);
      await backupFile.writeAsBytes(snapshot.data, flush: true);

      _logger.info('BackupManager: Data backup created at $backupFilePath');
      return backupFilePath;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to create data backup: $e', e, stackTrace);
      throw DataBackupCreationException('Failed to create data backup.');
    }
  }

  Future<bool> restoreDataBackup(String backupFilePath) async {
    try {
      _logger.info(
          'BackupManager: Starting data restoration from $backupFilePath');

      final backupFile = File(backupFilePath);

      if (!await backupFile.exists()) {
        _logger.error(
            'BackupManager: Data backup file not found at $backupFilePath');
        throw DataBackupFileNotFoundException('Data backup file not found.');
      }

      final backupData = await backupFile.readAsBytes();

      // Create a snapshot from the backup data
      final snapshot = Snapshot(
        timestamp: DateTime.now(),
        data: backupData,
      );

      // Restore the data storage engine from the snapshot
      await _dataStorage.restoreFromSnapshot(snapshot);

      _logger.info(
          'BackupManager: Data restoration successful from $backupFilePath');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to restore data backup: $e', e, stackTrace);

      throw DataBackupFileNotFoundException('Data backup file not found: $e');
    }
  }

  Future<List<String>> listDataBackups() async {
    try {
      _logger.info('BackupManager: Listing all data backups.');

      final backupFiles = _dataBackupDirectory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.zip')
          .map((file) => file.path)
          .toList();

      _logger.info('BackupManager: Found ${backupFiles.length} data backups.');
      return backupFiles;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to list data backups: $e', e, stackTrace);
      throw BackupException('Failed to list data backups.');
    }
  }

  Future<String?> findLatestDataBackup() async {
    try {
      _logger.info('BackupManager: Finding the latest data backup.');

      final backups = _dataBackupDirectory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.zip')
          .toList();

      if (backups.isEmpty) {
        _logger.warning('BackupManager: No data backups found.');
        return null;
      }

      backups.sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified)); // Descending

      final latestBackup = backups.first.path;
      _logger.info('BackupManager: Latest data backup is at $latestBackup');
      return latestBackup;
    } catch (e, stackTrace) {
      _logger.error('BackupManager: Failed to find latest data backup: $e', e,
          stackTrace);
      throw BackupException('Failed to find latest data backup.');
    }
  }

  // -------------------
  // User Storage Backup Methods
  // -------------------

  Future<String> createUserBackup() async {
    try {
      _logger.info('BackupManager: Starting user backup creation.');

      // Generate a snapshot from the user storage engine
      final snapshot = await _userStorage.getSnapshot();

      // Define the backup file name and path
      final backupFileName =
          'user_backup_${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip';
      final backupFilePath = p.join(_userBackupDirectory.path, backupFileName);

      // Write the snapshot to the file
      final backupFile = File(backupFilePath);
      await backupFile.writeAsBytes(snapshot.data, flush: true);

      _logger.info('BackupManager: User backup created at $backupFilePath');
      return backupFilePath;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to create user backup: $e', e, stackTrace);
      throw UserBackupCreationException('Failed to create user backup.');
    }
  }

  Future<bool> restoreUserBackup(String backupFilePath) async {
    try {
      _logger.info(
          'BackupManager: Starting user restoration from $backupFilePath');

      final backupFile = File(backupFilePath);

      if (!await backupFile.exists()) {
        _logger.error(
            'BackupManager: User backup file not found at $backupFilePath');
        throw UserBackupFileNotFoundException('User backup file not found.');
      }

      final backupData = await backupFile.readAsBytes();

      // Create a snapshot from the backup data
      final snapshot = Snapshot(
        timestamp: DateTime.now(),
        data: backupData,
      );

      // Restore the user storage engine from the snapshot
      await _userStorage.restoreFromSnapshot(snapshot);

      _logger.info(
          'BackupManager: User restoration successful from $backupFilePath');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to restore user backup: $e', e, stackTrace);
      throw UserBackupFileNotFoundException('User backup file not found.');
    }
  }

  Future<List<String>> listUserBackups() async {
    try {
      _logger.info('BackupManager: Listing all user backups.');

      final backupFiles = _userBackupDirectory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.zip')
          .map((file) => file.path)
          .toList();

      _logger.info('BackupManager: Found ${backupFiles.length} user backups.');
      return backupFiles;
    } catch (e, stackTrace) {
      _logger.error(
          'BackupManager: Failed to list user backups: $e', e, stackTrace);
      throw BackupException('Failed to list user backups.');
    }
  }

  Future<String?> findLatestUserBackup() async {
    try {
      _logger.info('BackupManager: Finding the latest user backup.');

      final backups = _userBackupDirectory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.zip')
          .toList();

      if (backups.isEmpty) {
        _logger.warning('BackupManager: No user backups found.');
        return null;
      }

      backups.sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified)); // Descending

      final latestBackup = backups.first.path;
      _logger.info('BackupManager: Latest user backup is at $latestBackup');
      return latestBackup;
    } catch (e, stackTrace) {
      _logger.error('BackupManager: Failed to find latest user backup: $e', e,
          stackTrace);
      throw UserBackupFileNotFoundException(
          'Failed to find latest user backup.');
    }
  }
}
