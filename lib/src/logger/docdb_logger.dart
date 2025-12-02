import 'dart:io';

import 'package:logging/logging.dart';
import 'package:synchronized/synchronized.dart';

import 'log_level.dart';
import 'logger_config.dart';

/// A thread-safe logging utility for DocDB with module-specific contexts.
///
/// Provides structured logging capabilities with multiple log levels,
/// synchronized file access, and optional console output.
///
/// ## Initialization
///
/// The logger must be initialized before use:
///
/// ```dart
/// // Production setup (file logging only)
/// await DocDBLogger.initialize();
///
/// // Development setup (file + console logging)
/// await DocDBLogger.initialize(config: LoggerConfig.development);
/// ```
///
/// ## Creating Logger Instances
///
/// Create a logger for each module using [LoggerNameConstants]:
///
/// ```dart
/// final logger = DocDBLogger(LoggerNameConstants.authentication);
/// ```
///
/// ## Logging Messages
///
/// ```dart
/// await logger.info('User logged in successfully');
/// await logger.warning('Session expiring soon');
/// await logger.error('Authentication failed', error, stackTrace);
/// await logger.debug('Token payload', {'userId': '123'});
/// ```
///
/// ## Cleanup
///
/// Always dispose the logger during application shutdown:
///
/// ```dart
/// await DocDBLogger.dispose();
/// ```
class DocDBLogger {
  /// The name of the module using this logger instance.
  final String moduleName;

  /// The underlying logger instance from the logging package.
  final Logger _logger;

  /// Lock for synchronizing file access and logger initialization.
  static final Lock _lock = Lock();

  /// Map of log file paths to their corresponding IOSinks.
  static final Map<String, IOSink> _logSinks = {};

  /// Tracks whether the logger has been initialized.
  static bool _isInitialized = false;

  /// Current logger configuration.
  static LoggerConfig _config = LoggerConfig.production;

  /// Creates a new logger instance for the specified module.
  ///
  /// [moduleName] identifies the source of log messages in the log output.
  ///
  /// **Important**: Call [DocDBLogger.initialize] before creating instances.
  /// If not initialized, logging operations will be no-ops until initialization.
  DocDBLogger(this.moduleName) : _logger = Logger(moduleName);

  /// Returns `true` if the logger system has been initialized.
  static bool get isInitialized => _isInitialized;

  /// Returns the current log file path.
  static String get logPath => _config.logPath;

  /// Returns the current logger configuration.
  static LoggerConfig get config => _config;

  /// Initializes the logging system with the given configuration.
  ///
  /// Must be called before any logging operations. Safe to call multiple times;
  /// subsequent calls are no-ops unless [dispose] was called first.
  ///
  /// - [config]: Logger configuration (defaults to [LoggerConfig.production])
  ///
  /// Example:
  /// ```dart
  /// // Production setup
  /// await DocDBLogger.initialize();
  ///
  /// // Development setup with console output
  /// await DocDBLogger.initialize(config: LoggerConfig.development);
  ///
  /// // Custom configuration
  /// await DocDBLogger.initialize(
  ///   config: LoggerConfig(
  ///     logPath: 'custom/path/app.log',
  ///     minLevel: LogLevel.warning,
  ///     enableConsoleOutput: true,
  ///   ),
  /// );
  /// ```
  static Future<void> initialize({
    LoggerConfig config = LoggerConfig.production,
  }) async {
    await _lock.synchronized(() async {
      if (_isInitialized) return;

      _config = config;

      // Set root logger level based on config
      Logger.root.level = _logLevelToLevel(_config.minLevel);

      // Create log directory if needed
      final logDir = Directory(_config.logPath).parent;
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }

      // Open log file for appending
      final sink = File(_config.logPath).openWrite(mode: FileMode.append);
      _logSinks[_config.logPath] = sink;

      // Configure log record handler
      Logger.root.onRecord.listen(_handleLogRecord);

      _isInitialized = true;
    });
  }

  /// Handles incoming log records by writing to file and optionally console.
  static void _handleLogRecord(LogRecord record) {
    final timestamp = record.time.toIso8601String();
    final level = record.level.name.padRight(7);
    final logMessage =
        '$timestamp [$level] [${record.loggerName}] ${record.message}';

    // Write to file
    _logSinks[_config.logPath]?.writeln(logMessage);

    // Optionally write to console
    if (_config.enableConsoleOutput) {
      // Use stderr for warnings and errors, stdout for others
      if (record.level >= Level.WARNING) {
        stderr.writeln(logMessage);
      } else {
        stdout.writeln(logMessage);
      }
    }
  }

  /// Converts [LogLevel] to the logging package's [Level].
  static Level _logLevelToLevel(LogLevel level) {
    return switch (level) {
      LogLevel.debug => Level.FINE,
      LogLevel.info => Level.INFO,
      LogLevel.warning => Level.WARNING,
      LogLevel.error => Level.SEVERE,
    };
  }

  /// Cleans up logger resources by flushing and closing all log sinks.
  ///
  /// Should be called during application shutdown to ensure all log
  /// messages are written to disk.
  ///
  /// After calling this method, [initialize] must be called again
  /// before any logging operations.
  static Future<void> dispose() async {
    await _lock.synchronized(() async {
      for (final sink in _logSinks.values) {
        await sink.flush();
        await sink.close();
      }
      _logSinks.clear();
      _isInitialized = false;
      _config = LoggerConfig.production;
    });
  }

  /// Flushes all pending log writes to disk.
  ///
  /// Use this method to ensure all log messages are persisted
  /// without closing the logger.
  static Future<void> flush() async {
    await _lock.synchronized(() async {
      for (final sink in _logSinks.values) {
        await sink.flush();
      }
    });
  }

  /// Logs an informational message.
  ///
  /// Use for general operational messages that highlight the progress
  /// of the application.
  ///
  /// - [message]: The information to log.
  Future<void> info(String message) async {
    await _log(Level.INFO, message);
  }

  /// Logs a warning message.
  ///
  /// Use for potentially harmful situations that should be reviewed
  /// but don't prevent the application from functioning.
  ///
  /// - [message]: The warning to log.
  Future<void> warning(String message) async {
    await _log(Level.WARNING, message);
  }

  /// Logs an error message with optional error object and stack trace.
  ///
  /// Use for error events that might still allow the application to
  /// continue running.
  ///
  /// - [message]: Description of the error.
  /// - [error]: Optional error object that caused the issue.
  /// - [stackTrace]: Optional stack trace associated with the error.
  Future<void> error(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) async {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer
        ..writeln()
        ..write('Error: ')
        ..write(error);
      if (stackTrace != null) {
        buffer
          ..writeln()
          ..write('Stack Trace:')
          ..writeln()
          ..write(stackTrace);
      }
    }
    await _log(Level.SEVERE, buffer.toString());
  }

  /// Logs a debug message with optional metadata.
  ///
  /// Use for detailed information useful during development and debugging.
  /// These messages are typically filtered out in production.
  ///
  /// - [message]: The debug information to log.
  /// - [metadata]: Optional key-value pairs providing additional context.
  Future<void> debug(String message, [Map<String, dynamic>? metadata]) async {
    final buffer = StringBuffer(message);
    if (metadata != null && metadata.isNotEmpty) {
      buffer
        ..writeln()
        ..write('Metadata: ')
        ..write(metadata);
    }
    await _log(Level.FINE, buffer.toString());
  }

  /// Internal method to perform the actual logging operation.
  ///
  /// Thread-safe through synchronization. No-op if logger is not initialized.
  Future<void> _log(Level level, String message) async {
    if (!_isInitialized) return;

    await _lock.synchronized(() {
      _logger.log(level, message);
    });
  }
}
