import 'dart:io';
import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/config_loader.dart';

void main() {
  group('ConfigLoader', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('supafreeze_test_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    group('loadConfig', () {
      test('returns null when config file does not exist', () async {
        final loader = ConfigLoader();
        final config =
            await loader.loadConfig('${tempDir.path}/nonexistent.yaml');

        expect(config, isNull);
      });

      test('loads config from yaml file', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString('''
url: https://test.supabase.co
secret_key: test-secret-key
output: lib/generated
schema: public
''');

        final loader = ConfigLoader();
        final config = await loader.loadConfig(configFile.path);

        expect(config, isNotNull);
        expect(config!.url, 'https://test.supabase.co');
        expect(config.secretKey, 'test-secret-key');
        expect(config.output, 'lib/generated');
        expect(config.schema, 'public');
      });

      test('uses default values for optional fields', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString('''
url: https://test.supabase.co
secret_key: test-key
''');

        final loader = ConfigLoader();
        final config = await loader.loadConfig(configFile.path);

        expect(config!.output, 'lib/models');
        expect(config.schema, 'public');
        expect(config.fetch, FetchMode.always);
        expect(config.generateBarrel, false);
      });

      test('parses include list', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString('''
url: https://test.supabase.co
secret_key: test-key
include:
  - users
  - posts
''');

        final loader = ConfigLoader();
        final config = await loader.loadConfig(configFile.path);

        expect(config!.include, ['users', 'posts']);
      });

      test('parses exclude list', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString('''
url: https://test.supabase.co
secret_key: test-key
exclude:
  - _migrations
  - audit_logs
''');

        final loader = ConfigLoader();
        final config = await loader.loadConfig(configFile.path);

        expect(config!.exclude, ['_migrations', 'audit_logs']);
      });

      test('parses fetch mode', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString('''
url: https://test.supabase.co
secret_key: test-key
fetch: if_no_cache
''');

        final loader = ConfigLoader();
        final config = await loader.loadConfig(configFile.path);

        expect(config!.fetch, FetchMode.ifNoCache);
      });
    });

    group('variable resolution', () {
      test('resolves variables from environment', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString(r'''
url: ${TEST_URL}
secret_key: ${TEST_KEY}
''');

        final loader = ConfigLoader(
          envVars: {
            'TEST_URL': 'https://from-env.supabase.co',
            'TEST_KEY': 'env-secret-key',
          },
        );
        final config = await loader.loadConfig(configFile.path);

        expect(config!.url, 'https://from-env.supabase.co');
        expect(config.secretKey, 'env-secret-key');
      });

      test('resolves variables from .env file', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString(r'''
url: ${DOTENV_URL}
secret_key: ${DOTENV_KEY}
''');

        final dotEnvFile = File('${tempDir.path}/.env');
        await dotEnvFile.writeAsString('''
DOTENV_URL=https://from-dotenv.supabase.co
DOTENV_KEY=dotenv-secret-key
''');

        // Need to run from temp dir to pick up .env
        final currentDir = Directory.current;
        Directory.current = tempDir;

        try {
          final loader = ConfigLoader();
          final config = await loader.loadConfig(configFile.path);

          expect(config!.url, 'https://from-dotenv.supabase.co');
          expect(config.secretKey, 'dotenv-secret-key');
        } finally {
          Directory.current = currentDir;
        }
      });

      test('dart-define takes priority over env vars', () async {
        final configFile = File('${tempDir.path}/supafreeze.yaml');
        await configFile.writeAsString(r'''
url: ${MY_URL}
secret_key: test
''');

        final loader = ConfigLoader(
          dartDefines: {'MY_URL': 'https://from-dart-define.supabase.co'},
          envVars: {'MY_URL': 'https://from-env.supabase.co'},
        );
        final config = await loader.loadConfig(configFile.path);

        expect(config!.url, 'https://from-dart-define.supabase.co');
      });
    });
  });

  group('SupafreezeConfig', () {
    group('isValid', () {
      test('returns true when url and secretKey are set', () {
        const config = SupafreezeConfig(
          url: 'https://test.supabase.co',
          secretKey: 'secret-key',
        );

        expect(config.isValid, isTrue);
      });

      test('returns false when url is missing', () {
        const config = SupafreezeConfig(secretKey: 'secret-key');

        expect(config.isValid, isFalse);
      });

      test('returns false when secretKey is missing', () {
        const config = SupafreezeConfig(url: 'https://test.supabase.co');

        expect(config.isValid, isFalse);
      });
    });

    group('shouldIncludeTable', () {
      test('includes all tables by default', () {
        const config = SupafreezeConfig();

        expect(config.shouldIncludeTable('users'), isTrue);
        expect(config.shouldIncludeTable('posts'), isTrue);
      });

      test('only includes tables in include list', () {
        const config = SupafreezeConfig(include: ['users', 'posts']);

        expect(config.shouldIncludeTable('users'), isTrue);
        expect(config.shouldIncludeTable('posts'), isTrue);
        expect(config.shouldIncludeTable('comments'), isFalse);
      });

      test('excludes tables in exclude list', () {
        const config = SupafreezeConfig(exclude: ['_migrations', 'audit_logs']);

        expect(config.shouldIncludeTable('users'), isTrue);
        expect(config.shouldIncludeTable('_migrations'), isFalse);
        expect(config.shouldIncludeTable('audit_logs'), isFalse);
      });
    });

    group('validate', () {
      test('returns empty list for valid config', () {
        const config = SupafreezeConfig(
          url: 'https://test.supabase.co',
          secretKey: 'a-valid-secret-key-longer-than-20-chars',
        );

        expect(config.validate(), isEmpty);
      });

      test('returns issues for missing url', () {
        const config = SupafreezeConfig(
          secretKey: 'a-valid-secret-key-longer-than-20-chars',
        );

        final issues = config.validate();
        expect(issues, contains(contains('URL is not configured')));
      });

      test('returns issues for non-https url', () {
        const config = SupafreezeConfig(
          url: 'http://test.supabase.co',
          secretKey: 'a-valid-secret-key-longer-than-20-chars',
        );

        final issues = config.validate();
        expect(issues, contains(contains('should start with https')));
      });

      test('returns issues for short secret key', () {
        const config = SupafreezeConfig(
          url: 'https://test.supabase.co',
          secretKey: 'short',
        );

        final issues = config.validate();
        expect(issues, contains(contains('appears too short')));
      });

      test('returns issues when both include and exclude are set', () {
        const config = SupafreezeConfig(
          url: 'https://test.supabase.co',
          secretKey: 'a-valid-secret-key-longer-than-20-chars',
          include: ['users'],
          exclude: ['posts'],
        );

        final issues = config.validate();
        expect(issues, contains(contains('Both include and exclude')));
      });
    });
  });

  group('FetchMode', () {
    test('has correct values', () {
      expect(FetchMode.values, contains(FetchMode.always));
      expect(FetchMode.values, contains(FetchMode.ifNoCache));
      expect(FetchMode.values, contains(FetchMode.never));
    });
  });
}
