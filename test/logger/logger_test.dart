/// Tests for the Logger module.
import 'dart:io';

import 'package:docdb/src/logger/logger.dart';
import 'package:test/test.dart';

void main() {
  group('LogLevel', () {
    test('should have correct ordering by severity', () {
      // LogLevel enum values are ordered from lowest to highest severity
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.warning.index, lessThan(LogLevel.error.index));
    });

    test('should have all expected levels', () {
      expect(LogLevel.values, hasLength(4));
      expect(LogLevel.values, contains(LogLevel.debug));
      expect(LogLevel.values, contains(LogLevel.info));
      expect(LogLevel.values, contains(LogLevel.warning));
      expect(LogLevel.values, contains(LogLevel.error));
    });
  });

  group('LoggerConfig', () {
    test('should have correct default values', () {
      const config = LoggerConfig();
      expect(config.logPath, 'logs/docdb.log');
      expect(config.minLevel, LogLevel.info);
      expect(config.enableConsoleOutput, isFalse);
    });

    test('should create production config with correct values', () {
      const config = LoggerConfig.production;
      expect(config.logPath, 'logs/docdb.log');
      expect(config.minLevel, LogLevel.info);
      expect(config.enableConsoleOutput, isFalse);
    });

    test('should create development config with correct values', () {
      const config = LoggerConfig.development;
      expect(config.minLevel, LogLevel.debug);
      expect(config.enableConsoleOutput, isTrue);
    });

    test('should create custom config', () {
      const config = LoggerConfig(
        logPath: 'custom/path.log',
        minLevel: LogLevel.warning,
        enableConsoleOutput: true,
      );

      expect(config.logPath, 'custom/path.log');
      expect(config.minLevel, LogLevel.warning);
      expect(config.enableConsoleOutput, isTrue);
    });

    test('should copy config with modifications', () {
      const original = LoggerConfig.production;
      final modified = original.copyWith(
        logPath: 'new/path.log',
        enableConsoleOutput: true,
      );

      expect(modified.logPath, 'new/path.log');
      expect(modified.minLevel, original.minLevel);
      expect(modified.enableConsoleOutput, isTrue);
    });

    test('should copy config without modifications', () {
      const original = LoggerConfig(
        logPath: 'test.log',
        minLevel: LogLevel.warning,
        enableConsoleOutput: true,
      );
      final copy = original.copyWith();

      expect(copy.logPath, original.logPath);
      expect(copy.minLevel, original.minLevel);
      expect(copy.enableConsoleOutput, original.enableConsoleOutput);
    });

    test('should implement equality correctly', () {
      const config1 = LoggerConfig(
        logPath: 'test.log',
        minLevel: LogLevel.info,
        enableConsoleOutput: true,
      );
      const config2 = LoggerConfig(
        logPath: 'test.log',
        minLevel: LogLevel.info,
        enableConsoleOutput: true,
      );
      const config3 = LoggerConfig(
        logPath: 'different.log',
        minLevel: LogLevel.info,
        enableConsoleOutput: true,
      );

      expect(config1, equals(config2));
      expect(config1, isNot(equals(config3)));
      expect(config1.hashCode, equals(config2.hashCode));
    });

    test('should have correct toString representation', () {
      const config = LoggerConfig(
        logPath: 'test.log',
        minLevel: LogLevel.warning,
        enableConsoleOutput: true,
      );

      final str = config.toString();
      expect(str, contains('LoggerConfig'));
      expect(str, contains('test.log'));
      expect(str, contains('warning'));
      expect(str, contains('true'));
    });
  });

  group('DocDBLogger', () {
    late Directory tempDir;
    late String logPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docdb_logger_test_');
      logPath = '${tempDir.path}/test.log';

      // Ensure logger is disposed before each test
      await DocDBLogger.dispose();
    });

    tearDown(() async {
      await DocDBLogger.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('should not be initialized initially', () {
      expect(DocDBLogger.isInitialized, isFalse);
    });

    test('should initialize successfully', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      expect(DocDBLogger.isInitialized, isTrue);
      expect(DocDBLogger.logPath, logPath);
    });

    test('should create log directory if it does not exist', () async {
      final nestedPath = '${tempDir.path}/nested/deep/test.log';

      await DocDBLogger.initialize(config: LoggerConfig(logPath: nestedPath));

      expect(DocDBLogger.isInitialized, isTrue);
      expect(await Directory('${tempDir.path}/nested/deep').exists(), isTrue);
    });

    test('should be idempotent on multiple initialize calls', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));
      await DocDBLogger.initialize(
        config: LoggerConfig(logPath: '${tempDir.path}/other.log'),
      );

      // Should keep the first initialization
      expect(DocDBLogger.logPath, logPath);
    });

    test('should create logger with module name', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      expect(logger.moduleName, 'TestModule');
    });

    test('should log info messages', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      await logger.info('Test info message');
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('INFO'));
      expect(content, contains('TestModule'));
      expect(content, contains('Test info message'));
    });

    test('should log warning messages', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      await logger.warning('Test warning message');
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('WARNING'));
      expect(content, contains('Test warning message'));
    });

    test('should log error messages with error object', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      await logger.error('Test error message', Exception('Test exception'));
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('SEVERE'));
      expect(content, contains('Test error message'));
      expect(content, contains('Test exception'));
    });

    test('should log error messages with stack trace', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      final stackTrace = StackTrace.current;
      await logger.error('Test error', Exception('Test'), stackTrace);
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('Stack Trace'));
    });

    test('should log debug messages with metadata', () async {
      await DocDBLogger.initialize(
        config: LoggerConfig(logPath: logPath, minLevel: LogLevel.debug),
      );

      final logger = DocDBLogger('TestModule');
      await logger.debug('Test debug', {'key': 'value', 'count': 42});
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('Test debug'));
      expect(content, contains('Metadata'));
      expect(content, contains('key'));
      expect(content, contains('value'));
    });

    test('should not log when not initialized', () async {
      final logger = DocDBLogger('TestModule');

      // Should not throw, just be a no-op
      await logger.info('This should not be logged');

      expect(DocDBLogger.isInitialized, isFalse);
    });

    test('should dispose correctly', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      expect(DocDBLogger.isInitialized, isTrue);

      await DocDBLogger.dispose();

      expect(DocDBLogger.isInitialized, isFalse);
    });

    test('should allow re-initialization after dispose', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));
      await DocDBLogger.dispose();

      final newPath = '${tempDir.path}/new.log';
      await DocDBLogger.initialize(config: LoggerConfig(logPath: newPath));

      expect(DocDBLogger.isInitialized, isTrue);
      expect(DocDBLogger.logPath, newPath);
    });

    test('should return current config', () async {
      final customConfig = LoggerConfig(
        logPath: logPath,
        minLevel: LogLevel.warning,
        enableConsoleOutput: true,
      );

      await DocDBLogger.initialize(config: customConfig);

      expect(DocDBLogger.config, equals(customConfig));
    });

    test('should flush pending writes', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      await logger.info('Message 1');
      await logger.info('Message 2');
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      expect(content, contains('Message 1'));
      expect(content, contains('Message 2'));
    });

    test('should include timestamp in log messages', () async {
      await DocDBLogger.initialize(config: LoggerConfig(logPath: logPath));

      final logger = DocDBLogger('TestModule');
      await logger.info('Timestamped message');
      await DocDBLogger.flush();

      final content = await File(logPath).readAsString();
      // ISO 8601 format includes T separator
      expect(content, contains('T'));
      expect(RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(content), isTrue);
    });
  });
}
