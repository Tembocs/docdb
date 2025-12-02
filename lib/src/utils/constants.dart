// PATH: lib/src/utils/constants.dart

/// Default configuration constants
const int defaultTimeout = 5000; // Timeout in milliseconds
const String defaultRole = "user";
const String errorMessageUnauthorized = "Unauthorized access.";
const String defaultDatabaseVersion = "1.0.0";

/// Logger name constants for various modules
class LoggerNameConstants {
  // Prevent instantiation.
  LoggerNameConstants._();

  static const String docdbMain = "DocDbMain";
  static const String authentication = "Authentication";
  static const String authorization = "Authorization";
  static const String backup = "Backup";
  static const String document = "Document";
  static const String dataCollection = "DataCollection";
  static const String userCollection = "UserCollection";
  static const String encryption = "Encryption";
  static const String exception = "Exception";
  static const String index = "Index";
  static const String migration = "Migration";
  static const String query = "Query";
  static const String schema = "Schema";
  static const String dataFileStorage = "DataFileStorage";
  static const String dataInMemoryStorage = "DataInMemoryStorage";
  static const String userFileStorage = "UserFileStorage";
  static const String userInMemoryStorage = "UserInMemoryStorage";
  static const String transaction = "Transaction";
  static const String typeRegistry = "TypeRegistry";
}

/// Database file path constants.
class DatabaseFilePaths {
  // Prevent instantiation.
  DatabaseFilePaths._();

  static const String dataPath = "data/data.db";
  static const String dataBackupPath = "data/data_backup.db";
  static const String userPath = "data/user.db";
  static const String userBackupPath = "data/user_backup.db";
  static const String logPath = "logs/docdb.log";
}

/// Migration file path constants
class MigrationFilePaths {
  // Prevent instantiation.
  MigrationFilePaths._();

  static const String dataSchemaPath = "data_schema.json";
  static const String userSchemaPath = "user_schema.json";
  static const String dataMigrationLogPath = "data_migration_log.json";
  static const String userMigrationLogPath = "user_migration_log.json";
}
