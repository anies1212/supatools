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
    test('テーブル名からカスタムファイル名を生成', () {
      expect(
        migrator.getCustomFileName('user_profiles'),
        'user_profiles_repository.custom.dart',
      );
    });
  });

  group('extractCustomMethods', () {
    test('標準メソッドのみのファイル → 空リスト', () {
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

    test('カスタムメソッド1つ → 正しく抽出', () {
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

  /// アクティブなユーザーを取得
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
        contains('アクティブなユーザーを取得'),
      );
    });

    test('カスタムメソッド複数 → 全て抽出', () {
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

    test('getAllWith{Relation}は標準メソッドとして除外', () {
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

    test('ネストした波括弧を含むメソッド → 正しい境界検出', () {
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

    test('カスタムimportの検出', () {
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

    test('文字列リテラル内の波括弧はスキップ', () {
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
    test('正しいextensionファイルを生成', () {
      final methods = [
        const MethodInfo(
          name: 'getActive',
          source: '''  /// アクティブなユーザーを取得
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

      expect(code, contains('extension UsersRepositoryCustom on UsersRepository'));
      expect(code, contains("import 'users_repository.dart';"));
      // User型を参照 → model importあり
      expect(code, contains("import '../models/user.supafreeze.dart';"));
      // SupabaseClient型は直接参照なし → supabase importなし
      expect(code, isNot(contains('supabase_flutter')));
      // _client → client 置換
      expect(code, contains('await client'));
      expect(code, isNot(contains('_client')));
    });

    test('SupabaseClient型を直接参照 → supabase importあり', () {
      final methods = [
        const MethodInfo(
          name: 'getClient',
          source:
              '  SupabaseClient get rawClient => client;',
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

    test('model型を参照しない → model importなし', () {
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

    test('カスタムimportが含まれる', () {
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
    test('重複メソッドはスキップ', () {
      const existingCode = '''
extension UsersRepositoryCustom on UsersRepository {
  Future<List<User>> getActive() async {
    // 既存の実装
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

    test('新規メソッドは追加', () {
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

  group('private field移行', () {
    test('カスタムメソッドが参照するprivate fieldが抽出される', () {
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

    test('参照されないprivate fieldは移行しない', () {
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

    test('private fieldがextensionに含まれる', () {
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

    test('複数行のstatic const fieldが正しく抽出される', () {
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
    test('extension本体とimportを正しく抽出', () {
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

  /// アクティブなレコードを取得
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
      // supabase, supafreeze, self-importは除外
      expect(result!.imports, hasLength(1));
      expect(
        result.imports.first,
        "import 'package:data/some_model.dart';",
      );
      // extension本体にメソッドとフィールドが含まれる
      expect(result.body, contains('_joinSelect'));
      expect(result.body, contains('getActive'));
      expect(result.body, contains('アクティブなレコードを取得'));
    });

    test('空のextension → null', () {
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

    test('extensionなし → null', () {
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
    test('未使用のsupabase/supafreeze importを除去', () {
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
      // supabase, supafreeze importが除去される
      expect(cleaned, isNot(contains('package:supabase')));
      expect(cleaned, isNot(contains('.supafreeze.dart')));
      // 参照されているimportは保持
      expect(cleaned, contains('some_result.dart'));
      expect(cleaned, contains('test_repository.dart'));
    });

    test('全importが必要な場合 → null', () {
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

  group('_client → client 置換', () {
    test('メソッド内の_clientがclientに置換される', () {
      final methods = [
        const MethodInfo(
          name: 'test',
          source:
              '  Future<void> test() async {\n'
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

  group('カスタムメソッド埋め込み（RepositoryGenerator連携）', () {
    test('customContentが生成されるクラスに埋め込まれる', () {
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

  /// アクティブなレコードを取得
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

      // カスタムimportが含まれる
      expect(code, contains("import 'package:data/some_model.dart';"));
      // カスタムメソッドがクラス内に埋め込まれる
      expect(code, contains('getActive'));
      expect(code, contains('_joinSelect'));
      // extensionではなくクラス内に存在する
      expect(code, isNot(contains('extension ')));
      // クラス定義がある
      expect(code, contains('class TestTableRepository'));
    });
  });
}
