import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';

void main() {
  setUp(() {
    TypeMapper.clearEnums();
  });

  group('SchemaFetcher.mergeEnumTypes', () {
    test('replaces OpenAPI enum name with pg_enum name via openApiEnums', () {
      // Simulate: OpenAPI detected enum as "receipt_campaigns_type"
      // but pg_enum has it as "campaign_type"
      final openApiEnums = {
        'receipt_campaigns_type': ['normal', 'trial'],
      };

      // TypeMapper now has pg_enum names only
      TypeMapper.registerEnum('campaign_type', ['normal', 'trial']);

      final tables = [
        TableInfo(
          name: 'receipt_campaigns',
          columns: [
            ColumnInfo(
              name: 'id',
              dataType: 'uuid',
              isNullable: false,
            ),
            ColumnInfo(
              name: 'type',
              dataType: 'receipt_campaigns_type',
              isNullable: false,
            ),
          ],
        ),
      ];

      final pgEnums = [
        EnumInfo(name: 'campaign_type', values: ['normal', 'trial']),
      ];

      final merged = SchemaFetcher.mergeEnumTypes(
        tables,
        pgEnums,
        openApiEnums: openApiEnums,
      );

      expect(merged[0].columns[1].dataType, 'campaign_type');
    });

    test('works without openApiEnums when TypeMapper has matching enum', () {
      TypeMapper.registerEnum('my_enum', ['a', 'b']);

      final tables = [
        TableInfo(
          name: 'test',
          columns: [
            ColumnInfo(
              name: 'status',
              dataType: 'my_enum',
              isNullable: false,
            ),
          ],
        ),
      ];

      final pgEnums = [
        EnumInfo(name: 'real_enum', values: ['a', 'b']),
      ];

      final merged = SchemaFetcher.mergeEnumTypes(tables, pgEnums);

      expect(merged[0].columns[0].dataType, 'real_enum');
    });

    test('leaves non-enum columns unchanged', () {
      final tables = [
        TableInfo(
          name: 'test',
          columns: [
            ColumnInfo(
              name: 'name',
              dataType: 'text',
              isNullable: false,
            ),
          ],
        ),
      ];

      final pgEnums = [
        EnumInfo(name: 'status', values: ['a', 'b']),
      ];

      final merged = SchemaFetcher.mergeEnumTypes(tables, pgEnums);

      expect(merged[0].columns[0].dataType, 'text');
    });

    test('returns tables unchanged when pgEnums is empty', () {
      final tables = [
        TableInfo(
          name: 'test',
          columns: [
            ColumnInfo(
              name: 'id',
              dataType: 'uuid',
              isNullable: false,
            ),
          ],
        ),
      ];

      final merged = SchemaFetcher.mergeEnumTypes(tables, []);

      expect(merged[0].columns[0].dataType, 'uuid');
    });
  });
}
