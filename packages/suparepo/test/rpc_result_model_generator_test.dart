import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/rpc_result_model_generator.dart';
import 'package:test/test.dart';

void main() {
  late RpcResultModelGenerator generator;

  setUp(() {
    generator = RpcResultModelGenerator();
  });

  group('resultClassName', () {
    test('snake_case→PascalCase+Result', () {
      expect(
        RpcResultModelGenerator.resultClassName(
          'get_my_invite_code',
        ),
        'GetMyInviteCodeResult',
      );
    });

    test('single word', () {
      expect(
        RpcResultModelGenerator.resultClassName('status'),
        'StatusResult',
      );
    });
  });

  group('resultFileName', () {
    test('function_name + _result.dart', () {
      expect(
        RpcResultModelGenerator.resultFileName(
          'get_my_invite_code',
        ),
        'get_my_invite_code_result.dart',
      );
    });
  });

  group('generateResultModel', () {
    test('returns null when tableColumns is null', () {
      final func = RpcFunctionInfo(
        name: 'no_table',
        params: [],
        returnType: 'int4',
      );

      expect(generator.generateResultModel(func), isNull);
    });

    test('returns null when tableColumns is empty', () {
      final func = RpcFunctionInfo(
        name: 'empty_table',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [],
      );

      expect(generator.generateResultModel(func), isNull);
    });

    test('generates basic Freezed model', () {
      final func = RpcFunctionInfo(
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
          RpcTableColumn(
            name: 'is_active',
            dataType: 'bool',
          ),
        ],
      );

      final output = generator.generateResultModel(func);

      expect(output, isNotNull);
      expect(
        output,
        contains('GENERATED CODE - DO NOT MODIFY BY HAND'),
      );
      expect(
        output,
        contains(
          "import 'package:freezed_annotation/"
          "freezed_annotation.dart'",
        ),
      );
      expect(
        output,
        contains(
          "part 'get_my_invite_code_result.freezed.dart'",
        ),
      );
      expect(output, contains('@freezed'));
      expect(
        output,
        contains(
          'abstract class GetMyInviteCodeResult '
          'with _\$GetMyInviteCodeResult',
        ),
      );
      expect(
        output,
        contains('required String code,'),
      );
      expect(
        output,
        contains('required int maxInvites,'),
      );
      expect(
        output,
        contains('required bool isActive,'),
      );
      expect(
        output,
        contains(') = _GetMyInviteCodeResult;'),
      );
      // fromRow
      expect(
        output,
        contains(
          'factory GetMyInviteCodeResult.fromRow('
          'Map<String, dynamic> row)',
        ),
      );
      expect(
        output,
        contains("code: row['code'] as String,"),
      );
      expect(
        output,
        contains(
          "maxInvites: row['max_invites'] as int,",
        ),
      );
      expect(
        output,
        contains(
          "isActive: row['is_active'] as bool,",
        ),
      );
    });

    test('DateTime column type', () {
      final func = RpcFunctionInfo(
        name: 'get_events',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'name', dataType: 'text'),
          RpcTableColumn(
            name: 'created_at',
            dataType: 'timestamptz',
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      expect(output, contains('required DateTime createdAt,'));
      expect(
        output,
        contains(
          "createdAt: DateTime.parse("
          "row['created_at'] as String),",
        ),
      );
    });

    test('jsonb column maps to dynamic (RPC result model only)', () {
      final func = RpcFunctionInfo(
        name: 'get_data',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(
            name: 'metadata',
            dataType: 'jsonb',
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      // field type is dynamic
      expect(
        output,
        contains(
          'required dynamic metadata,',
        ),
      );
      // fromRow has no as cast
      expect(
        output,
        contains("metadata: row['metadata'],"),
      );
      // as dynamic is redundant, should not be present
      expect(
        output,
        isNot(contains("as dynamic")),
      );
    });

    test('json column also maps to dynamic (for json_agg arrays)', () {
      final func = RpcFunctionInfo(
        name: 'get_detail',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'calendar', dataType: 'json'),
        ],
      );

      final output = generator.generateResultModel(func)!;

      expect(
        output,
        contains('required dynamic calendar,'),
      );
      expect(
        output,
        contains("calendar: row['calendar'],"),
      );
    });

    test('RETURNS TABLE with mixed json/non-json columns', () {
      final func = RpcFunctionInfo(
        name: 'get_membership_rank_detail',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'rank', dataType: 'text'),
          RpcTableColumn(
            name: 'upload_days',
            dataType: 'int4',
          ),
          RpcTableColumn(
            name: 'calendar',
            dataType: 'json',
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      // text/int4 use standard type mapping
      expect(
        output,
        contains('required String rank,'),
      );
      expect(
        output,
        contains('required int uploadDays,'),
      );
      // json maps to dynamic
      expect(
        output,
        contains('required dynamic calendar,'),
      );
      // fromRow: text/int4 have as cast
      expect(
        output,
        contains("rank: row['rank'] as String,"),
      );
      expect(
        output,
        contains(
          "uploadDays: row['upload_days'] as int,",
        ),
      );
      // fromRow: json has no as cast
      expect(
        output,
        contains("calendar: row['calendar'],"),
      );
    });

    test('doc comment includes function name', () {
      final func = RpcFunctionInfo(
        name: 'get_stats',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'count', dataType: 'int4'),
        ],
      );

      final output = generator.generateResultModel(func)!;

      expect(
        output,
        contains('/// Response model for `get_stats` RPC.'),
      );
    });
  });

  group('nullable columns', () {
    test('nullable scalar becomes Type? and is not required', () {
      final func = RpcFunctionInfo(
        name: 'list_cards_with_top_price',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'card_master_id', dataType: 'int8'),
          RpcTableColumn(
            name: 'image_url',
            dataType: 'text',
            nullable: true,
          ),
          RpcTableColumn(
            name: 'top_price',
            dataType: 'int4',
            nullable: true,
          ),
          RpcTableColumn(name: 'store_count', dataType: 'int4'),
        ],
      );

      final output = generator.generateResultModel(func)!;

      // non-null columns stay required
      expect(output, contains('required int cardMasterId,'));
      expect(output, contains('required int storeCount,'));
      // nullable columns become optional Type?
      expect(output, contains('String? imageUrl,'));
      expect(output, contains('int? topPrice,'));
      expect(output, isNot(contains('required String? imageUrl,')));
      // required declared before optional
      expect(
        output.indexOf('required int storeCount,'),
        lessThan(output.indexOf('String? imageUrl,')),
      );
      // fromRow uses null-safe casts
      expect(output, contains("imageUrl: row['image_url'] as String?,"));
      expect(output, contains("topPrice: row['top_price'] as int?,"));
    });

    test('nullable DateTime is null-safe in fromRow', () {
      final func = RpcFunctionInfo(
        name: 'get_card_comparison',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'store_id', dataType: 'int8'),
          RpcTableColumn(
            name: 'captured_at',
            dataType: 'timestamptz',
            nullable: true,
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      expect(output, contains('DateTime? capturedAt,'));
      expect(
        output,
        contains(
          "capturedAt: row['captured_at'] != null"
          " ? DateTime.parse(row['captured_at'] as String)"
          " : null,",
        ),
      );
    });
  });

  group('generateAllResultModels', () {
    test('generates only for functions with tableColumns', () {
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
          name: 'count_items',
          params: [],
          returnType: 'int4',
        ),
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

      final result = generator.generateAllResultModels(functions);

      expect(result, hasLength(2));
      expect(
        result.containsKey('get_invite_code_result.dart'),
        isTrue,
      );
      expect(
        result.containsKey('get_stats_result.dart'),
        isTrue,
      );
      expect(
        result.containsKey('count_items_result.dart'),
        isFalse,
      );
    });

    test('returns empty map when no functions have tableColumns', () {
      final functions = [
        RpcFunctionInfo(
          name: 'simple_func',
          params: [],
          returnType: 'bool',
        ),
      ];

      final result = generator.generateAllResultModels(functions);

      expect(result, isEmpty);
    });
  });

  group('generateErrorClass', () {
    test('generates sealed error class', () {
      final func = RpcFunctionInfo(
        name: 'execute_exchange_atomic',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'success', dataType: 'bool'),
          RpcTableColumn(name: 'error', dataType: 'text'),
        ],
        errorCodes: [
          'daily_limit_exceeded',
          'insufficient_balance',
        ],
      );

      final output = generator.generateErrorClass(func)!;

      // sealed class
      expect(
        output,
        contains(
          'sealed class ExecuteExchangeAtomicError',
        ),
      );
      // named constructors
      expect(
        output,
        contains(
          'ExecuteExchangeAtomicError.dailyLimitExceeded()',
        ),
      );
      expect(
        output,
        contains(
          'ExecuteExchangeAtomicError.insufficientBalance()',
        ),
      );
      // unknown variant
      expect(
        output,
        contains(
          'ExecuteExchangeAtomicError.unknown({',
        ),
      );
      expect(
        output,
        contains('required String code,'),
      );
      // fromErrorCode factory
      expect(
        output,
        contains(
          'ExecuteExchangeAtomicError.fromErrorCode(',
        ),
      );
      // switch cases
      expect(
        output,
        contains("'daily_limit_exceeded' =>"),
      );
      expect(
        output,
        contains("'insufficient_balance' =>"),
      );
      // Freezed annotation
      expect(output, contains('@freezed'));
      expect(output, contains('.freezed.dart'));
    });

    test('returns null when errorCodes is null', () {
      final func = RpcFunctionInfo(
        name: 'get_data',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'data', dataType: 'text'),
        ],
      );

      expect(generator.generateErrorClass(func), isNull);
    });

    test('returns null when errorCodes is empty', () {
      final func = RpcFunctionInfo(
        name: 'get_data',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'error', dataType: 'text'),
        ],
        errorCodes: [],
      );

      expect(generator.generateErrorClass(func), isNull);
    });
  });

  group('generateResultModel with errorCodes', () {
    test('error column is replaced with error type', () {
      final func = RpcFunctionInfo(
        name: 'execute_exchange_atomic',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(
            name: 'success',
            dataType: 'bool',
          ),
          RpcTableColumn(
            name: 'error',
            dataType: 'text',
          ),
        ],
        errorCodes: [
          'daily_limit_exceeded',
          'insufficient_balance',
        ],
      );

      final output = generator.generateResultModel(func)!;

      // error field uses error type
      expect(
        output,
        contains(
          'required ExecuteExchangeAtomicError error,',
        ),
      );
      // fromRow uses fromErrorCode conversion
      expect(
        output,
        contains(
          'ExecuteExchangeAtomicError.fromErrorCode('
          "row['error'] as String)",
        ),
      );
      // import
      expect(
        output,
        contains(
          "import 'execute_exchange_atomic_error.dart'",
        ),
      );
      // success remains a normal bool
      expect(
        output,
        contains('required bool success,'),
      );
    });
  });

  group('generateAllErrorClasses', () {
    test('generates only for functions with errorCodes', () {
      final functions = [
        RpcFunctionInfo(
          name: 'execute_exchange',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(
              name: 'success',
              dataType: 'bool',
            ),
            RpcTableColumn(
              name: 'error',
              dataType: 'text',
            ),
          ],
          errorCodes: ['some_error'],
        ),
        RpcFunctionInfo(
          name: 'get_data',
          params: [],
          returnType: 'jsonb',
          returnsSetOf: true,
          tableColumns: [
            RpcTableColumn(
              name: 'value',
              dataType: 'text',
            ),
          ],
        ),
      ];

      final result = generator.generateAllErrorClasses(functions);

      expect(result, hasLength(1));
      expect(
        result.containsKey('execute_exchange_error.dart'),
        isTrue,
      );
    });
  });

  group('nested json column model generation', () {
    test('json_agg column becomes List<NestedModel>', () {
      final func = RpcFunctionInfo(
        name: 'get_membership_rank_detail',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(name: 'rank', dataType: 'text'),
          RpcTableColumn(
            name: 'calendar',
            dataType: 'json',
            isArray: true,
            nestedColumns: [
              RpcTableColumn(
                name: 'date',
                dataType: 'date',
              ),
              RpcTableColumn(
                name: 'uploaded',
                dataType: 'bool',
              ),
            ],
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      // field type is List<NestedModel>
      expect(
        output,
        contains(
          'required List<'
          'GetMembershipRankDetailResultCalendarItem>'
          ' calendar,',
        ),
      );
      // fromRow maps List<dynamic>
      expect(
        output,
        contains(
          "(row['calendar'] as List<dynamic>)",
        ),
      );
      expect(
        output,
        contains(
          'GetMembershipRankDetailResultCalendarItem'
          '.fromRow(',
        ),
      );
      // nested model class generated in the same file
      expect(
        output,
        contains(
          'abstract class '
          'GetMembershipRankDetailResultCalendarItem',
        ),
      );
      expect(
        output,
        contains('required DateTime date,'),
      );
      expect(
        output,
        contains('required bool uploaded,'),
      );
      // nested model fromRow
      expect(
        output,
        contains(
          "date: DateTime.parse("
          "row['date'] as String),",
        ),
      );
      expect(
        output,
        contains(
          "uploaded: row['uploaded'] as bool,",
        ),
      );
      // normal columns are unaffected
      expect(
        output,
        contains('required String rank,'),
      );
    });

    test('json without nestedColumns remains dynamic', () {
      final func = RpcFunctionInfo(
        name: 'get_data',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [
          RpcTableColumn(
            name: 'metadata',
            dataType: 'json',
          ),
        ],
      );

      final output = generator.generateResultModel(func)!;

      expect(
        output,
        contains('required dynamic metadata,'),
      );
      expect(
        output,
        isNot(contains('Item')),
      );
    });
  });
}
