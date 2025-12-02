import 'package:uuid/uuid.dart';

/// Cached UUID generator instance for efficient ID generation.
const Uuid _uuid = Uuid();

/// Generates a unique identifier using UUID v7.
///
/// UUID v7 is time-ordered, which provides better database indexing
/// performance compared to random UUIDs (v4) as sequential IDs
/// cluster together in B+ tree indexes.
///
/// Returns a new UUID v7 string in the format:
/// `xxxxxxxx-xxxx-7xxx-xxxx-xxxxxxxxxxxx`
///
/// Example:
/// ```dart
/// final id = generateUniqueId();
/// print(id); // e.g., '018c5a2e-8f3b-7000-8000-000000000000'
/// ```
String generateUniqueId() {
  return _uuid.v7();
}

/// Capitalizes the first letter of the input string.
///
/// Returns the original string if it's empty.
///
/// Example:
/// ```dart
/// print(capitalize('hello')); // 'Hello'
/// print(capitalize('WORLD')); // 'WORLD'
/// print(capitalize(''));      // ''
/// ```
String capitalize(String input) {
  if (input.isEmpty) return input;
  return input[0].toUpperCase() + input.substring(1);
}

/// Formats an error message with a standard prefix.
///
/// Capitalizes the first letter of the message and prepends "Error: ".
///
/// Example:
/// ```dart
/// print(formatErrorMessage('invalid input'));
/// // Output: 'Error: Invalid input'
/// ```
String formatErrorMessage(String message) {
  return 'Error: ${capitalize(message)}';
}

/// Parses an ISO 8601 timestamp string into a [DateTime] object.
///
/// The timestamp must be in ISO 8601 format:
/// `YYYY-MM-DDTHH:MM:SS[.sss][Z|±HH:MM]`
///
/// Throws a [FormatException] if:
/// - The string is empty
/// - The format is invalid
/// - The date values are invalid (e.g., February 30th)
///
/// Returns the parsed [DateTime] in UTC.
///
/// Example:
/// ```dart
/// final dt = parseTimestamp('2024-01-15T10:30:00Z');
/// print(dt); // 2024-01-15 10:30:00.000Z
/// ```
DateTime parseTimestamp(String timestamp) {
  if (timestamp.isEmpty) {
    throw const FormatException('Empty timestamp string');
  }

  // Validate basic format with regex
  final regex = RegExp(
    r'^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-][01]\d:[0-5]\d)?$',
  );
  if (!regex.hasMatch(timestamp)) {
    throw FormatException('Invalid timestamp format: $timestamp');
  }

  try {
    // Parse date components to validate leap year, etc.
    final parts = timestamp.split('T')[0].split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);

    if (!_isValidDate(year, month, day)) {
      throw FormatException('Invalid date: $timestamp');
    }

    final result = DateTime.parse(timestamp);
    return result.toUtc();
  } on FormatException {
    rethrow;
  } catch (e) {
    throw FormatException('Invalid timestamp: $timestamp');
  }
}

/// Validates that a date has a valid day for the given month and year.
///
/// Accounts for leap years when validating February dates.
///
/// Returns `true` if the date is valid, `false` otherwise.
bool _isValidDate(int year, int month, int day) {
  if (month == 2) {
    final isLeapYear = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0);
    return day <= (isLeapYear ? 29 : 28);
  }
  const daysInMonth = [0, 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= daysInMonth[month];
}
