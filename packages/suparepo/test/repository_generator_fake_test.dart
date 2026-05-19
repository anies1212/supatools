import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/config_loader.dart';
import 'package:suparepo/src/custom_method_migrator.dart';
import 'package:suparepo/src/repository_generator.dart';
import 'package:test/test.dart';

void main() {
  late RepositoryGenerator generator;

  setUp(() {
    generator = RepositoryGenerator();
  });

  TableInfo usersTable({List<ColumnInfo>? extraColumns}) {
    return TableInfo(
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
          isPrimaryKey: false,
        ),
        ...?extraColumns,
      ],
    );
  }

  group('file/class naming', () {
    test('getFakeFileName converts table name to .fake.dart', () {
      expect(
        generator.getFakeFileName('user_profiles'),
        'user_profiles_repository.fake.dart',
      );
    });

    test('getFakeClassName prefixes Fake to PascalCase repository', () {
      expect(
        generator.getFakeClassName('user_profiles'),
        'FakeUserProfilesRepository',
      );
    });
  });

  group('generateFake — untyped (no model import)', () {
    test('produces a class that implements the real repository', () {
      final output = generator.generateFake(usersTable());

      expect(output, contains("import 'users_repository.dart';"));
      expect(
        output,
        contains('class FakeUsersRepository implements UsersRepository'),
      );
    });

    test('uses Map<String, dynamic> as the record type', () {
      final output = generator.generateFake(usersTable());

      expect(output, contains('Map<dynamic, Map<String, dynamic>> store;'));
      expect(
        output,
        contains('Future<List<Map<String, dynamic>>> getAll()'),
      );
      expect(
        output,
        contains(
          'Future<Map<String, dynamic>?> getById(String id)',
        ),
      );
    });

    test('seed uses PK extracted from the map', () {
      final output = generator.generateFake(usersTable());
      expect(output, contains("store[record['id']] = record;"));
    });

    test('paginate uses sublist with clamp', () {
      final output = generator.generateFake(usersTable());
      expect(output, contains('all.sublist(from, to)'));
    });

    test('tableName getter returns the table name verbatim', () {
      final output = generator.generateFake(usersTable());
      expect(output, contains("String get tableName => 'users';"));
    });

    test('client getter throws UnimplementedError', () {
      final output = generator.generateFake(usersTable());
      expect(
        output,
        contains('SupabaseClient get client => throw UnimplementedError'),
      );
    });
  });

  group('generateFake — typed (with supafreeze model)', () {
    setUp(() {
      generator.setConfig(
        const SuparepoConfig(
          url: 'https://example.supabase.co',
          secretKey: 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk',
          modelImportPrefix: '',
          generateFakes: true,
        ),
      );
    });

    test('imports the model from prefix', () {
      final output = generator.generateFake(usersTable());
      expect(output, contains("import 'users.supafreeze.dart';"));
    });

    test('uses the model class as the record type', () {
      final output = generator.generateFake(usersTable());
      expect(output, contains('Map<dynamic, Users> store;'));
      expect(output, contains('Future<List<Users>> getAll()'));
      expect(output, contains('Future<Users?> getById(String id)'));
    });

    test('seed extracts PK via toJson()', () {
      final output = generator.generateFake(usersTable());
      expect(
        output,
        contains("store[record.toJson()['id']] = record;"),
      );
    });
  });

  group('generateFake — relations', () {
    test('relation methods delegate to getAll', () {
      final table = usersTable(
        extraColumns: [
          ColumnInfo(
            name: 'company_id',
            dataType: 'uuid',
            isNullable: true,
            isPrimaryKey: false,
            foreignKey: ForeignKeyInfo(
              column: 'company_id',
              referencedTable: 'companies',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      final output = generator.generateFake(table);
      expect(
        output,
        contains('Future<List<Map<String, dynamic>>> getAllWithCompany() '
            '=> getAll();'),
      );
    });
  });

  group('generateFake — custom methods', () {
    test('public method body is replaced with UnimplementedError stub', () {
      const customBody = '''
  /// Fetches the active user.
  Future<Map<String, dynamic>?> getActive() async {
    final response = await client
        .from(tableName)
        .select()
        .eq('is_active', true)
        .maybeSingle();
    return response;
  }
''';
      final customContent = CustomFileContent(
        body: customBody,
        imports: [],
      );

      final output = generator.generateFake(
        usersTable(),
        customContent: customContent,
      );

      expect(output, contains('@override'));
      expect(
        output,
        contains('Future<Map<String, dynamic>?> getActive()'),
      );
      expect(
        output,
        contains(
          "'FakeUsersRepository.getActive is not faked. '",
        ),
      );
      // The original body must be gone.
      expect(output, isNot(contains('is_active')));
    });

    test('private members are skipped', () {
      const customBody = '''
  Future<int> _helperCalc() async => 42;

  Future<Map<String, dynamic>?> findOne() async {
    return null;
  }
''';
      final customContent = CustomFileContent(
        body: customBody,
        imports: [],
      );

      final output = generator.generateFake(
        usersTable(),
        customContent: customContent,
      );

      expect(output, isNot(contains('_helperCalc')));
      expect(output, contains('findOne()'));
    });

    test('preserves custom imports', () {
      final customContent = CustomFileContent(
        body: '  Future<void> ping() async {}\n',
        imports: ["import 'package:my_lib/my_lib.dart';"],
      );

      final output = generator.generateFake(
        usersTable(),
        customContent: customContent,
      );

      expect(
        output,
        contains("import 'package:my_lib/my_lib.dart';"),
      );
    });

    test('multi-line signature is preserved', () {
      const customBody = '''
  Future<List<Map<String, dynamic>>> queryByRange({
    required DateTime start,
    required DateTime end,
  }) async {
    return [];
  }
''';
      final customContent = CustomFileContent(
        body: customBody,
        imports: [],
      );

      final output = generator.generateFake(
        usersTable(),
        customContent: customContent,
      );

      expect(output, contains('Future<List<Map<String, dynamic>>>'));
      expect(output, contains('queryByRange({'));
      expect(output, contains('required DateTime start,'));
      expect(output, contains('required DateTime end,'));
      expect(output, contains('=> throw UnimplementedError('));
    });
  });

  group('generateAllRepositories — generateFakes opt-in', () {
    test('emits *.fake.dart when generateFakes is enabled', () {
      generator.setConfig(
        const SuparepoConfig(
          url: 'https://example.supabase.co',
          secretKey: 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk',
          generateFakes: true,
        ),
      );

      final files = generator.generateAllRepositories([usersTable()]);

      expect(files.keys, contains('users_repository.dart'));
      expect(files.keys, contains('users_repository.fake.dart'));
    });

    test('does not emit fakes when the flag is off', () {
      generator.setConfig(
        const SuparepoConfig(
          url: 'https://example.supabase.co',
          secretKey: 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk',
        ),
      );

      final files = generator.generateAllRepositories([usersTable()]);

      expect(files.keys, contains('users_repository.dart'));
      expect(
        files.keys.any((k) => k.endsWith('.fake.dart')),
        isFalse,
      );
    });
  });

  group('CustomMethodMigrator — signature extraction', () {
    final migrator = CustomMethodMigrator();

    test('extracts a simple async method signature', () {
      const source = '  Future<int> count() async {\n    return 0;\n  }';
      expect(
        migrator.extractMemberSignature(source)?.trim(),
        'Future<int> count()',
      );
    });

    test('extracts a method with named parameters', () {
      const source =
          '  Future<List<int>> page({int p = 1, int s = 20}) async {\n  '
          '  return [];\n  }';
      expect(
        migrator.extractMemberSignature(source)?.trim(),
        'Future<List<int>> page({int p = 1, int s = 20})',
      );
    });

    test('extracts a getter signature', () {
      const source = '  String get label => "hello";';
      expect(
        migrator.extractMemberSignature(source)?.trim(),
        'String get label',
      );
    });
  });
}
