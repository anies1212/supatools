import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';

/// Loads and resolves configuration from various sources
class SuparepoConfigLoader extends BaseConfigLoader {
  SuparepoConfigLoader({
    super.dartDefines,
    super.envVars,
  });

  /// Loads configuration from suparepo.yaml
  Future<SuparepoConfig?> loadConfig(
      [String configPath = 'suparepo.yaml']) async {
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      return null;
    }

    // Load .env file if exists
    await loadDotEnv();

    final content = await configFile.readAsString();
    final yaml = loadYaml(content) as YamlMap?;

    if (yaml == null) return null;

    return SuparepoConfig(
      url: resolveValue(yaml['url']?.toString()),
      secretKey: resolveValue(yaml['secret_key']?.toString()),
      output: yaml['output']?.toString() ?? 'lib/repositories',
      schema: yaml['schema']?.toString() ?? 'public',
      include: parseStringList(yaml['include']),
      exclude: parseStringList(yaml['exclude']),
      fetch: parseFetchMode(resolveValue(yaml['fetch']?.toString())),
      generateBarrel: yaml['generate_barrel'] == true,
      modelImportPath: yaml['model_import_path']?.toString(),
    );
  }
}

/// Configuration for suparepo
class SuparepoConfig extends BaseSupabaseConfig {
  final bool generateBarrel;

  /// Import path for model classes (e.g., 'package:myapp/models/models.dart')
  /// If not specified, repositories will use dynamic types
  final String? modelImportPath;

  const SuparepoConfig({
    super.url,
    super.secretKey,
    super.output = 'lib/repositories',
    super.schema = 'public',
    super.include,
    super.exclude,
    super.fetch = FetchMode.always,
    this.generateBarrel = false,
    this.modelImportPath,
  });

  /// Returns detailed configuration status for debugging
  String toDebugString() {
    return '''
SuparepoConfig:
  url: ${url != null ? '${url!.substring(0, 30)}...' : 'NOT SET'}
  secretKey: ${secretKey != null ? '***${secretKey!.substring(secretKey!.length - 4)}' : 'NOT SET'}
  output: $output
  schema: $schema
  fetch: $fetch
  include: ${include ?? 'none'}
  exclude: ${exclude ?? 'none'}
  generateBarrel: $generateBarrel
  modelImportPath: ${modelImportPath ?? 'none'}
''';
  }
}
