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
