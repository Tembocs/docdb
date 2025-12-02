/// DocDB Type Registry - Type Serializer Interface
///
/// Defines the contract for custom type serialization/deserialization.
/// Enables extensible support for non-primitive types in entity storage.
library;

import 'package:meta/meta.dart';

/// A serializer/deserializer pair for a specific data type.
///
/// Implement this interface to add support for custom types that cannot
/// be serialized directly to JSON-compatible primitives.
///
/// ## Usage Example
///
/// ```dart
/// class DateTimeSerializer implements TypeSerializer<DateTime> {
///   @override
///   String get typeName => 'DateTime';
///
///   @override
///   Object serialize(DateTime value) => value.toIso8601String();
///
///   @override
///   DateTime deserialize(Object data) => DateTime.parse(data as String);
/// }
/// ```
///
/// ## Built-in Types
///
/// The following types are handled natively and do not require serializers:
/// - `null`, `bool`, `int`, `double`, `String`
/// - `List<dynamic>`, `Map<String, dynamic>`
///
/// ## Type Safety
///
/// The serializer is generic over `T` to ensure type-safe conversions.
/// The [serialize] method receives a value of type `T` and returns a
/// JSON-compatible primitive. The [deserialize] method reverses this.
@immutable
abstract interface class TypeSerializer<T> {
  /// The unique string identifier for this type.
  ///
  /// Used to tag serialized data so the correct deserializer can be
  /// identified during reconstruction. Must be unique across all
  /// registered serializers.
  ///
  /// Convention: Use the Dart type name (e.g., 'DateTime', 'Duration').
  String get typeName;

  /// Converts a value of type [T] to a JSON-compatible representation.
  ///
  /// The returned value must be one of:
  /// - `null`, `bool`, `int`, `double`, `String`
  /// - `List<dynamic>` containing only serializable values
  /// - `Map<String, dynamic>` with only serializable values
  ///
  /// Throws [ArgumentError] if the value cannot be serialized.
  Object serialize(T value);

  /// Reconstructs a value of type [T] from its serialized representation.
  ///
  /// The [data] parameter is the value previously returned by [serialize].
  ///
  /// Throws [ArgumentError] if the data cannot be deserialized.
  /// Throws [FormatException] if the data format is invalid.
  T deserialize(Object data);
}

/// Entry holding a registered type serializer with runtime type information.
///
/// Used internally by [TypeRegistry] to map between Dart [Type] objects,
/// string type names, and their corresponding serializers.
@immutable
final class TypeSerializerEntry<T> {
  /// The runtime type this entry handles.
  final Type type;

  /// The serializer instance for this type.
  final TypeSerializer<T> serializer;

  /// Creates a new type serializer entry.
  const TypeSerializerEntry({required this.type, required this.serializer});

  /// The unique string name for this type.
  String get typeName => serializer.typeName;

  /// Serializes a value using this entry's serializer.
  ///
  /// Throws [TypeError] if [value] is not of type [T].
  Object serialize(Object value) => serializer.serialize(value as T);

  /// Deserializes data using this entry's serializer.
  T deserialize(Object data) => serializer.deserialize(data);
}
