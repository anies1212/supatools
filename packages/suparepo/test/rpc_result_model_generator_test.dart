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

    test('単一単語', () {
      expect(
        RpcResultModelGenerator.resultClassName('status'),
        'StatusResult',
      );
    });
  });

  group('resultFileName', () {
    test('関数名+_result.dart', () {
      expect(
        RpcResultModelGenerator.resultFileName(
          'get_my_invite_code',
        ),
        'get_my_invite_code_result.dart',
      );
    });
  });

  group('generateResultModel', () {
    test('tableColumnsがnullの場合はnull', () {
      final func = RpcFunctionInfo(
        name: 'no_table',
        params: [],
        returnType: 'int4',
      );

      expect(generator.generateResultModel(func), isNull);
    });

    test('tableColumnsが空の場合はnull', () {
      final func = RpcFunctionInfo(
        name: 'empty_table',
        params: [],
        returnType: 'jsonb',
        returnsSetOf: true,
        tableColumns: [],
      );

      expect(generator.generateResultModel(func), isNull);
    });

    test('基本的なFreezedモデル生成', () {
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

    test('DateTime型の列', () {
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

    test('jsonb型の列はdynamic（RPC result modelのみ）', () {
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

      // フィールド型は dynamic
      expect(
        output,
        contains(
          'required dynamic metadata,',
        ),
      );
      // fromRow で as キャストなし
      expect(
        output,
        contains("metadata: row['metadata'],"),
      );
      // as dynamic は冗長なので含まない
      expect(
        output,
        isNot(contains("as dynamic")),
      );
    });

    test('json型の列もdynamic（json_agg等の配列対応）', () {
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

    test('RETURNS TABLE に json/非json カラム混在', () {
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

      // text/int4 は通常の型マッピング
      expect(
        output,
        contains('required String rank,'),
      );
      expect(
        output,
        contains('required int uploadDays,'),
      );
      // json は dynamic
      expect(
        output,
        contains('required dynamic calendar,'),
      );
      // fromRow: text/int4 は as キャスト
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
      // fromRow: json は as キャストなし
      expect(
        output,
        contains("calendar: row['calendar'],"),
      );
    });

    test('docコメントに関数名が含まれる', () {
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
        contains('/// `get_stats` RPC のレスポンスモデル。'),
      );
    });
  });

  group('generateAllResultModels', () {
    test('tableColumnsを持つ関数のみ生成', () {
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

    test('tableColumnsを持つ関数がない場合は空マップ', () {
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
    test('sealed error class を生成', () {
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

    test('errorCodes が null なら null を返す', () {
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

    test('errorCodes が空なら null を返す', () {
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
    test('error カラムがエラー型に置換される', () {
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

      // error フィールドはエラー型
      expect(
        output,
        contains(
          'required ExecuteExchangeAtomicError error,',
        ),
      );
      // fromRow で fromErrorCode 変換
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
      // success は通常の bool
      expect(
        output,
        contains('required bool success,'),
      );
    });
  });

  group('generateAllErrorClasses', () {
    test('errorCodes を持つ関数のみ生成', () {
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

      final result =
          generator.generateAllErrorClasses(functions);

      expect(result, hasLength(1));
      expect(
        result.containsKey('execute_exchange_error.dart'),
        isTrue,
      );
    });
  });
}
