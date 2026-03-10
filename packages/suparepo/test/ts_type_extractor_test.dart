import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:suparepo/src/ts_type_extractor.dart';
import 'package:test/test.dart';

void main() {
  late TsTypeExtractor extractor;

  setUp(() {
    extractor = const TsTypeExtractor();
  });

  group('TsTypeExtractor', () {
    group('リクエスト型抽出', () {
      test('body as { ... } パターンからフィールド抽出', () {
        const source = '''
const body = await req.json();
const { amount, provider } = body as {
  amount?: number;
  provider?: string;
};
if (!amount || !provider) {
  return new Response(
    JSON.stringify({ error: "Missing" }),
    { status: 400, headers },
  );
}
''';
        final result = extractor.extract(indexSource: source);

        expect(result, isNotNull);
        expect(result!.request, isNotNull);
        expect(result.request, hasLength(2));

        final amount = result.request!.firstWhere((f) => f.name == 'amount');
        expect(amount.dataType, 'integer');
        expect(amount.isRequired, isTrue);

        final provider =
            result.request!.firstWhere((f) => f.name == 'provider');
        expect(provider.dataType, 'text');
        expect(provider.isRequired, isTrue);
      });

      test('?なしフィールドはrequired', () {
        const source = '''
const { id } = body as {
  id: string;
};
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.isRequired, isTrue);
      });

      test('?ありでバリデーションなしはoptional', () {
        const source = '''
const { note } = body as {
  note?: string;
};
return new Response(
  JSON.stringify({ ok: true }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.isRequired, isFalse);
      });

      test('booleanのtypeofチェックでrequired', () {
        const source = '''
const { is_active } = body as {
  is_active?: boolean;
};
if (typeof is_active !== "boolean") {
  return new Response(
    JSON.stringify({ error: "bad" }),
    { status: 400, headers },
  );
}
return new Response(
  JSON.stringify({ success: true }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.name, 'is_active');
        expect(result.request!.first.dataType, 'bool');
        expect(result.request!.first.isRequired, isTrue);
      });

      test('複数フィールドの混在（required/optional）', () {
        const source = '''
const {
  campaign_id,
  store_name,
  branch_name,
  total_amount,
} = body as {
  campaign_id?: string;
  store_name?: string;
  branch_name?: string;
  total_amount?: number;
};
if (!campaign_id || !store_name || !total_amount) {
  return new Response(
    JSON.stringify({ error: "Missing" }),
    { status: 400, headers },
  );
}
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request, hasLength(4));

        final campaignId =
            result.request!.firstWhere((f) => f.name == 'campaign_id');
        expect(campaignId.isRequired, isTrue);

        final branchName =
            result.request!.firstWhere((f) => f.name == 'branch_name');
        expect(branchName.isRequired, isFalse);
      });

      test('単一フィールドの短縮パターン', () {
        const source = '''
const { receipt_id } = body as { receipt_id?: string };
if (!receipt_id) {
  return new Response(
    JSON.stringify({ error: "required" }),
    { status: 400, headers },
  );
}
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request, hasLength(1));
        expect(result.request!.first.name, 'receipt_id');
        expect(result.request!.first.isRequired, isTrue);
      });
    });

    group('レスポンス型抽出', () {
      test('成功レスポンスのJSON.stringifyからフィールド抽出', () {
        const source = '''
return new Response(
  JSON.stringify({
    receipt_id: data.id,
    message: "OK",
  }),
  { status: 201, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.response, isNotNull);
        expect(result.response, hasLength(2));
        expect(
          result.response!.map((f) => f.name),
          containsAll(['receipt_id', 'message']),
        );
      });

      test('エラーレスポンス(status 400)は無視される', () {
        const source = '''
if (!id) {
  return new Response(
    JSON.stringify({ error: "Bad request" }),
    { status: 400, headers },
  );
}
return new Response(
  JSON.stringify({ data: result }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.response, isNotNull);
        expect(result.response!.first.name, 'data');
      });

      test('booleanリテラルの型推論', () {
        const source = '''
return new Response(
  JSON.stringify({ success: true, is_favorite }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.response, isNotNull);

        final success = result.response!.firstWhere((f) => f.name == 'success');
        expect(success.dataType, 'bool');

        final isFavorite =
            result.response!.firstWhere((f) => f.name == 'is_favorite');
        expect(isFavorite.dataType, 'bool');
      });

      test('points/amountは整数型として推論', () {
        const source = '''
return new Response(
  JSON.stringify({
    rewarded_points: rewardedPoints,
    message: msg,
  }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        final points =
            result!.response!.firstWhere((f) => f.name == 'rewarded_points');
        expect(points.dataType, 'integer');
      });
    });

    group('handler.tsとの結合', () {
      test('index.tsに型情報なし、handler.tsから抽出', () {
        const indexSource = '''
import { handler } from "./handler.ts";
Deno.serve(handler);
''';
        const handlerSource = '''
export async function handler(req: Request): Promise<Response> {
  const body = await req.json();
  const { name } = body as { name?: string };
  if (!name) {
    return new Response(
      JSON.stringify({ error: "name required" }),
      { status: 400, headers },
    );
  }
  return new Response(
    JSON.stringify({ greeting: "Hello" }),
    { status: 200, headers },
  );
}
''';
        final result = extractor.extract(
          indexSource: indexSource,
          handlerSource: handlerSource,
        );
        expect(result, isNotNull);
        expect(result!.request, isNotNull);
        expect(result.request!.first.name, 'name');
        expect(result.request!.first.isRequired, isTrue);
        expect(result.response, isNotNull);
        expect(result.response!.first.name, 'greeting');
      });
    });

    group('型マッピング', () {
      test('string -> text', () {
        const source = '''
const { x } = body as { x: string };
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.dataType, 'text');
      });

      test('number -> integer', () {
        const source = '''
const { x } = body as { x: number };
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.dataType, 'integer');
      });

      test('boolean -> bool', () {
        const source = '''
const { x } = body as { x: boolean };
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.dataType, 'bool');
      });
    });

    group('エラーコード抽出', () {
      test('snake_caseのエラーコードを検出', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "outside_time_window", message: "Not in time" }),
  { status: 400, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result, isNotNull);
        expect(result!.errors, isNotNull);
        expect(result.errors, hasLength(1));
        expect(result.errors!.first.code, 'outside_time_window');
        expect(result.errors!.first.statusCode, 400);
      });

      test('汎用メッセージ（非snake_case）はスキップ', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "Missing" }),
  { status: 400, headers },
);
return new Response(
  JSON.stringify({ error: "Bad request" }),
  { status: 400, headers },
);
return new Response(
  JSON.stringify({ error: "required" }),
  { status: 400, headers },
);
return new Response(
  JSON.stringify({ error: "bad" }),
  { status: 400, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        // errorsがnullであること（snake_caseでないため）
        expect(result, isNull);
      });

      test('複数エラーコードの検出', () {
        const source = '''
if (outsideWindow) {
  return new Response(
    JSON.stringify({ error: "outside_time_window", message: "too late" }),
    { status: 400, headers },
  );
}
if (alreadyDone) {
  return new Response(
    JSON.stringify({ error: "already_participated", message: "done" }),
    { status: 409, headers },
  );
}
return new Response(
  JSON.stringify({ result: "ok" }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result, isNotNull);
        expect(result!.errors, hasLength(2));

        final codes = result.errors!.map((e) => e.code).toList();
        expect(codes, contains('outside_time_window'));
        expect(codes, contains('already_participated'));
      });

      test('ステータスコードの紐付け', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "insufficient_balance" }),
  { status: 402, headers },
);
return new Response(
  JSON.stringify({ error: "not_found_item" }),
  { status: 404, headers },
);
return new Response(
  JSON.stringify({ error: "server_internal_error" }),
  { status: 500, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(3));

        final balance = result.errors!.firstWhere(
          (e) => e.code == 'insufficient_balance',
        );
        expect(balance.statusCode, 402);

        final notFound = result.errors!.firstWhere(
          (e) => e.code == 'not_found_item',
        );
        expect(notFound.statusCode, 404);

        final internal = result.errors!.firstWhere(
          (e) => e.code == 'server_internal_error',
        );
        expect(internal.statusCode, 500);
      });

      test('重複エラーコードは1つにまとめる', () {
        const source = '''
if (cond1) {
  return new Response(
    JSON.stringify({ error: "duplicate_entry" }),
    { status: 400, headers },
  );
}
if (cond2) {
  return new Response(
    JSON.stringify({ error: "duplicate_entry" }),
    { status: 409, headers },
  );
}
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(1));
        expect(result.errors!.first.code, 'duplicate_entry');
      });

      test('成功レスポンス(2xx)のerrorフィールドは無視', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "some_error_code" }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        // 2xxなのでエラーとして検出されない
        expect(result?.errors, isNull);
      });

      test('リクエスト・レスポンス・エラーすべて抽出', () {
        const source = '''
const { name } = body as { name?: string };
if (!name) {
  return new Response(
    JSON.stringify({ error: "missing_name", message: "Name is required" }),
    { status: 400, headers },
  );
}
return new Response(
  JSON.stringify({ greeting: "Hello" }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result, isNotNull);
        expect(result!.request, isNotNull);
        expect(result.response, isNotNull);
        expect(result.errors, isNotNull);
        expect(result.errors!.first.code, 'missing_name');
      });
    });

    group('statusMapパターンのエラーコード抽出', () {
      test('Record<string, number>のstatusMapからエラーコード検出', () {
        const source = '''
if (data.error) {
  const statusMap: Record<string, number> = {
    campaign_not_found: 404,
    campaign_inactive: 400,
    outside_time_window: 400,
    already_participated: 409,
    duplicate_receipt: 409,
  };
  const status = statusMap[data.error] ?? 500;
  return new Response(
    JSON.stringify({ error: data.error, message: data.message }),
    { status, headers },
  );
}
''';
        final result = extractor.extract(indexSource: source);
        expect(result, isNotNull);
        expect(result!.errors, isNotNull);
        expect(result.errors, hasLength(5));

        final codes = result.errors!.map((e) => e.code).toSet();
        expect(codes, contains('campaign_not_found'));
        expect(codes, contains('campaign_inactive'));
        expect(codes, contains('outside_time_window'));
        expect(codes, contains('already_participated'));
        expect(codes, contains('duplicate_receipt'));
      });

      test('statusMapのステータスコードが正しく紐付く', () {
        const source = '''
const statusMap: Record<string, number> = {
  not_found_item: 404,
  rate_limited: 429,
};
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(2));

        final notFound = result.errors!.firstWhere(
          (e) => e.code == 'not_found_item',
        );
        expect(notFound.statusCode, 404);

        final rateLimited = result.errors!.firstWhere(
          (e) => e.code == 'rate_limited',
        );
        expect(rateLimited.statusCode, 429);
      });

      test('statusMapとリテラルエラーコードの混在', () {
        const source = '''
if (!name) {
  return new Response(
    JSON.stringify({ error: "missing_name", message: "required" }),
    { status: 400, headers },
  );
}
if (data.error) {
  const statusMap: Record<string, number> = {
    already_exists: 409,
  };
  const status = statusMap[data.error] ?? 500;
  return new Response(
    JSON.stringify({ error: data.error, message: data.message }),
    { status, headers },
  );
}
return new Response(
  JSON.stringify({ result: "ok" }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(2));

        final codes = result.errors!.map((e) => e.code).toSet();
        expect(codes, contains('missing_name'));
        expect(codes, contains('already_exists'));
      });

      test('statusMapの重複エラーコードはリテラルと統合', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "duplicate_entry" }),
  { status: 409, headers },
);
const statusMap: Record<string, number> = {
  duplicate_entry: 409,
  other_error: 400,
};
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(2));

        final codes = result.errors!.map((e) => e.code).toList();
        expect(codes.where((c) => c == 'duplicate_entry'), hasLength(1));
      });

      test('statusMap内の非snake_caseキーはスキップ', () {
        const source = '''
const statusMap: Record<string, number> = {
  valid_error: 400,
  InvalidKey: 401,
  another: 402,
};
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.errors, hasLength(1));
        expect(result.errors!.first.code, 'valid_error');
      });
    });

    group('エッジケース', () {
      test('body asパターンがない場合はnull', () {
        const source = 'console.log("hello");';
        final result = extractor.extract(indexSource: source);
        expect(result, isNull);
      });

      test('空文字列でnull', () {
        final result = extractor.extract(indexSource: '');
        expect(result, isNull);
      });

      test('コメント内のbody asパターンは無視', () {
        const source = '''
// const { x } = body as { x: string };
/* const { y } = body as { y: number }; */
console.log("no body as here");
''';
        final result = extractor.extract(indexSource: source);
        expect(result, isNull);
      });
    });
  });

  group('TsTypeExtractorLoader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ts_extract_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('handler.tsから型を抽出', () async {
      final funcDir = Directory(p.join(tempDir.path, 'my-func'));
      await funcDir.create();

      await File(p.join(funcDir.path, 'index.ts')).writeAsString(
        'import { handler } from "./handler.ts";\n'
        'Deno.serve(handler);\n',
      );

      await File(p.join(funcDir.path, 'handler.ts')).writeAsString('''
export async function handler(req: Request): Promise<Response> {
  const headers = { "Content-Type": "application/json" };
  const body = await req.json();
  const { user_id, amount } = body as {
    user_id?: string;
    amount?: number;
  };
  if (!user_id || !amount) {
    return new Response(
      JSON.stringify({ error: "Missing fields" }),
      { status: 400, headers },
    );
  }
  return new Response(
    JSON.stringify({ success: true, message: "done" }),
    { status: 200, headers },
  );
}
''');

      final loader = TsTypeExtractorLoader();
      final result = await loader.extractFromDirectory(funcDir.path);

      expect(result, isNotNull);
      expect(result!.request, hasLength(2));
      expect(result.response, isNotNull);

      final userId = result.request!.firstWhere((f) => f.name == 'user_id');
      expect(userId.dataType, 'text');
      expect(userId.isRequired, isTrue);

      final amount = result.request!.firstWhere((f) => f.name == 'amount');
      expect(amount.dataType, 'integer');
      expect(amount.isRequired, isTrue);
    });

    test('index.tsが存在しない場合はnull', () async {
      final funcDir = Directory(p.join(tempDir.path, 'no-func'));
      await funcDir.create();

      final loader = TsTypeExtractorLoader();
      final result = await loader.extractFromDirectory(funcDir.path);

      expect(result, isNull);
    });

    test('handler.tsなしでindex.tsから抽出', () async {
      final funcDir = Directory(p.join(tempDir.path, 'simple-func'));
      await funcDir.create();

      await File(p.join(funcDir.path, 'index.ts')).writeAsString('''
const body = await req.json();
const { name } = body as { name: string };
return new Response(
  JSON.stringify({ greeting: "hi" }),
  { status: 200, headers },
);
''');

      final loader = TsTypeExtractorLoader();
      final result = await loader.extractFromDirectory(funcDir.path);

      expect(result, isNotNull);
      expect(result!.request, hasLength(1));
      expect(result.request!.first.name, 'name');
    });
  });
}
