import 'package:suparepo/src/edge_function_info.dart';
import 'package:suparepo/src/edge_function_response_generator.dart';
import 'package:test/test.dart';

void main() {
  const generator = EdgeFunctionResponseGenerator();

  group('EdgeFunctionResponseGenerator', () {
    test('generates a Freezed json_serializable DTO with @JsonKey', () {
      final content = generator.generateResponseModel('get_daily_card', const [
        EdgeFunctionResponseField(jsonKey: 'card_date', dartScalarType: 'String'),
        EdgeFunctionResponseField(
          jsonKey: 'body',
          dartScalarType: 'String',
          nullable: true,
        ),
        EdgeFunctionResponseField(
          jsonKey: 'is_saved',
          dartScalarType: 'bool',
        ),
      ]);

      expect(content, isNotNull);
      expect(content, contains("part 'get_daily_card_response.freezed.dart';"));
      expect(content, contains("part 'get_daily_card_response.g.dart';"));
      expect(content, contains('abstract class GetDailyCardResponse'));
      // snake_case → @JsonKey + camelCase field.
      expect(
        content,
        contains("@JsonKey(name: 'card_date') required String cardDate,"),
      );
      // nullable field has no `required`; camelCase key needs no @JsonKey.
      expect(content, contains('    String? body,'));
      expect(content, contains("@JsonKey(name: 'is_saved') required bool isSaved,"));
      expect(
        content,
        contains(
          '  factory GetDailyCardResponse.fromJson(Map<String, dynamic> json) =>',
        ),
      );
      expect(content, contains(r'_$GetDailyCardResponseFromJson(json);'));
    });

    test('generates nested classes for nested objects', () {
      final content = generator.generateResponseModel('get_daily_card', const [
        EdgeFunctionResponseField(
          jsonKey: 'card',
          objectFields: [
            EdgeFunctionResponseField(jsonKey: 'preview', dartScalarType: 'String'),
            EdgeFunctionResponseField(jsonKey: 'locked', dartScalarType: 'bool'),
          ],
        ),
      ]);

      expect(content, contains('required GetDailyCardResponseCard card,'));
      expect(content, contains('abstract class GetDailyCardResponseCard'));
      expect(content, contains('required String preview,'));
      expect(content, contains('required bool locked,'));
    });

    test('list of nested objects → List<...Item>', () {
      final content =
          generator.generateResponseModel('get_saved_cards', const [
        EdgeFunctionResponseField(
          jsonKey: 'saved_cards',
          isList: true,
          objectFields: [
            EdgeFunctionResponseField(jsonKey: 'card_date', dartScalarType: 'String'),
          ],
        ),
      ]);

      expect(
        content,
        contains(
          "@JsonKey(name: 'saved_cards') "
          'required List<GetSavedCardsResponseSavedCardsItem> savedCards,',
        ),
      );
      expect(
        content,
        contains('abstract class GetSavedCardsResponseSavedCardsItem'),
      );
    });

    test('list of scalars → List<String>', () {
      final content = generator.generateResponseModel('get_tags', const [
        EdgeFunctionResponseField(
          jsonKey: 'tags',
          dartScalarType: 'String',
          isList: true,
        ),
      ]);
      expect(content, contains('required List<String> tags,'));
    });

    test('generateAllResponseModels keys by file name', () {
      final files = generator.generateAllResponseModels({
        'get_daily_card': const EdgeFunctionModelDef(
          responseObject: [
            EdgeFunctionResponseField(jsonKey: 'ok', dartScalarType: 'bool'),
          ],
        ),
        'no_response': const EdgeFunctionModelDef(),
      });

      expect(files.keys, contains('get_daily_card_response.dart'));
      expect(files.keys, isNot(contains('no_response_response.dart')));
    });
  });
}
