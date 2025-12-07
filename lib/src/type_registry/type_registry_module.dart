/// EntiDB Type Registry Module
///
/// Provides extensible type serialization support for custom Dart types.
/// Enables storage of non-primitive types like DateTime, Duration, and
/// custom classes in entity fields.
///
/// ## Overview
///
/// The type registry manages serializers that convert custom types to
/// JSON-compatible primitives and back. This allows entities to contain
/// fields of any registered type.
///
/// ## Usage
///
/// ```dart
/// import 'package:entidb/src/type_registry/type_registry.dart';
///
/// // Access the global registry
/// final registry = TypeRegistry.instance;
///
/// // Register a custom serializer
/// registry.register<MyType>(MyTypeSerializer());
///
/// // Built-in types are pre-registered:
/// // DateTime, Duration, Uri, BigInt, RegExp
/// ```
///
/// ## Custom Serializers
///
/// Implement [TypeSerializer] to add support for custom types:
///
/// ```dart
/// class ColorSerializer implements TypeSerializer<Color> {
///   @override
///   String get typeName => 'Color';
///
///   @override
///   Object serialize(Color value) => value.value;
///
///   @override
///   Color deserialize(Object data) => Color(data as int);
/// }
/// ```
library;

export 'builtin_serializers.dart'
    show
        BigIntSerializer,
        DateTimeSerializer,
        DurationSerializer,
        RegExpSerializer,
        UriSerializer,
        builtInSerializers;
export 'type_registry.dart' show TypeRegistry;
export 'type_serializer.dart' show TypeSerializer, TypeSerializerEntry;
