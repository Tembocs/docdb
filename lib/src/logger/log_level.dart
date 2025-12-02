/// Log level for filtering log output.
///
/// Levels are ordered by severity from lowest to highest:
/// [debug] < [info] < [warning] < [error]
///
/// Example usage:
/// ```dart
/// final config = LoggerConfig(minLevel: LogLevel.warning);
/// // Only warning and error messages will be logged
/// ```
enum LogLevel {
  /// Detailed information for debugging purposes.
  ///
  /// Use for verbose output that helps trace program execution.
  /// Typically disabled in production environments.
  debug,

  /// General informational messages.
  ///
  /// Use for normal operational messages that confirm the program
  /// is working as expected.
  info,

  /// Warning messages for potentially harmful situations.
  ///
  /// Use for unexpected situations that don't prevent the application
  /// from functioning but should be reviewed.
  warning,

  /// Error messages for serious problems.
  ///
  /// Use for error events that might still allow the application to
  /// continue running but indicate a failure.
  error,
}
