import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';

void main() {
  group('TypeMapper', () {
    setUp(() {
      TypeMapper.clearEnums();
    });

    group('mapType', () {
      test('maps integer types correctly', () {
        expect(TypeMapper.mapType('int2'), 'int');
        expect(TypeMapper.mapType('int4'), 'int');
        expect(TypeMapper.mapType('int8'), 'int');
        expect(TypeMapper.mapType('smallint'), 'int');
        expect(TypeMapper.mapType('integer'), 'int');
        expect(TypeMapper.mapType('bigint'), 'int');
        expect(TypeMapper.mapType('serial'), 'int');
      });

      test('maps floating-point types correctly', () {
        expect(TypeMapper.mapType('float4'), 'double');
        expect(TypeMapper.mapType('float8'), 'double');
        expect(TypeMapper.mapType('real'), 'double');
        expect(TypeMapper.mapType('double precision'), 'double');
        expect(TypeMapper.mapType('numeric'), 'double');
        expect(TypeMapper.mapType('decimal'), 'double');
      });

      test('maps string types correctly', () {
        expect(TypeMapper.mapType('text'), 'String');
        expect(TypeMapper.mapType('varchar'), 'String');
        expect(TypeMapper.mapType('character varying'), 'String');
        expect(TypeMapper.mapType('char'), 'String');
        expect(TypeMapper.mapType('uuid'), 'String');
      });

      test('maps boolean types correctly', () {
        expect(TypeMapper.mapType('bool'), 'bool');
        expect(TypeMapper.mapType('boolean'), 'bool');
      });

      test('maps date/time types correctly', () {
        expect(TypeMapper.mapType('date'), 'DateTime');
        expect(TypeMapper.mapType('timestamp'), 'DateTime');
        expect(TypeMapper.mapType('timestamptz'), 'DateTime');
        expect(TypeMapper.mapType('timestamp with time zone'), 'DateTime');
        expect(TypeMapper.mapType('timestamp without time zone'), 'DateTime');
        expect(TypeMapper.mapType('time'), 'String');
        expect(TypeMapper.mapType('timetz'), 'String');
      });

      test('maps JSON types correctly', () {
        expect(TypeMapper.mapType('json'), 'Map<String, dynamic>');
        expect(TypeMapper.mapType('jsonb'), 'Map<String, dynamic>');
      });

      test('maps array types correctly', () {
        expect(TypeMapper.mapType('text[]'), 'List<String>');
        expect(TypeMapper.mapType('int4[]'), 'List<int>');
        expect(TypeMapper.mapType('bool[]'), 'List<bool>');
        expect(TypeMapper.mapType('timestamptz[]'), 'List<DateTime>');
      });

      test('maps unknown types to dynamic', () {
        expect(TypeMapper.mapType('unknown_type'), 'dynamic');
        expect(TypeMapper.mapType('custom_type'), 'dynamic');
      });

      test('is case-insensitive', () {
        expect(TypeMapper.mapType('TEXT'), 'String');
        expect(TypeMapper.mapType('BOOLEAN'), 'bool');
        expect(TypeMapper.mapType('Int4'), 'int');
      });
    });

    group('custom enums', () {
      test('registers and retrieves enum values', () {
        TypeMapper.registerEnum('status', ['active', 'inactive', 'pending']);

        expect(TypeMapper.isCustomEnum('status'), isTrue);
        expect(TypeMapper.getEnumValues('status'),
            ['active', 'inactive', 'pending']);
      });

      test('maps custom enum to String when useEnumTypes is false', () {
        TypeMapper.registerEnum('user_role', ['admin', 'user', 'guest']);

        expect(TypeMapper.mapType('user_role'), 'String');
      });

      test('maps custom enum array to List<String> when useEnumTypes is false',
          () {
        TypeMapper.registerEnum('tag', ['a', 'b', 'c']);

        expect(TypeMapper.mapType('tag[]'), 'List<String>');
      });

      test('maps custom enum to Dart type name when useEnumTypes is true', () {
        TypeMapper.registerEnum('campaign_type', ['normal', 'trial']);
        TypeMapper.useEnumTypes = true;

        expect(TypeMapper.mapType('campaign_type'), 'CampaignType');
      });

      test('maps custom enum array to List<DartType> when useEnumTypes is true',
          () {
        TypeMapper.registerEnum('campaign_type', ['normal', 'trial']);
        TypeMapper.useEnumTypes = true;

        expect(TypeMapper.mapType('campaign_type[]'), 'List<CampaignType>');
      });

      test('clears enums and resets useEnumTypes', () {
        TypeMapper.registerEnum('status', ['a', 'b']);
        TypeMapper.useEnumTypes = true;
        expect(TypeMapper.isCustomEnum('status'), isTrue);
        expect(TypeMapper.useEnumTypes, isTrue);

        TypeMapper.clearEnums();
        expect(TypeMapper.isCustomEnum('status'), isFalse);
        expect(TypeMapper.useEnumTypes, isFalse);
      });

      test('enum lookup is case-insensitive', () {
        TypeMapper.registerEnum('Status', ['active', 'inactive']);

        expect(TypeMapper.isCustomEnum('status'), isTrue);
        expect(TypeMapper.isCustomEnum('STATUS'), isTrue);
      });
    });

    group('enumTypeName', () {
      test('converts snake_case to PascalCase', () {
        expect(TypeMapper.enumTypeName('campaign_type'), 'CampaignType');
      });

      test('handles single word', () {
        expect(TypeMapper.enumTypeName('status'), 'Status');
      });

      test('handles array type suffix', () {
        expect(TypeMapper.enumTypeName('campaign_type[]'), 'CampaignType');
      });
    });

    group('special types', () {
      test('maps bytea to List<int>', () {
        expect(TypeMapper.mapType('bytea'), 'List<int>');
      });

      test('maps vector to List<double>', () {
        expect(TypeMapper.mapType('vector'), 'List<double>');
      });

      test('maps hstore to Map<String, String>', () {
        expect(TypeMapper.mapType('hstore'), 'Map<String, String>');
      });

      test('maps money to String', () {
        expect(TypeMapper.mapType('money'), 'String');
      });
    });
  });
}
