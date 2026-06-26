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
    test('parses basic configuration', () async {
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

    test('parses RPC configuration', () async {
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

    test('parses Edge Function configuration', () async {
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

    test('parses Edge Function models section', () async {
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

    test('parses client_provider_output/import', () async {
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

    test('parses RPC return_types', () async {
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

    test('RPC return_types is null when not specified', () async {
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

    test('parses RPC generate_result_models', () async {
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

    test('parses RPC result_models', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  generate_result_models: true
  result_models:
    get_membership_rank_info:
      rank: { type: text }
      upload_days: { type: int4 }
      is_active: { type: bool }
    get_user_profile:
      name: { type: text }
      avatar_url: { type: text }
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      expect(config!.rpc.resultModels, isNotNull);
      final models = config.rpc.resultModels!;
      expect(models, hasLength(2));

      final rankInfo = models['get_membership_rank_info']!;
      expect(rankInfo, hasLength(3));
      expect(rankInfo[0].name, 'rank');
      expect(rankInfo[0].dataType, 'text');
      expect(rankInfo[1].name, 'upload_days');
      expect(rankInfo[1].dataType, 'int4');
      expect(rankInfo[2].name, 'is_active');
      expect(rankInfo[2].dataType, 'bool');

      final profile = models['get_user_profile']!;
      expect(profile, hasLength(2));
      expect(profile[0].name, 'name');
      expect(profile[1].name, 'avatar_url');
    });

    test('RPC result_models is null when not specified', () async {
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

      expect(config!.rpc.resultModels, isNull);
    });

    test('RPC result_models shorthand syntax', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  result_models:
    get_stats:
      total: int4
      name: text
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      final models = config!.rpc.resultModels!;
      final stats = models['get_stats']!;
      expect(stats[0].name, 'total');
      expect(stats[0].dataType, 'int4');
      expect(stats[1].name, 'name');
      expect(stats[1].dataType, 'text');
    });

    test('RPC result_models parses nullable flag', () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  result_models:
    list_cards_with_top_price:
      card_master_id: { type: int8 }
      image_url: { type: text, nullable: true }
      top_price: { type: int4, nullable: true }
      store_count: { type: int4 }
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      final cols = config!.rpc.resultModels!['list_cards_with_top_price']!;
      expect(cols[0].name, 'card_master_id');
      expect(cols[0].nullable, isFalse);
      expect(cols[1].name, 'image_url');
      expect(cols[1].nullable, isTrue);
      expect(cols[2].name, 'top_price');
      expect(cols[2].nullable, isTrue);
      expect(cols[3].name, 'store_count');
      expect(cols[3].nullable, isFalse);
    });

    test('RPC result_models shorthand defaults nullable to false',
        () async {
      final path = await writeConfig('''
url: https://example.supabase.co
secret_key: test-secret-key-long-enough
rpc:
  enabled: true
  result_models:
    get_stats:
      total: int4
''');

      final loader = SuparepoConfigLoader(
        envVars: const {},
      );
      final config = await loader.loadConfig(path);

      final cols = config!.rpc.resultModels!['get_stats']!;
      expect(cols[0].nullable, isFalse);
    });

    test('generate_result_models defaults to false', () async {
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

    test('applies default values', () async {
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

    test('returns null when file does not exist', () async {
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
    test('include list only includes specified functions', () {
      const config = RpcConfig(
        include: ['func_a', 'func_b'],
      );

      expect(config.shouldIncludeFunction('func_a'), isTrue);
      expect(config.shouldIncludeFunction('func_b'), isTrue);
      expect(config.shouldIncludeFunction('func_c'), isFalse);
    });

    test('exclude list excludes specified functions', () {
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

    test('includes all when no filter is set', () {
      const config = RpcConfig();

      expect(config.shouldIncludeFunction('any_func'), isTrue);
    });
  });

  group('EdgeFunctionConfig.shouldIncludeFunction', () {
    test('include list only includes specified functions', () {
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

    test('exclude list excludes specified functions', () {
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
