/// Tests for the Exceptions module.
import 'package:entidb/src/exceptions/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('EntiDBException', () {
    test('should be abstract and not directly instantiable', () {
      // EntiDBException is abstract, so we test through a concrete subclass
      final exception = StorageException('Test message');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('StorageException', () {
    test('should create with message only', () {
      const exception = StorageException('Storage error occurred');
      expect(exception.message, 'Storage error occurred');
      expect(exception.cause, isNull);
      expect(exception.stackTrace, isNull);
    });

    test('should create with message and path', () {
      const exception = StorageException('Error', path: '/data/db');
      expect(exception.path, '/data/db');
    });

    test('should create with message and cause', () {
      final cause = Exception('Root cause');
      final exception = StorageException('Storage error', cause: cause);
      expect(exception.message, 'Storage error');
      expect(exception.cause, cause);
    });

    test('should create with message and stack trace', () {
      final stackTrace = StackTrace.current;
      final exception = StorageException('Error', stackTrace: stackTrace);
      expect(exception.stackTrace, stackTrace);
    });

    test('toString should return formatted message', () {
      const exception = StorageException('Something went wrong');
      expect(exception.toString(), contains('Something went wrong'));
    });
  });

  group('StorageInitializationException', () {
    test('should extend StorageException', () {
      final exception = StorageInitializationException(
        storageName: 'testStorage',
      );
      expect(exception, isA<StorageException>());
    });

    test('should format message with storage name', () {
      final exception = StorageInitializationException(storageName: 'myDb');
      expect(exception.message, contains('myDb'));
    });
  });

  group('StorageReadException', () {
    test('should extend StorageException', () {
      final exception = StorageReadException(storageName: 'test');
      expect(exception, isA<StorageException>());
    });

    test('should create with storage name only', () {
      final exception = StorageReadException(storageName: 'testStorage');
      expect(exception.message, contains('testStorage'));
    });

    test('should create with storage name and entity ID', () {
      final exception = StorageReadException(
        storageName: 'users',
        entityId: 'user123',
      );
      expect(exception.message, contains('users'));
      expect(exception.message, contains('user123'));
      expect(exception.entityId, 'user123');
    });

    test('should create with all parameters', () {
      final cause = Exception('IO error');
      final stackTrace = StackTrace.current;
      final exception = StorageReadException(
        storageName: 'data',
        entityId: 'doc1',
        path: '/data/db.dat',
        cause: cause,
        stackTrace: stackTrace,
      );
      expect(exception.entityId, 'doc1');
      expect(exception.path, '/data/db.dat');
      expect(exception.cause, cause);
      expect(exception.stackTrace, stackTrace);
    });
  });

  group('StorageWriteException', () {
    test('should extend StorageException', () {
      final exception = StorageWriteException(storageName: 'test');
      expect(exception, isA<StorageException>());
    });

    test('should format message with entity ID', () {
      final exception = StorageWriteException(
        storageName: 'orders',
        entityId: 'order-456',
      );
      expect(exception.message, contains('orders'));
      expect(exception.message, contains('order-456'));
    });

    test('should preserve cause chain', () {
      final innerCause = Exception('Disk full');
      final exception = StorageWriteException(
        storageName: 'storage',
        cause: innerCause,
      );
      expect(exception.cause, innerCause);
    });
  });

  group('EntityAlreadyExistsException', () {
    test('should extend StorageException', () {
      final exception = EntityAlreadyExistsException(
        entityId: 'e1',
        storageName: 's1',
      );
      expect(exception, isA<StorageException>());
    });

    test('should include entity and storage in message', () {
      final exception = EntityAlreadyExistsException(
        entityId: 'user123',
        storageName: 'users',
      );
      expect(exception.entityId, 'user123');
      expect(exception.storageName, 'users');
      expect(exception.message, contains('user123'));
      expect(exception.message, contains('users'));
    });
  });

  group('EntityNotFoundException', () {
    test('should extend StorageException', () {
      final exception = EntityNotFoundException(
        entityId: 'e1',
        storageName: 's1',
      );
      expect(exception, isA<StorageException>());
    });
  });

  group('StorageCorruptedException', () {
    test('should extend StorageException', () {
      const exception = StorageCorruptedException('Data corrupted');
      expect(exception, isA<StorageException>());
    });
  });

  group('StorageVersionMismatchException', () {
    test('should extend StorageException', () {
      const exception = StorageVersionMismatchException(
        'Version mismatch',
        fileVersion: 2,
        supportedVersion: 1,
      );
      expect(exception, isA<StorageException>());
    });

    test('should track versions', () {
      const exception = StorageVersionMismatchException(
        'Incompatible',
        fileVersion: 3,
        supportedVersion: 2,
      );
      expect(exception.fileVersion, 3);
      expect(exception.supportedVersion, 2);
    });
  });

  group('StorageNotOpenException', () {
    test('should extend StorageException', () {
      final exception = StorageNotOpenException(storageName: 'test');
      expect(exception, isA<StorageException>());
    });

    test('should format message with storage name', () {
      final exception = StorageNotOpenException(storageName: 'myDb');
      expect(exception.message, contains('myDb'));
      expect(exception.message, contains('not open'));
    });

    test('should support custom message', () {
      const exception = StorageNotOpenException.withMessage('Custom message');
      expect(exception.message, 'Custom message');
      expect(exception.storageName, isNull);
    });
  });

  group('StorageOutOfSpaceException', () {
    test('should extend StorageException', () {
      const exception = StorageOutOfSpaceException('No space left');
      expect(exception, isA<StorageException>());
    });

    test('should track space values', () {
      const exception = StorageOutOfSpaceException(
        'Disk full',
        requiredBytes: 1024000,
        availableBytes: 512000,
      );
      expect(exception.requiredBytes, 1024000);
      expect(exception.availableBytes, 512000);
    });
  });

  group('TransactionAlreadyActiveException', () {
    test('should extend StorageException', () {
      final exception = TransactionAlreadyActiveException(storageName: 'test');
      expect(exception, isA<StorageException>());
    });
  });

  group('NoActiveTransactionException', () {
    test('should extend StorageException', () {
      final exception = NoActiveTransactionException(storageName: 'test');
      expect(exception, isA<StorageException>());
    });
  });

  group('AuthenticationException', () {
    test('should create with message', () {
      const exception = AuthenticationException('Auth failed');
      expect(exception.message, 'Auth failed');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('UserAlreadyExistsException', () {
    test('should extend AuthenticationException', () {
      const exception = UserAlreadyExistsException('User exists');
      expect(exception, isA<AuthenticationException>());
    });
  });

  group('InvalidUserOrPasswordException', () {
    test('should extend AuthenticationException', () {
      const exception = InvalidUserOrPasswordException('Bad credentials');
      expect(exception, isA<AuthenticationException>());
    });
  });

  group('InvalidOrExpiredTokenException', () {
    test('should extend AuthenticationException', () {
      const exception = InvalidOrExpiredTokenException('Token expired');
      expect(exception, isA<AuthenticationException>());
    });
  });

  group('JWTTokenException', () {
    test('should extend AuthenticationException', () {
      const exception = JWTTokenException('JWT error');
      expect(exception, isA<AuthenticationException>());
    });
  });

  group('AuthorizationException', () {
    test('should create with message', () {
      const exception = AuthorizationException('Not authorized');
      expect(exception.message, 'Not authorized');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('UndefinedRoleException', () {
    test('should extend AuthorizationException', () {
      const exception = UndefinedRoleException('Role not found');
      expect(exception, isA<AuthorizationException>());
    });
  });

  group('RoleAlreadyDefinedException', () {
    test('should extend AuthorizationException', () {
      const exception = RoleAlreadyDefinedException('Role exists');
      expect(exception, isA<AuthorizationException>());
    });
  });

  group('PermissionDeniedException', () {
    test('should extend AuthorizationException', () {
      const exception = PermissionDeniedException('Access denied');
      expect(exception, isA<AuthorizationException>());
    });

    test('should include permission and resource info', () {
      const exception = PermissionDeniedException(
        'Cannot write',
        requiredPermission: 'write',
        resource: 'users',
      );
      expect(exception.requiredPermission, 'write');
      expect(exception.resource, 'users');
    });

    test('toString should include permission and resource', () {
      const exception = PermissionDeniedException(
        'Denied',
        requiredPermission: 'delete',
        resource: 'documents',
      );
      final str = exception.toString();
      expect(str, contains('delete'));
      expect(str, contains('documents'));
    });
  });

  group('SystemRoleProtectionException', () {
    test('should require roleName', () {
      const exception = SystemRoleProtectionException(
        'Cannot modify admin',
        roleName: 'admin',
      );
      expect(exception.roleName, 'admin');
      expect(exception, isA<AuthorizationException>());
    });
  });

  group('CircularInheritanceException', () {
    test('should track involved roles', () {
      const exception = CircularInheritanceException(
        'Circular dependency',
        involvedRoles: ['admin', 'manager', 'admin'],
      );
      expect(exception.involvedRoles, ['admin', 'manager', 'admin']);
    });

    test('should default to empty list', () {
      const exception = CircularInheritanceException('Loop detected');
      expect(exception.involvedRoles, isEmpty);
    });
  });

  group('InheritanceDepthExceededException', () {
    test('should track max and actual depth', () {
      const exception = InheritanceDepthExceededException(
        'Too deep',
        maxDepth: 10,
        actualDepth: 15,
      );
      expect(exception.maxDepth, 10);
      expect(exception.actualDepth, 15);
    });
  });

  group('CollectionException', () {
    test('should create with message', () {
      const exception = CollectionException('Collection error');
      expect(exception.message, 'Collection error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('DocumentException', () {
    test('should create with message', () {
      const exception = DocumentException('Document error');
      expect(exception.message, 'Document error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('DocumentNotFoundException', () {
    test('should extend DocumentException', () {
      const exception = DocumentNotFoundException('Doc not found');
      expect(exception, isA<DocumentException>());
    });
  });

  group('IndexException', () {
    test('should create with message', () {
      const exception = IndexException('Index error');
      expect(exception.message, 'Index error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('IndexNotFoundException', () {
    test('should extend IndexException', () {
      const exception = IndexNotFoundException('Index missing');
      expect(exception, isA<IndexException>());
    });
  });

  group('UnsupportedIndexTypeException', () {
    test('should extend IndexException', () {
      const exception = UnsupportedIndexTypeException('Type not supported');
      expect(exception, isA<IndexException>());
    });
  });

  group('IndexAlreadyExistsException', () {
    test('should extend IndexException', () {
      const exception = IndexAlreadyExistsException('Index exists');
      expect(exception, isA<IndexException>());
    });
  });

  group('QueryException', () {
    test('should create with message', () {
      const exception = QueryException('Query failed');
      expect(exception.message, 'Query failed');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('UserNotFoundException', () {
    test('should extend QueryException', () {
      const exception = UserNotFoundException('User not found');
      expect(exception, isA<QueryException>());
    });
  });

  group('TransactionException', () {
    test('should create with message', () {
      const exception = TransactionException('Transaction failed');
      expect(exception.message, 'Transaction failed');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('ConcurrencyException', () {
    test('should extend TransactionException', () {
      const exception = ConcurrencyException('Concurrent modification');
      expect(exception, isA<TransactionException>());
    });
  });

  group('EncryptionException', () {
    test('should create with message', () {
      const exception = EncryptionException('Encryption error');
      expect(exception.message, 'Encryption error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('EncryptionFailedException', () {
    test('should extend EncryptionException', () {
      const exception = EncryptionFailedException('Encrypt failed');
      expect(exception, isA<EncryptionException>());
    });
  });

  group('DecryptionException', () {
    test('should extend EncryptionException', () {
      const exception = DecryptionException('Decrypt failed');
      expect(exception, isA<EncryptionException>());
    });
  });

  group('AuthenticationFailedException (encryption)', () {
    test('should extend DecryptionException', () {
      const exception = AuthenticationFailedException();
      expect(exception, isA<DecryptionException>());
    });

    test('should have default message', () {
      const exception = AuthenticationFailedException();
      expect(exception.message, contains('tampered'));
    });
  });

  group('InvalidKeyException', () {
    test('should extend EncryptionException', () {
      const exception = InvalidKeyException('Bad key');
      expect(exception, isA<EncryptionException>());
    });

    test('should track expected and actual bits', () {
      const exception = InvalidKeyException(
        'Wrong size',
        expectedBits: 256,
        actualBits: 128,
      );
      expect(exception.expectedBits, 256);
      expect(exception.actualBits, 128);
    });

    test('invalidSize factory should format message', () {
      final exception = InvalidKeyException.invalidSize(
        expected: 256,
        actual: 128,
      );
      expect(exception.message, contains('256'));
      expect(exception.message, contains('128'));
    });

    test('unsupportedSize factory should list supported sizes', () {
      final exception = InvalidKeyException.unsupportedSize(
        actual: 64,
        supported: [128, 192, 256],
      );
      expect(exception.message, contains('64'));
      expect(exception.message, contains('128'));
      expect(exception.message, contains('256'));
    });
  });

  group('KeyDerivationException', () {
    test('should extend EncryptionException', () {
      const exception = KeyDerivationException('Derivation failed');
      expect(exception, isA<EncryptionException>());
    });
  });

  group('EncryptionNotInitializedException', () {
    test('should extend EncryptionException', () {
      const exception = EncryptionNotInitializedException();
      expect(exception, isA<EncryptionException>());
    });

    test('should have default message', () {
      const exception = EncryptionNotInitializedException();
      expect(exception.message, contains('not initialized'));
    });
  });

  group('InvalidIvException', () {
    test('should extend EncryptionException', () {
      const exception = InvalidIvException('Bad IV');
      expect(exception, isA<EncryptionException>());
    });

    test('should track expected and actual bytes', () {
      const exception = InvalidIvException(
        'Wrong IV size',
        expectedBytes: 12,
        actualBytes: 16,
      );
      expect(exception.expectedBytes, 12);
      expect(exception.actualBytes, 16);
    });
  });

  group('BackupException', () {
    test('should create with message', () {
      const exception = BackupException('Backup error');
      expect(exception.message, 'Backup error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('BackupIntegrityException', () {
    test('should extend BackupException', () {
      const exception = BackupIntegrityException('Integrity check failed');
      expect(exception, isA<BackupException>());
    });

    test('should track checksums', () {
      const exception = BackupIntegrityException(
        'Checksum mismatch',
        expectedChecksum: 'abc123',
        actualChecksum: 'def456',
      );
      expect(exception.expectedChecksum, 'abc123');
      expect(exception.actualChecksum, 'def456');
    });
  });

  group('BackupDecompressionException', () {
    test('should extend BackupException', () {
      const exception = BackupDecompressionException('Decompression failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('BackupCompressionException', () {
    test('should extend BackupException', () {
      const exception = BackupCompressionException('Compression failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('BackupVersionException', () {
    test('should extend BackupException', () {
      const exception = BackupVersionException('Version mismatch');
      expect(exception, isA<BackupException>());
    });

    test('should track versions', () {
      const exception = BackupVersionException(
        'Incompatible version',
        backupVersion: '2.0',
        supportedVersion: '1.0',
      );
      expect(exception.backupVersion, '2.0');
      expect(exception.supportedVersion, '1.0');
    });
  });

  group('BackupTimeoutException', () {
    test('should extend BackupException', () {
      const exception = BackupTimeoutException('Timeout');
      expect(exception, isA<BackupException>());
    });

    test('should track timeout duration', () {
      const exception = BackupTimeoutException(
        'Operation timed out',
        timeout: Duration(seconds: 30),
      );
      expect(exception.timeout, const Duration(seconds: 30));
    });
  });

  group('BackupQuotaExceededException', () {
    test('should extend BackupException', () {
      const exception = BackupQuotaExceededException('Quota exceeded');
      expect(exception, isA<BackupException>());
    });

    test('should track quota values', () {
      const exception = BackupQuotaExceededException(
        'Too many backups',
        currentValue: 10,
        maxValue: 5,
      );
      expect(exception.currentValue, 10);
      expect(exception.maxValue, 5);
    });
  });

  group('EmptyBackupException', () {
    test('should extend BackupException', () {
      const exception = EmptyBackupException('Empty backup');
      expect(exception, isA<BackupException>());
    });
  });

  group('BackupNotSupportedException', () {
    test('should extend BackupException', () {
      const exception = BackupNotSupportedException('Not supported');
      expect(exception, isA<BackupException>());
    });

    test('should track operation', () {
      const exception = BackupNotSupportedException(
        'Incremental not supported',
        operation: 'incremental',
      );
      expect(exception.operation, 'incremental');
    });
  });

  group('UserBackupFileNotFoundException', () {
    test('should extend BackupException', () {
      const exception = UserBackupFileNotFoundException('File not found');
      expect(exception, isA<BackupException>());
    });
  });

  group('DataBackupFileNotFoundException', () {
    test('should extend BackupException', () {
      const exception = DataBackupFileNotFoundException('File not found');
      expect(exception, isA<BackupException>());
    });
  });

  group('DataBackupCreationException', () {
    test('should extend BackupException', () {
      const exception = DataBackupCreationException('Creation failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('DataBackupRestorationException', () {
    test('should extend BackupException', () {
      const exception = DataBackupRestorationException('Restoration failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('UserBackupCreationException', () {
    test('should extend BackupException', () {
      const exception = UserBackupCreationException('Creation failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('UserBackupRestorationException', () {
    test('should extend BackupException', () {
      const exception = UserBackupRestorationException('Restoration failed');
      expect(exception, isA<BackupException>());
    });
  });

  group('MigrationException', () {
    test('should create with message', () {
      const exception = MigrationException('Migration failed');
      expect(exception.message, 'Migration failed');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('SchemaValidationException', () {
    test('should create with message', () {
      const exception = SchemaValidationException('Validation failed');
      expect(exception.message, 'Validation failed');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('ServerException', () {
    test('should create with message', () {
      const exception = ServerException('Server error');
      expect(exception.message, 'Server error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('DatabaseException', () {
    test('should create with message', () {
      const exception = DatabaseException('Database error');
      expect(exception.message, 'Database error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('DatabaseOpenException', () {
    test('should extend DatabaseException', () {
      final exception = DatabaseOpenException();
      expect(exception, isA<DatabaseException>());
    });

    test('should format message with path', () {
      final exception = DatabaseOpenException(path: '/data/mydb');
      expect(exception.message, contains('/data/mydb'));
      expect(exception.path, '/data/mydb');
    });
  });

  group('DatabaseNotOpenException', () {
    test('should extend DatabaseException', () {
      const exception = DatabaseNotOpenException();
      expect(exception, isA<DatabaseException>());
    });

    test('should have default message', () {
      const exception = DatabaseNotOpenException();
      expect(exception.message, contains('not open'));
    });
  });

  group('DatabaseDisposedException', () {
    test('should extend DatabaseException', () {
      const exception = DatabaseDisposedException();
      expect(exception, isA<DatabaseException>());
    });

    test('should have default message', () {
      const exception = DatabaseDisposedException();
      expect(exception.message, contains('disposed'));
    });
  });

  group('CollectionOperationException', () {
    test('should extend DatabaseException', () {
      final exception = CollectionOperationException(
        collectionName: 'users',
        operation: 'create',
      );
      expect(exception, isA<DatabaseException>());
    });

    test('should format message with collection name and operation', () {
      final exception = CollectionOperationException(
        collectionName: 'orders',
        operation: 'drop',
      );
      expect(exception.message, contains('orders'));
      expect(exception.message, contains('drop'));
      expect(exception.collectionName, 'orders');
    });
  });

  group('CollectionTypeMismatchException', () {
    test('should extend DatabaseException', () {
      final exception = CollectionTypeMismatchException(
        collectionName: 'users',
        expectedType: String,
        actualType: int,
      );
      expect(exception, isA<DatabaseException>());
    });

    test('should include all type info in message', () {
      final exception = CollectionTypeMismatchException(
        collectionName: 'products',
        expectedType: Map,
        actualType: List,
      );
      expect(exception.collectionName, 'products');
      expect(exception.expectedType, Map);
      expect(exception.actualType, List);
      expect(exception.message, contains('products'));
    });
  });

  group('TypeRegistryException', () {
    test('should create with message', () {
      const exception = TypeRegistryException('Registry error');
      expect(exception.message, 'Registry error');
      expect(exception, isA<EntiDBException>());
    });
  });

  group('TypeAlreadyRegisteredException', () {
    test('should extend TypeRegistryException', () {
      final exception = TypeAlreadyRegisteredException(
        type: String,
        existingTypeName: 'String',
      );
      expect(exception, isA<TypeRegistryException>());
    });

    test('should track type and name', () {
      final exception = TypeAlreadyRegisteredException(
        type: int,
        existingTypeName: 'Integer',
      );
      expect(exception.type, int);
      expect(exception.existingTypeName, 'Integer');
    });

    test('should have formatted message', () {
      final exception = TypeAlreadyRegisteredException(
        type: String,
        existingTypeName: 'Str',
      );
      expect(exception.message, contains('String'));
      expect(exception.message, contains('overwrite'));
    });
  });

  group('TypeNameConflictException', () {
    test('should extend TypeRegistryException', () {
      final exception = TypeNameConflictException(
        typeName: 'MyType',
        existingType: String,
        newType: int,
      );
      expect(exception, isA<TypeRegistryException>());
    });

    test('should track all type info', () {
      final exception = TypeNameConflictException(
        typeName: 'Number',
        existingType: int,
        newType: double,
      );
      expect(exception.typeName, 'Number');
      expect(exception.existingType, int);
      expect(exception.newType, double);
    });
  });

  group('TypeNotRegisteredException', () {
    test('should extend TypeRegistryException', () {
      final exception = TypeNotRegisteredException(typeName: 'Unknown');
      expect(exception, isA<TypeRegistryException>());
    });

    test('should track type name', () {
      final exception = TypeNotRegisteredException(typeName: 'CustomClass');
      expect(exception.typeName, 'CustomClass');
      expect(exception.message, contains('CustomClass'));
    });
  });

  group('TypeSerializationException', () {
    test('should extend TypeRegistryException', () {
      final exception = TypeSerializationException(type: String);
      expect(exception, isA<TypeRegistryException>());
    });

    test('should track type and value', () {
      final exception = TypeSerializationException(
        type: Map,
        value: {'key': 'value'},
      );
      expect(exception.type, Map);
      expect(exception.value, {'key': 'value'});
    });

    test('should include cause in chain', () {
      final cause = Exception('Inner error');
      final exception = TypeSerializationException(type: List, cause: cause);
      expect(exception.cause, cause);
    });
  });

  group('TypeDeserializationException', () {
    test('should extend TypeRegistryException', () {
      final exception = TypeDeserializationException(typeName: 'Test');
      expect(exception, isA<TypeRegistryException>());
    });

    test('should track type name and data', () {
      final exception = TypeDeserializationException(
        typeName: 'Person',
        data: {'name': 'John'},
      );
      expect(exception.typeName, 'Person');
      expect(exception.data, {'name': 'John'});
    });
  });

  group('Exception hierarchy', () {
    test('all exceptions should extend EntiDBException', () {
      final exceptions = <EntiDBException>[
        const StorageException('test'),
        StorageInitializationException(storageName: 'test'),
        StorageReadException(storageName: 'test'),
        StorageWriteException(storageName: 'test'),
        EntityAlreadyExistsException(entityId: 'e', storageName: 's'),
        EntityNotFoundException(entityId: 'e', storageName: 's'),
        const StorageCorruptedException('test'),
        const StorageVersionMismatchException(
          'test',
          fileVersion: 1,
          supportedVersion: 2,
        ),
        StorageNotOpenException(storageName: 'test'),
        const StorageOutOfSpaceException('test'),
        TransactionAlreadyActiveException(storageName: 'test'),
        NoActiveTransactionException(storageName: 'test'),
        const AuthenticationException('test'),
        const UserAlreadyExistsException('test'),
        const InvalidUserOrPasswordException('test'),
        const InvalidOrExpiredTokenException('test'),
        const JWTTokenException('test'),
        const AuthorizationException('test'),
        const UndefinedRoleException('test'),
        const RoleAlreadyDefinedException('test'),
        const PermissionDeniedException('test'),
        const SystemRoleProtectionException('test', roleName: 'admin'),
        const CircularInheritanceException('test'),
        const InheritanceDepthExceededException(
          'test',
          maxDepth: 10,
          actualDepth: 15,
        ),
        const CollectionException('test'),
        const DocumentException('test'),
        const DocumentNotFoundException('test'),
        const IndexException('test'),
        const IndexNotFoundException('test'),
        const UnsupportedIndexTypeException('test'),
        const IndexAlreadyExistsException('test'),
        const QueryException('test'),
        const UserNotFoundException('test'),
        const TransactionException('test'),
        const ConcurrencyException('test'),
        const EncryptionException('test'),
        const EncryptionFailedException('test'),
        const DecryptionException('test'),
        const AuthenticationFailedException(),
        const InvalidKeyException('test'),
        const KeyDerivationException('test'),
        const EncryptionNotInitializedException(),
        const InvalidIvException('test'),
        const BackupException('test'),
        const BackupIntegrityException('test'),
        const BackupDecompressionException('test'),
        const BackupCompressionException('test'),
        const BackupVersionException('test'),
        const BackupTimeoutException('test'),
        const BackupQuotaExceededException('test'),
        const EmptyBackupException('test'),
        const BackupNotSupportedException('test'),
        const UserBackupFileNotFoundException('test'),
        const DataBackupFileNotFoundException('test'),
        const DataBackupCreationException('test'),
        const DataBackupRestorationException('test'),
        const UserBackupCreationException('test'),
        const UserBackupRestorationException('test'),
        const MigrationException('test'),
        const SchemaValidationException('test'),
        const ServerException('test'),
        const DatabaseException('test'),
        DatabaseOpenException(),
        const DatabaseNotOpenException(),
        const DatabaseDisposedException(),
        CollectionOperationException(collectionName: 'c', operation: 'o'),
        CollectionTypeMismatchException(
          collectionName: 'c',
          expectedType: int,
          actualType: String,
        ),
        const TypeRegistryException('test'),
        TypeAlreadyRegisteredException(type: String, existingTypeName: 'Str'),
        TypeNameConflictException(
          typeName: 'T',
          existingType: int,
          newType: double,
        ),
        TypeNotRegisteredException(typeName: 'X'),
        TypeSerializationException(type: Object),
        TypeDeserializationException(typeName: 'Y'),
      ];

      for (final e in exceptions) {
        expect(e, isA<EntiDBException>());
      }
    });
  });

  group('Exception immutability', () {
    test('exceptions should be immutable and const constructible', () {
      // All exception classes are marked with @immutable,
      // so we verify they can be created as const where possible
      const exception1 = StorageException('test');
      const exception2 = AuthenticationException('test');
      const exception3 = BackupException('test');

      expect(exception1.message, 'test');
      expect(exception2.message, 'test');
      expect(exception3.message, 'test');
    });
  });
}
