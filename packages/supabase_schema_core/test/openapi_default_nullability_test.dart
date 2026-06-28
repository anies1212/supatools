import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:test/test.dart';

void main() {
  late SchemaFetcher fetcher;

  setUp(() {
    fetcher = SchemaFetcher(
      supabaseUrl: 'https://example.supabase.co',
      supabaseKey: 'test-key',
    );
  });

  ColumnInfo columnOf(List<TableInfo> tables, String name) =>
      tables.single.columns.firstWhere((c) => c.name == name);

  group('parseOpenApiSpec nullability', () {
    // PostgREST omits NOT NULL columns that carry a default from the
    // `required` list (they are optional on insert). Such a column must
    // still be treated as non-nullable with a default, so consumers emit
    // `@Default(...)` rather than `required` or a nullable type.
    final spec = {
      'definitions': {
        'card_master': {
          'required': ['id', 'name_ja'],
          'properties': {
            'id': {'type': 'integer', 'format': 'bigint'},
            'name_ja': {'type': 'string', 'format': 'text'},
            'lang': {'type': 'string', 'format': 'text', 'default': 'ja'},
            'rarity': {'type': 'string', 'format': 'text'},
          },
        },
      },
    };

    test('NOT NULL column with a default is non-nullable + keeps default', () {
      final tables = fetcher.parseOpenApiSpec(spec);
      final lang = columnOf(tables, 'lang');

      expect(lang.isNullable, isFalse);
      // String defaults are normalized to the single-quoted PG literal form
      // so downstream default parsing (which expects `'value'`) works.
      expect(lang.defaultValue, "'ja'");
    });

    test('numeric/boolean defaults pass through unquoted', () {
      final numSpec = {
        'definitions': {
          't': {
            'required': <String>[],
            'properties': {
              'qty': {'type': 'integer', 'default': 5},
              'flag': {'type': 'boolean', 'default': false},
            },
          },
        },
      };
      final tables = fetcher.parseOpenApiSpec(numSpec);
      expect(columnOf(tables, 'qty').defaultValue, '5');
      expect(columnOf(tables, 'qty').isNullable, isFalse);
      expect(columnOf(tables, 'flag').defaultValue, 'false');
    });

    test('required column is non-nullable', () {
      final tables = fetcher.parseOpenApiSpec(spec);
      expect(columnOf(tables, 'name_ja').isNullable, isFalse);
    });

    test('expression defaults stay unquoted (not a bogus literal)', () {
      final exprSpec = {
        'definitions': {
          't': {
            'required': <String>[],
            'properties': {
              'id': {'type': 'string', 'default': 'gen_random_uuid()'},
              'created_at': {'type': 'string', 'default': 'now()'},
            },
          },
        },
      };
      final tables = fetcher.parseOpenApiSpec(exprSpec);
      // Non-literal: stays unquoted so consumers treat it as non-default.
      expect(columnOf(tables, 'id').defaultValue, 'gen_random_uuid()');
      expect(columnOf(tables, 'id').isNullable, isFalse);
      expect(columnOf(tables, 'created_at').defaultValue, 'now()');
    });

    test('non-required column without a default stays nullable', () {
      final tables = fetcher.parseOpenApiSpec(spec);
      final rarity = columnOf(tables, 'rarity');

      expect(rarity.isNullable, isTrue);
      expect(rarity.defaultValue, isNull);
    });
  });
}
