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
