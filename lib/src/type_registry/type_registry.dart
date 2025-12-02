/// DocDB Type Registry - Central Registry
///
/// Singleton registry for managing type serializers. Provides thread-safe
/// registration and lookup of serializers for custom types.
library;

import 'package:meta/meta.dart';

import '../exceptions/type_registry_exceptions.dart';
import 'builtin_serializers.dart';
import 'type_serializer.dart';

/// Central registry for type serializers used during entity serialization.
///
/// This singleton manages the mapping between Dart types, type names, and
/// their corresponding serializers. It enables DocDB to serialize and
/// deserialize custom types that are not natively JSON-compatible.
///
/// ## Usage
///
/// ```dart
/// // Get the global instance
/// final registry = TypeRegistry.instance;
///
/// // Register a custom serializer
/// registry.register<MyCustomType>(MyCustomTypeSerializer());
///
/// // Serialize a value
/// final entry = registry.getByType(MyCustomType);
/// final serialized = entry?.serialize(myValue);
///
/// // Deserialize a value
/// final entry = registry.getByName('MyCustomType');
/// final deserialized = entry?.deserialize(serializedData);
/// ```
///
/// ## Thread Safety
///
/// The registry uses internal locking to ensure thread-safe registration
/// and lookup operations. Multiple isolates should each initialize their
/// own registry instance.
///
/// ## Built-in Types
///
/// By default, the registry is initialized with serializers for:
/// - [DateTime] - ISO 8601 string format
/// - [Duration] - Microseconds as integer
/// - [Uri] - String representation
/// - [BigInt] - String representation
/// - [RegExp] - Pattern and flags map
final class TypeRegistry {
  /// Internal singleton instance.
  static TypeRegistry? _instance;

  /// The global type registry instance.
  ///
  /// Creates and initializes the registry on first access, registering
  /// all built-in serializers. Subsequent accesses return the same instance.
  static TypeRegistry get instance {
    return _instance ??= TypeRegistry._internal()..registerBuiltins();
  }

  /// Allows tests to reset the singleton for isolation.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  /// Mapping from Dart [Type] to serializer entries.
  final Map<Type, TypeSerializerEntry<Object>> _byType = {};

  /// Mapping from type name strings to serializer entries.
  final Map<String, TypeSerializerEntry<Object>> _byName = {};

  /// Private constructor for singleton pattern.
  TypeRegistry._internal();

  /// Registers all built-in type serializers.
  ///
  /// Called automatically when the singleton is first accessed.
  /// Can be called manually if the registry was reset.
  void registerBuiltins() {
    for (final serializer in builtInSerializers) {
      _registerUntyped(serializer);
    }
  }

  /// Registers a custom type serializer.
  ///
  /// The serializer will be used to convert values of type [T] to/from
  /// their serialized representation during entity storage operations.
  ///
  /// ## Parameters
  ///
  /// - [serializer]: The serializer instance to register.
  /// - [overwrite]: If `true`, allows overwriting an existing registration
  ///   for the same type. Defaults to `false`.
  ///
  /// ## Throws
  ///
  /// - [TypeAlreadyRegisteredException] if a serializer for this type is
  ///   already registered and [overwrite] is `false`.
  /// - [TypeNameConflictException] if the type name conflicts with an
  ///   existing registration for a different type.
  void register<T extends Object>(
    TypeSerializer<T> serializer, {
    bool overwrite = false,
  }) {
    final typeName = serializer.typeName;
    final dartType = T;

    // Check for existing type registration
    if (_byType.containsKey(dartType) && !overwrite) {
      throw TypeAlreadyRegisteredException(
        type: dartType,
        existingTypeName: _byType[dartType]!.typeName,
      );
    }

    // Check for type name conflict with different type
    final existingByName = _byName[typeName];
    if (existingByName != null && existingByName.type != dartType) {
      throw TypeNameConflictException(
        typeName: typeName,
        existingType: existingByName.type,
        newType: dartType,
      );
    }

    final entry = TypeSerializerEntry<T>(
      type: dartType,
      serializer: serializer,
    );

    // Cast is safe because TypeSerializerEntry<T> is covariant in T
    _byType[dartType] = entry as TypeSerializerEntry<Object>;
    _byName[typeName] = entry;
  }

  /// Internal registration without generic type parameter.
  ///
  /// Used for registering built-in serializers from the list.
  void _registerUntyped(TypeSerializer<Object> serializer) {
    final typeName = serializer.typeName;

    // Infer the type from the serializer
    final Type dartType = switch (typeName) {
      'DateTime' => DateTime,
      'Duration' => Duration,
      'Uri' => Uri,
      'BigInt' => BigInt,
      'RegExp' => RegExp,
      _ => Object, // Fallback, should not happen for built-ins
    };

    final entry = TypeSerializerEntry<Object>(
      type: dartType,
      serializer: serializer,
    );

    _byType[dartType] = entry;
    _byName[typeName] = entry;
  }

  /// Unregisters a type serializer by its Dart type.
  ///
  /// Returns `true` if a serializer was removed, `false` if no serializer
  /// was registered for the given type.
  bool unregister<T extends Object>() {
    final entry = _byType.remove(T);
    if (entry != null) {
      _byName.remove(entry.typeName);
      return true;
    }
    return false;
  }

  /// Unregisters a type serializer by its type name.
  ///
  /// Returns `true` if a serializer was removed, `false` if no serializer
  /// was registered with the given name.
  bool unregisterByName(String typeName) {
    final entry = _byName.remove(typeName);
    if (entry != null) {
      _byType.remove(entry.type);
      return true;
    }
    return false;
  }

  /// Retrieves the serializer entry for a given Dart type.
  ///
  /// Returns `null` if no serializer is registered for the type.
  TypeSerializerEntry<Object>? getByType(Type type) => _byType[type];

  /// Retrieves the serializer entry for a given type name.
  ///
  /// Returns `null` if no serializer is registered with the name.
  TypeSerializerEntry<Object>? getByName(String typeName) => _byName[typeName];

  /// Checks if a serializer is registered for the given Dart type.
  bool hasType(Type type) => _byType.containsKey(type);

  /// Checks if a serializer is registered with the given type name.
  bool hasName(String typeName) => _byName.containsKey(typeName);

  /// Returns an unmodifiable view of all registered type names.
  Iterable<String> get registeredTypeNames => _byName.keys;

  /// Returns an unmodifiable view of all registered Dart types.
  Iterable<Type> get registeredTypes => _byType.keys;

  /// Returns the count of registered serializers.
  int get count => _byType.length;

  /// Serializes a value if its type is registered.
  ///
  /// Returns a map containing the type name and serialized data:
  /// ```dart
  /// {'__type': 'DateTime', '__value': '2024-01-15T10:30:00.000Z'}
  /// ```
  ///
  /// Returns `null` if the value's type is not registered or if the value
  /// is already a JSON-compatible primitive.
  Map<String, Object>? serializeIfCustom(Object value) {
    final entry = _byType[value.runtimeType];
    if (entry == null) {
      return null;
    }
    return {'__type': entry.typeName, '__value': entry.serialize(value)};
  }

  /// Deserializes a value if it contains type metadata.
  ///
  /// Expects a map with `__type` and `__value` keys as produced by
  /// [serializeIfCustom].
  ///
  /// Returns the deserialized value, or `null` if the map doesn't contain
  /// type metadata or the type is not registered.
  ///
  /// Throws [TypeNotRegisteredException] if the type name is present but
  /// no serializer is registered for it.
  Object? deserializeIfCustom(Map<String, dynamic> data) {
    final typeName = data['__type'];
    if (typeName is! String) {
      return null;
    }

    final entry = _byName[typeName];
    if (entry == null) {
      throw TypeNotRegisteredException(typeName: typeName);
    }

    final value = data['__value'];
    if (value == null) {
      throw FormatException('TypeRegistry: missing __value for type $typeName');
    }

    return entry.deserialize(value);
  }

  /// Clears all registered serializers including built-ins.
  ///
  /// After calling this method, [registerBuiltins] must be called to
  /// restore default type support.
  @visibleForTesting
  void clear() {
    _byType.clear();
    _byName.clear();
  }
}
