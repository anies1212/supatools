import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/rpc_generator.dart';
import 'package:test/test.dart';

void main() {
  late RpcGenerator generator;

  setUp(() {
    generator = RpcGenerator();
  });

  group('applyReturnTypeOverrides', () {
    test('scalar type override', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_invite_code',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final result = applyReturnTypeOverrides(
        functions,
        {'get_invite_code': 'text'},
      );

      expect(result[0].returnType, 'text');
      expect(result[0].returnsSetOf, isFalse);
    });

    test('setof prefix sets returnsSetOf to true', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_items',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final result = applyReturnTypeOverrides(
        functions,
        {'get_items': 'setof jsonb'},
      );

      expect(result[0].returnType, 'jsonb');
      expect(result[0].returnsSetOf, isTrue);
    });

    test('unmatched functions remain unchanged', () {
      final functions = [
        RpcFunctionInfo(
          name: 'unrelated_func',
          params: [],
          returnType: 'int4',
          returnsSetOf: false,
        ),
      ];

      final result = applyReturnTypeOverrides(
        functions,
        {'other_func': 'text'},
      );

      expect(result[0].returnType, 'int4');
      expect(result[0].returnsSetOf, isFalse);
    });

    test('override multiple functions', () {
      final functions = [
        RpcFunctionInfo(
          name: 'func_a',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
        RpcFunctionInfo(
          name: 'func_b',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
        RpcFunctionInfo(
          name: 'func_c',
          params: [],
          returnType: 'int4',
          returnsSetOf: false,
        ),
      ];

      final result = applyReturnTypeOverrides(
        functions,
        {
          'func_a': 'bool',
          'func_b': 'setof text',
        },
      );

      expect(result[0].returnType, 'bool');
      expect(result[0].returnsSetOf, isFalse);
      expect(result[1].returnType, 'text');
      expect(result[1].returnsSetOf, isTrue);
      expect(result[2].returnType, 'int4');
      expect(result[2].returnsSetOf, isFalse);
    });

    test('explicit override to void', () {
      final functions = [
        RpcFunctionInfo(
          name: 'fire_and_forget',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];

      final result = applyReturnTypeOverrides(
        functions,
        {'fire_and_forget': 'void'},
      );

      expect(result[0].returnType, 'void');
      expect(result[0].returnsSetOf, isFalse);
    });
  });

  group('RpcGenerator', () {
    test('generates client for function with parameters', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_user_posts',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: true,
          description: 'Get posts by user',
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('class SupabaseRpcClient'));
      expect(output, contains('Future<List<Map<String, dynamic>>>'));
      expect(output, contains('getUserPosts'));
      expect(output, contains('required String userId'));
      expect(
        output,
        contains("_client.rpc<dynamic>('get_user_posts'"),
      );
      expect(output, contains("'user_id': userId"));
      expect(output, contains('/// Get posts by user'));
      expect(output, contains('response.cast<Map<String, dynamic>>()'));
    });

    test('setof function generates rawResponse to response normalization', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_items',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      // calls with rpc<dynamic>
      expect(
        output,
        contains("_client.rpc<dynamic>('get_items')"),
      );
      // normalize rawResponse to response
      expect(
        output,
        contains(
          'final response = rawResponse is List'
          ' ? rawResponse : [rawResponse];',
        ),
      );
    });

    test('RETURNS TABLE + result model also normalizes rawResponse', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_rank_info',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'rank', dataType: 'text'),
            RpcTableColumn(
              name: 'upload_days',
              dataType: 'int4',
            ),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      // rawResponse to response normalization
      expect(
        output,
        contains('rawResponse is List'),
      );
      // fromRow mapping after normalization
      expect(
        output,
        contains(
          '.map(GetRankInfoResult.fromRow).toList()',
        ),
      );
    });

    test('generates client for function without parameters', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_server_time',
          params: [],
          returnType: 'timestamptz',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('getServerTime'));
      expect(output, contains('Future<DateTime>'));
      expect(
        output,
        contains("return await _client.rpc<DateTime>('get_server_time')"),
      );
      // scalar types need no cast
      expect(output, isNot(contains('response as')));
    });

    test('generates client for void return type', () {
      final functions = [
        RpcFunctionInfo(
          name: 'cleanup_old_data',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('Future<void>'));
      expect(output, contains('cleanupOldData'));
      // void return type does not include response variable
      expect(output, isNot(contains('final response')));
      expect(output, contains("await _client.rpc<void>('cleanup_old_data')"));
    });

    test('generates client for scalar return type', () {
      final functions = [
        RpcFunctionInfo(
          name: 'count_active_users',
          params: [],
          returnType: 'int8',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('Future<int>'));
      expect(
        output,
        contains("return await _client.rpc<int>('count_active_users')"),
      );
    });

    test('generates client for setof scalar return type', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_all_ids',
          params: [],
          returnType: 'uuid',
          returnsSetOf: true,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('Future<List<String>>'));
      expect(output, contains('response.cast<String>()'));
    });

    test('snake_case to camelCase conversion', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_user_by_email_address',
          params: [
            RpcParamInfo(
              name: 'email_address',
              dataType: 'text',
              isRequired: true,
            ),
            RpcParamInfo(
              name: 'include_deleted',
              dataType: 'bool',
              isRequired: false,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('getUserByEmailAddress'));
      expect(output, contains('required String emailAddress'));
      expect(output, contains('bool? includeDeleted'));
      // parameter map uses snake_case
      expect(output, contains("'email_address': emailAddress"));
      expect(
        output,
        contains("'include_deleted': includeDeleted"),
      );
    });

    test('reserved word escaping', () {
      final functions = [
        RpcFunctionInfo(
          name: 'do_something',
          params: [
            RpcParamInfo(
              name: 'class',
              dataType: 'text',
              isRequired: true,
            ),
            RpcParamInfo(
              name: 'default',
              dataType: 'int4',
              isRequired: false,
            ),
          ],
          returnType: 'void',
        ),
      ];

      final output = generator.generateRpcClient(functions);

      // reserved words are escaped with $ suffix
      expect(output, contains(r'class$'));
      expect(output, contains(r'default$'));
    });

    test('optional parameters are output with if guard', () {
      final functions = [
        RpcFunctionInfo(
          name: 'search',
          params: [
            RpcParamInfo(
              name: 'query',
              dataType: 'text',
              isRequired: true,
            ),
            RpcParamInfo(
              name: 'limit_count',
              dataType: 'int4',
              isRequired: false,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains("'query': query"));
      expect(
        output,
        contains("if (limitCount != null) 'limit_count': limitCount"),
      );
    });

    test('generates client for boolean return type', () {
      final functions = [
        RpcFunctionInfo(
          name: 'is_active_user',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
          returnType: 'bool',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('Future<bool>'));
      expect(output, contains('isActiveUser'));
      expect(
        output,
        contains("return await _client.rpc<bool>('is_active_user'"),
      );
    });

    test('generates client for multiple functions', () {
      final functions = [
        RpcFunctionInfo(
          name: 'func_a',
          params: [],
          returnType: 'bool',
          returnsSetOf: false,
        ),
        RpcFunctionInfo(
          name: 'func_b',
          params: [],
          returnType: 'text',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('funcA'));
      expect(output, contains('funcB'));
    });

    test('includes header comment', () {
      final output = generator.generateRpcClient([]);

      expect(
        output,
        contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
      );
      expect(output, contains('Generated by suparepo'));
      expect(
        output,
        contains("import 'package:supabase_flutter/supabase_flutter.dart'"),
      );
    });

    test('does not generate inline providers', () {
      final functions = [
        RpcFunctionInfo(
          name: 'test_func',
          params: [],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, isNot(contains('@Riverpod')));
      expect(output, isNot(contains('riverpod_annotation')));
      expect(output, isNot(contains('part ')));
    });
  });

  group('RpcGenerator (DateTime serialization)', () {
    test('date parameter is converted to date-only string', () {
      final functions = [
        RpcFunctionInfo(
          name: 'toggle_receipt_for_date',
          params: [
            RpcParamInfo(
              name: 'p_date',
              dataType: 'date',
              isRequired: true,
            ),
          ],
          returnType: 'json',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('required DateTime pDate'));
      expect(
        output,
        contains(
          "'p_date': pDate.toIso8601String().split('T').first",
        ),
      );
    });

    test('timestamp parameter is converted to ISO8601 string', () {
      final functions = [
        RpcFunctionInfo(
          name: 'log_event',
          params: [
            RpcParamInfo(
              name: 'event_time',
              dataType: 'timestamp',
              isRequired: true,
            ),
          ],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('required DateTime eventTime'));
      expect(
        output,
        contains("'event_time': eventTime.toIso8601String()"),
      );
    });

    test('timestamptz parameter is converted to ISO8601 string', () {
      final functions = [
        RpcFunctionInfo(
          name: 'schedule_task',
          params: [
            RpcParamInfo(
              name: 'scheduled_at',
              dataType: 'timestamptz',
              isRequired: true,
            ),
          ],
          returnType: 'void',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(
        output,
        contains(
          "'scheduled_at': scheduledAt.toIso8601String()",
        ),
      );
    });

    test('optional date parameter uses ?. for safe access', () {
      final functions = [
        RpcFunctionInfo(
          name: 'filter_by_date',
          params: [
            RpcParamInfo(
              name: 'start_date',
              dataType: 'date',
              isRequired: false,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains('DateTime? startDate'));
      expect(
        output,
        contains(
          "'start_date': "
          "startDate.toIso8601String().split('T').first",
        ),
      );
    });

    test('non-DateTime parameters are passed as-is', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_user',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: false,
        ),
      ];

      final output = generator.generateRpcClient(functions);

      expect(output, contains("'user_id': userId,"));
      expect(
        output,
        isNot(contains('toIso8601String')),
      );
    });
  });

  group('RpcGenerator (generateResultModels)', () {
    test('functions with tableColumns get typed return values', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_my_invite_code',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'code', dataType: 'text'),
            RpcTableColumn(
              name: 'max_invites',
              dataType: 'int4',
            ),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<List<GetMyInviteCodeResult>>'),
      );
      expect(
        output,
        contains(
          'response.cast<Map<String, dynamic>>()',
        ),
      );
      expect(
        output,
        contains(
          '.map(GetMyInviteCodeResult.fromRow).toList()',
        ),
      );
      // import is added
      expect(
        output,
        contains(
          "import 'get_my_invite_code_result.dart'",
        ),
      );
    });

    test('functions without tableColumns use legacy format', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_user_posts',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<List<Map<String, dynamic>>>'),
      );
      expect(
        output,
        isNot(contains('GetUserPostsResult')),
      );
    });

    test('ignores tableColumns when generateResultModels=false', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_data',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'id', dataType: 'int4'),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: false,
      );

      expect(
        output,
        contains('Future<List<Map<String, dynamic>>>'),
      );
      expect(
        output,
        isNot(contains('GetDataResult')),
      );
    });

    test('mixed typed and Map return types', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_invite_code',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'code', dataType: 'text'),
          ],
        ),
        RpcFunctionInfo(
          name: 'get_user_posts',
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

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<List<GetInviteCodeResult>>'),
      );
      expect(
        output,
        contains('Future<List<Map<String, dynamic>>>'),
      );
      expect(output, contains('Future<int>'));
      // only typed function imports
      expect(
        output,
        contains("import 'get_invite_code_result.dart'"),
      );
      expect(
        output,
        isNot(contains(
          "import 'get_user_posts_result.dart'",
        )),
      );
    });

    test('resultModelsImportPrefix is applied', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_stats',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'total', dataType: 'int4'),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
        resultModelsImportPrefix: '../models/',
      );

      expect(
        output,
        contains(
          "import '../models/get_stats_result.dart'",
        ),
      );
    });

    test('typed function with parameters', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_user_stats',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'posts', dataType: 'int4'),
            RpcTableColumn(
              name: 'followers',
              dataType: 'int4',
            ),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<List<GetUserStatsResult>>'),
      );
      expect(output, contains('required String userId'));
      expect(
        output,
        contains(
          ".map(GetUserStatsResult.fromRow).toList()",
        ),
      );
    });
    test('returns json + YAML result_models returns single model', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_membership_rank_info',
          params: [
            RpcParamInfo(
              name: 'user_id',
              dataType: 'uuid',
              isRequired: true,
            ),
          ],
          returnType: 'json',
          returnsSetOf: false,
          tableColumns: [
            RpcTableColumn(name: 'rank', dataType: 'text'),
            RpcTableColumn(
              name: 'upload_days',
              dataType: 'int4',
            ),
            RpcTableColumn(
              name: 'is_active',
              dataType: 'bool',
            ),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      // single object return (not List)
      expect(
        output,
        contains(
          'Future<GetMembershipRankInfoResult> '
          'getMembershipRankInfo',
        ),
      );
      // calls with rpc<Map<String, dynamic>>
      expect(
        output,
        contains("rpc<Map<String, dynamic>>"),
      );
      // direct fromRow conversion (not .map().toList())
      expect(
        output,
        contains(
          'GetMembershipRankInfoResult.fromRow(response)',
        ),
      );
      expect(
        output,
        isNot(contains('.map(')),
      );
      // import
      expect(
        output,
        contains(
          "import 'get_membership_rank_info_result.dart'",
        ),
      );
    });

    test('returns json + result_models without parameters', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_app_config',
          params: [],
          returnType: 'json',
          returnsSetOf: false,
          tableColumns: [
            RpcTableColumn(
              name: 'version',
              dataType: 'text',
            ),
            RpcTableColumn(
              name: 'maintenance',
              dataType: 'bool',
            ),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<GetAppConfigResult> getAppConfig()'),
      );
      expect(
        output,
        contains('GetAppConfigResult.fromRow(response)'),
      );
    });

    test('setof json + result_models returns List<Model>', () {
      final functions = [
        RpcFunctionInfo(
          name: 'get_rankings',
          params: [],
          returnType: 'json',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(name: 'rank', dataType: 'int4'),
            RpcTableColumn(name: 'name', dataType: 'text'),
          ],
        ),
      ];

      final output = generator.generateRpcClient(
        functions,
        generateResultModels: true,
      );

      expect(
        output,
        contains('Future<List<GetRankingsResult>>'),
      );
      expect(
        output,
        contains('.map(GetRankingsResult.fromRow).toList()'),
      );
    });
  });
}
