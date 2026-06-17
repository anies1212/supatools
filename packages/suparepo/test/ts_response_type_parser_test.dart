import 'package:suparepo/src/edge_function_info.dart';
import 'package:suparepo/src/ts_response_type_parser.dart';
import 'package:test/test.dart';

void main() {
  const parser = TsResponseTypeParser();

  EdgeFunctionResponseField field(
    List<EdgeFunctionResponseField> fields,
    String key,
  ) =>
      fields.firstWhere((f) => f.jsonKey == key);

  group('TsResponseTypeParser', () {
    group('explicit <Name>Response interface', () {
      test('parses scalars, nullable (T | null), and string[]', () {
        const source = '''
export interface GetDailyCardResponse {
  card_date: string;
  body: string | null;
  count: number;
  is_saved: boolean;
  tags: string[];
}
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
        );

        expect(result, isNotNull);
        expect(field(result!, 'card_date').dartScalarType, 'String');
        expect(field(result, 'card_date').nullable, isFalse);

        final body = field(result, 'body');
        expect(body.dartScalarType, 'String');
        expect(body.nullable, isTrue);

        expect(field(result, 'count').dartScalarType, 'int');
        expect(field(result, 'is_saved').dartScalarType, 'bool');

        final tags = field(result, 'tags');
        expect(tags.dartScalarType, 'String');
        expect(tags.isList, isTrue);
      });

      test('resolves nested interface references recursively', () {
        const source = '''
export interface CardView {
  card_date: string;
  preview: string;
  locked: boolean;
}
export interface GetDailyCardResponse {
  card: CardView;
}
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
        );

        final card = field(result!, 'card');
        expect(card.isObject, isTrue);
        expect(card.isList, isFalse);
        expect(card.objectFields, hasLength(3));
        expect(field(card.objectFields!, 'locked').dartScalarType, 'bool');
      });

      test('resolves array of interface references (Foo[])', () {
        const source = '''
export interface SavedCardView {
  card_date: string;
  locked: boolean;
}
export interface GetSavedCardsResponse {
  saved_cards: SavedCardView[];
  isEntitled: boolean;
}
''';
        final result = parser.parse(
          functionName: 'get_saved_cards',
          indexSource: source,
        );

        final saved = field(result!, 'saved_cards');
        expect(saved.isObject, isTrue);
        expect(saved.isList, isTrue);
        expect(saved.objectFields, hasLength(2));
        expect(field(result, 'isEntitled').dartScalarType, 'bool');
      });
    });

    group('jsonResponse fallback (no <Name>Response interface)', () {
      test('infers list type from a function return annotation', () {
        // Mirrors get_saved_daily_cards/handler.ts.
        const source = '''
export interface SavedDailyCardView {
  card_date: string;
  body: string | null;
  locked: boolean;
  preview: string;
}
export function viewSavedCards(
  rows: readonly SavedDailyCardRow[],
  isPaid: boolean,
): SavedDailyCardView[] {
  return [];
}
export const handler = async (req) => {
  return jsonResponse({
    saved_cards: viewSavedCards(data ?? [], isPaid),
    isEntitled: isPaid,
  });
};
''';
        final result = parser.parse(
          functionName: 'get_saved_daily_cards',
          indexSource: source,
        );

        expect(result, isNotNull);
        final saved = field(result!, 'saved_cards');
        expect(saved.isObject, isTrue, reason: 'resolved via return type');
        expect(saved.isList, isTrue);
        expect(saved.objectFields, hasLength(4));
        expect(field(saved.objectFields!, 'body').nullable, isTrue);

        // `isEntitled: isPaid` → name heuristic → bool.
        expect(field(result, 'isEntitled').dartScalarType, 'bool');
      });

      test('unions multiple success returns; partial keys are optional', () {
        // Mirrors complete_daily_todo/handler.ts: two success returns.
        const source = '''
export function computeAllDone(todos): boolean { return true; }
export const handler = async (req) => {
  if (already) return jsonResponse({ already: true });
  const allDone = computeAllDone(allTodos ?? []);
  return jsonResponse({ completed: true, allDone });
};
''';
        final result = parser.parse(
          functionName: 'complete_daily_todo',
          indexSource: source,
        );

        expect(result, isNotNull);
        expect(
          result!.map((f) => f.jsonKey),
          ['already', 'completed', 'allDone'],
        );
        // Each appears in only one of two returns → all optional.
        for (final f in result) {
          expect(f.nullable, isTrue, reason: '${f.jsonKey} should be optional');
          expect(f.dartScalarType, 'bool', reason: f.jsonKey);
        }
      });

      test('unwraps Promise<T> from an awaited async helper (cross-file)', () {
        // Mirrors generate_bond_daily/handler.ts: `const isPaid = await
        // isEntitledUser(...)` where the helper is imported from _shared.
        // The async helper returns `Promise<boolean>`; previously the
        // cross-file return type resolved to `dynamic` instead of `bool`.
        const handlerSource = '''
export const handler = async (req) => {
  const isPaid = await isEntitledUser(admin, auth.userId);
  return jsonResponse({ is_paid: isPaid });
};
''';
        const importedSources = '''
export async function isEntitledUser(
  admin: Admin,
  userId: string,
): Promise<boolean> {
  return true;
}
''';
        final result = parser.parse(
          functionName: 'generate_bond_daily',
          indexSource: handlerSource,
          importedSources: importedSources,
        );

        expect(result, isNotNull);
        expect(field(result!, 'is_paid').dartScalarType, 'bool');
        expect(field(result, 'is_paid').isObject, isFalse);
        expect(field(result, 'is_paid').isList, isFalse);
      });

      test('unwraps Promise<T> from an inline awaited async helper call', () {
        // `await helper()` written directly as a field value (no intermediate
        // const). Uses a non-`is_`/`has_` key so the name heuristic can't mask
        // a regression: it must resolve via the unwrapped Promise<string>.
        const handlerSource = '''
export const handler = async (req) => {
  return jsonResponse({ label: await resolveLabel(admin, auth.userId) });
};
''';
        const importedSources = '''
export async function resolveLabel(
  admin: Admin,
  userId: string,
): Promise<string> {
  return "x";
}
''';
        final result = parser.parse(
          functionName: 'resolve_label',
          indexSource: handlerSource,
          importedSources: importedSources,
        );

        expect(result, isNotNull);
        expect(field(result!, 'label').dartScalarType, 'String');
        expect(field(result, 'label').isList, isFalse);
      });

      test('sync helper return type is unaffected (no Promise unwrap)', () {
        const handlerSource = '''
export const handler = async (req) => {
  const allDone = computeAllDone(rows);
  return jsonResponse({ all_done: allDone });
};
''';
        const importedSources = '''
export function computeAllDone(rows: TodoRow[]): boolean {
  return true;
}
''';
        final result = parser.parse(
          functionName: 'daily_todos',
          indexSource: handlerSource,
          importedSources: importedSources,
        );

        expect(result, isNotNull);
        expect(field(result!, 'all_done').dartScalarType, 'bool');
      });

      test('key present in all returns stays required', () {
        const source = '''
export const handler = async (req) => {
  if (x) return jsonResponse({ ok: true, extra: true });
  return jsonResponse({ ok: true });
};
''';
        final result = parser.parse(
          functionName: 'do_thing',
          indexSource: source,
        );
        final ok = field(result!, 'ok');
        expect(ok.nullable, isFalse, reason: 'present in both returns');
        expect(field(result, 'extra').nullable, isTrue);
      });

      test('conflicting types across returns → dynamic', () {
        const source = '''
export const handler = async (req) => {
  if (x) return jsonResponse({ value: true });
  return jsonResponse({ value: someText });
};
''';
        final result = parser.parse(
          functionName: 'do_thing',
          indexSource: source,
        );
        final value = field(result!, 'value');
        expect(value.dartScalarType, 'dynamic');
        // Present in both returns → stays required despite the type conflict.
        expect(value.nullable, isFalse);
      });

      test('skips error-only JSON.stringify blocks', () {
        const source = '''
export const handler = async (req) => {
  if (bad) {
    return new Response(JSON.stringify({ error: "nope" }), { status: 400 });
  }
  return jsonResponse({ ok: true });
};
''';
        final result = parser.parse(
          functionName: 'do_thing',
          indexSource: source,
        );
        expect(result, hasLength(1));
        expect(result!.first.jsonKey, 'ok');
        expect(result.first.dartScalarType, 'bool');
      });
    });

    group('select-projection inference (strategy 3)', () {
      final schemas = {
        'daily_cards': const [
          EfTableColumn(name: 'card_date', dartType: 'String'),
          EfTableColumn(name: 'body', dartType: 'String', nullable: true),
          EfTableColumn(name: 'feedback_rating', dartType: 'int', nullable: true),
          EfTableColumn(name: 'generated_at', dartType: 'DateTime'),
          EfTableColumn(name: 'user_id', dartType: 'String'),
        ],
        'wishes': const [
          EfTableColumn(name: 'id', dartType: 'String'),
          EfTableColumn(name: 'title', dartType: 'String'),
        ],
        'bonds': const [
          EfTableColumn(name: 'id', dartType: 'String'),
        ],
      };

      test('spread of single-row select → typed nested object', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client
    .from("daily_cards")
    .select("card_date, body, feedback_rating, generated_at")
    .eq("user_id", auth.userId)
    .maybeSingle();
  return jsonResponse({ card: { ...data, is_saved: saved !== null } });
};
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
          tableSchemas: schemas,
        );

        final card = field(result!, 'card');
        expect(card.isObject, isTrue);
        expect(card.isList, isFalse);
        // Only selected columns + the extra computed field.
        final keys = card.objectFields!.map((f) => f.jsonKey).toSet();
        expect(keys, {
          'card_date',
          'body',
          'feedback_rating',
          'generated_at',
          'is_saved',
        });
        // user_id was NOT selected → must be absent.
        expect(keys, isNot(contains('user_id')));
        // Column types/nullability come from the schema.
        expect(field(card.objectFields!, 'card_date').dartScalarType, 'String');
        expect(field(card.objectFields!, 'card_date').nullable, isFalse);
        expect(field(card.objectFields!, 'body').nullable, isTrue);
        expect(field(card.objectFields!, 'generated_at').dartScalarType,
            'DateTime');
        // Computed property typed by heuristic.
        expect(field(card.objectFields!, 'is_saved').dartScalarType, 'bool');
      });

      test('bare select var without maybeSingle → List<object>', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("wishes").select("id, title").eq("u", x);
  return jsonResponse({ wishes: data });
};
''';
        final result = parser.parse(
          functionName: 'get_wishes',
          indexSource: source,
          tableSchemas: schemas,
        );

        final wishes = field(result!, 'wishes');
        expect(wishes.isObject, isTrue);
        expect(wishes.isList, isTrue);
        expect(wishes.objectFields, hasLength(2));
      });

      test('column alias a:b uses alias as key, source column type', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("daily_cards")
    .select("when:card_date, body").maybeSingle();
  return jsonResponse({ card: { ...data } });
};
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
          tableSchemas: schemas,
        );
        final card = field(result!, 'card');
        final keys = card.objectFields!.map((f) => f.jsonKey).toSet();
        expect(keys, {'when', 'body'});
        expect(field(card.objectFields!, 'when').dartScalarType, 'String');
      });

      test('select("*") expands to all table columns', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("wishes").select("*").maybeSingle();
  return jsonResponse({ wish: { ...data } });
};
''';
        final result = parser.parse(
          functionName: 'get_wish',
          indexSource: source,
          tableSchemas: schemas,
        );
        expect(field(result!, 'wish').objectFields, hasLength(2));
      });

      test('no-arg .select() (insert+select) → all columns, typed', () {
        // Mirrors create_wish/handler.ts: `.insert({...}).select().single()`.
        const source = '''
export const handler = async (req) => {
  const { data, error } = await admin
    .from("wishes")
    .insert({ user_id: auth.userId, title: t })
    .select()
    .single();
  return jsonResponse({ wish: data, windowDates: compute(x) });
};
''';
        final result = parser.parse(
          functionName: 'create_wish',
          indexSource: source,
          tableSchemas: schemas,
        );

        final wish = field(result!, 'wish');
        expect(wish.isObject, isTrue, reason: 'no-arg select → all columns');
        expect(wish.isList, isFalse);
        expect(wish.objectFields, hasLength(2));
        expect(field(wish.objectFields!, 'id').dartScalarType, 'String');
      });

      test('relation embed → safe dynamic fallback', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("wishes")
    .select("id, bond:bonds(*)").maybeSingle();
  return jsonResponse({ wish: { ...data } });
};
''';
        final result = parser.parse(
          functionName: 'get_wish',
          indexSource: source,
          tableSchemas: schemas,
        );
        final wish = field(result!, 'wish');
        expect(wish.isObject, isFalse);
        expect(wish.dartScalarType, 'dynamic');
      });

      test('.map() reshaping → safe dynamic fallback', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("wishes").select("id, title");
  return jsonResponse({ luckyDays: data.map((d) => ({ x: d.id })) });
};
''';
        final result = parser.parse(
          functionName: 'get_lucky_days',
          indexSource: source,
          tableSchemas: schemas,
        );
        expect(field(result!, 'luckyDays').dartScalarType, 'dynamic');
      });

      test('off by default (no tableSchemas) → dynamic, as in 1.21.0', () {
        const source = '''
export const handler = async (req) => {
  const { data } = await client.from("daily_cards").select("card_date").maybeSingle();
  return jsonResponse({ card: { ...data, is_saved: saved !== null } });
};
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
        );
        expect(field(result!, 'card').dartScalarType, 'dynamic');
      });

      test('strategy 1 interface still wins over select inference', () {
        const source = '''
export interface GetDailyCardResponse { ok: boolean; }
export const handler = async (req) => {
  const { data } = await client.from("daily_cards").select("card_date").maybeSingle();
  return jsonResponse({ card: { ...data } });
};
''';
        final result = parser.parse(
          functionName: 'get_daily_card',
          indexSource: source,
          tableSchemas: schemas,
        );
        expect(result, hasLength(1));
        expect(result!.first.jsonKey, 'ok');
      });
    });

    test('returns null when no response shape is present', () {
      const source = '''
export const handler = async (req) => {
  return new Response("ok");
};
''';
      final result = parser.parse(
        functionName: 'noop',
        indexSource: source,
      );
      expect(result, isNull);
    });
  });
}
