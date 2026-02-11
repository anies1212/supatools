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

      final limitParam =
          params.firstWhere((p) => p.name == 'limit_count');
      expect(limitParam.isRequired, isFalse);
      expect(limitParam.dataType, 'int4');

      final offsetParam =
          params.firstWhere((p) => p.name == 'offset_count');
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
}

Map<String, dynamic> _buildSpec(Map<String, dynamic> paths) {
  return {
    'paths': paths,
    'definitions': <String, dynamic>{},
  };
}
