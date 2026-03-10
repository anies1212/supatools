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
}

Map<String, dynamic> _buildSpec(Map<String, dynamic> paths) {
  return {
    'paths': paths,
    'definitions': <String, dynamic>{},
  };
}
