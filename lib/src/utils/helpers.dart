// lib/src/utils/helpers.dart
import 'package:uuid/uuid.dart';

String generateUniqueId() {
  return Uuid().v7();
}

String capitalize(String input) {
  if (input.isEmpty) return input;
  return input[0].toUpperCase() + input.substring(1);
}

String formatErrorMessage(String message) {
  return "Error: ${capitalize(message)}";
}

DateTime parseTimestamp(String timestamp) {
  if (timestamp.isEmpty) {
    throw FormatException('Empty timestamp string');
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
  } catch (e) {
    throw FormatException('Invalid timestamp: $timestamp');
  }
}

bool _isValidDate(int year, int month, int day) {
  if (month == 2) {
    final isLeapYear = (year % 4 == 0) && (year % 100 != 0 || year % 400 == 0);
    return day <= (isLeapYear ? 29 : 28);
  }
  final daysInMonth = [0, 31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= daysInMonth[month];
}
