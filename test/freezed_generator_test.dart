import 'package:test/test.dart';
import 'package:supafreeze/src/freezed_generator.dart';
import 'package:supafreeze/src/schema_fetcher.dart';

void main() {
  late FreezedGenerator generator;

  setUp(() {
    generator = FreezedGenerator();
  });

  group('FreezedGenerator', () {
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

        expect(result, contains("class Users with _\$Users"));
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
            ColumnInfo(name: 'created_at', dataType: 'timestamptz', isNullable: false),
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

        expect(result, contains('class Table123Data'));
      });

      test('sorts columns with required first', () {
        final table = TableInfo(
          name: 'test_table',
          columns: [
            ColumnInfo(name: 'optional_field', dataType: 'text', isNullable: true),
            ColumnInfo(name: 'required_field', dataType: 'text', isNullable: false),
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

        expect(result, contains('class ClassModel'));
      });
    });

    group('getFileName', () {
      test('returns correct file name for table', () {
        expect(generator.getFileName('users'), 'users.supafreeze.dart');
        expect(generator.getFileName('user_profiles'), 'user_profiles.supafreeze.dart');
        expect(generator.getFileName('UserProfiles'), 'user_profiles.supafreeze.dart');
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
