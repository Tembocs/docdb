/// Type Registry Module Tests.
///
/// Comprehensive tests for TypeRegistry, TypeSerializer interface,
/// built-in serializers, and custom type serialization.
library;

import 'package:test/test.dart';

import 'package:entidb/src/exceptions/type_registry_exceptions.dart';
import 'package:entidb/src/type_registry/builtin_serializers.dart';
import 'package:entidb/src/type_registry/type_registry.dart';
import 'package:entidb/src/type_registry/type_serializer.dart';

// =============================================================================
// Custom Test Serializers
// =============================================================================

/// A custom type for testing serialization.
class Point {
  final double x;
  final double y;

  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Point && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point($x, $y)';
}

/// Serializer for Point type.
class PointSerializer implements TypeSerializer<Point> {
  const PointSerializer();

  @override
  String get typeName => 'Point';

  @override
  Object serialize(Point value) => {'x': value.x, 'y': value.y};

  @override
  Point deserialize(Object data) {
    if (data is Map<String, dynamic>) {
      return Point(
        (data['x'] as num).toDouble(),
        (data['y'] as num).toDouble(),
      );
    }
    throw FormatException(
      'PointSerializer: expected Map<String, dynamic>, got ${data.runtimeType}',
    );
  }
}

/// Another custom type for testing.
class Color {
  final int r;
  final int g;
  final int b;

  const Color(this.r, this.g, this.b);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Color && r == other.r && g == other.g && b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

/// Serializer for Color type.
class ColorSerializer implements TypeSerializer<Color> {
  const ColorSerializer();

  @override
  String get typeName => 'Color';

  @override
  Object serialize(Color value) => (value.r << 16) | (value.g << 8) | value.b;

  @override
  Color deserialize(Object data) {
    if (data is int) {
      return Color((data >> 16) & 0xFF, (data >> 8) & 0xFF, data & 0xFF);
    }
    throw FormatException(
      'ColorSerializer: expected int, got ${data.runtimeType}',
    );
  }
}

/// Alternative serializer for Point with a different name.
class PointSerializerV2 implements TypeSerializer<Point> {
  const PointSerializerV2();

  @override
  String get typeName => 'PointV2';

  @override
  Object serialize(Point value) => [value.x, value.y];

  @override
  Point deserialize(Object data) {
    if (data is List) {
      return Point((data[0] as num).toDouble(), (data[1] as num).toDouble());
    }
    throw FormatException(
      'PointSerializerV2: expected List, got ${data.runtimeType}',
    );
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  group('TypeRegistry', () {
    late TypeRegistry registry;

    setUp(() {
      // Reset singleton for test isolation
      TypeRegistry.resetForTesting();
      registry = TypeRegistry.instance;
    });

    tearDown(() {
      TypeRegistry.resetForTesting();
    });

    group('Singleton Pattern', () {
      test('should return same instance', () {
        final instance1 = TypeRegistry.instance;
        final instance2 = TypeRegistry.instance;
        expect(identical(instance1, instance2), isTrue);
      });

      test('should reset for testing', () {
        final before = TypeRegistry.instance;
        TypeRegistry.resetForTesting();
        final after = TypeRegistry.instance;
        expect(identical(before, after), isFalse);
      });
    });

    group('Built-in Serializers', () {
      test('should register all built-in serializers on initialization', () {
        expect(registry.hasType(DateTime), isTrue);
        expect(registry.hasType(Duration), isTrue);
        expect(registry.hasType(Uri), isTrue);
        expect(registry.hasType(BigInt), isTrue);
        expect(registry.hasType(RegExp), isTrue);
      });

      test('should have correct type names for built-ins', () {
        expect(registry.hasName('DateTime'), isTrue);
        expect(registry.hasName('Duration'), isTrue);
        expect(registry.hasName('Uri'), isTrue);
        expect(registry.hasName('BigInt'), isTrue);
        expect(registry.hasName('RegExp'), isTrue);
      });

      test('should count built-in serializers', () {
        expect(registry.count, 5);
      });

      test('should list registered type names', () {
        final names = registry.registeredTypeNames.toList();
        expect(
          names,
          containsAll(['DateTime', 'Duration', 'Uri', 'BigInt', 'RegExp']),
        );
      });

      test('should list registered types', () {
        final types = registry.registeredTypes.toList();
        expect(types, containsAll([DateTime, Duration, Uri, BigInt, RegExp]));
      });
    });

    group('Custom Type Registration', () {
      test('should register a custom serializer', () {
        registry.register<Point>(const PointSerializer());

        expect(registry.hasType(Point), isTrue);
        expect(registry.hasName('Point'), isTrue);
        expect(registry.count, 6);
      });

      test('should retrieve serializer by type', () {
        registry.register<Point>(const PointSerializer());

        final entry = registry.getByType(Point);
        expect(entry, isNotNull);
        expect(entry!.typeName, 'Point');
      });

      test('should retrieve serializer by name', () {
        registry.register<Point>(const PointSerializer());

        final entry = registry.getByName('Point');
        expect(entry, isNotNull);
        expect(entry!.type, Point);
      });

      test('should throw on duplicate registration', () {
        registry.register<Point>(const PointSerializer());

        expect(
          () => registry.register<Point>(const PointSerializer()),
          throwsA(isA<TypeAlreadyRegisteredException>()),
        );
      });

      test('should allow overwriting with overwrite: true', () {
        registry.register<Point>(const PointSerializer());
        registry.register<Point>(const PointSerializerV2(), overwrite: true);

        final entry = registry.getByType(Point);
        expect(entry!.typeName, 'PointV2');
      });

      test('should throw on type name conflict with different type', () {
        registry.register<Point>(const PointSerializer());

        // Create a serializer for Color but with name 'Point'
        final conflictingSerializer = _ConflictingSerializer();

        expect(
          () => registry.register<Color>(conflictingSerializer),
          throwsA(isA<TypeNameConflictException>()),
        );
      });

      test('should register multiple custom types', () {
        registry.register<Point>(const PointSerializer());
        registry.register<Color>(const ColorSerializer());

        expect(registry.hasType(Point), isTrue);
        expect(registry.hasType(Color), isTrue);
        expect(registry.count, 7);
      });
    });

    group('Unregistration', () {
      test('should unregister by type', () {
        registry.register<Point>(const PointSerializer());
        expect(registry.hasType(Point), isTrue);

        final result = registry.unregister<Point>();
        expect(result, isTrue);
        expect(registry.hasType(Point), isFalse);
        expect(registry.hasName('Point'), isFalse);
      });

      test('should return false when unregistering non-existent type', () {
        final result = registry.unregister<Point>();
        expect(result, isFalse);
      });

      test('should unregister by name', () {
        registry.register<Point>(const PointSerializer());

        final result = registry.unregisterByName('Point');
        expect(result, isTrue);
        expect(registry.hasType(Point), isFalse);
        expect(registry.hasName('Point'), isFalse);
      });

      test('should return false when unregistering non-existent name', () {
        final result = registry.unregisterByName('NonExistent');
        expect(result, isFalse);
      });
    });

    group('Serialization', () {
      test('should serialize custom type with serializeIfCustom', () {
        registry.register<Point>(const PointSerializer());

        const point = Point(1.5, 2.5);
        final result = registry.serializeIfCustom(point);

        expect(result, isNotNull);
        expect(result!['__type'], 'Point');
        expect(result['__value'], {'x': 1.5, 'y': 2.5});
      });

      test('should return null for unregistered type', () {
        final result = registry.serializeIfCustom(const Point(1.0, 2.0));
        expect(result, isNull);
      });

      test('should deserialize custom type with deserializeIfCustom', () {
        registry.register<Point>(const PointSerializer());

        final data = {
          '__type': 'Point',
          '__value': {'x': 3.0, 'y': 4.0},
        };

        final result = registry.deserializeIfCustom(data);
        expect(result, isA<Point>());
        expect(result, const Point(3.0, 4.0));
      });

      test('should return null for data without type metadata', () {
        final result = registry.deserializeIfCustom({'x': 1, 'y': 2});
        expect(result, isNull);
      });

      test('should throw for unregistered type name in deserialization', () {
        final data = {'__type': 'UnknownType', '__value': 'some data'};

        expect(
          () => registry.deserializeIfCustom(data),
          throwsA(isA<TypeNotRegisteredException>()),
        );
      });

      test('should throw for missing __value in deserialization', () {
        registry.register<Point>(const PointSerializer());

        final data = {'__type': 'Point'};

        expect(
          () => registry.deserializeIfCustom(data),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('Clear', () {
      test('should clear all registrations', () {
        registry.register<Point>(const PointSerializer());
        registry.register<Color>(const ColorSerializer());

        registry.clear();

        expect(registry.count, 0);
        expect(registry.hasType(DateTime), isFalse);
        expect(registry.hasType(Point), isFalse);
      });

      test('should allow re-registration after clear', () {
        registry.clear();
        registry.registerBuiltins();

        expect(registry.hasType(DateTime), isTrue);
        expect(registry.count, 5);
      });
    });
  });

  group('Built-in Serializers', () {
    group('DateTimeSerializer', () {
      const serializer = DateTimeSerializer();

      test('should have correct type name', () {
        expect(serializer.typeName, 'DateTime');
      });

      test('should serialize DateTime to ISO 8601 string', () {
        final dt = DateTime.utc(2024, 1, 15, 10, 30, 45, 123);
        final result = serializer.serialize(dt);

        expect(result, isA<String>());
        expect(result, '2024-01-15T10:30:45.123Z');
      });

      test('should convert local time to UTC on serialization', () {
        final local = DateTime(2024, 1, 15, 10, 30);
        final result = serializer.serialize(local) as String;

        expect(result.endsWith('Z'), isTrue);
      });

      test('should deserialize ISO 8601 string to DateTime', () {
        final result = serializer.deserialize('2024-01-15T10:30:45.123Z');

        expect(result, isA<DateTime>());
        expect(result.year, 2024);
        expect(result.month, 1);
        expect(result.day, 15);
        expect(result.hour, 10);
        expect(result.minute, 30);
        expect(result.second, 45);
        expect(result.millisecond, 123);
      });

      test('should throw on invalid format', () {
        expect(
          () => serializer.deserialize(12345),
          throwsA(isA<FormatException>()),
        );
      });

      test('should roundtrip DateTime', () {
        final original = DateTime.utc(2024, 6, 15, 14, 30, 0);
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });
    });

    group('DurationSerializer', () {
      const serializer = DurationSerializer();

      test('should have correct type name', () {
        expect(serializer.typeName, 'Duration');
      });

      test('should serialize Duration to microseconds', () {
        const duration = Duration(hours: 1, minutes: 30, seconds: 45);
        final result = serializer.serialize(duration);

        expect(result, isA<int>());
        expect(result, duration.inMicroseconds);
      });

      test('should deserialize microseconds to Duration', () {
        const microseconds = 5400000000; // 1.5 hours
        final result = serializer.deserialize(microseconds);

        expect(result, isA<Duration>());
        expect(result.inMinutes, 90);
      });

      test('should throw on invalid format', () {
        expect(
          () => serializer.deserialize('not an int'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should roundtrip Duration', () {
        const original = Duration(days: 1, hours: 2, minutes: 3, seconds: 4);
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });

      test('should handle negative durations', () {
        const original = Duration(seconds: -30);
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });
    });

    group('UriSerializer', () {
      const serializer = UriSerializer();

      test('should have correct type name', () {
        expect(serializer.typeName, 'Uri');
      });

      test('should serialize Uri to string', () {
        final uri = Uri.parse('https://example.com/path?query=value');
        final result = serializer.serialize(uri);

        expect(result, isA<String>());
        expect(result, 'https://example.com/path?query=value');
      });

      test('should deserialize string to Uri', () {
        final result = serializer.deserialize('https://dart.dev');

        expect(result, isA<Uri>());
        expect(result.host, 'dart.dev');
      });

      test('should throw on invalid format', () {
        expect(
          () => serializer.deserialize(12345),
          throwsA(isA<FormatException>()),
        );
      });

      test('should roundtrip Uri', () {
        final original = Uri.parse(
          'https://example.com:8080/api?key=value#fragment',
        );
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });

      test('should handle file URIs', () {
        final original = Uri.file('/path/to/file.txt');
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized.path, original.path);
      });
    });

    group('BigIntSerializer', () {
      const serializer = BigIntSerializer();

      test('should have correct type name', () {
        expect(serializer.typeName, 'BigInt');
      });

      test('should serialize BigInt to string', () {
        final bigInt = BigInt.parse('123456789012345678901234567890');
        final result = serializer.serialize(bigInt);

        expect(result, isA<String>());
        expect(result, '123456789012345678901234567890');
      });

      test('should deserialize string to BigInt', () {
        final result = serializer.deserialize('999999999999999999999');

        expect(result, isA<BigInt>());
        expect(result, BigInt.parse('999999999999999999999'));
      });

      test('should throw on invalid format', () {
        expect(
          () => serializer.deserialize(12345),
          throwsA(isA<FormatException>()),
        );
      });

      test('should roundtrip BigInt', () {
        final original = BigInt.from(2).pow(256);
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });

      test('should handle negative BigInt', () {
        final original = -BigInt.parse('123456789012345678901234567890');
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized, original);
      });
    });

    group('RegExpSerializer', () {
      const serializer = RegExpSerializer();

      test('should have correct type name', () {
        expect(serializer.typeName, 'RegExp');
      });

      test('should serialize RegExp with all flags', () {
        final regex = RegExp(
          r'\d+',
          multiLine: true,
          caseSensitive: false,
          unicode: true,
          dotAll: true,
        );
        final result = serializer.serialize(regex) as Map<String, dynamic>;

        expect(result['pattern'], r'\d+');
        expect(result['multiLine'], true);
        expect(result['caseSensitive'], false);
        expect(result['unicode'], true);
        expect(result['dotAll'], true);
      });

      test('should deserialize map to RegExp', () {
        final data = {
          'pattern': r'[a-z]+',
          'multiLine': false,
          'caseSensitive': true,
          'unicode': false,
          'dotAll': false,
        };

        final result = serializer.deserialize(data);
        expect(result, isA<RegExp>());
        expect(result.pattern, r'[a-z]+');
        expect(result.isMultiLine, false);
        expect(result.isCaseSensitive, true);
      });

      test('should throw on invalid format', () {
        expect(
          () => serializer.deserialize('not a map'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should roundtrip RegExp', () {
        final original = RegExp(r'^test$', multiLine: true);
        final serialized = serializer.serialize(original);
        final deserialized = serializer.deserialize(serialized);

        expect(deserialized.pattern, original.pattern);
        expect(deserialized.isMultiLine, original.isMultiLine);
        expect(deserialized.isCaseSensitive, original.isCaseSensitive);
      });

      test('should use defaults for missing flags', () {
        final data = {'pattern': r'\w+'};
        final result = serializer.deserialize(data);

        expect(result.isMultiLine, false);
        expect(result.isCaseSensitive, true);
        expect(result.isUnicode, false);
        expect(result.isDotAll, false);
      });
    });
  });

  group('TypeSerializerEntry', () {
    test('should expose type and typeName', () {
      const serializer = PointSerializer();
      final entry = TypeSerializerEntry<Point>(
        type: Point,
        serializer: serializer,
      );

      expect(entry.type, Point);
      expect(entry.typeName, 'Point');
    });

    test('should serialize using entry', () {
      const serializer = PointSerializer();
      final entry = TypeSerializerEntry<Point>(
        type: Point,
        serializer: serializer,
      );

      final result = entry.serialize(const Point(1.0, 2.0));
      expect(result, {'x': 1.0, 'y': 2.0});
    });

    test('should deserialize using entry', () {
      const serializer = PointSerializer();
      final entry = TypeSerializerEntry<Point>(
        type: Point,
        serializer: serializer,
      );

      final result = entry.deserialize({'x': 3.0, 'y': 4.0});
      expect(result, const Point(3.0, 4.0));
    });
  });

  group('Built-in Serializers List', () {
    test('should contain 5 built-in serializers', () {
      expect(builtInSerializers.length, 5);
    });

    test('should have unique type names', () {
      final names = builtInSerializers.map((s) => s.typeName).toSet();
      expect(names.length, 5);
    });
  });

  group('Integration Tests', () {
    setUp(() {
      TypeRegistry.resetForTesting();
    });

    tearDown(() {
      TypeRegistry.resetForTesting();
    });

    test('should handle complex nested serialization', () {
      final registry = TypeRegistry.instance;
      registry.register<Point>(const PointSerializer());

      const point = Point(10.5, 20.5);
      final serialized = registry.serializeIfCustom(point);
      final deserialized = registry.deserializeIfCustom(serialized!);

      expect(deserialized, point);
    });

    test('should work with multiple custom types', () {
      final registry = TypeRegistry.instance;
      registry.register<Point>(const PointSerializer());
      registry.register<Color>(const ColorSerializer());

      const point = Point(1.0, 2.0);
      const color = Color(255, 128, 64);

      final pointSerialized = registry.serializeIfCustom(point);
      final colorSerialized = registry.serializeIfCustom(color);

      final pointDeserialized = registry.deserializeIfCustom(pointSerialized!);
      final colorDeserialized = registry.deserializeIfCustom(colorSerialized!);

      expect(pointDeserialized, point);
      expect(colorDeserialized, color);
    });

    test('should handle serialization of built-in types', () {
      final registry = TypeRegistry.instance;

      final now = DateTime.now();
      final serialized = registry.serializeIfCustom(now);
      expect(serialized, isNotNull);

      final deserialized = registry.deserializeIfCustom(serialized!);
      expect(deserialized, isA<DateTime>());
    });
  });
}

/// Helper serializer that causes a name conflict.
class _ConflictingSerializer implements TypeSerializer<Color> {
  @override
  String get typeName => 'Point'; // Conflicts with PointSerializer

  @override
  Object serialize(Color value) => value.r;

  @override
  Color deserialize(Object data) => Color(data as int, 0, 0);
}
