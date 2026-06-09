import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:test/test.dart';
import 'package:suparepo/src/custom_method_migrator.dart';
import 'package:suparepo/src/repository_generator.dart';

void main() {
  late CustomMethodMigrator migrator;

  setUp(() {
    migrator = CustomMethodMigrator();
  });

  group('getCustomFileName', () {
    test('generates custom file name from table name', () {
      expect(
        migrator.getCustomFileName('user_profiles'),
        'user_profiles_repository.custom.dart',
      );
    });
  });

  group('extractCustomMethods', () {
    test('file with only standard methods returns empty list', () {
      const source = '''
class UsersRepository {
  final SupabaseClient _client;

  UsersRepository(this._client);

  String get tableName => 'users';

  SupabaseClient get client => _client;

  Future<List<User>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => User.fromJson(e)).toList();
  }

  Future<User?> getById(String id) async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return response != null ? User.fromJson(response) : null;
  }

  Future<User> create(User data) async {
    final response = await _client
        .from(tableName)
        .insert(data.toJson())
        .select()
        .single();
    return User.fromJson(response);
  }

  Future<User> update(String id, User data) async {
    final response = await _client
        .from(tableName)
        .update(data.toJson())
        .eq('id', id)
        .select()
        .single();
    return User.fromJson(response);
  }

  Future<void> delete(String id) async {
    await _client
        .from(tableName)
        .delete()
        .eq('id', id);
  }

  Future<int> count() async {
    final response = await _client
        .from(tableName)
        .select()
        .count(CountOption.exact);
    return response.count;
  }

  Future<List<User>> paginate({int page = 1, int perPage = 20}) async {
    final from = (page - 1) * perPage;
    final to = from + perPage - 1;
    final response = await _client
        .from(tableName)
        .select()
        .range(from, to);
    return response.map((e) => User.fromJson(e)).toList();
  }
}
''';

      final result = migrator.extractCustomMethods(source, 'UsersRepository');
      expect(result.customMethods, isEmpty);
    });

    test('single custom method is correctly extracted', () {
      const source = '''
class UsersRepository {
  final SupabaseClient _client;

  UsersRepository(this._client);

  String get tableName => 'users';

  SupabaseClient get client => _client;

  Future<List<User>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => User.fromJson(e)).toList();
  }

  Future<User?> getById(String id) async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return response != null ? User.fromJson(response) : null;
  }

  Future<User> create(User data) async {
    final response = await _client
        .from(tableName)
        .insert(data.toJson())
        .select()
        .single();
    return User.fromJson(response);
  }

  Future<User> update(String id, User data) async {
    final response = await _client
        .from(tableName)
        .update(data.toJson())
        .eq('id', id)
        .select()
        .single();
    return User.fromJson(response);
  }

  Future<void> delete(String id) async {
    await _client
        .from(tableName)
        .delete()
        .eq('id', id);
  }

  Future<int> count() async {
    final response = await _client
        .from(tableName)
        .select()
        .count(CountOption.exact);
    return response.count;
  }

  Future<List<User>> paginate({int page = 1, int perPage = 20}) async {
    final from = (page - 1) * perPage;
    final to = from + perPage - 1;
    final response = await _client
        .from(tableName)
        .select()
        .range(from, to);
    return response.map((e) => User.fromJson(e)).toList();
  }

  /// Get active users
  Future<List<User>> getActive() async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('is_active', true);
    return response.map((e) => User.fromJson(e)).toList();
  }
}
''';

      final result = migrator.extractCustomMethods(source, 'UsersRepository');
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'getActive');
      expect(
        result.customMethods.first.source,
        contains('getActive'),
      );
      expect(
        result.customMethods.first.source,
        contains('Get active users'),
      );
    });

    test('multiple custom methods are all extracted', () {
      const source = '''
class ProjectsRepository {
  final SupabaseClient _client;

  ProjectsRepository(this._client);

  String get tableName => 'projects';

  SupabaseClient get client => _client;

  Future<List<Project>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => Project.fromJson(e)).toList();
  }

  Future<Project?> getById(String id) async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('id', id)
        .maybeSingle();
    return response != null ? Project.fromJson(response) : null;
  }

  Future<Project> create(Project data) async {
    final response = await _client
        .from(tableName)
        .insert(data.toJson())
        .select()
        .single();
    return Project.fromJson(response);
  }

  Future<Project> update(String id, Project data) async {
    final response = await _client
        .from(tableName)
        .update(data.toJson())
        .eq('id', id)
        .select()
        .single();
    return Project.fromJson(response);
  }

  Future<void> delete(String id) async {
    await _client.from(tableName).delete().eq('id', id);
  }

  Future<int> count() async {
    final response = await _client
        .from(tableName)
        .select()
        .count(CountOption.exact);
    return response.count;
  }

  Future<List<Project>> paginate({int page = 1, int perPage = 20}) async {
    final from = (page - 1) * perPage;
    final to = from + perPage - 1;
    final response = await _client
        .from(tableName)
        .select()
        .range(from, to);
    return response.map((e) => Project.fromJson(e)).toList();
  }

  Future<List<Project>> getActive() async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('is_active', true);
    return response.map((e) => Project.fromJson(e)).toList();
  }

  Future<Project?> getByExternalId(String externalId) async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('external_id', externalId)
        .maybeSingle();
    return response != null ? Project.fromJson(response) : null;
  }

  Future<String> getParticipationUrl(String projectId) async {
    final response = await _client
        .from(tableName)
        .select('participation_url')
        .eq('id', projectId)
        .single();
    return response['participation_url'] as String;
  }
}
''';

      final result = migrator.extractCustomMethods(
        source,
        'ProjectsRepository',
      );
      expect(result.customMethods, hasLength(3));
      expect(
        result.customMethods.map((m) => m.name).toList(),
        ['getActive', 'getByExternalId', 'getParticipationUrl'],
      );
    });

    test('getAllWith{Relation} is excluded as standard method', () {
      const source = '''
class OrdersRepository {
  final SupabaseClient _client;

  OrdersRepository(this._client);

  String get tableName => 'orders';

  SupabaseClient get client => _client;

  Future<List<Order>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => Order.fromJson(e)).toList();
  }

  Future<List<Order>> getAllWithUser() async {
    final response = await _client
        .from(tableName)
        .select('*, user:users(*)');
    return response.map((e) => Order.fromJson(e)).toList();
  }

  Future<List<Order>> getByStatus(String status) async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('status', status);
    return response.map((e) => Order.fromJson(e)).toList();
  }
}
''';

      final result = migrator.extractCustomMethods(
        source,
        'OrdersRepository',
      );
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'getByStatus');
    });

    test('method with nested braces has correct boundary detection', () {
      const source = '''
class UsersRepository {
  final SupabaseClient _client;

  UsersRepository(this._client);

  String get tableName => 'users';

  SupabaseClient get client => _client;

  Future<List<User>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => User.fromJson(e)).toList();
  }

  Future<List<User>> searchByCondition(Map<String, dynamic> condition) async {
    var query = _client.from(tableName).select();
    for (final entry in condition.entries) {
      if (entry.value != null) {
        query = query.eq(entry.key, entry.value);
      }
    }
    final response = await query;
    return response.map((e) {
      return User.fromJson(e);
    }).toList();
  }
}
''';

      final result = migrator.extractCustomMethods(
        source,
        'UsersRepository',
      );
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'searchByCondition');
      expect(
        result.customMethods.first.source,
        contains('for (final entry'),
      );
      expect(
        result.customMethods.first.source,
        contains('}).toList()'),
      );
    });

    test('detects custom imports', () {
      const source = '''
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.supafreeze.dart';
import 'package:some_package/some_package.dart';
import '../utils/date_helper.dart';

class UsersRepository {
  final SupabaseClient _client;

  UsersRepository(this._client);

  String get tableName => 'users';

  SupabaseClient get client => _client;

  Future<List<User>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => User.fromJson(e)).toList();
  }
}
''';

      final result = migrator.extractCustomMethods(
        source,
        'UsersRepository',
      );
      expect(result.customImports, hasLength(2));
      expect(
        result.customImports,
        contains("import 'package:some_package/some_package.dart';"),
      );
      expect(
        result.customImports,
        contains("import '../utils/date_helper.dart';"),
      );
    });

    test('skips braces inside string literals', () {
      const source = '''
class UsersRepository {
  final SupabaseClient _client;

  UsersRepository(this._client);

  String get tableName => 'users';

  SupabaseClient get client => _client;

  Future<List<User>> getAll() async {
    final response = await _client.from(tableName).select();
    return response.map((e) => User.fromJson(e)).toList();
  }

  Future<void> logAction(String userId) async {
    final message = 'User {action} for id: \$userId';
    print('Debug: \${message}');
    await _client.from('logs').insert({'user_id': userId, 'message': message});
  }
}
''';

      final result = migrator.extractCustomMethods(
        source,
        'UsersRepository',
      );
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'logAction');
    });
  });

  group('generateExtensionFile', () {
    test('generates correct extension file', () {
      final methods = [
        const MethodInfo(
          name: 'getActive',
          source: '''  /// Get active users
  Future<List<User>> getActive() async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('is_active', true);
    return response.map((e) => User.fromJson(e)).toList();
  }''',
        ),
      ];

      final code = migrator.generateExtensionFile(
        className: 'UsersRepository',
        repositoryFileName: 'users_repository.dart',
        methods: methods,
        customImports: [],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
        modelImport: '../models/user.supafreeze.dart',
      );

      expect(
          code, contains('extension UsersRepositoryCustom on UsersRepository'));
      expect(code, contains("import 'users_repository.dart';"));
      // references User type -> model import present
      expect(code, contains("import '../models/user.supafreeze.dart';"));
      // SupabaseClient not directly referenced -> no supabase import
      expect(code, isNot(contains('supabase_flutter')));
      // _client -> client replacement
      expect(code, contains('await client'));
      expect(code, isNot(contains('_client')));
    });

    test('directly references SupabaseClient -> supabase import present', () {
      final methods = [
        const MethodInfo(
          name: 'getClient',
          source: '  SupabaseClient get rawClient => client;',
        ),
      ];

      final code = migrator.generateExtensionFile(
        className: 'UsersRepository',
        repositoryFileName: 'users_repository.dart',
        methods: methods,
        customImports: [],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
      );

      expect(code, contains('supabase_flutter'));
    });

    test('no model type reference -> no model import', () {
      final methods = [
        const MethodInfo(
          name: 'doSomething',
          source: '  Future<void> doSomething() async {}',
        ),
      ];

      final code = migrator.generateExtensionFile(
        className: 'UsersRepository',
        repositoryFileName: 'users_repository.dart',
        methods: methods,
        customImports: [],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
        modelImport: '../models/user.supafreeze.dart',
      );

      expect(code, isNot(contains('supafreeze')));
    });

    test('includes custom imports', () {
      final code = migrator.generateExtensionFile(
        className: 'UsersRepository',
        repositoryFileName: 'users_repository.dart',
        methods: [
          const MethodInfo(
            name: 'test',
            source: '  Future<void> test() async {}',
          ),
        ],
        customImports: [
          "import 'package:some_package/some_package.dart';",
        ],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
      );

      expect(
        code,
        contains("import 'package:some_package/some_package.dart';"),
      );
    });
  });

  group('mergeWithExisting', () {
    test('skips duplicate methods', () {
      const existingCode = '''
extension UsersRepositoryCustom on UsersRepository {
  Future<List<User>> getActive() async {
    // existing implementation
    return [];
  }
}
''';

      final newMethods = [
        const MethodInfo(
          name: 'getActive',
          source: '  Future<List<User>> getActive() async { return []; }',
        ),
      ];

      final result = migrator.mergeWithExisting(existingCode, newMethods);
      expect(result.skipped, contains('getActive'));
      expect(result.added, isEmpty);
    });

    test('adds new methods', () {
      const existingCode = '''
extension UsersRepositoryCustom on UsersRepository {
  Future<List<User>> getActive() async {
    return [];
  }
}
''';

      final newMethods = [
        const MethodInfo(
          name: 'getActive',
          source: '  Future<List<User>> getActive() async { return []; }',
        ),
        const MethodInfo(
          name: 'getInactive',
          source:
              '  Future<List<User>> getInactive() async {\n    return [];\n  }',
        ),
      ];

      final result = migrator.mergeWithExisting(existingCode, newMethods);
      expect(result.skipped, contains('getActive'));
      expect(result.added, contains('getInactive'));
      expect(result.mergedCode, contains('getInactive'));
    });
  });

  group('private field migration', () {
    test('private fields referenced by custom methods are extracted', () {
      const source = '''
class TestRepo {
  final SupabaseClient _client;

  TestRepo(this._client);

  String get tableName => 'test';

  SupabaseClient get client => _client;

  Future<List<Map<String, dynamic>>> getAll() async {
    final response = await _client.from(tableName).select();
    return response;
  }

  static const _joinSelect = 'id, name, products(*)';

  Future<List<Map<String, dynamic>>> getActive() async {
    final response = await _client
        .from(tableName)
        .select(_joinSelect)
        .eq('is_active', true);
    return response;
  }
}
''';

      final result = migrator.extractCustomMethods(source, 'TestRepo');
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'getActive');
      expect(result.privateFields, hasLength(1));
      expect(result.privateFields.first.name, '_joinSelect');
    });

    test('unreferenced private fields are not migrated', () {
      const source = '''
class TestRepo {
  final SupabaseClient _client;

  TestRepo(this._client);

  String get tableName => 'test';

  SupabaseClient get client => _client;

  Future<List<Map<String, dynamic>>> getAll() async {
    final response = await _client.from(tableName).select();
    return response;
  }

  static const _unusedField = 'unused';

  Future<List<Map<String, dynamic>>> getActive() async {
    final response = await _client
        .from(tableName)
        .select()
        .eq('is_active', true);
    return response;
  }
}
''';

      final result = migrator.extractCustomMethods(source, 'TestRepo');
      expect(result.customMethods, hasLength(1));
      expect(result.privateFields, isEmpty);
    });

    test('private fields are included in extension', () {
      final code = migrator.generateExtensionFile(
        className: 'TestRepo',
        repositoryFileName: 'test_repository.dart',
        methods: [
          const MethodInfo(
            name: 'getActive',
            source: '  Future<void> getActive() async {}',
          ),
        ],
        customImports: [],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
        privateFields: [
          const MethodInfo(
            name: '_joinSelect',
            source: "  static const _joinSelect = 'id, name';",
          ),
        ],
      );

      expect(code, contains("static const _joinSelect = 'id, name'"));
      expect(code, contains('getActive'));
    });

    test('multi-line static const fields are correctly extracted', () {
      const source = '''
class TestRepo {
  final SupabaseClient _client;

  TestRepo(this._client);

  String get tableName => 'test';

  SupabaseClient get client => _client;

  Future<List<Map<String, dynamic>>> getAll() async {
    return await _client.from(tableName).select();
  }

  static const _selectQuery =
      'id, name, description, products(image_url, name)';

  Future<List<Map<String, dynamic>>> custom() async {
    return await _client.from(tableName).select(_selectQuery);
  }
}
''';

      final result = migrator.extractCustomMethods(source, 'TestRepo');
      expect(result.customMethods, hasLength(1));
      expect(result.customMethods.first.name, 'custom');
      expect(result.privateFields, hasLength(1));
      expect(result.privateFields.first.name, '_selectQuery');
      expect(
        result.privateFields.first.source,
        contains('products(image_url, name)'),
      );
    });
  });

  group('extractFromCustomFile', () {
    test('correctly extracts extension body and imports', () {
      const customCode = '''
// Custom methods migrated from TestRepository
// This file is auto-migrated by suparepo and will NOT be overwritten.
// ignore_for_file: type=lint

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:data/test.supafreeze.dart';
import 'package:data/some_model.dart';
import 'test_repository.dart';

extension TestRepositoryCustom on TestRepository {
  static const _joinSelect = 'id, name, products(*)';

  /// Get active records
  Future<List<Map<String, dynamic>>> getActive() async {
    final response = await client
        .from(tableName)
        .select(_joinSelect)
        .eq('is_active', true);
    return response;
  }
}
''';

      final result = migrator.extractFromCustomFile(
        customCode,
        'test_repository.dart',
      );

      expect(result, isNotNull);
      // supabase, supafreeze, self-import are excluded
      expect(result!.imports, hasLength(1));
      expect(
        result.imports.first,
        "import 'package:data/some_model.dart';",
      );
      // extension body contains methods and fields
      expect(result.body, contains('_joinSelect'));
      expect(result.body, contains('getActive'));
      expect(result.body, contains('Get active records'));
    });

    test('empty extension returns null', () {
      const customCode = '''
extension TestRepositoryCustom on TestRepository {
}
''';

      final result = migrator.extractFromCustomFile(
        customCode,
        'test_repository.dart',
      );

      expect(result, isNull);
    });

    test('no extension returns null', () {
      const customCode = '''
// Just a comment
import 'test_repository.dart';
''';

      final result = migrator.extractFromCustomFile(
        customCode,
        'test_repository.dart',
      );

      expect(result, isNull);
    });
  });

  group('cleanupCustomFileImports', () {
    test('removes unused supabase/supafreeze imports', () {
      const customCode = '''
// ignore_for_file: type=lint

import 'package:supabase/supabase.dart';
import 'package:data/test.supafreeze.dart';
import 'package:data/some_result.dart';
import 'test_repository.dart';

extension TestRepositoryCustom on TestRepository {
  Future<List<SomeResult>> getActive() async {
    return [];
  }
}
''';

      final cleaned = migrator.cleanupCustomFileImports(customCode);
      expect(cleaned, isNotNull);
      // supabase, supafreeze imports are removed
      expect(cleaned, isNot(contains('package:supabase')));
      expect(cleaned, isNot(contains('.supafreeze.dart')));
      // referenced imports are kept
      expect(cleaned, contains('some_result.dart'));
      expect(cleaned, contains('test_repository.dart'));
    });

    test('removes supafreeze import with partial class name match', () {
      // tentame_projects.supafreeze.dart -> TentameProjects
      // should not match TentameProjectsRepository as substring
      const customCode = '''
// ignore_for_file: type=lint

import 'package:data/tentame_projects.supafreeze.dart';
import 'package:data/get_active_result.dart';
import 'tentame_projects_repository.dart';

extension TentameProjectsRepositoryCustom on TentameProjectsRepository {
  Future<List<GetActiveResult>> getActive() async {
    final response = await client.from(tableName).select();
    return response.map(GetActiveResult.fromRow).toList();
  }
}
''';

      final cleaned = migrator.cleanupCustomFileImports(customCode);
      expect(cleaned, isNotNull);
      expect(cleaned, isNot(contains('.supafreeze.dart')));
      expect(cleaned, contains('get_active_result.dart'));
      expect(cleaned, contains('tentame_projects_repository.dart'));
    });

    test('returns null when all imports are needed', () {
      const customCode = '''
import 'package:data/some_result.dart';
import 'test_repository.dart';

extension TestRepositoryCustom on TestRepository {
  Future<SomeResult> get() async => SomeResult();
}
''';

      final cleaned = migrator.cleanupCustomFileImports(customCode);
      expect(cleaned, isNull);
    });
  });

  group('_client to client replacement', () {
    test('_client in methods is replaced with client', () {
      final methods = [
        const MethodInfo(
          name: 'test',
          source: '  Future<void> test() async {\n'
              '    await _client.from(tableName).select();\n'
              '  }',
        ),
      ];

      final code = migrator.generateExtensionFile(
        className: 'TestRepository',
        repositoryFileName: 'test_repository.dart',
        methods: methods,
        customImports: [],
        supabaseImport: 'package:supabase_flutter/supabase_flutter.dart',
      );

      expect(code, contains('await client.from'));
      expect(code, isNot(contains('_client')));
    });
  });

  group('custom method embedding (RepositoryGenerator integration)', () {
    test('customContent is embedded in generated class', () {
      final generator = RepositoryGenerator();
      final table = TableInfo(
        name: 'test_table',
        columns: [
          ColumnInfo(
            name: 'id',
            dataType: 'uuid',
            isNullable: false,
            isPrimaryKey: true,
          ),
        ],
      );

      const customContent = CustomFileContent(
        body: '''
  static const _joinSelect = 'id, name, products(*)';

  /// Get active records
  Future<List<Map<String, dynamic>>> getActive() async {
    final response = await client
        .from(tableName)
        .select(_joinSelect)
        .eq('is_active', true);
    return response;
  }
''',
        imports: [
          "import 'package:data/some_model.dart';",
        ],
      );

      final code = generator.generateRepository(
        table,
        customContent: customContent,
      );

      // custom import is included
      expect(code, contains("import 'package:data/some_model.dart';"));
      // custom methods are embedded in the class
      expect(code, contains('getActive'));
      expect(code, contains('_joinSelect'));
      // exists in class, not extension
      expect(code, isNot(contains('extension ')));
      // class definition exists
      expect(code, contains('class TestTableRepository'));
    });
  });
}
