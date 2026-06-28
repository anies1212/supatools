import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:test/test.dart';

void main() {
  group('rowsFromAggregatedResponse', () {
    test('returns rows as-is for EXECUTE ... INTO style execute_sql', () {
      // `EXECUTE 'SELECT json_agg(sub) ...' INTO result` yields the array
      // directly.
      final response = [
        {
          'function_name': 'get_a',
          'return_type': 'record',
          'returns_set': true
        },
        {'function_name': 'get_b', 'return_type': 'int4', 'returns_set': false},
      ];

      final rows = SchemaFetcher.rowsFromAggregatedResponse(response);

      expect(rows, hasLength(2));
      expect(rows.first['function_name'], 'get_a');
    });

    test('unwraps the double-wrapped jsonb_agg(t) style execute_sql', () {
      // A `select jsonb_agg(t) from (SELECT json_agg(sub) ...) t` helper
      // wraps the inner json_agg array once more.
      final response = [
        {
          'json_agg': [
            {'function_name': 'get_a', 'return_type': 'record'},
            {'function_name': 'get_b', 'return_type': 'int4'},
          ],
        },
      ];

      final rows = SchemaFetcher.rowsFromAggregatedResponse(response);

      expect(rows, hasLength(2));
      expect(rows.first['function_name'], 'get_a');
      expect(rows.last['return_type'], 'int4');
    });

    test('returns empty list when response is null', () {
      expect(SchemaFetcher.rowsFromAggregatedResponse(null), isEmpty);
    });

    test('does not unwrap a genuine single-row result', () {
      // A real one-row result whose map happens to have multiple keys must
      // not be mistaken for the json_agg wrapper.
      final response = [
        {'function_name': 'only_one', 'return_type': 'jsonb'},
      ];

      final rows = SchemaFetcher.rowsFromAggregatedResponse(response);

      expect(rows, hasLength(1));
      expect(rows.first['function_name'], 'only_one');
    });

    test('treats empty json_agg wrapper as no rows', () {
      final response = [
        {'json_agg': <dynamic>[]},
      ];
      expect(SchemaFetcher.rowsFromAggregatedResponse(response), isEmpty);
    });
  });

  group('applyResultModels', () {
    RpcFunctionInfo func(String name, List<RpcTableColumn>? cols) =>
        RpcFunctionInfo(
          name: name,
          params: const [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: cols,
        );

    test('keeps introspected columns the override does not mention', () {
      // get_card_comparison: introspection finds all 12 columns; the
      // override only specifies nullability for a subset. The location
      // columns must survive (regression guard for dropped columns).
      final functions = [
        func('get_card_comparison', const [
          RpcTableColumn(name: 'store_id', dataType: 'int8'),
          RpcTableColumn(name: 'store_name', dataType: 'text'),
          RpcTableColumn(name: 'store_address', dataType: 'text'),
          RpcTableColumn(name: 'latitude', dataType: 'float8'),
          RpcTableColumn(name: 'longitude', dataType: 'float8'),
        ]),
      ];
      final overrides = {
        'get_card_comparison': const [
          RpcTableColumn(name: 'store_id', dataType: 'int8'),
          RpcTableColumn(name: 'store_name', dataType: 'text'),
        ],
      };

      final result =
          SchemaFetcher.applyResultModels(functions, overrides).single;

      expect(
        result.tableColumns!.map((c) => c.name),
        ['store_id', 'store_name', 'store_address', 'latitude', 'longitude'],
      );
    });

    test('overrides nullability and type for named columns', () {
      final functions = [
        func('get_x', const [
          RpcTableColumn(name: 'a', dataType: 'int8'),
          RpcTableColumn(name: 'b', dataType: 'text'),
        ]),
      ];
      final overrides = {
        'get_x': const [
          RpcTableColumn(name: 'b', dataType: 'int4', nullable: true),
        ],
      };

      final cols = SchemaFetcher.applyResultModels(functions, overrides)
          .single
          .tableColumns!;

      expect(cols.firstWhere((c) => c.name == 'a').nullable, isFalse);
      final b = cols.firstWhere((c) => c.name == 'b');
      expect(b.nullable, isTrue);
      expect(b.dataType, 'int4');
    });

    test('appends override columns missing from introspection', () {
      final functions = [
        func('get_x', const [
          RpcTableColumn(name: 'a', dataType: 'int8'),
        ]),
      ];
      final overrides = {
        'get_x': const [
          RpcTableColumn(name: 'extra', dataType: 'text', nullable: true),
        ],
      };

      final cols = SchemaFetcher.applyResultModels(functions, overrides)
          .single
          .tableColumns!;

      expect(cols.map((c) => c.name), ['a', 'extra']);
    });

    test('uses override as full definition when introspection found nothing',
        () {
      final functions = [func('get_x', null)];
      final overrides = {
        'get_x': const [
          RpcTableColumn(name: 'a', dataType: 'int8'),
          RpcTableColumn(name: 'b', dataType: 'text', nullable: true),
        ],
      };

      final cols = SchemaFetcher.applyResultModels(functions, overrides)
          .single
          .tableColumns!;

      expect(cols.map((c) => c.name), ['a', 'b']);
    });

    test('leaves functions without an override entry unchanged', () {
      final original = func('untouched', const [
        RpcTableColumn(name: 'a', dataType: 'int8'),
      ]);

      final result = SchemaFetcher.applyResultModels([original], const {});

      expect(result.single, same(original));
    });
  });
}
