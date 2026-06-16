import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:suparepo/src/edge_function_info.dart';
import 'package:suparepo/src/ts_type_extractor.dart';
import 'package:test/test.dart';

void main() {
  late TsTypeExtractor extractor;

  setUp(() {
    extractor = const TsTypeExtractor();
  });

  group('TsTypeExtractor', () {
    test('populates responseObject from exported <Name>Response interface', () {
      const source = '''
export interface GetDailyCardResponse {
  card_date: string;
  body: string | null;
}
export const handler = async (req) => jsonResponse({ card_date: "x" });
''';
      final result = extractor.extract(
        indexSource: source,
        functionName: 'get_daily_card',
      );

      expect(result, isNotNull);
      expect(result!.responseObject, isNotNull);
      expect(result.responseObject, hasLength(2));
      final body =
          result.responseObject!.firstWhere((f) => f.jsonKey == 'body');
      expect(body.nullable, isTrue);
    });

    test('threads tableSchemas → select-projection responseObject', () {
      const source = '''
export const handler = async (req) => {
  const { data } = await client.from("daily_cards")
    .select("card_date, body").maybeSingle();
  return jsonResponse({ card: { ...data, is_saved: x !== null } });
};
''';
      final result = extractor.extract(
        indexSource: source,
        functionName: 'get_daily_card',
        tableSchemas: const {
          'daily_cards': [
            EfTableColumn(name: 'card_date', dartType: 'String'),
            EfTableColumn(name: 'body', dartType: 'String', nullable: true),
          ],
        },
      );

      final card =
          result!.responseObject!.firstWhere((f) => f.jsonKey == 'card');
      expect(card.isObject, isTrue);
      expect(
        card.objectFields!.map((f) => f.jsonKey),
        containsAll(['card_date', 'body', 'is_saved']),
      );
    });

    test('resolves imported helper return types across relative imports',
        () async {
      final tmp = Directory.systemTemp.createTempSync('suparepo_ef_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final funcDir = Directory(p.join(tmp.path, 'functions', 'complete_daily_todo'))
        ..createSync(recursive: true);
      final sharedDir = Directory(p.join(tmp.path, 'functions', '_shared'))
        ..createSync(recursive: true);

      File(p.join(sharedDir.path, 'daily_todos.ts')).writeAsStringSync('''
export function computeAllDone(
  todos: ReadonlyArray<{ completed_at: string | null }>,
): boolean {
  return todos.length > 0;
}
''');
      File(p.join(funcDir.path, 'index.ts')).writeAsStringSync('''
import { computeAllDone } from "../_shared/daily_todos.ts";
export const handler = async (req) => {
  if (already) return jsonResponse({ already: true });
  const allDone = computeAllDone(allTodos ?? []);
  return jsonResponse({ completed: true, allDone });
};
''');

      final def = await const TsTypeExtractorLoader()
          .extractFromDirectory(funcDir.path);
      final ro = def!.responseObject!;

      expect(ro.map((f) => f.jsonKey), ['already', 'completed', 'allDone']);
      // allDone resolves to bool via the imported computeAllDone(): boolean.
      final allDone = ro.firstWhere((f) => f.jsonKey == 'allDone');
      expect(allDone.dartScalarType, 'bool');
      expect(allDone.nullable, isTrue, reason: 'only in one of two returns');
    });

    test('responseObject is null when functionName is omitted', () {
      const source = '''
export interface FooResponse { ok: boolean; }
''';
      final result = extractor.extract(indexSource: source);
      expect(result?.responseObject, isNull);
    });

    group('request type extraction', () {
      test('extracts fields from body as { ... } pattern', () {
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

      test('field without ? is required', () {
        const source = '''
const { id } = body as {
  id: string;
};
''';
        final result = extractor.extract(indexSource: source);
        expect(result!.request!.first.isRequired, isTrue);
      });

      test('field with ? and no validation is optional', () {
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

      test('boolean typeof check makes field required', () {
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

      test('mixed required/optional fields', () {
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

      test('single field shorthand pattern', () {
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

    group('usage-based request inference (inferRequestFromUsage)', () {
      test('is off by default: no body-access inference', () {
        const source = '''
const body = await req.json();
const todoId = body.todo_id;
if (typeof todoId !== "string") return badRequest("required");
''';
        final result = extractor.extract(indexSource: source);
        expect(result?.request, isNull);
      });

      test('infers fields from req.json() as { ... } cast', () {
        const source = '''
const body = await req.json() as { authorization_code?: unknown };
const authorizationCode = body.authorization_code;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        expect(result!.request, hasLength(1));
        expect(result.request!.first.name, 'authorization_code');
      });

      test('infers fields from body.<field> access', () {
        const source = '''
let body;
try {
  body = await req.json();
} catch {
  return badRequest("invalid");
}
const bondType = body.bond_type;
if (!VALID.includes(bondType)) return badRequest("invalid");
const birthDate = typeof body.birth_date === "string"
  ? body.birth_date
  : null;
const nickname = typeof body.nickname === "string" ? body.nickname : null;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        final fields = {for (final f in result!.request!) f.name: f};
        expect(
            fields.keys, containsAll(['bond_type', 'birth_date', 'nickname']));
        // bare access + validation -> required
        expect(fields['bond_type']!.isRequired, isTrue);
        // typeof ternary with default -> optional
        expect(fields['birth_date']!.isRequired, isFalse);
        expect(fields['nickname']!.isRequired, isFalse);
      });

      test('infers boolean from body.x === true and marks it optional', () {
        const source = '''
const body = await req.json();
const bondId = body.bond_id;
if (typeof bondId !== "string") return badRequest("required");
const isPinned = body.is_pinned === true;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        final fields = {for (final f in result!.request!) f.name: f};
        expect(fields['bond_id']!.isRequired, isTrue);
        expect(fields['is_pinned']!.dataType, 'bool');
        expect(fields['is_pinned']!.isRequired, isFalse);
      });

      test('!== undefined guard makes a field optional', () {
        const source = '''
const body = await req.json();
if (body.birth_date !== undefined) update.birth_date = body.birth_date;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        expect(result!.request!.first.name, 'birth_date');
        expect(result.request!.first.isRequired, isFalse);
      });

      test('typeof number guard infers integer', () {
        const source = '''
const body = await req.json();
const count = typeof body.count === "number" ? body.count : 0;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        expect(result!.request!.first.dataType, 'integer');
      });

      test('explicit body as { } takes precedence over inference', () {
        const source = '''
const { id } = body as { id: string };
const x = body.other_field;
''';
        final result = extractor.extract(
          indexSource: source,
          inferRequestFromUsage: true,
        );
        // Explicit annotation wins; the body-access path is not used.
        expect(result!.request, hasLength(1));
        expect(result.request!.first.name, 'id');
      });
    });

    group('response type extraction', () {
      test('extracts fields from success response JSON.stringify', () {
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

      test('error response (status 400) is ignored', () {
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

      test('boolean literal type inference', () {
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

      test('points/amount are inferred as integer type', () {
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

    group('handler.ts integration', () {
      test('no type info in index.ts, extracts from handler.ts', () {
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

    group('type mapping', () {
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

    group('error code extraction', () {
      test('detects snake_case error codes', () {
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

      test('skips generic messages (non-snake_case)', () {
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
        // errors should be null (not snake_case)
        expect(result, isNull);
      });

      test('detects multiple error codes', () {
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

      test('associates status codes correctly', () {
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

      test('deduplicates error codes', () {
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

      test('ignores error field in success response (2xx)', () {
        const source = '''
return new Response(
  JSON.stringify({ error: "some_error_code" }),
  { status: 200, headers },
);
''';
        final result = extractor.extract(indexSource: source);
        // 2xx status, not detected as error
        expect(result?.errors, isNull);
      });

      test('extracts request, response, and errors all together', () {
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

    group('statusMap pattern error code extraction', () {
      test('detects error codes from Record<string, number> statusMap', () {
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

      test('statusMap status codes are correctly associated', () {
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

      test('mixed statusMap and literal error codes', () {
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

      test('statusMap duplicate error codes are merged with literals', () {
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

      test('skips non-snake_case keys in statusMap', () {
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

    group('edge cases', () {
      test('returns null when no body as pattern', () {
        const source = 'console.log("hello");';
        final result = extractor.extract(indexSource: source);
        expect(result, isNull);
      });

      test('returns null for empty string', () {
        final result = extractor.extract(indexSource: '');
        expect(result, isNull);
      });

      test('ignores body as pattern inside comments', () {
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

    test('extracts types from handler.ts', () async {
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

    test('returns null when index.ts does not exist', () async {
      final funcDir = Directory(p.join(tempDir.path, 'no-func'));
      await funcDir.create();

      final loader = TsTypeExtractorLoader();
      final result = await loader.extractFromDirectory(funcDir.path);

      expect(result, isNull);
    });

    test('extracts from index.ts without handler.ts', () async {
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
