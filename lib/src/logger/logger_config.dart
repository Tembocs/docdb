import 'package:meta/meta.dart';

import '../utils/constants.dart';
import 'log_level.dart';

/// Configuration options for [EntiDBLogger].
///
/// Use this class to customize logger behavior, including log file path,
/// minimum log level, and console output settings.
///
/// Example usage:
/// ```dart
/// // Use predefined configurations
/// await EntiDBLogger.initialize(config: LoggerConfig.development);
///
/// // Or create a custom configuration
/// final config = LoggerConfig(
///   logPath: 'logs/custom.log',
///   minLevel: LogLevel.warning,
///   enableConsoleOutput: true,
/// );
/// await EntiDBLogger.initialize(config: config);
/// ```
@immutable
class LoggerConfig {
  /// Path to the log file.
  ///
  /// The directory will be created automatically if it doesn't exist.
  final String logPath;

  /// Minimum level of messages to log.
  ///
  /// Messages below this level are ignored. For example, if set to
  /// [LogLevel.warning], only warning and error messages are logged.
  final LogLevel minLevel;

  /// Whether to also print log messages to the console.
  ///
  /// When enabled:
  /// - Debug and info messages are written to stdout
  /// - Warning and error messages are written to stderr
  final bool enableConsoleOutput;

  /// Creates a new logger configuration.
  ///
  /// - [logPath]: Path to the log file (defaults to [DatabaseFilePaths.logPath])
  /// - [minLevel]: Minimum log level (defaults to [LogLevel.info])
  /// - [enableConsoleOutput]: Whether to print to console (defaults to false)
  const LoggerConfig({
    this.logPath = DatabaseFilePaths.logPath,
    this.minLevel = LogLevel.info,
    this.enableConsoleOutput = false,
  });

  /// Default configuration for production use.
  ///
  /// - Logs to the default log path
  /// - Minimum level: info
  /// - Console output: disabled
  static const LoggerConfig production = LoggerConfig();

  /// Configuration for development with console output and debug logging.
  ///
  /// - Logs to the default log path
  /// - Minimum level: debug (all messages)
  /// - Console output: enabled
  static const LoggerConfig development = LoggerConfig(
    minLevel: LogLevel.debug,
    enableConsoleOutput: true,
  );

  /// Creates a copy of this configuration with the given fields replaced.
  LoggerConfig copyWith({
    String? logPath,
    LogLevel? minLevel,
    bool? enableConsoleOutput,
  }) {
    return LoggerConfig(
      logPath: logPath ?? this.logPath,
      minLevel: minLevel ?? this.minLevel,
      enableConsoleOutput: enableConsoleOutput ?? this.enableConsoleOutput,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoggerConfig &&
        other.logPath == logPath &&
        other.minLevel == minLevel &&
        other.enableConsoleOutput == enableConsoleOutput;
  }

  @override
  int get hashCode => Object.hash(logPath, minLevel, enableConsoleOutput);

  @override
  String toString() {
    return 'LoggerConfig(logPath: $logPath, minLevel: $minLevel, '
        'enableConsoleOutput: $enableConsoleOutput)';
  }
}
