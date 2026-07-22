import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/config_loader.dart';
import 'package:supafreeze/src/dart_mappable_generator.dart';

void main() {
  late DartMappableGenerator generator;

  setUp(() {
    generator = DartMappableGenerator();
  });

  group('ModelFormat.parse', () {
    test('defaults to freezed for null/unknown', () {
      expect(ModelFormat.parse(null), ModelFormat.freezed);
      expect(ModelFormat.parse('freezed'), ModelFormat.freezed);
      expect(ModelFormat.parse('something'), ModelFormat.freezed);
    });

    test('recognizes dart_mappable aliases', () {
      expect(ModelFormat.parse('dart_mappable'), ModelFormat.dartMappable);
      expect(ModelFormat.parse('dart-mappable'), ModelFormat.dartMappable);
      expect(ModelFormat.parse('DartMappable'), ModelFormat.dartMappable);
      expect(ModelFormat.parse(' mappable '), ModelFormat.dartMappable);
    });
  });

  group('DartMappableGenerator', () {
    group('generateModel', () {
      test('generates a basic mappable model', () {
        final table = TableInfo(
          name: 'users',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ColumnInfo(name: 'name', dataType: 'text', isNullable: false),
            ColumnInfo(name: 'email', dataType: 'text', isNullable: true),
          ],
        );

        final result = generator.generateModel(table);

        expect(
          result,
          contains("import 'package:dart_mappable/dart_mappable.dart';"),
        );
        expect(result, contains("part 'users.supafreeze.mapper.dart';"));
        expect(result, contains('class Users with UsersMappable {'));
        expect(result, contains('required this.id,'));
        expect(result, contains('required this.name,'));
        expect(result, contains('this.email,'));
        expect(result, contains('final String id;'));
        expect(result, contains('final String? email;'));
      });

      test('generates suparepo-compatible JSON interop', () {
        final table = TableInfo(
          name: 'users',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(
          result,
          contains(
            'factory Users.fromJson(Map<String, dynamic> json) =>',
          ),
        );
        expect(result, contains('UsersMapper.fromMap(json);'));
        expect(result, contains('Map<String, dynamic> toJson() =>'));
        expect(
          result,
          contains('UsersMapper.ensureInitialized().encodeMap<Users>(this);'),
        );
      });

      test('omits the encode mixin methods so toJson can return a Map', () {
        final table = TableInfo(
          name: 'users',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('GenerateMethods.decode'));
        expect(result, contains('GenerateMethods.copy'));
        expect(result, contains('GenerateMethods.equals'));
        expect(result, contains('GenerateMethods.stringify'));
        expect(result, isNot(contains('GenerateMethods.encode')));
      });

      test('renames camelCase fields with @MappableField', () {
        final table = TableInfo(
          name: 'posts',
          columns: [
            ColumnInfo(
                name: 'created_at', dataType: 'timestamptz', isNullable: false),
            ColumnInfo(name: 'user_id', dataType: 'uuid', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains("@MappableField(key: 'created_at')"));
        expect(result, contains('final DateTime createdAt;'));
        expect(result, contains("@MappableField(key: 'user_id')"));
        expect(result, contains('final String userId;'));
      });

      test('emits constructor defaults for DB defaults', () {
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

        expect(result, contains('this.isActive = true,'));
        expect(result, contains('this.count = 0,'));
      });

      test('handles table name starting with a number', () {
        final table = TableInfo(
          name: '123_data',
          columns: [
            ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('class Table123Data with Table123DataMappable'));
      });

      test('escapes reserved words in field and class names', () {
        final table = TableInfo(
          name: 'class',
          columns: [
            ColumnInfo(name: 'class', dataType: 'text', isNullable: false),
            ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
          ],
        );

        final result = generator.generateModel(table);

        expect(result, contains('class ClassModel with ClassModelMappable'));
        expect(result, contains(r'final String class$;'));
        expect(result, contains("@MappableField(key: 'class')"));
      });
    });

    group('enum handling', () {
      setUp(() {
        TypeMapper.clearEnums();
      });

      tearDown(() {
        TypeMapper.clearEnums();
      });

      test('generates enum-typed field with default member', () {
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

        final result = generator.generateModel(table);

        expect(result, contains('this.status = BondStoryStatus.pending,'));
        expect(result, contains('final BondStoryStatus status;'));
        expect(
          result,
          contains("import 'enums/bond_story_status.supafreeze.dart';"),
        );
      });
    });

    group('insert models', () {
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

      test('does not emit an insert model by default', () {
        final result = generator.generateModel(table);
        expect(result, isNot(contains('BondStoryPurchasesInsert')));
      });

      test('emits an ignoreNull insert model with optional defaults', () {
        final gen = DartMappableGenerator()
          ..setConfig(const SupafreezeConfig(generateInsertModels: true));
        final result = gen.generateModel(table);

        expect(
          result,
          contains('@MappableClass(ignoreNull: true,'),
        );
        expect(
          result,
          contains(
            'class BondStoryPurchasesInsert '
            'with BondStoryPurchasesInsertMappable',
          ),
        );
        // NOT NULL, no default → required non-null.
        expect(result, contains('required this.bondId,'));
        expect(result, contains('final String bondId;'));
        // NOT NULL with DB default → optional nullable.
        expect(result, contains('this.id,'));
        expect(result, contains('final String? id;'));
        expect(result, contains("@MappableField(key: 'created_at')"));
      });
    });

    group('file helpers', () {
      test('getFileName returns the shared extension', () {
        expect(generator.getFileName('users'), 'users.supafreeze.dart');
        expect(
          generator.getFileName('UserProfiles'),
          'user_profiles.supafreeze.dart',
        );
      });

      test('outputFileNames lists the base and mapper part', () {
        expect(
          generator.outputFileNames('users'),
          ['users.supafreeze.dart', 'users.supafreeze.mapper.dart'],
        );
      });

      test('generateBarrelFile exports every model', () {
        final tables = [
          TableInfo(name: 'users', columns: []),
          TableInfo(name: 'posts', columns: []),
        ];

        final result = generator.generateBarrelFile(tables, '');

        expect(result, contains("export 'users.supafreeze.dart';"));
        expect(result, contains("export 'posts.supafreeze.dart';"));
      });
    });
  });
}
