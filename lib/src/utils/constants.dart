/// Default timeout for operations in milliseconds.
const int defaultTimeout = 5000;

/// Default role assigned to new users.
const String defaultRole = 'user';

/// Error message returned for unauthorized access attempts.
const String errorMessageUnauthorized = 'Unauthorized access.';

/// Current database schema version.
const String defaultDatabaseVersion = '1.0.0';

/// Logger name constants for various DocDB modules.
///
/// These constants provide consistent naming for loggers across the system,
/// enabling filtered log output and module-specific debugging.
///
/// Example usage:
/// ```dart
/// final logger = DocDBLogger(LoggerNameConstants.authentication);
/// logger.info('User logged in successfully');
/// ```
abstract final class LoggerNameConstants {
  /// Logger name for the main DocDB entry point.
  static const String docdbMain = 'DocDbMain';

  /// Logger name for authentication operations.
  static const String authentication = 'Authentication';

  /// Logger name for authorization and permission checks.
  static const String authorization = 'Authorization';

  /// Logger name for backup and restore operations.
  static const String backup = 'Backup';

  /// Logger name for document operations.
  static const String document = 'Document';

  /// Logger name for data collection operations.
  static const String dataCollection = 'DataCollection';

  /// Logger name for user collection operations.
  static const String userCollection = 'UserCollection';

  /// Logger name for encryption and decryption operations.
  static const String encryption = 'Encryption';

  /// Logger name for exception handling.
  static const String exception = 'Exception';

  /// Logger name for index operations.
  static const String index = 'Index';

  /// Logger name for migration operations.
  static const String migration = 'Migration';

  /// Logger name for query execution.
  static const String query = 'Query';

  /// Logger name for schema validation.
  static const String schema = 'Schema';

  /// Logger name for file-based data storage.
  static const String dataFileStorage = 'DataFileStorage';

  /// Logger name for in-memory data storage.
  static const String dataInMemoryStorage = 'DataInMemoryStorage';

  /// Logger name for file-based user storage.
  static const String userFileStorage = 'UserFileStorage';

  /// Logger name for in-memory user storage.
  static const String userInMemoryStorage = 'UserInMemoryStorage';

  /// Logger name for transaction operations.
  static const String transaction = 'Transaction';

  /// Logger name for type registry operations.
  static const String typeRegistry = 'TypeRegistry';
}

/// Default file paths for database storage.
///
/// These paths define the standard locations for database files,
/// backups, and logs within the application's data directory.
abstract final class DatabaseFilePaths {
  /// Path to the main data storage file.
  static const String dataPath = 'data/data.db';

  /// Path to the data backup file.
  static const String dataBackupPath = 'data/data_backup.db';

  /// Path to the user authentication storage file.
  static const String userPath = 'data/user.db';

  /// Path to the user backup file.
  static const String userBackupPath = 'data/user_backup.db';

  /// Path to the application log file.
  static const String logPath = 'logs/docdb.log';
}

/// File paths for migration-related data.
///
/// These paths define the locations for schema definitions and
/// migration logs used during database upgrades.
abstract final class MigrationFilePaths {
  /// Path to the data schema definition file.
  static const String dataSchemaPath = 'data_schema.json';

  /// Path to the user schema definition file.
  static const String userSchemaPath = 'user_schema.json';

  /// Path to the data migration log file.
  static const String dataMigrationLogPath = 'data_migration_log.json';

  /// Path to the user migration log file.
  static const String userMigrationLogPath = 'user_migration_log.json';
}
