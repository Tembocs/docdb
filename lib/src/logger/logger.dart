/// Logger module for EntiDB.
///
/// This module provides structured, thread-safe logging capabilities
/// with multiple log levels, synchronized file access, and optional
/// console output.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:entidb/src/logger/logger.dart';
///
/// // Initialize once at startup
/// await EntiDBLogger.initialize();
///
/// // Create a logger for your module
/// final logger = EntiDBLogger('MyModule');
///
/// // Log messages at various levels
/// await logger.info('Operation completed');
/// await logger.warning('Resource running low');
/// await logger.error('Failed to process', error, stackTrace);
/// await logger.debug('Debug info', {'key': 'value'});
///
/// // Cleanup at shutdown
/// await EntiDBLogger.dispose();
/// ```
///
/// ## Log Levels
///
/// - [LogLevel.debug]: Detailed debugging information (disabled in production)
/// - [LogLevel.info]: General operational information
/// - [LogLevel.warning]: Potentially harmful situations
/// - [LogLevel.error]: Error events that may still allow continued operation
///
/// ## Configuration
///
/// Use [LoggerConfig] to customize behavior:
///
/// ```dart
/// await EntiDBLogger.initialize(
///   config: LoggerConfig(
///     logPath: 'custom/logs/app.log',
///     minLevel: LogLevel.warning,
///     enableConsoleOutput: true,
///   ),
/// );
/// ```
///
/// Or use predefined configurations:
///
/// ```dart
/// // For production (file only, info level)
/// await EntiDBLogger.initialize(config: LoggerConfig.production);
///
/// // For development (console + file, debug level)
/// await EntiDBLogger.initialize(config: LoggerConfig.development);
/// ```
library;

export 'entidb_logger.dart';
export 'log_level.dart';
export 'logger_config.dart';
