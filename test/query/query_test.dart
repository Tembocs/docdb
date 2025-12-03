/// DocDB Query Module Tests
///
/// Comprehensive tests for the query module including QueryBuilder fluent API
/// and all query types (EqualsQuery, NotEqualsQuery, AndQuery, OrQuery, etc.).
library;

import 'package:test/test.dart';

import 'package:docdb/src/query/query.dart';

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
}
