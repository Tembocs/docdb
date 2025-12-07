/// EntiDB Type Registry - Built-in Serializers
///
/// Provides serializers for common Dart types that are not directly
/// JSON-compatible. These are automatically registered with the TypeRegistry.
library;

import 'type_serializer.dart';

/// Serializer for [DateTime] values.
///
/// Converts DateTime to ISO 8601 string format for storage and
/// parses it back on deserialization.
final class DateTimeSerializer implements TypeSerializer<DateTime> {
  /// Creates a new DateTime serializer.
  const DateTimeSerializer();

  @override
  String get typeName => 'DateTime';

  @override
  Object serialize(DateTime value) => value.toUtc().toIso8601String();

  @override
  DateTime deserialize(Object data) {
    if (data is String) {
      return DateTime.parse(data);
    }
    throw FormatException(
      'DateTimeSerializer: expected String, got ${data.runtimeType}',
    );
  }
}

/// Serializer for [Duration] values.
///
/// Converts Duration to microseconds for precise storage and
/// reconstructs it on deserialization.
final class DurationSerializer implements TypeSerializer<Duration> {
  /// Creates a new Duration serializer.
  const DurationSerializer();

  @override
  String get typeName => 'Duration';

  @override
  Object serialize(Duration value) => value.inMicroseconds;

  @override
  Duration deserialize(Object data) {
    if (data is int) {
      return Duration(microseconds: data);
    }
    throw FormatException(
      'DurationSerializer: expected int, got ${data.runtimeType}',
    );
  }
}

/// Serializer for [Uri] values.
///
/// Converts Uri to its string representation for storage.
final class UriSerializer implements TypeSerializer<Uri> {
  /// Creates a new Uri serializer.
  const UriSerializer();

  @override
  String get typeName => 'Uri';

  @override
  Object serialize(Uri value) => value.toString();

  @override
  Uri deserialize(Object data) {
    if (data is String) {
      return Uri.parse(data);
    }
    throw FormatException(
      'UriSerializer: expected String, got ${data.runtimeType}',
    );
  }
}

/// Serializer for [BigInt] values.
///
/// Converts BigInt to its string representation to preserve
/// full precision regardless of size.
final class BigIntSerializer implements TypeSerializer<BigInt> {
  /// Creates a new BigInt serializer.
  const BigIntSerializer();

  @override
  String get typeName => 'BigInt';

  @override
  Object serialize(BigInt value) => value.toString();

  @override
  BigInt deserialize(Object data) {
    if (data is String) {
      return BigInt.parse(data);
    }
    throw FormatException(
      'BigIntSerializer: expected String, got ${data.runtimeType}',
    );
  }
}

/// Serializer for [RegExp] values.
///
/// Stores the pattern and flags to fully reconstruct the RegExp.
final class RegExpSerializer implements TypeSerializer<RegExp> {
  /// Creates a new RegExp serializer.
  const RegExpSerializer();

  @override
  String get typeName => 'RegExp';

  @override
  Object serialize(RegExp value) => {
    'pattern': value.pattern,
    'multiLine': value.isMultiLine,
    'caseSensitive': value.isCaseSensitive,
    'unicode': value.isUnicode,
    'dotAll': value.isDotAll,
  };

  @override
  RegExp deserialize(Object data) {
    if (data is Map<String, dynamic>) {
      return RegExp(
        data['pattern'] as String,
        multiLine: data['multiLine'] as bool? ?? false,
        caseSensitive: data['caseSensitive'] as bool? ?? true,
        unicode: data['unicode'] as bool? ?? false,
        dotAll: data['dotAll'] as bool? ?? false,
      );
    }
    throw FormatException(
      'RegExpSerializer: expected Map<String, dynamic>, got ${data.runtimeType}',
    );
  }
}

/// Collection of all built-in type serializers.
///
/// These serializers are automatically registered when [TypeRegistry]
/// is initialized with default configuration.
const List<TypeSerializer<Object>> builtInSerializers = [
  DateTimeSerializer(),
  DurationSerializer(),
  UriSerializer(),
  BigIntSerializer(),
  RegExpSerializer(),
];
