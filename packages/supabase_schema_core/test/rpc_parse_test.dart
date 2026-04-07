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

  group('parseRpcFunctions', () {
    test('パラメータあり・setof戻り値の関数をパース', () {
      final spec = _buildSpec({
        '/rpc/get_user_posts': {
          'post': {
            'description': 'Get posts by user',
            'parameters': [
              {
                'in': 'body',
                'schema': {
                  'properties': {
                    'user_id': {
                      'type': 'string',
                      'format': 'uuid',
                    },
                  },
                  'required': ['user_id'],
                },
              },
            ],
            'responses': {
              '200': {
                'schema': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                  },
                },
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'get_user_posts');
      expect(functions[0].description, 'Get posts by user');
      expect(functions[0].returnsSetOf, isTrue);
      expect(functions[0].returnType, 'jsonb');
      expect(functions[0].params, hasLength(1));
      expect(functions[0].params[0].name, 'user_id');
      expect(functions[0].params[0].dataType, 'uuid');
      expect(functions[0].params[0].isRequired, isTrue);
    });

    test('パラメータなし関数をパース', () {
      final spec = _buildSpec({
        '/rpc/get_server_time': {
          'post': {
            'parameters': <dynamic>[],
            'responses': {
              '200': {
                'schema': {
                  'type': 'string',
                  'format': 'date-time',
                },
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'get_server_time');
      expect(functions[0].params, isEmpty);
      expect(functions[0].returnsSetOf, isFalse);
      expect(functions[0].returnType, 'timestamptz');
    });

    test('複数パラメータ + required/optional判定', () {
      final spec = _buildSpec({
        '/rpc/search_users': {
          'post': {
            'parameters': [
              {
                'in': 'body',
                'schema': {
                  'properties': {
                    'query': {
                      'type': 'string',
                      'format': 'text',
                    },
                    'limit_count': {
                      'type': 'integer',
                      'format': 'int32',
                    },
                    'offset_count': {
                      'type': 'integer',
                      'format': 'int32',
                    },
                  },
                  'required': ['query'],
                },
              },
            ],
            'responses': {
              '200': {
                'schema': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                  },
                },
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      final params = functions[0].params;
      expect(params, hasLength(3));

      final queryParam = params.firstWhere((p) => p.name == 'query');
      expect(queryParam.isRequired, isTrue);
      expect(queryParam.dataType, 'text');

      final limitParam = params.firstWhere((p) => p.name == 'limit_count');
      expect(limitParam.isRequired, isFalse);
      expect(limitParam.dataType, 'int4');

      final offsetParam = params.firstWhere((p) => p.name == 'offset_count');
      expect(offsetParam.isRequired, isFalse);
    });

    test('スカラー戻り値をパース', () {
      final spec = _buildSpec({
        '/rpc/count_active_users': {
          'post': {
            'parameters': <dynamic>[],
            'responses': {
              '200': {
                'schema': {
                  'type': 'integer',
                  'format': 'int64',
                },
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].returnsSetOf, isFalse);
      expect(functions[0].returnType, 'int8');
    });

    test('void戻り値をパース', () {
      final spec = _buildSpec({
        '/rpc/cleanup_old_data': {
          'post': {
            'parameters': <dynamic>[],
            'responses': {
              '200': <String, dynamic>{},
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].returnType, 'void');
      expect(functions[0].returnsSetOf, isFalse);
    });

    test('/rpc/以外のパスは無視', () {
      final spec = _buildSpec({
        '/users': {
          'get': {
            'responses': {
              '200': {
                'schema': {'type': 'array'},
              },
            },
          },
        },
        '/rpc/my_func': {
          'post': {
            'parameters': <dynamic>[],
            'responses': {
              '200': {
                'schema': {'type': 'boolean'},
              },
            },
          },
        },
        '/posts': {
          'get': {
            'responses': {
              '200': {
                'schema': {'type': 'array'},
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].name, 'my_func');
    });

    test('複数RPC関数をパース', () {
      final spec = _buildSpec({
        '/rpc/func_a': {
          'post': {
            'parameters': <dynamic>[],
            'responses': {
              '200': {
                'schema': {'type': 'boolean'},
              },
            },
          },
        },
        '/rpc/func_b': {
          'post': {
            'parameters': [
              {
                'in': 'body',
                'schema': {
                  'properties': {
                    'id': {
                      'type': 'string',
                      'format': 'uuid',
                    },
                  },
                  'required': ['id'],
                },
              },
            ],
            'responses': {
              '200': {
                'schema': {
                  'type': 'string',
                  'format': 'text',
                },
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(2));
      expect(functions.map((f) => f.name), containsAll(['func_a', 'func_b']));
    });

    test('bodyパラメータがない場合は空のパラメータリスト', () {
      final spec = _buildSpec({
        '/rpc/no_body': {
          'post': {
            'parameters': [
              {
                'in': 'header',
                'name': 'Prefer',
                'type': 'string',
              },
            ],
            'responses': {
              '200': {
                'schema': {'type': 'string'},
              },
            },
          },
        },
      });

      final functions = fetcher.parseRpcFunctions(spec);

      expect(functions, hasLength(1));
      expect(functions[0].params, isEmpty);
    });

    test('pathsが空の場合は空リスト', () {
      final spec = <String, dynamic>{
        'paths': <String, dynamic>{},
      };

      final functions = fetcher.parseRpcFunctions(spec);
      expect(functions, isEmpty);
    });

    test('pathsキーがない場合は空リスト', () {
      final spec = <String, dynamic>{};

      final functions = fetcher.parseRpcFunctions(spec);
      expect(functions, isEmpty);
    });
  });

  group('mergeReturnTypes', () {
    test('voidをboolに補正', () {
      final functions = [
        RpcFunctionInfo(
          name: 'is_active',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'is_active': (typeName: 'bool', returnsSet: false),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'bool');
      expect(result[0].returnsSetOf, isFalse);
    });

    test('voidをint4に補正', () {
      final functions = [
        RpcFunctionInfo(
          name: 'count_items',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'count_items': (typeName: 'int4', returnsSet: false),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'int4');
      expect(result[0].returnsSetOf, isFalse);
    });

    test('非voidはそのまま維持', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_count',
          params: [],
          returnType: 'int8',
        ),
      ];
      final pgTypes = {
        'get_count': (typeName: 'int4', returnsSet: false),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'int8');
    });

    test('pg_proc結果が空でも壊れない', () {
      final functions = [
        RpcFunctionInfo(
          name: 'my_func',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = <String, ({String typeName, bool returnsSet})>{};

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'void');
    });

    test('record型(非setof)はvoidのまま維持', () {
      final functions = [
        RpcFunctionInfo(
          name: 'do_something',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'do_something': (typeName: 'record', returnsSet: false),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'void');
    });

    test('record型 + returnsSet(RETURNS TABLE)はsetof jsonbに補正', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_statuses',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'get_statuses': (typeName: 'record', returnsSet: true),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'jsonb');
      expect(result[0].returnsSetOf, isTrue);
    });

    test('returnsSetも補正される', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_names',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'get_names': (typeName: 'text', returnsSet: true),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'text');
      expect(result[0].returnsSetOf, isTrue);
    });

    test('複数関数の混在ケース', () {
      final functions = [
        RpcFunctionInfo(
          name: 'is_active',
          params: [],
          returnType: 'void',
        ),
        RpcFunctionInfo(
          name: 'get_count',
          params: [],
          returnType: 'int8',
        ),
        RpcFunctionInfo(
          name: 'cleanup',
          params: [],
          returnType: 'void',
        ),
      ];
      final pgTypes = {
        'is_active': (typeName: 'bool', returnsSet: false),
        'get_count': (typeName: 'int4', returnsSet: false),
        'cleanup': (typeName: 'record', returnsSet: false),
      };

      final result = SchemaFetcher.mergeReturnTypes(
        functions,
        pgTypes,
      );

      expect(result[0].returnType, 'bool');
      expect(result[1].returnType, 'int8');
      expect(result[2].returnType, 'void');
    });
  });

  group('mergeTableColumns', () {
    test('該当する関数にtableColumnsをマージ', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_invite_code',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
        RpcFunctionInfo(
          name: 'count_items',
          params: [],
          returnType: 'int4',
        ),
      ];
      final tableColumnsMap = {
        'get_invite_code': [
          RpcTableColumn(name: 'code', dataType: 'text'),
          RpcTableColumn(name: 'max_invites', dataType: 'int4'),
        ],
      };

      final result = SchemaFetcher.mergeTableColumns(
        functions,
        tableColumnsMap,
      );

      expect(result[0].tableColumns, isNotNull);
      expect(result[0].tableColumns, hasLength(2));
      expect(result[0].tableColumns![0].name, 'code');
      expect(result[0].tableColumns![0].dataType, 'text');
      expect(result[0].tableColumns![1].name, 'max_invites');
      expect(result[0].tableColumns![1].dataType, 'int4');
      expect(result[1].tableColumns, isNull);
    });

    test('空のマップでも壊れない', () {
      final functions = [
        RpcFunctionInfo(
          name: 'my_func',
          params: [],
          returnType: 'void',
        ),
      ];
      final tableColumnsMap = <String, List<RpcTableColumn>>{};

      final result = SchemaFetcher.mergeTableColumns(
        functions,
        tableColumnsMap,
      );

      expect(result[0].tableColumns, isNull);
    });

    test('複数関数への一括マージ', () {
      final functions = [
        RpcFunctionInfo(
          name: 'func_a',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
        RpcFunctionInfo(
          name: 'func_b',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];
      final tableColumnsMap = {
        'func_a': [
          RpcTableColumn(name: 'id', dataType: 'int4'),
        ],
        'func_b': [
          RpcTableColumn(name: 'name', dataType: 'text'),
          RpcTableColumn(name: 'active', dataType: 'bool'),
        ],
      };

      final result = SchemaFetcher.mergeTableColumns(
        functions,
        tableColumnsMap,
      );

      expect(result[0].tableColumns, hasLength(1));
      expect(result[1].tableColumns, hasLength(2));
    });

    test('既存のreturnType/returnsSetOfは維持される', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_data',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: true,
          description: 'Get data',
        ),
      ];
      final tableColumnsMap = {
        'get_data': [
          RpcTableColumn(name: 'col1', dataType: 'text'),
        ],
      };

      final result = SchemaFetcher.mergeTableColumns(
        functions,
        tableColumnsMap,
      );

      expect(result[0].returnType, 'jsonb');
      expect(result[0].returnsSetOf, isTrue);
      expect(result[0].description, 'Get data');
      expect(result[0].params, hasLength(1));
      expect(result[0].tableColumns, hasLength(1));
    });
  });

  group('parseJsonBuildObject', () {
    test('basic json_build_object with variable types', () {
      final source = '''
DECLARE
  v_rank text;
  v_upload_days int4;
  v_is_active bool;
BEGIN
  RETURN json_build_object(
    'rank', v_rank,
    'upload_days', v_upload_days,
    'is_active', v_is_active
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(3));
      expect(columns[0].name, 'rank');
      expect(columns[0].dataType, 'text');
      expect(columns[1].name, 'upload_days');
      expect(columns[1].dataType, 'int4');
      expect(columns[2].name, 'is_active');
      expect(columns[2].dataType, 'bool');
    });

    test('jsonb_build_object also supported', () {
      final source = '''
DECLARE
  v_total int4;
  v_name text;
BEGIN
  RETURN jsonb_build_object('total', v_total, 'name', v_name);
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'total');
      expect(columns[0].dataType, 'int4');
      expect(columns[1].name, 'name');
      expect(columns[1].dataType, 'text');
    });

    test('type cast expressions', () {
      final source = '''
BEGIN
  RETURN json_build_object(
    'count', some_expr::int4,
    'ratio', other_expr::float8
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'count');
      expect(columns[0].dataType, 'int4');
      expect(columns[1].name, 'ratio');
      expect(columns[1].dataType, 'float8');
    });

    test('nested function calls are handled', () {
      final source = '''
DECLARE
  v_rank text;
BEGIN
  RETURN json_build_object(
    'rank', v_rank,
    'created_at', now()
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'rank');
      expect(columns[0].dataType, 'text');
      // now() falls back to text since no variable match
      expect(columns[1].name, 'created_at');
      expect(columns[1].dataType, 'text');
    });

    test('array types in declarations', () {
      final source = '''
DECLARE
  v_flags boolean[];
  v_scores int4[];
BEGIN
  RETURN json_build_object(
    'flags', v_flags,
    'scores', v_scores
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'flags');
      expect(columns[0].dataType, 'boolean[]');
      expect(columns[1].name, 'scores');
      expect(columns[1].dataType, 'int4[]');
    });

    test('coalesce(..., false) → bool', () {
      final source = '''
BEGIN
  RETURN json_build_object(
    'date', g.d::date,
    'uploaded', coalesce(
      (select true from t1),
      (select true from t2),
      false
    )
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'date');
      expect(columns[0].dataType, 'date');
      expect(columns[1].name, 'uploaded');
      expect(columns[1].dataType, 'bool');
    });

    test('coalesce(..., 0) → int4', () {
      final source = '''
BEGIN
  RETURN json_build_object(
    'count', coalesce(v_count, 0)
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(1));
      expect(columns[0].name, 'count');
      expect(columns[0].dataType, 'int4');
    });

    test('NOT expr → bool', () {
      final source = '''
BEGIN
  RETURN json_build_object(
    'is_new', not v_exists
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(1));
      expect(columns[0].name, 'is_new');
      expect(columns[0].dataType, 'bool');
    });

    test('EXISTS(...) → bool', () {
      final source = '''
BEGIN
  RETURN json_build_object(
    'has_items', exists(select 1 from items)
  );
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(1));
      expect(columns[0].name, 'has_items');
      expect(columns[0].dataType, 'bool');
    });

    test('no json_build_object returns empty', () {
      final source = '''
BEGIN
  RETURN query_result;
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);
      expect(columns, isEmpty);
    });

    test('variable with DEFAULT assignment', () {
      final source = '''
DECLARE
  v_count int4 DEFAULT 0;
  v_label text := 'default';
BEGIN
  RETURN json_build_object('count', v_count, 'label', v_label);
END;
''';

      final columns = SchemaFetcher.parseJsonBuildObject(source);

      expect(columns, hasLength(2));
      expect(columns[0].name, 'count');
      expect(columns[0].dataType, 'int4');
      expect(columns[1].name, 'label');
      expect(columns[1].dataType, 'text');
    });
  });

  group('parseRpcErrorCodes', () {
    test('return query select false パターン', () {
      final source = '''
BEGIN
  IF condition1 THEN
    return query select false, 'daily_limit_exceeded'::text;
  END IF;
  IF condition2 THEN
    return query select false, 'insufficient_balance'::text;
  END IF;
  return query select true, ''::text;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);

      expect(codes, hasLength(2));
      expect(codes, contains('daily_limit_exceeded'));
      expect(codes, contains('insufficient_balance'));
    });

    test('return query select false::bool パターン', () {
      final source = '''
BEGIN
  return query select false::bool, 'account_age_requirement'::text;
  return query select true::bool, ''::text;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);

      expect(codes, hasLength(1));
      expect(codes, contains('account_age_requirement'));
    });

    test('error := パターン', () {
      final source = '''
DECLARE
  error text;
BEGIN
  error := 'rate_limited';
  error := 'invalid_input';
  return query select false, error;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);

      expect(codes, hasLength(2));
      expect(codes, contains('rate_limited'));
      expect(codes, contains('invalid_input'));
    });

    test('空文字列と非snake_caseは無視', () {
      final source = '''
BEGIN
  return query select false, ''::text;
  return query select false, 'This is not a code'::text;
  return query select false, 'valid_code'::text;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);

      expect(codes, hasLength(1));
      expect(codes, contains('valid_code'));
    });

    test('エラーコードなしは空リスト', () {
      final source = '''
BEGIN
  return query select true, ''::text;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);
      expect(codes, isEmpty);
    });

    test('重複コードは除去される', () {
      final source = '''
BEGIN
  return query select false, 'same_error'::text;
  return query select false, 'same_error'::text;
END;
''';

      final codes = SchemaFetcher.parseRpcErrorCodes(source);
      expect(codes, hasLength(1));
    });
  });

  group('parseNestedJsonColumns', () {
    test('json_agg(json_build_object(...)) as alias', () {
      final source = '''
BEGIN
  return query
  select
    (select json_agg(
      json_build_object(
        'date', g.d::date,
        'uploaded', g.flag::bool
      )
    ) from generate_series(1,7) as g(d,flag)
    ) as v_calendar
  from computed;
END;
''';

      final result =
          SchemaFetcher.parseNestedJsonColumns(source);

      expect(result, contains('calendar'));
      final info = result['calendar']!;
      expect(info.isArray, isTrue);
      expect(info.columns, hasLength(2));
      expect(info.columns[0].name, 'date');
      expect(info.columns[0].dataType, 'date');
      expect(info.columns[1].name, 'uploaded');
    });

    test('json_agg パターンなしは空マップ', () {
      final source = '''
BEGIN
  return query select 1;
END;
''';

      final result =
          SchemaFetcher.parseNestedJsonColumns(source);
      expect(result, isEmpty);
    });

    test('jsonb_agg(jsonb_build_object(...))', () {
      final source = '''
BEGIN
  select jsonb_agg(
    jsonb_build_object('id', v.id::int4, 'name', v.name::text)
  ) as v_items
  from vals v;
END;
''';

      final result =
          SchemaFetcher.parseNestedJsonColumns(source);

      expect(result, contains('items'));
      final info = result['items']!;
      expect(info.isArray, isTrue);
      expect(info.columns, hasLength(2));
      expect(info.columns[0].name, 'id');
      expect(info.columns[0].dataType, 'int4');
      expect(info.columns[1].name, 'name');
      expect(info.columns[1].dataType, 'text');
    });
  });
}

Map<String, dynamic> _buildSpec(Map<String, dynamic> paths) {
  return {
    'paths': paths,
    'definitions': <String, dynamic>{},
  };
}
