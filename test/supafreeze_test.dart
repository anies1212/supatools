import 'package:supafreeze/supafreeze.dart';
import 'package:test/test.dart';

void main() {
  group('TypeMapper', () {
    test('maps basic PostgreSQL types to Dart types', () {
      expect(TypeMapper.mapType('int4'), equals('int'));
      expect(TypeMapper.mapType('int8'), equals('int'));
      expect(TypeMapper.mapType('text'), equals('String'));
      expect(TypeMapper.mapType('bool'), equals('bool'));
      expect(TypeMapper.mapType('float8'), equals('double'));
      expect(TypeMapper.mapType('uuid'), equals('String'));
      expect(TypeMapper.mapType('timestamptz'), equals('DateTime'));
    });

    test('maps array types correctly', () {
      expect(TypeMapper.mapType('text[]'), equals('List<String>'));
      expect(TypeMapper.mapType('int4[]'), equals('List<int>'));
      expect(TypeMapper.mapType('uuid[]'), equals('List<String>'));
    });

    test('maps JSON types to Map', () {
      expect(TypeMapper.mapType('json'), equals('Map<String, dynamic>'));
      expect(TypeMapper.mapType('jsonb'), equals('Map<String, dynamic>'));
    });
  });

  group('FreezedGenerator', () {
    test('generates valid Freezed model with .supafreeze.dart extension', () {
      final table = TableInfo(
        name: 'users',
        columns: [
          ColumnInfo(
            name: 'id',
            dataType: 'uuid',
            isNullable: false,
            isPrimaryKey: true,
          ),
          ColumnInfo(
            name: 'name',
            dataType: 'text',
            isNullable: false,
          ),
          ColumnInfo(
            name: 'email',
            dataType: 'text',
            isNullable: true,
          ),
          ColumnInfo(
            name: 'created_at',
            dataType: 'timestamptz',
            isNullable: false,
          ),
        ],
      );

      final generator = FreezedGenerator();
      final code = generator.generateModel(table);

      expect(code, contains('@freezed'));
      expect(code, contains('class Users with _\$Users'));
      expect(code, contains('required String id'));
      expect(code, contains('required String name'));
      expect(code, contains('String? email'));
      expect(code, contains('required DateTime createdAt'));
      expect(code, contains('factory Users.fromJson'));
      // Check for .supafreeze extension in part directives
      expect(code, contains("part 'users.supafreeze.freezed.dart';"));
      expect(code, contains("part 'users.supafreeze.g.dart';"));
    });

    test('converts snake_case to camelCase for field names', () {
      final table = TableInfo(
        name: 'user_profiles',
        columns: [
          ColumnInfo(
            name: 'user_id',
            dataType: 'uuid',
            isNullable: false,
          ),
          ColumnInfo(
            name: 'first_name',
            dataType: 'text',
            isNullable: false,
          ),
        ],
      );

      final generator = FreezedGenerator();
      final code = generator.generateModel(table);

      expect(code, contains('class UserProfiles'));
      expect(code, contains('userId'));
      expect(code, contains('firstName'));
      expect(code, contains("@JsonKey(name: 'user_id')"));
      expect(code, contains("@JsonKey(name: 'first_name')"));
    });

    test('generates files with .supafreeze.dart extension', () {
      final tables = [
        TableInfo(
          name: 'users',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
          ],
        ),
        TableInfo(
          name: 'posts',
          columns: [
            ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
          ],
        ),
      ];

      final generator = FreezedGenerator();
      final files = generator.generateAllModels(tables);

      expect(files.keys, contains('users.supafreeze.dart'));
      expect(files.keys, contains('posts.supafreeze.dart'));
      expect(files.keys, contains('models.dart'));
    });
  });

  group('SupafreezeConfig', () {
    test('validates config with url and key', () {
      final validConfig = SupafreezeConfig(
        url: 'https://example.supabase.co',
        secretKey: 'test-key',
      );
      expect(validConfig.isValid, isTrue);

      final invalidConfig = SupafreezeConfig(
        url: null,
        secretKey: 'test-key',
      );
      expect(invalidConfig.isValid, isFalse);
    });

    test('shouldIncludeTable with include list', () {
      final config = SupafreezeConfig(
        url: 'https://example.supabase.co',
        secretKey: 'test-key',
        include: ['users', 'posts'],
      );

      expect(config.shouldIncludeTable('users'), isTrue);
      expect(config.shouldIncludeTable('posts'), isTrue);
      expect(config.shouldIncludeTable('comments'), isFalse);
    });

    test('shouldIncludeTable with exclude list', () {
      final config = SupafreezeConfig(
        url: 'https://example.supabase.co',
        secretKey: 'test-key',
        exclude: ['_migrations', 'schema_versions'],
      );

      expect(config.shouldIncludeTable('users'), isTrue);
      expect(config.shouldIncludeTable('_migrations'), isFalse);
      expect(config.shouldIncludeTable('schema_versions'), isFalse);
    });
  });
}
