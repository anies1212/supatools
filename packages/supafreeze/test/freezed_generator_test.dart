import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/config_loader.dart';
import 'package:supafreeze/src/freezed_generator.dart';

void main() {
  late FreezedGenerator generator;

  setUp(() {
    generator = FreezedGenerator();
  });

  group('FreezedGenerator', () {
    group('generateInsertModels', () {
      final table = TableInfo(
        name: 'bond_story_purchases',
        columns: [
          ColumnInfo(
            name: 'id',
            dataType: 'uuid',
            isNullable: false,
            isPrimaryKey: true,
            defaultValue: 'gen_random_uuid()',
          ),
          ColumnInfo(
            name: 'created_at',
            dataType: 'timestamptz',
            isNullable: false,
            defaultValue: 'now()',
          ),
          ColumnInfo(name: 'bond_id', dataType: 'uuid', isNullable: false),
          ColumnInfo(name: 'note', dataType: 'text', isNullable: true),
        ],
      );

      test('does not emit insert model by default', () {
        final result = generator.generateModel(table);
        expect(result, isNot(contains('BondStoryPurchasesInsert')));
      });

      test('emits insert model with default-backed columns optional', () {
        final gen = FreezedGenerator();
        gen.setConfig(const SupafreezeConfig(generateInsertModels: true));
        final result = gen.generateModel(table);

        expect(result, contains('abstract class BondStoryPurchasesInsert'));
        // NOT NULL, no default → required.
        expect(result, contains('required String bondId,'));
        // NOT NULL but DB default → optional + omit-if-null.
        expect(result, contains('@JsonKey(includeIfNull: false) String? id,'));
        expect(
          result,
          contains(
            "@JsonKey(name: 'created_at', includeIfNull: false) "
            'DateTime? createdAt,',
          ),
        );
        // nullable column → optional.
        expect(result, contains('String? note,'));
        // The fetch model keeps id/created_at required.
        expect(result, contains('required String id,'));
      });
    });

    group('preserveColumnOrder', () {
      final table = TableInfo(
        name: 'items',
        columns: [
          ColumnInfo(name: 'zebra', dataType: 'text', isNullable: true),
          ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
        ],
      );

      test('default order sorts required-first (id before zebra)', () {
        final result = generator.generateModel(table);
        expect(result.indexOf('id,'), lessThan(result.indexOf('zebra,')));
      });

      test('preserves DB column order when enabled (zebra before id)', () {
        final gen = FreezedGenerator();
        gen.setConfig(const SupafreezeConfig(preserveColumnOrder: true));
        final result = gen.generateModel(table);
        expect(result.indexOf('zebra,'), lessThan(result.indexOf('id,')));
      });
    });

    group('generateModel', () {
      test('generates basic model correctly', () {
        final table = TableInfo(
          name: 'users',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ColumnInfo(name: 'name', dataType: 'text', isNullable: false),
            ColumnInfo(name: 'email', dataType: 'text', isNullable: true),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains("abstract class Users with _\$Users"));
        expect(result, contains("required String id"));
        expect(result, contains("required String name"));
        expect(result, contains("String? email"));
        expect(result, contains("part 'users.supafreeze.freezed.dart'"));
        expect(result, contains("part 'users.supafreeze.g.dart'"));
      });

      test('converts snake_case column names to camelCase', () {
        final table = TableInfo(
          name: 'posts',
          columns: [
            ColumnInfo(
                name: 'created_at', dataType: 'timestamptz', isNullable: false),
            ColumnInfo(name: 'user_id', dataType: 'uuid', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('createdAt'));
        expect(result, contains('userId'));
        expect(result, contains("@JsonKey(name: 'created_at')"));
        expect(result, contains("@JsonKey(name: 'user_id')"));
      });

      test('handles default values', () {
        final table = TableInfo(
          name: 'settings',
          columns: [
            ColumnInfo(
              name: 'is_active',
              dataType: 'bool',
              isNullable: false,
              defaultValue: 'true',
            ),
            ColumnInfo(
              name: 'count',
              dataType: 'int4',
              isNullable: false,
              defaultValue: '0',
            ),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('@Default(true)'));
        expect(result, contains('@Default(0)'));
      });

      test('handles table name starting with number', () {
        final table = TableInfo(
          name: '123_data',
          columns: [
            ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('abstract class Table123Data'));
      });

      test('sorts columns with required first', () {
        final table = TableInfo(
          name: 'test_table',
          columns: [
            ColumnInfo(
                name: 'optional_field', dataType: 'text', isNullable: true),
            ColumnInfo(
                name: 'required_field', dataType: 'text', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        final requiredIndex = result.indexOf('required String requiredField');
        final optionalIndex = result.indexOf('String? optionalField');
        expect(requiredIndex, lessThan(optionalIndex));
      });
    });

    group('reserved words handling', () {
      test('escapes Dart reserved words in field names', () {
        final table = TableInfo(
          name: 'test',
          columns: [
            ColumnInfo(name: 'class', dataType: 'text', isNullable: false),
            ColumnInfo(name: 'if', dataType: 'bool', isNullable: false),
            ColumnInfo(name: 'switch', dataType: 'text', isNullable: true),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains(r'class$'));
        expect(result, contains(r'if$'));
        expect(result, contains(r'switch$'));
        expect(result, contains("@JsonKey(name: 'class')"));
        expect(result, contains("@JsonKey(name: 'if')"));
        expect(result, contains("@JsonKey(name: 'switch')"));
      });

      test('handles reserved word as table name', () {
        final table = TableInfo(
          name: 'class',
          columns: [
            ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('abstract class ClassModel'));
      });
    });

    group('enum type fields', () {
      setUp(() {
        TypeMapper.clearEnums();
      });

      tearDown(() {
        TypeMapper.clearEnums();
      });

      test('enum default → @Default(Enum.member), not required', () {
        TypeMapper.registerEnum('bond_story_status', ['pending', 'purchased']);
        TypeMapper.useEnumTypes = true;

        final table = TableInfo(
          name: 'bond_story_purchases',
          columns: [
            ColumnInfo(
              name: 'status',
              dataType: 'bond_story_status',
              isNullable: false,
              defaultValue: "'pending'::bond_story_status",
            ),
          ],
        );

        final gen = FreezedGenerator();
        gen.enumImportPrefix = 'enums/';
        final result = gen.generateModel(table);

        expect(result, contains('@Default(BondStoryStatus.pending)'));
        expect(result, contains('BondStoryStatus status'));
        expect(result, isNot(contains('required BondStoryStatus status')));
      });

      test('enum default with schema-qualified cast', () {
        TypeMapper.registerEnum('order_status', ['pending', 'shipped']);
        TypeMapper.useEnumTypes = true;

        final table = TableInfo(
          name: 'orders',
          columns: [
            ColumnInfo(
              name: 'status',
              dataType: 'order_status',
              isNullable: false,
              defaultValue: "'shipped'::public.order_status",
            ),
          ],
        );

        final gen = FreezedGenerator();
        gen.enumImportPrefix = 'enums/';
        final result = gen.generateModel(table);

        expect(result, contains('@Default(OrderStatus.shipped)'));
      });

      test('unknown enum default value falls back to required', () {
        TypeMapper.registerEnum('order_status', ['pending', 'shipped']);
        TypeMapper.useEnumTypes = true;

        final table = TableInfo(
          name: 'orders',
          columns: [
            ColumnInfo(
              name: 'status',
              dataType: 'order_status',
              isNullable: false,
              defaultValue: "'mystery'::order_status",
            ),
          ],
        );

        final gen = FreezedGenerator();
        gen.enumImportPrefix = 'enums/';
        final result = gen.generateModel(table);

        expect(result, contains('required OrderStatus status'));
      });

      test('generates enum type field when useEnumTypes is true', () {
        TypeMapper.registerEnum('campaign_type', ['normal', 'trial']);
        TypeMapper.useEnumTypes = true;

        final table = TableInfo(
          name: 'campaigns',
          columns: [
            ColumnInfo(
              name: 'id',
              dataType: 'uuid',
              isNullable: false,
            ),
            ColumnInfo(
              name: 'type',
              dataType: 'campaign_type',
              isNullable: false,
            ),
          ],
        );

        final gen = FreezedGenerator();
        gen.enumImportPrefix = 'enums/';
        final result = gen.generateModel(table);

        expect(result, contains('required CampaignType type'));
        expect(
          result,
          contains("import 'enums/campaign_type.supafreeze.dart'"),
        );
      });

      test('generates String field when useEnumTypes is false', () {
        TypeMapper.registerEnum('campaign_type', ['normal', 'trial']);
        TypeMapper.useEnumTypes = false;

        final table = TableInfo(
          name: 'campaigns',
          columns: [
            ColumnInfo(
              name: 'type',
              dataType: 'campaign_type',
              isNullable: false,
            ),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('required String type'));
        expect(result, isNot(contains("import 'enums/")));
      });

      test('generates nullable enum type field', () {
        TypeMapper.registerEnum('order_status', ['pending', 'shipped']);
        TypeMapper.useEnumTypes = true;

        final table = TableInfo(
          name: 'orders',
          columns: [
            ColumnInfo(
              name: 'status',
              dataType: 'order_status',
              isNullable: true,
            ),
          ],
        );

        final gen = FreezedGenerator();
        gen.enumImportPrefix = 'enums/';
        final result = gen.generateModel(table);

        expect(result, contains('OrderStatus? status'));
      });
    });

    group('getFileName', () {
      test('returns correct file name for table', () {
        expect(generator.getFileName('users'), 'users.supafreeze.dart');
        expect(generator.getFileName('user_profiles'),
            'user_profiles.supafreeze.dart');
        expect(generator.getFileName('UserProfiles'),
            'user_profiles.supafreeze.dart');
      });
    });

    group('generateBarrelFile', () {
      test('generates barrel file with exports', () {
        final tables = [
          TableInfo(name: 'users', columns: []),
          TableInfo(name: 'posts', columns: []),
        ];

        final result = generator.generateBarrelFile(tables, '');

        expect(result, contains("export 'users.supafreeze.dart'"));
        expect(result, contains("export 'posts.supafreeze.dart'"));
      });
    });
  });
}
