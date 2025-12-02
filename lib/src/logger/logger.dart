/// Logger module for DocDB.
///
/// This module provides structured, thread-safe logging capabilities
/// with multiple log levels, synchronized file access, and optional
/// console output.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:docdb/src/logger/logger.dart';
///
/// // Initialize once at startup
/// await DocDBLogger.initialize();
///
/// // Create a logger for your module
/// final logger = DocDBLogger('MyModule');
///
/// // Log messages at various levels
/// await logger.info('Operation completed');
/// await logger.warning('Resource running low');
/// await logger.error('Failed to process', error, stackTrace);
/// await logger.debug('Debug info', {'key': 'value'});
///
/// // Cleanup at shutdown
/// await DocDBLogger.dispose();
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
/// await DocDBLogger.initialize(
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
/// await DocDBLogger.initialize(config: LoggerConfig.production);
///
/// // For development (console + file, debug level)
/// await DocDBLogger.initialize(config: LoggerConfig.development);
/// ```
library;

export 'docdb_logger.dart';
export 'log_level.dart';
export 'logger_config.dart';
