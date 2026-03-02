import 'dart:io';
import 'package:suparepo/src/config_loader.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('config_test_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<String> writeConfig(String yaml) async {
    final path = '${tempDir.path}/suparepo.yaml';
    await File(path).writeAsString(yaml);
    return path;
  }

  group('SuparepoConfigLoader', () {
    test('基本設定のパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
output: lib/repos
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config, isNotNull);
      expect(config!.url, 'https://example.supabase.co');
      expect(config.output, 'lib/repos');
      expect(config.rpc.enabled, isFalse);
      expect(config.edgeFunctions.enabled, isFalse);
    });

    test('RPC設定のパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  output: lib/rpc/rpc_client.dart
  include:
    - get_user_posts
    - search_users
  exclude:
    - internal_cleanup
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.enabled, isTrue);
      expect(
        config.rpc.output,
        'lib/rpc/rpc_client.dart',
      );
      expect(
        config.rpc.include,
        ['get_user_posts', 'search_users'],
      );
      expect(config.rpc.exclude, ['internal_cleanup']);
    });

    test('Edge Function設定のパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
edge_functions:
  enabled: true
  functions_path: supabase/functions
  include:
    - send-email
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.edgeFunctions.enabled, isTrue);
      expect(
        config.edgeFunctions.functionsPath,
        'supabase/functions',
      );
      expect(config.edgeFunctions.include, ['send-email']);
    });

    test('Edge Function modelsセクションのパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
edge_functions:
  enabled: true
  models:
    send-email:
      request:
        to:
          type: text
          required: true
        subject:
          type: text
          required: true
      response:
        success:
          type: bool
          required: true
        message_id:
          type: text
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      final models = config!.edgeFunctions.models;
      expect(models, isNotNull);
      expect(models!.containsKey('send-email'), isTrue);

      final sendEmail = models['send-email']!;
      expect(sendEmail.request, isNotNull);
      expect(sendEmail.request, hasLength(2));
      expect(sendEmail.request![0].name, 'to');
      expect(sendEmail.request![0].dataType, 'text');
      expect(sendEmail.request![0].isRequired, isTrue);
      expect(sendEmail.request![1].name, 'subject');

      expect(sendEmail.response, isNotNull);
      expect(sendEmail.response, hasLength(2));
      expect(sendEmail.response![0].name, 'success');
      expect(sendEmail.response![0].dataType, 'bool');
      expect(sendEmail.response![0].isRequired, isTrue);
      expect(sendEmail.response![1].name, 'message_id');
      expect(sendEmail.response![1].isRequired, isFalse);
    });

    test('client_provider_output/importのパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
generate_providers: true
client_provider_output: ../gateway/lib/supabase/supabase_client_provider.dart
client_provider_import: package:gateway/supabase/supabase_client_provider.dart
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.generateProviders, isTrue);
      expect(
        config.clientProviderOutput,
        '../gateway/lib/supabase/supabase_client_provider.dart',
      );
      expect(
        config.clientProviderImport,
        'package:gateway/supabase/supabase_client_provider.dart',
      );
    });

    test('RPC return_typesのパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  return_types:
    get_my_invite_code: text
    execute_exchange_atomic: void
    get_favorite_products: setof jsonb
    is_active_user: bool
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.returnTypes, isNotNull);
      final rt = config.rpc.returnTypes!;
      expect(rt['get_my_invite_code'], 'text');
      expect(rt['execute_exchange_atomic'], 'void');
      expect(rt['get_favorite_products'], 'setof jsonb');
      expect(rt['is_active_user'], 'bool');
    });

    test('RPC return_types未指定はnull', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.returnTypes, isNull);
    });

    test('RPC generate_result_modelsのパース', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  generate_result_models: true
  result_models_output: lib/models/rpc
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.generateResultModels, isTrue);
      expect(
        config.rpc.resultModelsOutput,
        'lib/models/rpc',
      );
    });

    test('generate_result_modelsデフォルトはfalse', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.generateResultModels, isFalse);
      expect(config.rpc.resultModelsOutput, isNull);
    });

    test('デフォルト値の適用', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.output, 'lib/repositories');
      expect(config.schema, 'public');
      expect(config.generateBarrel, isFalse);
      expect(config.generateProviders, isFalse);
      expect(config.clientProviderOutput, isNull);
      expect(config.clientProviderImport, isNull);
      expect(config.rpc.enabled, isFalse);
      expect(config.rpc.output, isNull);
      expect(config.rpc.include, isNull);
      expect(config.rpc.exclude, isNull);
      expect(config.edgeFunctions.enabled, isFalse);
      expect(
        config.edgeFunctions.functionsPath,
        'supabase/functions',
      );
    });

    test('ファイルが存在しない場合はnull', () async {
      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(
        '${tempDir.path}/nonexistent.yaml',
      );

      expect(config, isNull);
    });
  });

  group('RpcConfig.shouldIncludeFunction', () {
    test('includeリストで指定された関数のみ含める', () {
      const config = RpcConfig(
        include: ['func_a', 'func_b'],
      );

      expect(config.shouldIncludeFunction('func_a'), isTrue);
      expect(config.shouldIncludeFunction('func_b'), isTrue);
      expect(config.shouldIncludeFunction('func_c'), isFalse);
    });

    test('excludeリストで指定された関数を除外', () {
      const config = RpcConfig(
        exclude: ['internal_func'],
      );

      expect(
        config.shouldIncludeFunction('public_func'),
        isTrue,
      );
      expect(
        config.shouldIncludeFunction('internal_func'),
        isFalse,
      );
    });

    test('フィルタなしの場合は全て含める', () {
      const config = RpcConfig();

      expect(config.shouldIncludeFunction('any_func'), isTrue);
    });
  });

  group('EdgeFunctionConfig.shouldIncludeFunction', () {
    test('includeリストで指定された関数のみ含める', () {
      const config = EdgeFunctionConfig(
        include: ['send-email'],
      );

      expect(
        config.shouldIncludeFunction('send-email'),
        isTrue,
      );
      expect(
        config.shouldIncludeFunction('other-func'),
        isFalse,
      );
    });

    test('excludeリストで指定された関数を除外', () {
      const config = EdgeFunctionConfig(
        exclude: ['debug-func'],
      );

      expect(
        config.shouldIncludeFunction('send-email'),
        isTrue,
      );
      expect(
        config.shouldIncludeFunction('debug-func'),
        isFalse,
      );
    });
  });
}
