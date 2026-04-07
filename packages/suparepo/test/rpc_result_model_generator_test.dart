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

    test('jsonb型の列', () {
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

      expect(
        output,
        contains(
          'required dynamic metadata,',
        ),
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
}
