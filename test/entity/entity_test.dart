/// Entity Module Tests.
///
/// Comprehensive tests for the Entity interface and various entity
/// implementation patterns including nested objects, optional fields,
/// complex types, and serialization edge cases.
library;

import 'package:test/test.dart';

import 'package:entidb/src/entity/entity.dart';

// =============================================================================
// Test Entity Implementations
// =============================================================================

/// Simple entity with basic fields.
class SimpleEntity implements Entity {
  @override
  final String? id;
  final String name;
  final int count;

  const SimpleEntity({this.id, required this.name, required this.count});

  @override
  Map<String, dynamic> toMap() => {'name': name, 'count': count};

  factory SimpleEntity.fromMap(String id, Map<String, dynamic> map) {
    return SimpleEntity(
      id: id,
      name: map['name'] as String,
      count: map['count'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SimpleEntity &&
          id == other.id &&
          name == other.name &&
          count == other.count;

  @override
  int get hashCode => Object.hash(id, name, count);
}

/// Entity with optional/nullable fields.
class OptionalFieldsEntity implements Entity {
  @override
  final String? id;
  final String requiredField;
  final String? optionalString;
  final int? optionalInt;
  final List<String>? optionalList;

  const OptionalFieldsEntity({
    this.id,
    required this.requiredField,
    this.optionalString,
    this.optionalInt,
    this.optionalList,
  });

  @override
  Map<String, dynamic> toMap() => {
    'requiredField': requiredField,
    if (optionalString != null) 'optionalString': optionalString,
    if (optionalInt != null) 'optionalInt': optionalInt,
    if (optionalList != null) 'optionalList': optionalList,
  };

  factory OptionalFieldsEntity.fromMap(String id, Map<String, dynamic> map) {
    return OptionalFieldsEntity(
      id: id,
      requiredField: map['requiredField'] as String,
      optionalString: map['optionalString'] as String?,
      optionalInt: map['optionalInt'] as int?,
      optionalList: (map['optionalList'] as List?)?.cast<String>(),
    );
  }
}

/// Entity with all supported primitive types.
class AllTypesEntity implements Entity {
  @override
  final String? id;
  final String stringField;
  final int intField;
  final double doubleField;
  final bool boolField;
  final num numField;

  const AllTypesEntity({
    this.id,
    required this.stringField,
    required this.intField,
    required this.doubleField,
    required this.boolField,
    required this.numField,
  });

  @override
  Map<String, dynamic> toMap() => {
    'stringField': stringField,
    'intField': intField,
    'doubleField': doubleField,
    'boolField': boolField,
    'numField': numField,
  };

  factory AllTypesEntity.fromMap(String id, Map<String, dynamic> map) {
    return AllTypesEntity(
      id: id,
      stringField: map['stringField'] as String,
      intField: map['intField'] as int,
      doubleField: (map['doubleField'] as num).toDouble(),
      boolField: map['boolField'] as bool,
      numField: map['numField'] as num,
    );
  }
}

/// Entity with collection fields.
class CollectionFieldsEntity implements Entity {
  @override
  final String? id;
  final List<String> stringList;
  final List<int> intList;
  final Map<String, dynamic> metadata;
  final Set<String> tags;

  const CollectionFieldsEntity({
    this.id,
    required this.stringList,
    required this.intList,
    required this.metadata,
    required this.tags,
  });

  @override
  Map<String, dynamic> toMap() => {
    'stringList': stringList,
    'intList': intList,
    'metadata': metadata,
    // Sets need to be converted to lists for JSON
    'tags': tags.toList(),
  };

  factory CollectionFieldsEntity.fromMap(String id, Map<String, dynamic> map) {
    return CollectionFieldsEntity(
      id: id,
      stringList: (map['stringList'] as List).cast<String>(),
      intList: (map['intList'] as List).cast<int>(),
      metadata: Map<String, dynamic>.from(map['metadata'] as Map),
      tags: Set<String>.from(map['tags'] as List),
    );
  }
}

/// Nested value object (not an Entity itself).
class Address {
  final String street;
  final String city;
  final String country;

  const Address({
    required this.street,
    required this.city,
    required this.country,
  });

  Map<String, dynamic> toMap() => {
    'street': street,
    'city': city,
    'country': country,
  };

  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      street: map['street'] as String,
      city: map['city'] as String,
      country: map['country'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Address &&
          street == other.street &&
          city == other.city &&
          country == other.country;

  @override
  int get hashCode => Object.hash(street, city, country);
}

/// Entity with nested objects.
class NestedObjectEntity implements Entity {
  @override
  final String? id;
  final String name;
  final Address address;
  final List<Address> previousAddresses;

  const NestedObjectEntity({
    this.id,
    required this.name,
    required this.address,
    this.previousAddresses = const [],
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'address': address.toMap(),
    'previousAddresses': previousAddresses.map((a) => a.toMap()).toList(),
  };

  factory NestedObjectEntity.fromMap(String id, Map<String, dynamic> map) {
    return NestedObjectEntity(
      id: id,
      name: map['name'] as String,
      address: Address.fromMap(map['address'] as Map<String, dynamic>),
      previousAddresses:
          (map['previousAddresses'] as List?)
              ?.map((a) => Address.fromMap(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Entity with DateTime fields.
class DateTimeEntity implements Entity {
  @override
  final String? id;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DateTimeEntity({this.id, required this.createdAt, this.updatedAt});

  @override
  Map<String, dynamic> toMap() => {
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  factory DateTimeEntity.fromMap(String id, Map<String, dynamic> map) {
    return DateTimeEntity(
      id: id,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
    );
  }
}

/// Entity with enum fields.
enum Status { draft, published, archived }

class EnumEntity implements Entity {
  @override
  final String? id;
  final Status status;
  final List<Status> statusHistory;

  const EnumEntity({
    this.id,
    required this.status,
    this.statusHistory = const [],
  });

  @override
  Map<String, dynamic> toMap() => {
    'status': status.name,
    'statusHistory': statusHistory.map((s) => s.name).toList(),
  };

  factory EnumEntity.fromMap(String id, Map<String, dynamic> map) {
    return EnumEntity(
      id: id,
      status: Status.values.byName(map['status'] as String),
      statusHistory:
          (map['statusHistory'] as List?)
              ?.map((s) => Status.values.byName(s as String))
              .toList() ??
          [],
    );
  }
}

/// Entity with deeply nested structure.
class DeeplyNestedEntity implements Entity {
  @override
  final String? id;
  final Map<String, List<Map<String, dynamic>>> complexData;

  const DeeplyNestedEntity({this.id, required this.complexData});

  @override
  Map<String, dynamic> toMap() => {'complexData': complexData};

  factory DeeplyNestedEntity.fromMap(String id, Map<String, dynamic> map) {
    final rawData = map['complexData'] as Map<String, dynamic>;
    final complexData = <String, List<Map<String, dynamic>>>{};
    for (final entry in rawData.entries) {
      complexData[entry.key] = (entry.value as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
    return DeeplyNestedEntity(id: id, complexData: complexData);
  }
}

/// Entity using default values.
class DefaultValuesEntity implements Entity {
  @override
  final String? id;
  final String name;
  final int priority;
  final bool isActive;
  final List<String> tags;

  const DefaultValuesEntity({
    this.id,
    required this.name,
    this.priority = 0,
    this.isActive = true,
    this.tags = const [],
  });

  @override
  Map<String, dynamic> toMap() => {
    'name': name,
    'priority': priority,
    'isActive': isActive,
    'tags': tags,
  };

  factory DefaultValuesEntity.fromMap(String id, Map<String, dynamic> map) {
    return DefaultValuesEntity(
      id: id,
      name: map['name'] as String,
      priority: map['priority'] as int? ?? 0,
      isActive: map['isActive'] as bool? ?? true,
      tags: (map['tags'] as List?)?.cast<String>() ?? [],
    );
  }
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  group('Entity Interface', () {
    group('SimpleEntity', () {
      test('should have null id for new entities', () {
        const entity = SimpleEntity(name: 'Test', count: 5);
        expect(entity.id, isNull);
      });

      test('should have non-null id when specified', () {
        const entity = SimpleEntity(id: 'test-1', name: 'Test', count: 5);
        expect(entity.id, 'test-1');
      });

      test('should serialize to map correctly', () {
        const entity = SimpleEntity(id: 'test-1', name: 'Test', count: 5);
        final map = entity.toMap();

        expect(map, {'name': 'Test', 'count': 5});
        expect(map.containsKey('id'), isFalse);
      });

      test('should deserialize from map correctly', () {
        final entity = SimpleEntity.fromMap('test-1', {
          'name': 'Test',
          'count': 5,
        });

        expect(entity.id, 'test-1');
        expect(entity.name, 'Test');
        expect(entity.count, 5);
      });

      test('should roundtrip serialize/deserialize', () {
        const original = SimpleEntity(id: 'test-1', name: 'Test', count: 5);
        final map = original.toMap();
        final restored = SimpleEntity.fromMap('test-1', map);

        expect(restored, equals(original));
      });
    });

    group('OptionalFieldsEntity', () {
      test('should serialize with all fields present', () {
        const entity = OptionalFieldsEntity(
          id: 'opt-1',
          requiredField: 'required',
          optionalString: 'optional',
          optionalInt: 42,
          optionalList: ['a', 'b'],
        );

        final map = entity.toMap();
        expect(map['requiredField'], 'required');
        expect(map['optionalString'], 'optional');
        expect(map['optionalInt'], 42);
        expect(map['optionalList'], ['a', 'b']);
      });

      test('should omit null fields in serialization', () {
        const entity = OptionalFieldsEntity(
          id: 'opt-1',
          requiredField: 'required',
        );

        final map = entity.toMap();
        expect(map.containsKey('requiredField'), isTrue);
        expect(map.containsKey('optionalString'), isFalse);
        expect(map.containsKey('optionalInt'), isFalse);
        expect(map.containsKey('optionalList'), isFalse);
      });

      test('should deserialize with missing optional fields', () {
        final entity = OptionalFieldsEntity.fromMap('opt-1', {
          'requiredField': 'required',
        });

        expect(entity.requiredField, 'required');
        expect(entity.optionalString, isNull);
        expect(entity.optionalInt, isNull);
        expect(entity.optionalList, isNull);
      });

      test('should deserialize with all fields present', () {
        final entity = OptionalFieldsEntity.fromMap('opt-1', {
          'requiredField': 'required',
          'optionalString': 'optional',
          'optionalInt': 42,
          'optionalList': ['a', 'b'],
        });

        expect(entity.optionalString, 'optional');
        expect(entity.optionalInt, 42);
        expect(entity.optionalList, ['a', 'b']);
      });
    });

    group('AllTypesEntity', () {
      test('should serialize all primitive types', () {
        const entity = AllTypesEntity(
          id: 'types-1',
          stringField: 'hello',
          intField: 42,
          doubleField: 3.14,
          boolField: true,
          numField: 100,
        );

        final map = entity.toMap();
        expect(map['stringField'], isA<String>());
        expect(map['intField'], isA<int>());
        expect(map['doubleField'], isA<double>());
        expect(map['boolField'], isA<bool>());
        expect(map['numField'], isA<num>());
      });

      test('should roundtrip all primitive types', () {
        const original = AllTypesEntity(
          stringField: 'hello',
          intField: 42,
          doubleField: 3.14159,
          boolField: false,
          numField: -100,
        );

        final map = original.toMap();
        final restored = AllTypesEntity.fromMap('test', map);

        expect(restored.stringField, original.stringField);
        expect(restored.intField, original.intField);
        expect(restored.doubleField, original.doubleField);
        expect(restored.boolField, original.boolField);
        expect(restored.numField, original.numField);
      });

      test('should handle edge case numbers', () {
        const entity = AllTypesEntity(
          stringField: '',
          intField: -9223372036854775808, // min int64
          doubleField: double.maxFinite,
          boolField: true,
          numField: 0,
        );

        final map = entity.toMap();
        final restored = AllTypesEntity.fromMap('test', map);

        expect(restored.intField, entity.intField);
        expect(restored.doubleField, entity.doubleField);
      });
    });

    group('CollectionFieldsEntity', () {
      test('should serialize collection fields', () {
        final entity = CollectionFieldsEntity(
          id: 'coll-1',
          stringList: ['a', 'b', 'c'],
          intList: [1, 2, 3],
          metadata: {
            'key': 'value',
            'nested': {'deep': true},
          },
          tags: {'tag1', 'tag2'},
        );

        final map = entity.toMap();
        expect(map['stringList'], ['a', 'b', 'c']);
        expect(map['intList'], [1, 2, 3]);
        expect(map['metadata'], {
          'key': 'value',
          'nested': {'deep': true},
        });
        expect(map['tags'], containsAll(['tag1', 'tag2']));
      });

      test('should handle empty collections', () {
        final entity = CollectionFieldsEntity(
          stringList: [],
          intList: [],
          metadata: {},
          tags: {},
        );

        final map = entity.toMap();
        expect(map['stringList'], isEmpty);
        expect(map['intList'], isEmpty);
        expect(map['metadata'], isEmpty);
        expect(map['tags'], isEmpty);
      });

      test('should roundtrip collection fields', () {
        final original = CollectionFieldsEntity(
          stringList: ['x', 'y'],
          intList: [10, 20],
          metadata: {'count': 5},
          tags: {'important', 'urgent'},
        );

        final map = original.toMap();
        final restored = CollectionFieldsEntity.fromMap('test', map);

        expect(restored.stringList, original.stringList);
        expect(restored.intList, original.intList);
        expect(restored.metadata, original.metadata);
        expect(restored.tags, original.tags);
      });
    });

    group('NestedObjectEntity', () {
      test('should serialize nested objects', () {
        const entity = NestedObjectEntity(
          id: 'nested-1',
          name: 'John Doe',
          address: Address(
            street: '123 Main St',
            city: 'Springfield',
            country: 'USA',
          ),
        );

        final map = entity.toMap();
        expect(map['name'], 'John Doe');
        expect(map['address'], isA<Map<String, dynamic>>());
        expect(map['address']['street'], '123 Main St');
        expect(map['address']['city'], 'Springfield');
      });

      test('should serialize list of nested objects', () {
        const entity = NestedObjectEntity(
          name: 'Jane Doe',
          address: Address(street: 'New St', city: 'Boston', country: 'USA'),
          previousAddresses: [
            Address(street: 'Old St 1', city: 'NYC', country: 'USA'),
            Address(street: 'Old St 2', city: 'LA', country: 'USA'),
          ],
        );

        final map = entity.toMap();
        expect(map['previousAddresses'], isA<List>());
        expect(map['previousAddresses'].length, 2);
        expect(map['previousAddresses'][0]['city'], 'NYC');
      });

      test('should roundtrip nested objects', () {
        const original = NestedObjectEntity(
          name: 'Test User',
          address: Address(street: 'Test St', city: 'Test City', country: 'TC'),
          previousAddresses: [
            Address(street: 'Prev St', city: 'Prev City', country: 'PC'),
          ],
        );

        final map = original.toMap();
        final restored = NestedObjectEntity.fromMap('test', map);

        expect(restored.name, original.name);
        expect(restored.address, original.address);
        expect(restored.previousAddresses.length, 1);
        expect(restored.previousAddresses[0], original.previousAddresses[0]);
      });
    });

    group('DateTimeEntity', () {
      test('should serialize DateTime to ISO 8601', () {
        final entity = DateTimeEntity(
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 0),
        );

        final map = entity.toMap();
        expect(map['createdAt'], '2024-01-15T10:30:00.000Z');
      });

      test('should handle optional DateTime', () {
        final entity = DateTimeEntity(
          createdAt: DateTime.utc(2024, 1, 15),
          updatedAt: DateTime.utc(2024, 6, 20),
        );

        final map = entity.toMap();
        expect(map.containsKey('updatedAt'), isTrue);

        final entityWithoutUpdate = DateTimeEntity(
          createdAt: DateTime.utc(2024, 1, 15),
        );
        final mapWithoutUpdate = entityWithoutUpdate.toMap();
        expect(mapWithoutUpdate.containsKey('updatedAt'), isFalse);
      });

      test('should roundtrip DateTime fields', () {
        final original = DateTimeEntity(
          createdAt: DateTime.utc(2024, 1, 15, 10, 30, 45, 123),
          updatedAt: DateTime.utc(2024, 6, 20, 14, 0, 0),
        );

        final map = original.toMap();
        final restored = DateTimeEntity.fromMap('test', map);

        expect(restored.createdAt, original.createdAt);
        expect(restored.updatedAt, original.updatedAt);
      });
    });

    group('EnumEntity', () {
      test('should serialize enums to string', () {
        const entity = EnumEntity(
          status: Status.published,
          statusHistory: [Status.draft, Status.published],
        );

        final map = entity.toMap();
        expect(map['status'], 'published');
        expect(map['statusHistory'], ['draft', 'published']);
      });

      test('should deserialize enums from string', () {
        final entity = EnumEntity.fromMap('test', {
          'status': 'archived',
          'statusHistory': ['draft', 'published', 'archived'],
        });

        expect(entity.status, Status.archived);
        expect(entity.statusHistory, [
          Status.draft,
          Status.published,
          Status.archived,
        ]);
      });

      test('should roundtrip enum fields', () {
        const original = EnumEntity(
          status: Status.draft,
          statusHistory: [Status.draft],
        );

        final map = original.toMap();
        final restored = EnumEntity.fromMap('test', map);

        expect(restored.status, original.status);
        expect(restored.statusHistory, original.statusHistory);
      });
    });

    group('DeeplyNestedEntity', () {
      test('should handle deeply nested structures', () {
        const entity = DeeplyNestedEntity(
          complexData: {
            'users': [
              {'name': 'Alice', 'age': 30},
              {'name': 'Bob', 'age': 25},
            ],
            'products': [
              {'sku': 'ABC', 'price': 99.99},
            ],
          },
        );

        final map = entity.toMap();
        expect(map['complexData']['users'], isA<List>());
        expect(map['complexData']['users'].length, 2);
        expect(map['complexData']['products'][0]['sku'], 'ABC');
      });

      test('should roundtrip deeply nested structures', () {
        const original = DeeplyNestedEntity(
          complexData: {
            'level1': [
              {'level2': 'value'},
            ],
          },
        );

        final map = original.toMap();
        final restored = DeeplyNestedEntity.fromMap('test', map);

        expect(restored.complexData['level1']![0]['level2'], 'value');
      });
    });

    group('DefaultValuesEntity', () {
      test('should use default values when not specified', () {
        const entity = DefaultValuesEntity(name: 'Test');

        expect(entity.priority, 0);
        expect(entity.isActive, true);
        expect(entity.tags, isEmpty);
      });

      test('should allow overriding default values', () {
        const entity = DefaultValuesEntity(
          name: 'Test',
          priority: 5,
          isActive: false,
          tags: ['custom'],
        );

        expect(entity.priority, 5);
        expect(entity.isActive, false);
        expect(entity.tags, ['custom']);
      });

      test('should deserialize with defaults for missing fields', () {
        final entity = DefaultValuesEntity.fromMap('test', {'name': 'Test'});

        expect(entity.priority, 0);
        expect(entity.isActive, true);
        expect(entity.tags, isEmpty);
      });
    });

    group('Edge Cases', () {
      test('should handle empty string fields', () {
        const entity = SimpleEntity(name: '', count: 0);
        final map = entity.toMap();
        final restored = SimpleEntity.fromMap('test', map);

        expect(restored.name, '');
        expect(restored.count, 0);
      });

      test('should handle special characters in strings', () {
        const entity = SimpleEntity(
          name: 'Test with "quotes" and \\backslashes\\ and\nnewlines',
          count: 1,
        );

        final map = entity.toMap();
        final restored = SimpleEntity.fromMap('test', map);

        expect(restored.name, entity.name);
      });

      test('should handle unicode characters', () {
        const entity = SimpleEntity(name: '日本語テスト 🚀 émojis ñ', count: 1);

        final map = entity.toMap();
        final restored = SimpleEntity.fromMap('test', map);

        expect(restored.name, entity.name);
      });

      test('should handle very long strings', () {
        final longString = 'x' * 100000;
        final entity = SimpleEntity(name: longString, count: 1);

        final map = entity.toMap();
        final restored = SimpleEntity.fromMap('test', map);

        expect(restored.name.length, 100000);
      });

      test('should handle large nested structures', () {
        final largeList = List.generate(1000, (i) => 'item_$i');
        final entity = CollectionFieldsEntity(
          stringList: largeList,
          intList: List.generate(1000, (i) => i),
          metadata: {'count': 1000},
          tags: Set.from(largeList.take(100)),
        );

        final map = entity.toMap();
        final restored = CollectionFieldsEntity.fromMap('test', map);

        expect(restored.stringList.length, 1000);
        expect(restored.intList.length, 1000);
        expect(restored.tags.length, 100);
      });
    });
  });
}
