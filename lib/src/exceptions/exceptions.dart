/// DocDB Exceptions Module
///
/// This module provides a comprehensive exception hierarchy for the DocDB
/// document database. All exceptions extend [DocDBException], enabling
/// uniform error handling across the library.
///
/// Example usage:
/// ```dart
/// try {
///   await collection.insert(document);
/// } on DocDBException catch (e) {
///   print('DocDB error: ${e.message}');
///   if (e.cause != null) {
///     print('Caused by: ${e.cause}');
///   }
/// }
/// ```
library;

export 'authentication_exceptions.dart';
export 'authorization_exceptions.dart';
export 'backup_exceptions.dart';
export 'collection_exceptions.dart';
export 'docdb_exception.dart';
export 'document_exceptions.dart';
export 'encryption_exceptions.dart';
export 'index_exceptions.dart';
export 'migration_exceptions.dart';
export 'query_exceptions.dart';
export 'schema_exceptions.dart';
export 'server_exceptions.dart';
export 'storage_exceptions.dart';
export 'transaction_exceptions.dart';
export 'type_registry_exceptions.dart';
