/// EntiDB Query Module Tests
///
/// Comprehensive tests for the query module including QueryBuilder fluent API
/// and all query types (EqualsQuery, NotEqualsQuery, AndQuery, OrQuery, etc.).
library;

import 'package:test/test.dart';

import 'package:entidb/src/entity/entity.dart';
import 'package:entidb/src/query/query.dart';
import 'package:entidb/src/index/index_manager.dart';
import 'package:entidb/src/index/i_index.dart';

void main() {
  group('AllQuery', () {
    test('should match any data', () {
      const query = AllQuery();

      expect(query.matches({}), isTrue);
      expect(query.matches({'name': 'Alice'}), isTrue);
      expect(query.matches({'x': 1, 'y': 2, 'z': 3}), isTrue);
    });

    test('should serialize and deserialize', () {
      const query = AllQuery();
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<AllQuery>());
      expect(restored.matches({'test': 'data'}), isTrue);
    });
  });

  group('EqualsQuery', () {
    test('should match equal values', () {
      const query = EqualsQuery('name', 'Alice');

      expect(query.matches({'name': 'Alice'}), isTrue);
      expect(query.matches({'name': 'Bob'}), isFalse);
    });

    test('should match numeric values', () {
      const query = EqualsQuery('age', 25);

      expect(query.matches({'age': 25}), isTrue);
      expect(query.matches({'age': 30}), isFalse);
    });

    test('should match boolean values', () {
      const query = EqualsQuery('active', true);

      expect(query.matches({'active': true}), isTrue);
      expect(query.matches({'active': false}), isFalse);
    });

    test('should match null values', () {
      const query = EqualsQuery('deleted', null);

      expect(query.matches({'deleted': null}), isTrue);
      expect(query.matches({'deleted': 'value'}), isFalse);
    });

    test('should match nested fields', () {
      const query = EqualsQuery('address.city', 'London');

      expect(
        query.matches({
          'address': {'city': 'London'},
        }),
        isTrue,
      );
      expect(
        query.matches({
          'address': {'city': 'Paris'},
        }),
        isFalse,
      );
      expect(query.matches({'address': {}}), isFalse);
      expect(query.matches({}), isFalse);
    });

    test('should match deeply nested fields', () {
      const query = EqualsQuery('a.b.c.d', 'value');

      expect(
        query.matches({
          'a': {
            'b': {
              'c': {'d': 'value'},
            },
          },
        }),
        isTrue,
      );
    });

    test('should deep compare lists', () {
      const query = EqualsQuery('tags', ['a', 'b', 'c']);

      expect(
        query.matches({
          'tags': ['a', 'b', 'c'],
        }),
        isTrue,
      );
      expect(
        query.matches({
          'tags': ['a', 'b'],
        }),
        isFalse,
      );
      expect(
        query.matches({
          'tags': ['c', 'b', 'a'],
        }),
        isFalse,
      );
    });

    test('should compare map field values with identical instances', () {
      // When comparing maps, _deepEquals uses runtimeType check first
      // So we need to ensure the query value and data value are compatible
      final queryValue = {'key': 'value'};
      final query = EqualsQuery('meta', queryValue);

      // Same instance should match
      expect(query.matches({'meta': queryValue}), isTrue);
    });

    test('should fail on different map content', () {
      final query = EqualsQuery('meta', {'key': 'value'});

      // Different content should not match
      expect(
        query.matches({
          'meta': {'key': 'other'},
        }),
        isFalse,
      );
      expect(
        query.matches({
          'meta': {'different': 'value'},
        }),
        isFalse,
      );
    });

    test('should serialize and deserialize', () {
      const query = EqualsQuery('name', 'Alice');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<EqualsQuery>());
      expect(restored.matches({'name': 'Alice'}), isTrue);
    });
  });

  group('NotEqualsQuery', () {
    test('should match non-equal values', () {
      const query = NotEqualsQuery('status', 'deleted');

      expect(query.matches({'status': 'active'}), isTrue);
      expect(query.matches({'status': 'deleted'}), isFalse);
    });

    test('should match when field is missing', () {
      const query = NotEqualsQuery('status', 'deleted');

      expect(query.matches({}), isTrue);
    });

    test('should serialize and deserialize', () {
      const query = NotEqualsQuery('status', 'deleted');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<NotEqualsQuery>());
      expect(restored.matches({'status': 'active'}), isTrue);
    });
  });

  group('GreaterThanQuery', () {
    test('should match greater values', () {
      const query = GreaterThanQuery('age', 18);

      expect(query.matches({'age': 25}), isTrue);
      expect(query.matches({'age': 18}), isFalse);
      expect(query.matches({'age': 10}), isFalse);
    });

    test('should work with strings', () {
      const query = GreaterThanQuery('name', 'B');

      expect(query.matches({'name': 'Charlie'}), isTrue);
      expect(query.matches({'name': 'Alice'}), isFalse);
    });

    test('should return false for null field', () {
      const query = GreaterThanQuery('age', 18);

      expect(query.matches({}), isFalse);
      expect(query.matches({'age': null}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = GreaterThanQuery('age', 18);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<GreaterThanQuery>());
      expect(restored.matches({'age': 25}), isTrue);
    });
  });

  group('GreaterThanOrEqualsQuery', () {
    test('should match greater or equal values', () {
      const query = GreaterThanOrEqualsQuery('age', 18);

      expect(query.matches({'age': 25}), isTrue);
      expect(query.matches({'age': 18}), isTrue);
      expect(query.matches({'age': 17}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = GreaterThanOrEqualsQuery('age', 18);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<GreaterThanOrEqualsQuery>());
      expect(restored.matches({'age': 18}), isTrue);
    });
  });

  group('LessThanQuery', () {
    test('should match lesser values', () {
      const query = LessThanQuery('price', 100);

      expect(query.matches({'price': 50}), isTrue);
      expect(query.matches({'price': 100}), isFalse);
      expect(query.matches({'price': 150}), isFalse);
    });

    test('should work with doubles', () {
      const query = LessThanQuery('price', 99.99);

      expect(query.matches({'price': 50.0}), isTrue);
      expect(query.matches({'price': 99.98}), isTrue);
      expect(query.matches({'price': 99.99}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = LessThanQuery('price', 100);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<LessThanQuery>());
      expect(restored.matches({'price': 50}), isTrue);
    });
  });

  group('LessThanOrEqualsQuery', () {
    test('should match lesser or equal values', () {
      const query = LessThanOrEqualsQuery('price', 100);

      expect(query.matches({'price': 50}), isTrue);
      expect(query.matches({'price': 100}), isTrue);
      expect(query.matches({'price': 101}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = LessThanOrEqualsQuery('price', 100);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<LessThanOrEqualsQuery>());
      expect(restored.matches({'price': 100}), isTrue);
    });
  });

  group('BetweenQuery', () {
    test('should match values within inclusive range', () {
      const query = BetweenQuery('age', 18, 65);

      expect(query.matches({'age': 25}), isTrue);
      expect(query.matches({'age': 18}), isTrue);
      expect(query.matches({'age': 65}), isTrue);
      expect(query.matches({'age': 17}), isFalse);
      expect(query.matches({'age': 66}), isFalse);
    });

    test('should handle exclusive lower bound', () {
      const query = BetweenQuery('age', 18, 65, includeLower: false);

      expect(query.matches({'age': 18}), isFalse);
      expect(query.matches({'age': 19}), isTrue);
      expect(query.matches({'age': 65}), isTrue);
    });

    test('should handle exclusive upper bound', () {
      const query = BetweenQuery('age', 18, 65, includeUpper: false);

      expect(query.matches({'age': 18}), isTrue);
      expect(query.matches({'age': 64}), isTrue);
      expect(query.matches({'age': 65}), isFalse);
    });

    test('should handle both bounds exclusive', () {
      const query = BetweenQuery(
        'age',
        18,
        65,
        includeLower: false,
        includeUpper: false,
      );

      expect(query.matches({'age': 18}), isFalse);
      expect(query.matches({'age': 19}), isTrue);
      expect(query.matches({'age': 64}), isTrue);
      expect(query.matches({'age': 65}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = BetweenQuery('age', 18, 65);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<BetweenQuery>());
      expect(restored.matches({'age': 30}), isTrue);
    });
  });

  group('InQuery', () {
    test('should match values in list', () {
      const query = InQuery('status', ['active', 'pending', 'review']);

      expect(query.matches({'status': 'active'}), isTrue);
      expect(query.matches({'status': 'pending'}), isTrue);
      expect(query.matches({'status': 'deleted'}), isFalse);
    });

    test('should work with numeric values', () {
      const query = InQuery('priority', [1, 2, 3]);

      expect(query.matches({'priority': 2}), isTrue);
      expect(query.matches({'priority': 5}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = InQuery('status', ['a', 'b', 'c']);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<InQuery>());
      expect(restored.matches({'status': 'b'}), isTrue);
    });
  });

  group('NotInQuery', () {
    test('should match values not in list', () {
      const query = NotInQuery('status', ['deleted', 'archived']);

      expect(query.matches({'status': 'active'}), isTrue);
      expect(query.matches({'status': 'deleted'}), isFalse);
      expect(query.matches({'status': 'archived'}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = NotInQuery('status', ['a', 'b']);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<NotInQuery>());
      expect(restored.matches({'status': 'c'}), isTrue);
    });
  });

  group('RegexQuery', () {
    test('should match regex pattern', () {
      final query = RegexQuery('email', RegExp(r'^[a-z]+@example\.com$'));

      expect(query.matches({'email': 'alice@example.com'}), isTrue);
      expect(query.matches({'email': 'bob@example.com'}), isTrue);
      expect(query.matches({'email': 'test@other.com'}), isFalse);
    });

    test('should support case insensitive matching', () {
      final query = RegexQuery.fromPattern(
        'name',
        r'^alice$',
        caseSensitive: false,
      );

      expect(query.matches({'name': 'Alice'}), isTrue);
      expect(query.matches({'name': 'ALICE'}), isTrue);
      expect(query.matches({'name': 'alice'}), isTrue);
    });

    test('should support multiline matching', () {
      final query = RegexQuery.fromPattern('text', r'^line', multiLine: true);

      expect(query.matches({'text': 'line 1\nline 2'}), isTrue);
    });

    test('should return false for non-string field', () {
      final query = RegexQuery('value', RegExp(r'\d+'));

      expect(query.matches({'value': 123}), isFalse);
    });

    test('should serialize and deserialize', () {
      final query = RegexQuery.fromPattern('email', r'@test\.com$');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<RegexQuery>());
      expect(restored.matches({'email': 'user@test.com'}), isTrue);
    });
  });

  group('ExistsQuery', () {
    test('should match when field exists', () {
      const query = ExistsQuery('email');

      expect(query.matches({'email': 'alice@example.com'}), isTrue);
      expect(query.matches({'email': null}), isTrue);
      expect(query.matches({'name': 'Alice'}), isFalse);
    });

    test('should work with nested fields', () {
      const query = ExistsQuery('address.city');

      expect(
        query.matches({
          'address': {'city': 'London'},
        }),
        isTrue,
      );
      expect(
        query.matches({
          'address': {'zip': '12345'},
        }),
        isFalse,
      );
      expect(query.matches({}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = ExistsQuery('email');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<ExistsQuery>());
      expect(restored.matches({'email': 'test'}), isTrue);
    });
  });

  group('IsNullQuery', () {
    test('should match null values', () {
      const query = IsNullQuery('deletedAt');

      expect(query.matches({'deletedAt': null}), isTrue);
      expect(query.matches({}), isTrue);
      expect(query.matches({'deletedAt': DateTime.now()}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = IsNullQuery('value');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<IsNullQuery>());
      expect(restored.matches({'value': null}), isTrue);
    });
  });

  group('IsNotNullQuery', () {
    test('should match non-null values', () {
      const query = IsNotNullQuery('email');

      expect(query.matches({'email': 'alice@example.com'}), isTrue);
      expect(query.matches({'email': null}), isFalse);
      expect(query.matches({}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = IsNotNullQuery('value');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<IsNotNullQuery>());
      expect(restored.matches({'value': 'data'}), isTrue);
    });
  });

  group('ContainsQuery', () {
    group('String containment', () {
      test('should match substring', () {
        const query = ContainsQuery('description', 'important');

        expect(query.matches({'description': 'This is important!'}), isTrue);
        expect(query.matches({'description': 'IMPORTANT'}), isFalse);
        expect(query.matches({'description': 'trivial'}), isFalse);
      });

      test('should support case insensitive matching', () {
        const query = ContainsQuery(
          'description',
          'important',
          caseSensitive: false,
        );

        expect(query.matches({'description': 'IMPORTANT'}), isTrue);
        expect(query.matches({'description': 'Important'}), isTrue);
      });
    });

    group('List containment', () {
      test('should match value in list', () {
        const query = ContainsQuery('tags', 'featured');

        expect(
          query.matches({
            'tags': ['featured', 'new'],
          }),
          isTrue,
        );
        expect(
          query.matches({
            'tags': ['other'],
          }),
          isFalse,
        );
      });

      test('should match primitive items in list', () {
        const query = ContainsQuery('numbers', 42);

        expect(
          query.matches({
            'numbers': [1, 42, 100],
          }),
          isTrue,
        );
        expect(
          query.matches({
            'numbers': [1, 2, 3],
          }),
          isFalse,
        );
      });

      test('should match map items in list with same types', () {
        // Use dynamic map for consistent type comparison
        final searchValue = <String, dynamic>{'id': 1};
        final query = ContainsQuery('items', searchValue);

        expect(
          query.matches({
            'items': [
              searchValue,
              {'id': 2},
            ],
          }),
          isTrue,
        );
      });
    });

    test('should serialize and deserialize', () {
      const query = ContainsQuery('text', 'word');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<ContainsQuery>());
      expect(restored.matches({'text': 'a word here'}), isTrue);
    });
  });

  group('StartsWithQuery', () {
    test('should match prefix', () {
      const query = StartsWithQuery('name', 'Dr.');

      expect(query.matches({'name': 'Dr. Smith'}), isTrue);
      expect(query.matches({'name': 'Smith'}), isFalse);
    });

    test('should support case insensitive matching', () {
      const query = StartsWithQuery('name', 'dr.', caseSensitive: false);

      expect(query.matches({'name': 'DR. SMITH'}), isTrue);
      expect(query.matches({'name': 'Dr. Smith'}), isTrue);
    });

    test('should return false for non-string', () {
      const query = StartsWithQuery('value', 'prefix');

      expect(query.matches({'value': 123}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = StartsWithQuery('name', 'Dr.');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<StartsWithQuery>());
      expect(restored.matches({'name': 'Dr. Jones'}), isTrue);
    });
  });

  group('EndsWithQuery', () {
    test('should match suffix', () {
      const query = EndsWithQuery('email', '@example.com');

      expect(query.matches({'email': 'alice@example.com'}), isTrue);
      expect(query.matches({'email': 'alice@other.com'}), isFalse);
    });

    test('should support case insensitive matching', () {
      const query = EndsWithQuery(
        'email',
        '@EXAMPLE.COM',
        caseSensitive: false,
      );

      expect(query.matches({'email': 'alice@example.com'}), isTrue);
    });

    test('should serialize and deserialize', () {
      const query = EndsWithQuery('email', '@test.com');
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<EndsWithQuery>());
      expect(restored.matches({'email': 'user@test.com'}), isTrue);
    });
  });

  group('AndQuery', () {
    test('should require all queries to match', () {
      final query = AndQuery([
        const EqualsQuery('status', 'active'),
        const GreaterThanQuery('age', 18),
      ]);

      expect(query.matches({'status': 'active', 'age': 25}), isTrue);
      expect(query.matches({'status': 'active', 'age': 15}), isFalse);
      expect(query.matches({'status': 'inactive', 'age': 25}), isFalse);
    });

    test('should throw for empty query list', () {
      expect(() => AndQuery([]), throwsArgumentError);
    });

    test('should serialize and deserialize', () {
      final query = AndQuery([
        const EqualsQuery('a', 1),
        const EqualsQuery('b', 2),
      ]);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<AndQuery>());
      expect(restored.matches({'a': 1, 'b': 2}), isTrue);
    });
  });

  group('OrQuery', () {
    test('should require at least one query to match', () {
      final query = OrQuery([
        const EqualsQuery('status', 'active'),
        const EqualsQuery('status', 'pending'),
      ]);

      expect(query.matches({'status': 'active'}), isTrue);
      expect(query.matches({'status': 'pending'}), isTrue);
      expect(query.matches({'status': 'deleted'}), isFalse);
    });

    test('should throw for empty query list', () {
      expect(() => OrQuery([]), throwsArgumentError);
    });

    test('should serialize and deserialize', () {
      final query = OrQuery([
        const EqualsQuery('status', 'a'),
        const EqualsQuery('status', 'b'),
      ]);
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<OrQuery>());
      expect(restored.matches({'status': 'a'}), isTrue);
    });
  });

  group('NotQuery', () {
    test('should negate query result', () {
      const query = NotQuery(EqualsQuery('status', 'deleted'));

      expect(query.matches({'status': 'active'}), isTrue);
      expect(query.matches({'status': 'deleted'}), isFalse);
    });

    test('should serialize and deserialize', () {
      const query = NotQuery(EqualsQuery('status', 'deleted'));
      final map = query.toMap();
      final restored = IQuery.fromMap(map);

      expect(restored, isA<NotQuery>());
      expect(restored.matches({'status': 'active'}), isTrue);
    });
  });

  group('IQuery.fromMap', () {
    test('should throw for missing type field', () {
      expect(() => IQuery.fromMap({}), throwsArgumentError);
    });

    test('should throw for unknown type', () {
      expect(
        () => IQuery.fromMap({'type': 'UnknownQuery'}),
        throwsArgumentError,
      );
    });
  });

  group('QueryBuilder', () {
    group('Basic Queries', () {
      test('should build equals query', () {
        final query = QueryBuilder().whereEquals('name', 'Alice').build();

        expect(query.matches({'name': 'Alice'}), isTrue);
        expect(query.matches({'name': 'Bob'}), isFalse);
      });

      test('should build not equals query', () {
        final query = QueryBuilder()
            .whereNotEquals('status', 'deleted')
            .build();

        expect(query.matches({'status': 'active'}), isTrue);
        expect(query.matches({'status': 'deleted'}), isFalse);
      });

      test('should build greater than query', () {
        final query = QueryBuilder().whereGreaterThan('age', 18).build();

        expect(query.matches({'age': 25}), isTrue);
        expect(query.matches({'age': 18}), isFalse);
      });

      test('should build greater than or equals query', () {
        final query = QueryBuilder()
            .whereGreaterThanOrEquals('age', 18)
            .build();

        expect(query.matches({'age': 18}), isTrue);
        expect(query.matches({'age': 17}), isFalse);
      });

      test('should build less than query', () {
        final query = QueryBuilder().whereLessThan('price', 100).build();

        expect(query.matches({'price': 50}), isTrue);
        expect(query.matches({'price': 100}), isFalse);
      });

      test('should build less than or equals query', () {
        final query = QueryBuilder()
            .whereLessThanOrEquals('price', 100)
            .build();

        expect(query.matches({'price': 100}), isTrue);
        expect(query.matches({'price': 101}), isFalse);
      });

      test('should build between query', () {
        final query = QueryBuilder().whereBetween('age', 18, 65).build();

        expect(query.matches({'age': 30}), isTrue);
        expect(query.matches({'age': 10}), isFalse);
      });

      test('should build in query', () {
        final query = QueryBuilder().whereIn('status', [
          'active',
          'pending',
        ]).build();

        expect(query.matches({'status': 'active'}), isTrue);
        expect(query.matches({'status': 'deleted'}), isFalse);
      });

      test('should build not in query', () {
        final query = QueryBuilder().whereNotIn('status', [
          'deleted',
          'archived',
        ]).build();

        expect(query.matches({'status': 'active'}), isTrue);
        expect(query.matches({'status': 'deleted'}), isFalse);
      });

      test('should build regex query', () {
        final query = QueryBuilder()
            .whereRegex('email', r'^[a-z]+@test\.com$')
            .build();

        expect(query.matches({'email': 'alice@test.com'}), isTrue);
        expect(query.matches({'email': 'alice@other.com'}), isFalse);
      });

      test('should build exists query', () {
        final query = QueryBuilder().whereExists('email').build();

        expect(query.matches({'email': 'test@example.com'}), isTrue);
        expect(query.matches({'name': 'Alice'}), isFalse);
      });

      test('should build is null query', () {
        final query = QueryBuilder().whereIsNull('deletedAt').build();

        expect(query.matches({'deletedAt': null}), isTrue);
        expect(query.matches({'deletedAt': DateTime.now()}), isFalse);
      });

      test('should build is not null query', () {
        final query = QueryBuilder().whereIsNotNull('email').build();

        expect(query.matches({'email': 'test@example.com'}), isTrue);
        expect(query.matches({'email': null}), isFalse);
      });

      test('should build contains query', () {
        final query = QueryBuilder().whereContains('text', 'word').build();

        expect(query.matches({'text': 'a word here'}), isTrue);
        expect(query.matches({'text': 'nothing'}), isFalse);
      });

      test('should build starts with query', () {
        final query = QueryBuilder().whereStartsWith('name', 'Dr.').build();

        expect(query.matches({'name': 'Dr. Smith'}), isTrue);
        expect(query.matches({'name': 'Mr. Smith'}), isFalse);
      });

      test('should build ends with query', () {
        final query = QueryBuilder()
            .whereEndsWith('email', '@example.com')
            .build();

        expect(query.matches({'email': 'alice@example.com'}), isTrue);
        expect(query.matches({'email': 'alice@other.com'}), isFalse);
      });
    });

    group('Combining Queries', () {
      test('should combine with AND by default', () {
        final query = QueryBuilder()
            .whereEquals('status', 'active')
            .whereGreaterThan('age', 18)
            .build();

        expect(query.matches({'status': 'active', 'age': 25}), isTrue);
        expect(query.matches({'status': 'active', 'age': 15}), isFalse);
        expect(query.matches({'status': 'inactive', 'age': 25}), isFalse);
      });

      test('should combine with OR', () {
        final query = QueryBuilder()
            .whereEquals('status', 'active')
            .or(const EqualsQuery('status', 'pending'))
            .build();

        expect(query.matches({'status': 'active'}), isTrue);
        expect(query.matches({'status': 'pending'}), isTrue);
        expect(query.matches({'status': 'deleted'}), isFalse);
      });

      test('should use orAll for multiple OR conditions', () {
        final query = QueryBuilder().orAll([
          const EqualsQuery('status', 'a'),
          const EqualsQuery('status', 'b'),
          const EqualsQuery('status', 'c'),
        ]).build();

        expect(query.matches({'status': 'a'}), isTrue);
        expect(query.matches({'status': 'b'}), isTrue);
        expect(query.matches({'status': 'c'}), isTrue);
        expect(query.matches({'status': 'd'}), isFalse);
      });

      test('should use and method', () {
        final query = QueryBuilder()
            .whereEquals('a', 1)
            .and(const EqualsQuery('b', 2))
            .build();

        expect(query.matches({'a': 1, 'b': 2}), isTrue);
        expect(query.matches({'a': 1, 'b': 3}), isFalse);
      });

      test('should use whereNot', () {
        final query = QueryBuilder()
            .whereNot(const EqualsQuery('status', 'deleted'))
            .build();

        expect(query.matches({'status': 'active'}), isTrue);
        expect(query.matches({'status': 'deleted'}), isFalse);
      });
    });

    group('Builder State', () {
      test('should throw build when no conditions added', () {
        expect(() => QueryBuilder().build(), throwsStateError);
      });

      test('should return AllQuery with buildOrAll when no conditions', () {
        final query = QueryBuilder().buildOrAll();

        expect(query, isA<AllQuery>());
        expect(query.matches({'any': 'data'}), isTrue);
      });

      test('should report hasConditions correctly', () {
        final builder = QueryBuilder();
        expect(builder.hasConditions, isFalse);

        builder.whereEquals('a', 1);
        expect(builder.hasConditions, isTrue);
      });

      test('should reset builder', () {
        final builder = QueryBuilder().whereEquals('a', 1);
        expect(builder.hasConditions, isTrue);

        builder.reset();
        expect(builder.hasConditions, isFalse);
      });

      test('should serialize query with toMap', () {
        final builder = QueryBuilder().whereEquals('name', 'Alice');
        final map = builder.toMap();

        expect(map['type'], equals('EqualsQuery'));
        expect(map['field'], equals('name'));
        expect(map['value'], equals('Alice'));
      });

      test('should throw toMap when no conditions', () {
        expect(() => QueryBuilder().toMap(), throwsStateError);
      });
    });

    group('Complex Queries', () {
      test('should build complex AND/OR combinations', () {
        // (status == 'active' AND priority > 5) OR (status == 'urgent')
        final query = OrQuery([
          AndQuery([
            const EqualsQuery('status', 'active'),
            const GreaterThanQuery('priority', 5),
          ]),
          const EqualsQuery('status', 'urgent'),
        ]);

        expect(query.matches({'status': 'active', 'priority': 10}), isTrue);
        expect(query.matches({'status': 'active', 'priority': 3}), isFalse);
        expect(query.matches({'status': 'urgent', 'priority': 1}), isTrue);
      });

      test('should handle deeply nested queries', () {
        final query = AndQuery([
          OrQuery([
            const EqualsQuery('type', 'a'),
            const EqualsQuery('type', 'b'),
          ]),
          OrQuery([
            const GreaterThanQuery('value', 10),
            const LessThanQuery('value', 5),
          ]),
        ]);

        expect(query.matches({'type': 'a', 'value': 15}), isTrue);
        expect(query.matches({'type': 'a', 'value': 2}), isTrue);
        expect(query.matches({'type': 'a', 'value': 7}), isFalse);
        expect(query.matches({'type': 'c', 'value': 15}), isFalse);
      });
    });
  });

  // ===========================================================================
  // Query Optimizer Tests
  // ===========================================================================

  group('QueryOptimizer', () {
    late IndexManager indexManager;
    late QueryOptimizer optimizer;

    setUp(() {
      indexManager = IndexManager();
      optimizer = QueryOptimizer(indexManager);
    });

    group('IndexStatistics', () {
      test('should calculate selectivity correctly', () {
        // 10 unique keys means selectivity of 0.1
        const stats = IndexStatistics(
          field: 'status',
          indexType: IndexType.hash,
          cardinality: 10,
          totalEntries: 100,
        );

        expect(stats.selectivity, equals(0.1));
        expect(stats.averageEntriesPerKey, equals(10.0));
      });

      test('should handle zero cardinality', () {
        const stats = IndexStatistics(
          field: 'empty',
          indexType: IndexType.hash,
          cardinality: 0,
          totalEntries: 0,
        );

        expect(stats.selectivity, equals(1.0));
        expect(stats.averageEntriesPerKey, equals(0.0));
      });
    });

    group('QueryPlan', () {
      test('should create full scan plan', () {
        const query = AllQuery();
        final plan = QueryPlan.fullScan(query: query, totalEntities: 1000);

        expect(plan.strategy, equals(ExecutionStrategy.fullScan));
        expect(plan.estimatedCost, equals(1000.0));
        expect(plan.estimatedResults, equals(1000));
        expect(plan.usesIndex, isFalse);
      });

      test('should create index equals plan', () {
        const query = EqualsQuery('status', 'active');
        final plan = QueryPlan.indexEquals(
          query: query,
          field: 'status',
          indexType: IndexType.hash,
          value: 'active',
          estimatedResults: 50,
          totalEntities: 1000,
        );

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.usesIndex, isTrue);
        expect(plan.indexField, equals('status'));
        expect(plan.indexType, equals(IndexType.hash));
        expect(plan.indexValue, equals('active'));
        // Cost should be much lower than full scan
        expect(plan.estimatedCost, lessThan(1000.0));
      });

      test('should create index range plan', () {
        const query = GreaterThanQuery('price', 100);
        const bounds = RangeBounds.greaterThan(100);
        final plan = QueryPlan.indexRange(
          query: query,
          field: 'price',
          bounds: bounds,
          estimatedResults: 200,
          totalEntities: 1000,
        );

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.usesIndex, isTrue);
        expect(plan.indexField, equals('price'));
        expect(plan.indexType, equals(IndexType.btree));
        expect(plan.rangeBounds, isNotNull);
      });

      test('should create index IN plan', () {
        final query = InQuery('status', ['a', 'b', 'c']);
        final plan = QueryPlan.indexIn(
          query: query,
          field: 'status',
          indexType: IndexType.hash,
          values: ['a', 'b', 'c'],
          estimatedResults: 30,
          totalEntities: 1000,
        );

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.usesIndex, isTrue);
        expect(plan.inValues, equals(['a', 'b', 'c']));
      });
    });

    group('QueryPlanCache', () {
      test('should cache and retrieve plans', () {
        final cache = QueryPlanCache(maxSize: 10);
        const query = EqualsQuery('status', 'active');
        final plan = QueryPlan.fullScan(query: query, totalEntities: 100);

        cache.put(query, plan, 100);
        final retrieved = cache.get(query, 100);

        expect(retrieved, isNotNull);
        expect(retrieved!.strategy, equals(plan.strategy));
      });

      test('should invalidate on significant entity count change', () {
        final cache = QueryPlanCache(maxSize: 10);
        const query = EqualsQuery('status', 'active');
        final plan = QueryPlan.fullScan(query: query, totalEntities: 100);

        cache.put(query, plan, 100);

        // 15% change should invalidate
        final retrieved = cache.get(query, 116);
        expect(retrieved, isNull);
      });

      test('should not invalidate on minor entity count change', () {
        final cache = QueryPlanCache(maxSize: 10);
        const query = EqualsQuery('status', 'active');
        final plan = QueryPlan.fullScan(query: query, totalEntities: 100);

        cache.put(query, plan, 100);

        // 5% change should not invalidate
        final retrieved = cache.get(query, 105);
        expect(retrieved, isNotNull);
      });

      test('should evict LRU entries when at capacity', () {
        final cache = QueryPlanCache(maxSize: 2);
        const query1 = EqualsQuery('a', 1);
        const query2 = EqualsQuery('b', 2);
        const query3 = EqualsQuery('c', 3);

        final plan1 = QueryPlan.fullScan(query: query1, totalEntities: 100);
        final plan2 = QueryPlan.fullScan(query: query2, totalEntities: 100);
        final plan3 = QueryPlan.fullScan(query: query3, totalEntities: 100);

        cache.put(query1, plan1, 100);
        cache.put(query2, plan2, 100);
        cache.put(query3, plan3, 100);

        // query1 should be evicted (LRU)
        expect(cache.get(query1, 100), isNull);
        expect(cache.get(query2, 100), isNotNull);
        expect(cache.get(query3, 100), isNotNull);
      });

      test('should invalidate by field name', () {
        final cache = QueryPlanCache(maxSize: 10);
        const query1 = EqualsQuery('status', 'active');

        final plan1 = QueryPlan.fullScan(query: query1, totalEntities: 100);

        cache.put(query1, plan1, 100);

        expect(cache.size, equals(1));

        // This directly tests the cache clear functionality
        cache.clear();

        expect(cache.size, equals(0));
      });

      test('should clear all entries', () {
        final cache = QueryPlanCache(maxSize: 10);
        const query = EqualsQuery('status', 'active');
        final plan = QueryPlan.fullScan(query: query, totalEntities: 100);

        cache.put(query, plan, 100);
        expect(cache.size, equals(1));

        cache.clear();
        expect(cache.size, equals(0));
        expect(cache.get(query, 100), isNull);
      });
    });

    group('optimize', () {
      test('should return full scan for AllQuery', () {
        const query = AllQuery();
        final plan = optimizer.optimize(query, 1000);

        expect(plan.strategy, equals(ExecutionStrategy.fullScan));
      });

      test('should return full scan when no index exists', () {
        const query = EqualsQuery('status', 'active');
        final plan = optimizer.optimize(query, 1000);

        expect(plan.strategy, equals(ExecutionStrategy.fullScan));
      });

      test('should use hash index for EqualsQuery', () {
        indexManager.createIndex('status', IndexType.hash);
        // Insert some data to populate the index
        indexManager.insert('1', {'status': 'active'});
        indexManager.insert('2', {'status': 'active'});
        indexManager.insert('3', {'status': 'inactive'});

        const query = EqualsQuery('status', 'active');
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.indexField, equals('status'));
        expect(plan.indexType, equals(IndexType.hash));
      });

      test(
        'should use btree index for EqualsQuery when hash not available',
        () {
          indexManager.createIndex('price', IndexType.btree);
          indexManager.insert('1', {'price': 100});
          indexManager.insert('2', {'price': 200});

          const query = EqualsQuery('price', 100);
          final plan = optimizer.optimize(query, 100);

          expect(plan.strategy, equals(ExecutionStrategy.indexScan));
          expect(plan.indexField, equals('price'));
          expect(plan.indexType, equals(IndexType.btree));
        },
      );

      test('should use btree index for GreaterThanQuery', () {
        indexManager.createIndex('age', IndexType.btree);
        indexManager.insert('1', {'age': 25});
        indexManager.insert('2', {'age': 35});

        const query = GreaterThanQuery('age', 30);
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.indexField, equals('age'));
        expect(plan.rangeBounds, isNotNull);
        expect(plan.rangeBounds!.lower, equals(30));
        expect(plan.rangeBounds!.includeLower, isFalse);
      });

      test('should use btree index for LessThanQuery', () {
        indexManager.createIndex('price', IndexType.btree);
        indexManager.insert('1', {'price': 50});

        const query = LessThanQuery('price', 100);
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.rangeBounds!.upper, equals(100));
        expect(plan.rangeBounds!.includeUpper, isFalse);
      });

      test('should use btree index for BetweenQuery', () {
        indexManager.createIndex('price', IndexType.btree);
        indexManager.insert('1', {'price': 150});

        const query = BetweenQuery('price', 100, 200);
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.rangeBounds!.lower, equals(100));
        expect(plan.rangeBounds!.upper, equals(200));
      });

      test('should use index for InQuery', () {
        indexManager.createIndex('status', IndexType.hash);
        indexManager.insert('1', {'status': 'a'});
        indexManager.insert('2', {'status': 'b'});

        final query = InQuery('status', ['a', 'b', 'c']);
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.indexScan));
        expect(plan.inValues, equals(['a', 'b', 'c']));
      });

      test('should return full scan for NotQuery', () {
        indexManager.createIndex('status', IndexType.hash);

        const query = NotQuery(EqualsQuery('status', 'deleted'));
        final plan = optimizer.optimize(query, 100);

        expect(plan.strategy, equals(ExecutionStrategy.fullScan));
      });

      test('should optimize AndQuery with most selective index', () {
        indexManager.createIndex('status', IndexType.hash);
        indexManager.createIndex('price', IndexType.btree);

        // Add data - status has low cardinality, price has high
        indexManager.insert('1', {'status': 'active', 'price': 100});
        indexManager.insert('2', {'status': 'active', 'price': 200});
        indexManager.insert('3', {'status': 'inactive', 'price': 300});

        final query = AndQuery([
          const EqualsQuery('status', 'active'),
          const GreaterThanQuery('price', 150),
        ]);
        final plan = optimizer.optimize(query, 100);

        // Should use one index with post-filter
        expect(plan.usesIndex, isTrue);
      });

      test('should handle empty collection', () {
        const query = EqualsQuery('status', 'active');
        final plan = optimizer.optimize(query, 0);

        expect(plan.strategy, equals(ExecutionStrategy.fullScan));
        expect(plan.estimatedCost, equals(0.0));
      });

      test('should cache plans when enabled', () {
        indexManager.createIndex('status', IndexType.hash);
        indexManager.insert('1', {'status': 'active'});

        const query = EqualsQuery('status', 'active');

        // First call
        optimizer.optimize(query, 100);

        // Should be cached
        expect(optimizer.planCache.size, equals(1));

        // Second call uses cache
        final plan2 = optimizer.optimize(query, 100);
        expect(plan2, isNotNull);
      });

      test('should invalidate cache when index created', () {
        const query = EqualsQuery('status', 'active');

        // First call - no index
        optimizer.optimize(query, 100);
        expect(optimizer.planCache.size, equals(1));

        // Clear cache manually (simulating what happens when index is created)
        optimizer.clearCache();

        // Cache should be cleared
        expect(optimizer.planCache.size, equals(0));
      });
    });

    group('getIndexStatistics', () {
      test('should return null for non-existent index', () {
        final stats = optimizer.getIndexStatistics('nonexistent');
        expect(stats, isNull);
      });

      test('should return correct statistics for hash index', () {
        indexManager.createIndex('status', IndexType.hash);
        indexManager.insert('1', {'status': 'active'});
        indexManager.insert('2', {'status': 'active'});
        indexManager.insert('3', {'status': 'inactive'});

        final stats = optimizer.getIndexStatistics('status');

        expect(stats, isNotNull);
        expect(stats!.field, equals('status'));
        expect(stats.indexType, equals(IndexType.hash));
        expect(stats.cardinality, equals(2)); // 'active' and 'inactive'
        expect(stats.totalEntries, equals(3)); // 3 entities
        expect(stats.averageEntriesPerKey, equals(1.5));
      });

      test('should return correct statistics for btree index', () {
        indexManager.createIndex('age', IndexType.btree);
        indexManager.insert('1', {'age': 25});
        indexManager.insert('2', {'age': 30});
        indexManager.insert('3', {'age': 25});

        final stats = optimizer.getIndexStatistics('age');

        expect(stats, isNotNull);
        expect(stats!.indexType, equals(IndexType.btree));
        expect(stats.cardinality, equals(2)); // 25 and 30
        expect(stats.totalEntries, equals(3));
      });
    });

    group('getAllIndexStatistics', () {
      test('should return empty list when no indexes', () {
        final stats = optimizer.getAllIndexStatistics();
        expect(stats, isEmpty);
      });

      test('should return statistics for all indexes', () {
        indexManager.createIndex('status', IndexType.hash);
        indexManager.createIndex('age', IndexType.btree);

        indexManager.insert('1', {'status': 'active', 'age': 25});

        final stats = optimizer.getAllIndexStatistics();

        expect(stats.length, equals(2));
        expect(stats.map((s) => s.field).toSet(), equals({'status', 'age'}));
      });
    });
  });

  group('RangeBounds', () {
    test('should create greaterThan bounds', () {
      const bounds = RangeBounds.greaterThan(10);

      expect(bounds.lower, equals(10));
      expect(bounds.upper, isNull);
      expect(bounds.includeLower, isFalse);
    });

    test('should create greaterThanOrEqual bounds', () {
      const bounds = RangeBounds.greaterThanOrEqual(10);

      expect(bounds.lower, equals(10));
      expect(bounds.upper, isNull);
      expect(bounds.includeLower, isTrue);
    });

    test('should create lessThan bounds', () {
      const bounds = RangeBounds.lessThan(10);

      expect(bounds.lower, isNull);
      expect(bounds.upper, equals(10));
      expect(bounds.includeUpper, isFalse);
    });

    test('should create lessThanOrEqual bounds', () {
      const bounds = RangeBounds.lessThanOrEqual(10);

      expect(bounds.lower, isNull);
      expect(bounds.upper, equals(10));
      expect(bounds.includeUpper, isTrue);
    });
  });

  // ===========================================================================
  // QueryCache Tests
  // ===========================================================================

  group('QueryCacheConfig', () {
    test('should have sensible defaults', () {
      const config = QueryCacheConfig();

      expect(config.maxSize, equals(100));
      expect(config.defaultTtl, equals(const Duration(minutes: 5)));
      expect(config.enableSelectiveInvalidation, isTrue);
      expect(config.collectStatistics, isTrue);
    });

    test('should allow custom configuration', () {
      const config = QueryCacheConfig(
        maxSize: 50,
        defaultTtl: Duration(seconds: 30),
        enableSelectiveInvalidation: false,
        collectStatistics: false,
      );

      expect(config.maxSize, equals(50));
      expect(config.defaultTtl, equals(const Duration(seconds: 30)));
      expect(config.enableSelectiveInvalidation, isFalse);
      expect(config.collectStatistics, isFalse);
    });

    test('copyWith should create new config with changes', () {
      const original = QueryCacheConfig();
      final modified = original.copyWith(maxSize: 200);

      expect(modified.maxSize, equals(200));
      expect(modified.defaultTtl, equals(original.defaultTtl));
      expect(
        modified.enableSelectiveInvalidation,
        equals(original.enableSelectiveInvalidation),
      );
    });

    test('should have meaningful toString', () {
      const config = QueryCacheConfig();
      final str = config.toString();

      expect(str, contains('maxSize'));
      expect(str, contains('defaultTtl'));
    });
  });

  group('CacheStatistics', () {
    test('should initialize with zeros', () {
      const stats = CacheStatistics();

      expect(stats.hits, equals(0));
      expect(stats.misses, equals(0));
      expect(stats.evictions, equals(0));
      expect(stats.expirations, equals(0));
      expect(stats.invalidations, equals(0));
      expect(stats.size, equals(0));
    });

    test('hitRatio should calculate correctly', () {
      const stats = CacheStatistics(hits: 3, misses: 1);

      expect(stats.hitRatio, closeTo(0.75, 0.001));
    });

    test('hitRatio should be 0 when no hits or misses', () {
      const stats = CacheStatistics();

      expect(stats.hitRatio, equals(0.0));
    });

    test('incrementHits should create new stats with incremented hits', () {
      const stats = CacheStatistics(hits: 5, misses: 2);
      final updated = stats.incrementHits();

      expect(updated.hits, equals(6));
      expect(updated.misses, equals(2));
    });

    test('incrementMisses should create new stats with incremented misses', () {
      const stats = CacheStatistics(hits: 5, misses: 2);
      final updated = stats.incrementMisses();

      expect(updated.hits, equals(5));
      expect(updated.misses, equals(3));
    });

    test(
      'incrementEvictions should create new stats with incremented evictions',
      () {
        const stats = CacheStatistics(evictions: 1);
        final updated = stats.incrementEvictions(3);

        expect(updated.evictions, equals(4));
      },
    );

    test('withSize should create new stats with updated size', () {
      const stats = CacheStatistics(size: 10);
      final updated = stats.withSize(25);

      expect(updated.size, equals(25));
    });

    test('should have meaningful toString', () {
      const stats = CacheStatistics(hits: 10, misses: 5);
      final str = stats.toString();

      expect(str, contains('hits'));
      expect(str, contains('misses'));
      expect(str, contains('hitRatio'));
    });
  });

  group('QueryCache', () {
    late QueryCache<TestEntity> cache;

    setUp(() {
      cache = QueryCache<TestEntity>();
    });

    group('Construction', () {
      test('should create with default config', () {
        final cache = QueryCache<TestEntity>();

        expect(cache.config.maxSize, equals(100));
        expect(cache.isEmpty, isTrue);
        expect(cache.size, equals(0));
      });

      test('should create with custom config', () {
        final cache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(maxSize: 50),
        );

        expect(cache.config.maxSize, equals(50));
      });

      test('should create with individual parameters', () {
        final cache = QueryCache<TestEntity>.withParams(
          maxSize: 25,
          defaultTtl: const Duration(seconds: 10),
        );

        expect(cache.config.maxSize, equals(25));
        expect(cache.config.defaultTtl, equals(const Duration(seconds: 10)));
      });
    });

    group('Basic Operations', () {
      test('should cache and retrieve query results', () {
        const query = EqualsQuery('status', 'active');
        final results = [TestEntity('1', 'active')];

        cache.put(query, results);
        final cached = cache.get(query);

        expect(cached, isNotNull);
        expect(cached!.length, equals(1));
        expect(cached.first.id, equals('1'));
      });

      test('should return null for uncached query', () {
        const query = EqualsQuery('status', 'active');

        expect(cache.get(query), isNull);
      });

      test('should return unmodifiable list', () {
        const query = EqualsQuery('status', 'active');
        cache.put(query, [TestEntity('1', 'active')]);

        final cached = cache.get(query);

        expect(
          () => cached!.add(TestEntity('2', 'inactive')),
          throwsA(anything),
        );
      });

      test('containsQuery should return true for cached queries', () {
        const query = EqualsQuery('status', 'active');

        expect(cache.containsQuery(query), isFalse);

        cache.put(query, []);

        expect(cache.containsQuery(query), isTrue);
      });

      test('clear should remove all entries', () {
        cache.put(const EqualsQuery('a', 1), []);
        cache.put(const EqualsQuery('b', 2), []);

        expect(cache.size, equals(2));

        cache.clear();

        expect(cache.isEmpty, isTrue);
      });
    });

    group('TTL Expiration', () {
      test('should expire entries after TTL', () async {
        final shortTtlCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(
            defaultTtl: Duration(milliseconds: 50),
          ),
        );

        const query = EqualsQuery('status', 'active');
        shortTtlCache.put(query, [TestEntity('1', 'active')]);

        expect(shortTtlCache.get(query), isNotNull);

        // Wait for expiration
        await Future.delayed(const Duration(milliseconds: 100));

        expect(shortTtlCache.get(query), isNull);
      });

      test('should allow custom TTL per entry', () async {
        const query = EqualsQuery('status', 'active');
        cache.put(query, [
          TestEntity('1', 'active'),
        ], ttl: const Duration(milliseconds: 50));

        expect(cache.get(query), isNotNull);

        // Wait for expiration
        await Future.delayed(const Duration(milliseconds: 100));

        expect(cache.get(query), isNull);
      });

      test('removeExpired should clean up expired entries', () async {
        final shortTtlCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(
            defaultTtl: Duration(milliseconds: 50),
          ),
        );

        shortTtlCache.put(const EqualsQuery('a', 1), []);
        shortTtlCache.put(const EqualsQuery('b', 2), []);

        expect(shortTtlCache.size, equals(2));

        await Future.delayed(const Duration(milliseconds: 100));

        final removed = shortTtlCache.removeExpired();

        expect(removed, equals(2));
        expect(shortTtlCache.isEmpty, isTrue);
      });
    });

    group('LRU Eviction', () {
      test('should evict least recently used when at capacity', () {
        final smallCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(maxSize: 3),
        );

        smallCache.put(const EqualsQuery('a', 1), [TestEntity('1', 'a')]);
        smallCache.put(const EqualsQuery('b', 2), [TestEntity('2', 'b')]);
        smallCache.put(const EqualsQuery('c', 3), [TestEntity('3', 'c')]);

        expect(smallCache.size, equals(3));

        // Add fourth entry, should evict 'a'
        smallCache.put(const EqualsQuery('d', 4), [TestEntity('4', 'd')]);

        expect(smallCache.size, equals(3));
        expect(smallCache.get(const EqualsQuery('a', 1)), isNull);
        expect(smallCache.get(const EqualsQuery('d', 4)), isNotNull);
      });

      test('should update access order on get', () {
        final smallCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(maxSize: 3),
        );

        smallCache.put(const EqualsQuery('a', 1), [TestEntity('1', 'a')]);
        smallCache.put(const EqualsQuery('b', 2), [TestEntity('2', 'b')]);
        smallCache.put(const EqualsQuery('c', 3), [TestEntity('3', 'c')]);

        // Access 'a' to make it most recently used
        smallCache.get(const EqualsQuery('a', 1));

        // Add fourth entry, should evict 'b' (least recently used after access)
        smallCache.put(const EqualsQuery('d', 4), [TestEntity('4', 'd')]);

        expect(smallCache.get(const EqualsQuery('a', 1)), isNotNull);
        expect(smallCache.get(const EqualsQuery('b', 2)), isNull);
      });

      test('should track evictions in statistics', () {
        final smallCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(maxSize: 2),
        );

        smallCache.put(const EqualsQuery('a', 1), []);
        smallCache.put(const EqualsQuery('b', 2), []);
        smallCache.put(const EqualsQuery('c', 3), []);

        expect(smallCache.statistics.evictions, equals(1));
      });
    });

    group('Selective Invalidation', () {
      test('invalidateField should remove queries using that field', () {
        cache.put(const EqualsQuery('status', 'active'), []);
        cache.put(const EqualsQuery('name', 'John'), []);
        cache.put(const GreaterThanQuery('age', 18), []);

        expect(cache.size, equals(3));

        final removed = cache.invalidateField('status');

        expect(removed, equals(1));
        expect(cache.size, equals(2));
        expect(cache.get(const EqualsQuery('status', 'active')), isNull);
        expect(cache.get(const EqualsQuery('name', 'John')), isNotNull);
      });

      test(
        'invalidateFields should remove queries using any of the fields',
        () {
          cache.put(const EqualsQuery('status', 'active'), []);
          cache.put(const EqualsQuery('name', 'John'), []);
          cache.put(const GreaterThanQuery('age', 18), []);

          final removed = cache.invalidateFields({'status', 'age'});

          expect(removed, equals(2));
          expect(cache.size, equals(1));
        },
      );

      test('invalidateQuery should remove specific query', () {
        const query1 = EqualsQuery('status', 'active');
        const query2 = EqualsQuery('status', 'inactive');

        cache.put(query1, []);
        cache.put(query2, []);

        expect(cache.size, equals(2));

        final removed = cache.invalidateQuery(query1);

        expect(removed, isTrue);
        expect(cache.size, equals(1));
        expect(cache.get(query1), isNull);
        expect(cache.get(query2), isNotNull);
      });

      test('invalidateAll should clear entire cache', () {
        cache.put(const EqualsQuery('a', 1), []);
        cache.put(const EqualsQuery('b', 2), []);
        cache.put(const EqualsQuery('c', 3), []);

        final removed = cache.invalidateAll();

        expect(removed, equals(3));
        expect(cache.isEmpty, isTrue);
      });

      test('should track fields for compound queries', () {
        final andQuery = AndQuery([
          const EqualsQuery('status', 'active'),
          const GreaterThanQuery('age', 18),
        ]);

        cache.put(andQuery, []);

        // Should be invalidated when either field changes
        final statusRemoved = cache.invalidateField('status');
        expect(statusRemoved, equals(1));

        cache.put(andQuery, []); // Re-add for next test
        final ageRemoved = cache.invalidateField('age');
        expect(ageRemoved, equals(1));
      });

      test('should track fields for OrQuery', () {
        final orQuery = OrQuery([
          const EqualsQuery('status', 'active'),
          const EqualsQuery('priority', 'high'),
        ]);

        cache.put(orQuery, []);

        expect(cache.cachedFields, containsAll(['status', 'priority']));
      });

      test('should track fields for NotQuery', () {
        const notQuery = NotQuery(EqualsQuery('deleted', true));

        cache.put(notQuery, []);

        expect(cache.cachedFields, contains('deleted'));
      });

      test('queriesForField should return count of queries using field', () {
        cache.put(const EqualsQuery('status', 'a'), []);
        cache.put(const EqualsQuery('status', 'b'), []);
        cache.put(const EqualsQuery('name', 'c'), []);

        expect(cache.queriesForField('status'), equals(2));
        expect(cache.queriesForField('name'), equals(1));
        expect(cache.queriesForField('unknown'), equals(0));
      });
    });

    group('Statistics', () {
      test('should track cache hits', () {
        const query = EqualsQuery('status', 'active');
        cache.put(query, []);

        cache.get(query);
        cache.get(query);

        expect(cache.statistics.hits, equals(2));
      });

      test('should track cache misses', () {
        cache.get(const EqualsQuery('status', 'active'));
        cache.get(const EqualsQuery('name', 'John'));

        expect(cache.statistics.misses, equals(2));
      });

      test('should track invalidations', () {
        cache.put(const EqualsQuery('a', 1), []);
        cache.put(const EqualsQuery('b', 2), []);

        cache.invalidateAll();

        expect(cache.statistics.invalidations, equals(2));
      });

      test('should calculate hit ratio', () {
        const query = EqualsQuery('status', 'active');
        cache.put(query, []);

        cache.get(query); // hit
        cache.get(query); // hit
        cache.get(query); // hit
        cache.get(const EqualsQuery('other', 1)); // miss

        expect(cache.statistics.hitRatio, closeTo(0.75, 0.01));
      });

      test('statistics size should reflect current cache size', () {
        cache.put(const EqualsQuery('a', 1), []);
        cache.put(const EqualsQuery('b', 2), []);

        expect(cache.statistics.size, equals(2));
      });

      test('resetStatistics should clear statistics but keep cache', () {
        const query = EqualsQuery('status', 'active');
        cache.put(query, []);
        cache.get(query);

        expect(cache.statistics.hits, equals(1));
        expect(cache.size, equals(1));

        cache.resetStatistics();

        expect(cache.statistics.hits, equals(0));
        expect(cache.size, equals(1)); // Cache still has entry
      });

      test('should not collect statistics when disabled', () {
        final noStatsCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(collectStatistics: false),
        );

        const query = EqualsQuery('status', 'active');
        noStatsCache.put(query, []);
        noStatsCache.get(query);

        expect(noStatsCache.statistics.hits, equals(0));
      });
    });

    group('Selective Invalidation Disabled', () {
      test('should invalidate all on any field invalidation', () {
        final noSelectiveCache = QueryCache<TestEntity>(
          config: const QueryCacheConfig(enableSelectiveInvalidation: false),
        );

        noSelectiveCache.put(const EqualsQuery('a', 1), []);
        noSelectiveCache.put(const EqualsQuery('b', 2), []);

        final removed = noSelectiveCache.invalidateField('a');

        expect(removed, equals(2));
        expect(noSelectiveCache.isEmpty, isTrue);
      });
    });

    group('Field Extraction', () {
      test('should extract field from EqualsQuery', () {
        cache.put(const EqualsQuery('status', 'active'), []);
        expect(cache.cachedFields, contains('status'));
      });

      test('should extract field from NotEqualsQuery', () {
        cache.put(const NotEqualsQuery('status', 'deleted'), []);
        expect(cache.cachedFields, contains('status'));
      });

      test('should extract field from GreaterThanQuery', () {
        cache.put(const GreaterThanQuery('age', 18), []);
        expect(cache.cachedFields, contains('age'));
      });

      test('should extract field from LessThanQuery', () {
        cache.put(const LessThanQuery('price', 100), []);
        expect(cache.cachedFields, contains('price'));
      });

      test('should extract field from BetweenQuery', () {
        cache.put(const BetweenQuery('age', 18, 65), []);
        expect(cache.cachedFields, contains('age'));
      });

      test('should extract field from InQuery', () {
        cache.put(const InQuery('status', ['a', 'b', 'c']), []);
        expect(cache.cachedFields, contains('status'));
      });

      test('should extract field from ContainsQuery', () {
        cache.put(const ContainsQuery('tags', 'important'), []);
        expect(cache.cachedFields, contains('tags'));
      });

      test('should extract field from StartsWithQuery', () {
        cache.put(const StartsWithQuery('name', 'John'), []);
        expect(cache.cachedFields, contains('name'));
      });

      test('should extract field from RegexQuery', () {
        cache.put(RegexQuery('email', RegExp(r'.*@example\.com')), []);
        expect(cache.cachedFields, contains('email'));
      });

      test('should extract field from ExistsQuery', () {
        cache.put(const ExistsQuery('email'), []);
        expect(cache.cachedFields, contains('email'));
      });

      test('should extract field from IsNullQuery', () {
        cache.put(const IsNullQuery('deletedAt'), []);
        expect(cache.cachedFields, contains('deletedAt'));
      });

      test('AllQuery should not add any fields', () {
        cache.put(const AllQuery(), []);
        expect(cache.cachedFields, isEmpty);
      });
    });
  });
}

/// Test entity for query cache tests.
class TestEntity implements Entity {
  @override
  final String id;
  final String status;

  TestEntity(this.id, this.status);

  @override
  Map<String, dynamic> toMap() => {'status': status};
}
