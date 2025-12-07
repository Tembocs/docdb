/// Tests for the Utils module.
import 'package:entidb/src/utils/utils.dart';
import 'package:test/test.dart';

void main() {
  group('Constants', () {
    group('Default Values', () {
      test('defaultTimeout should be 5000ms', () {
        expect(defaultTimeout, 5000);
      });

      test('defaultRole should be "user"', () {
        expect(defaultRole, 'user');
      });

      test('errorMessageUnauthorized should be set', () {
        expect(errorMessageUnauthorized, 'Unauthorized access.');
      });

      test('defaultDatabaseVersion should be "1.0.0"', () {
        expect(defaultDatabaseVersion, '1.0.0');
      });
    });

    group('LoggerNameConstants', () {
      test('should have all required logger names', () {
        expect(LoggerNameConstants.entidbMain, 'EntiDbMain');
        expect(LoggerNameConstants.entidb, 'EntiDB');
        expect(LoggerNameConstants.authentication, 'Authentication');
        expect(LoggerNameConstants.authorization, 'Authorization');
        expect(LoggerNameConstants.backup, 'Backup');
        expect(LoggerNameConstants.collection, 'Collection');
        expect(LoggerNameConstants.encryption, 'Encryption');
        expect(LoggerNameConstants.exception, 'Exception');
        expect(LoggerNameConstants.index, 'Index');
        expect(LoggerNameConstants.migration, 'Migration');
        expect(LoggerNameConstants.query, 'Query');
        expect(LoggerNameConstants.schema, 'Schema');
        expect(LoggerNameConstants.storage, 'Storage');
        expect(LoggerNameConstants.transaction, 'Transaction');
        expect(LoggerNameConstants.typeRegistry, 'TypeRegistry');
      });
    });

    group('DatabaseFilePaths', () {
      test('should have correct data paths', () {
        expect(DatabaseFilePaths.dataPath, 'data/data.db');
        expect(DatabaseFilePaths.dataBackupPath, 'data/data_backup.db');
      });

      test('should have correct user paths', () {
        expect(DatabaseFilePaths.userPath, 'data/user.db');
        expect(DatabaseFilePaths.userBackupPath, 'data/user_backup.db');
      });

      test('should have correct log path', () {
        expect(DatabaseFilePaths.logPath, 'logs/entidb.log');
      });
    });

    group('MigrationFilePaths', () {
      test('should have correct schema paths', () {
        expect(MigrationFilePaths.dataSchemaPath, 'data_schema.json');
        expect(MigrationFilePaths.userSchemaPath, 'user_schema.json');
      });

      test('should have correct migration log paths', () {
        expect(
          MigrationFilePaths.dataMigrationLogPath,
          'data_migration_log.json',
        );
        expect(
          MigrationFilePaths.userMigrationLogPath,
          'user_migration_log.json',
        );
      });
    });
  });

  group('Helpers', () {
    group('generateUniqueId', () {
      test('should generate non-empty ID', () {
        final id = generateUniqueId();
        expect(id, isNotEmpty);
      });

      test('should generate unique IDs', () {
        final ids = <String>{};
        for (var i = 0; i < 100; i++) {
          ids.add(generateUniqueId());
        }
        expect(ids.length, 100);
      });

      test('should generate valid UUID format', () {
        final id = generateUniqueId();
        // UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(id),
          isTrue,
        );
      });
    });

    group('capitalize', () {
      test('should capitalize first letter', () {
        expect(capitalize('hello'), 'Hello');
      });

      test('should handle already capitalized string', () {
        expect(capitalize('World'), 'World');
      });

      test('should handle all uppercase string', () {
        expect(capitalize('HELLO'), 'HELLO');
      });

      test('should return empty string for empty input', () {
        expect(capitalize(''), '');
      });

      test('should handle single character', () {
        expect(capitalize('a'), 'A');
        expect(capitalize('A'), 'A');
      });

      test('should handle mixed case', () {
        expect(capitalize('hELLO wORLD'), 'HELLO wORLD');
      });
    });

    group('formatErrorMessage', () {
      test('should format error message with prefix', () {
        expect(
          formatErrorMessage('something went wrong'),
          'Error: Something went wrong',
        );
      });

      test('should handle already capitalized message', () {
        expect(
          formatErrorMessage('Already capitalized'),
          'Error: Already capitalized',
        );
      });

      test('should handle empty message', () {
        expect(formatErrorMessage(''), 'Error: ');
      });
    });

    group('parseTimestamp', () {
      test('should parse valid ISO 8601 timestamp', () {
        final dt = parseTimestamp('2024-01-15T10:30:00Z');
        expect(dt.year, 2024);
        expect(dt.month, 1);
        expect(dt.day, 15);
        expect(dt.hour, 10);
        expect(dt.minute, 30);
        expect(dt.second, 0);
        expect(dt.isUtc, isTrue);
      });

      test('should parse timestamp with timezone offset', () {
        final dt = parseTimestamp('2024-06-20T15:45:30+05:30');
        expect(dt.isUtc, isTrue);
      });

      test('should parse timestamp with milliseconds', () {
        final dt = parseTimestamp('2024-03-10T08:15:45.123Z');
        expect(dt.millisecond, 123);
      });

      test('should throw FormatException for empty string', () {
        expect(() => parseTimestamp(''), throwsA(isA<FormatException>()));
      });

      test('should throw FormatException for invalid format', () {
        expect(
          () => parseTimestamp('not-a-timestamp'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for incomplete timestamp', () {
        expect(
          () => parseTimestamp('2024-01-15'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for invalid date', () {
        // February 30th doesn't exist
        expect(
          () => parseTimestamp('2024-02-30T10:00:00Z'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should handle leap year correctly', () {
        // 2024 is a leap year
        final dt = parseTimestamp('2024-02-29T12:00:00Z');
        expect(dt.day, 29);

        // 2023 is not a leap year
        expect(
          () => parseTimestamp('2023-02-29T12:00:00Z'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw for invalid month', () {
        expect(
          () => parseTimestamp('2024-13-01T10:00:00Z'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw for invalid day', () {
        expect(
          () => parseTimestamp('2024-04-31T10:00:00Z'),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });

  group('Validators', () {
    group('isValidEmail', () {
      test('should return true for valid emails', () {
        expect(isValidEmail('user@example.com'), isTrue);
        expect(isValidEmail('user.name@example.com'), isTrue);
        expect(isValidEmail('user+tag@example.co.uk'), isTrue);
        expect(isValidEmail('user123@subdomain.example.org'), isTrue);
      });

      test('should return false for invalid emails', () {
        expect(isValidEmail(''), isFalse);
        expect(isValidEmail('invalid'), isFalse);
        expect(isValidEmail('missing@domain'), isFalse);
        expect(isValidEmail('@example.com'), isFalse);
        expect(isValidEmail('user@'), isFalse);
        expect(isValidEmail('user@.com'), isFalse);
        expect(isValidEmail('user@example.'), isFalse);
        expect(isValidEmail('user @example.com'), isFalse);
      });
    });

    group('isValidVersion', () {
      test('should return true for valid semantic versions', () {
        expect(isValidVersion('1.0.0'), isTrue);
        expect(isValidVersion('0.0.1'), isTrue);
        expect(isValidVersion('10.20.30'), isTrue);
        expect(isValidVersion('123.456.789'), isTrue);
      });

      test('should return false for invalid versions', () {
        expect(isValidVersion(''), isFalse);
        expect(isValidVersion('1.0'), isFalse);
        expect(isValidVersion('1'), isFalse);
        expect(isValidVersion('v1.0.0'), isFalse);
        expect(isValidVersion('1.0.0-beta'), isFalse);
        expect(isValidVersion('1.0.0.0'), isFalse);
        expect(isValidVersion('a.b.c'), isFalse);
      });
    });

    group('isValidUsername', () {
      test('should return true for valid usernames', () {
        expect(isValidUsername('john'), isTrue);
        expect(isValidUsername('john_doe'), isTrue);
        expect(isValidUsername('user-123'), isTrue);
        expect(isValidUsername('User123'), isTrue);
        expect(isValidUsername('abc'), isTrue);
      });

      test('should return false for too short usernames', () {
        expect(isValidUsername(''), isFalse);
        expect(isValidUsername('ab'), isFalse);
      });

      test('should return false for too long usernames', () {
        expect(isValidUsername('a' * 33), isFalse);
      });

      test('should return false for usernames starting with special chars', () {
        expect(isValidUsername('_invalid'), isFalse);
        expect(isValidUsername('-invalid'), isFalse);
      });

      test('should return false for usernames with invalid chars', () {
        expect(isValidUsername('user@name'), isFalse);
        expect(isValidUsername('user name'), isFalse);
        expect(isValidUsername('user.name'), isFalse);
      });
    });

    group('isValidCollectionName', () {
      test('should return true for valid collection names', () {
        expect(isValidCollectionName('users'), isTrue);
        expect(isValidCollectionName('order_items'), isTrue);
        expect(isValidCollectionName('Products123'), isTrue);
        expect(isValidCollectionName('a'), isTrue);
      });

      test('should return false for invalid collection names', () {
        expect(isValidCollectionName(''), isFalse);
        expect(isValidCollectionName('123invalid'), isFalse);
        expect(isValidCollectionName('_private'), isFalse);
        expect(isValidCollectionName('has-dash'), isFalse);
        expect(isValidCollectionName('has space'), isFalse);
      });

      test('should return false for too long names', () {
        expect(isValidCollectionName('a' * 65), isFalse);
      });
    });

    group('isValidDocumentId', () {
      test('should return true for valid document IDs', () {
        expect(isValidDocumentId('abc123'), isTrue);
        expect(isValidDocumentId('018c5a2e-8f3b-7000-8000'), isTrue);
        expect(isValidDocumentId('user_1'), isTrue);
        expect(isValidDocumentId('a'), isTrue);
      });

      test('should return false for empty ID', () {
        expect(isValidDocumentId(''), isFalse);
      });

      test('should return false for too long IDs', () {
        expect(isValidDocumentId('a' * 129), isFalse);
      });

      test('should return false for IDs with invalid chars', () {
        expect(isValidDocumentId('id with spaces'), isFalse);
        expect(isValidDocumentId('id@special'), isFalse);
        expect(isValidDocumentId('id.dotted'), isFalse);
      });
    });

    group('isValidFieldName', () {
      test('should return true for valid field names', () {
        expect(isValidFieldName('name'), isTrue);
        expect(isValidFieldName('user_email'), isTrue);
        expect(isValidFieldName('_id'), isTrue);
        expect(isValidFieldName('nested.field'), isTrue);
        expect(isValidFieldName('Field123'), isTrue);
      });

      test('should return false for invalid field names', () {
        expect(isValidFieldName(''), isFalse);
        expect(isValidFieldName('123field'), isFalse);
        expect(isValidFieldName(r'$system'), isFalse);
        expect(isValidFieldName('has-dash'), isFalse);
        expect(isValidFieldName('has space'), isFalse);
      });

      test('should return false for too long field names', () {
        expect(isValidFieldName('a' * 65), isFalse);
      });
    });

    group('isValidPassword', () {
      test('should return true for valid passwords', () {
        expect(isValidPassword('password'), isTrue);
        expect(isValidPassword('securepass123'), isTrue);
        expect(isValidPassword('a' * 8), isTrue);
        expect(isValidPassword('a' * 128), isTrue);
      });

      test('should return false for too short passwords', () {
        expect(isValidPassword(''), isFalse);
        expect(isValidPassword('short'), isFalse);
        expect(isValidPassword('1234567'), isFalse);
      });

      test('should return false for too long passwords', () {
        expect(isValidPassword('a' * 129), isFalse);
      });
    });

    group('isNotBlank', () {
      test('should return true for non-blank strings', () {
        expect(isNotBlank('hello'), isTrue);
        expect(isNotBlank('  hi  '), isTrue);
        expect(isNotBlank('a'), isTrue);
      });

      test('should return false for blank strings', () {
        expect(isNotBlank(''), isFalse);
        expect(isNotBlank('   '), isFalse);
        expect(isNotBlank('\t\n'), isFalse);
      });

      test('should return false for null', () {
        expect(isNotBlank(null), isFalse);
      });
    });
  });
}
