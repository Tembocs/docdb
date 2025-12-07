import 'package:meta/meta.dart';

import 'entidb_exception.dart';

/// Base exception for type registry errors.
///
/// Thrown when type registration or lookup operations fail, such as
/// duplicate type registration, missing serializers, or type
/// resolution errors.
@immutable
class TypeRegistryException extends EntiDBException {
  /// Creates a new [TypeRegistryException].
  ///
  /// - [message]: A descriptive error message.
  /// - [cause]: The underlying exception that caused this error.
  /// - [stackTrace]: The stack trace for debugging.
  const TypeRegistryException(super.message, {super.cause, super.stackTrace});
}

/// Exception thrown when attempting to register a type that is already registered.
///
/// This occurs when [TypeRegistry.register] is called for a type that already
/// has a serializer registered, and the `overwrite` parameter is `false`.
@immutable
class TypeAlreadyRegisteredException extends TypeRegistryException {
  /// The Dart type that was already registered.
  final Type type;

  /// The type name of the existing serializer.
  final String existingTypeName;

  /// Creates a new [TypeAlreadyRegisteredException].
  ///
  /// - [type]: The Dart type that was already registered.
  /// - [existingTypeName]: The type name of the existing serializer.
  TypeAlreadyRegisteredException({
    required this.type,
    required this.existingTypeName,
  }) : super(
         'Type $type is already registered with name "$existingTypeName". '
         'Use overwrite: true to replace the existing registration.',
       );
}

/// Exception thrown when a type name conflicts with an existing registration.
///
/// This occurs when attempting to register a serializer with a type name that
/// is already used by a different Dart type.
@immutable
class TypeNameConflictException extends TypeRegistryException {
  /// The conflicting type name.
  final String typeName;

  /// The existing Dart type using this name.
  final Type existingType;

  /// The new Dart type attempting to use this name.
  final Type newType;

  /// Creates a new [TypeNameConflictException].
  ///
  /// - [typeName]: The conflicting type name.
  /// - [existingType]: The existing Dart type using this name.
  /// - [newType]: The new Dart type attempting to use this name.
  TypeNameConflictException({
    required this.typeName,
    required this.existingType,
    required this.newType,
  }) : super(
         'Type name "$typeName" is already registered for $existingType. '
         'Cannot register for $newType with the same name.',
       );
}

/// Exception thrown when attempting to deserialize an unregistered type.
///
/// This occurs when [TypeRegistry.deserializeIfCustom] encounters a type name
/// in the serialized data that has no registered serializer.
@immutable
class TypeNotRegisteredException extends TypeRegistryException {
  /// The type name that was not found in the registry.
  final String typeName;

  /// Creates a new [TypeNotRegisteredException].
  ///
  /// - [typeName]: The type name that was not found.
  TypeNotRegisteredException({required this.typeName})
    : super(
        'No serializer registered for type "$typeName". '
        'Register a TypeSerializer before deserializing this type.',
      );
}

/// Exception thrown when type serialization fails.
///
/// This occurs when a [TypeSerializer.serialize] method throws an exception
/// or returns an invalid value.
@immutable
class TypeSerializationException extends TypeRegistryException {
  /// The type that failed to serialize.
  final Type type;

  /// The value that could not be serialized.
  final Object? value;

  /// Creates a new [TypeSerializationException].
  ///
  /// - [type]: The type that failed to serialize.
  /// - [value]: The value that could not be serialized.
  /// - [cause]: The underlying exception.
  TypeSerializationException({
    required this.type,
    this.value,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
         'Failed to serialize value of type $type',
         cause: cause,
         stackTrace: stackTrace,
       );
}

/// Exception thrown when type deserialization fails.
///
/// This occurs when a [TypeSerializer.deserialize] method throws an exception
/// or the serialized data is malformed.
@immutable
class TypeDeserializationException extends TypeRegistryException {
  /// The type name that failed to deserialize.
  final String typeName;

  /// The data that could not be deserialized.
  final Object? data;

  /// Creates a new [TypeDeserializationException].
  ///
  /// - [typeName]: The type name that failed to deserialize.
  /// - [data]: The data that could not be deserialized.
  /// - [cause]: The underlying exception.
  TypeDeserializationException({
    required this.typeName,
    this.data,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(
         'Failed to deserialize data for type "$typeName"',
         cause: cause,
         stackTrace: stackTrace,
       );
}
