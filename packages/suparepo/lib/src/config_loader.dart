import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'edge_function_info.dart';

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
      fetch: parseFetchMode(
        resolveValue(yaml['fetch']?.toString()),
      ),
      generateBarrel: yaml['generate_barrel'] == true,
      modelImportPath: yaml['model_import_path']?.toString(),
      rpc: _parseRpcConfig(yaml['rpc']),
      edgeFunctions: _parseEdgeFunctionConfig(
        yaml['edge_functions'],
      ),
    );
  }

  RpcConfig _parseRpcConfig(dynamic value) {
    if (value == null || value is! YamlMap) return const RpcConfig();

    return RpcConfig(
      enabled: value['enabled'] == true,
      output: value['output']?.toString(),
      include: parseStringList(value['include']),
      exclude: parseStringList(value['exclude']),
    );
  }

  EdgeFunctionConfig _parseEdgeFunctionConfig(dynamic value) {
    if (value == null || value is! YamlMap) {
      return const EdgeFunctionConfig();
    }

    return EdgeFunctionConfig(
      enabled: value['enabled'] == true,
      output: value['output']?.toString(),
      functionsPath: value['functions_path']?.toString() ??
          'supabase/functions',
      include: parseStringList(value['include']),
      exclude: parseStringList(value['exclude']),
      models: _parseEdgeFunctionModels(value['models']),
    );
  }

  Map<String, EdgeFunctionModelDef>? _parseEdgeFunctionModels(
    dynamic value,
  ) {
    if (value == null || value is! YamlMap) return null;

    final result = <String, EdgeFunctionModelDef>{};

    for (final entry in value.entries) {
      final funcName = entry.key.toString();
      final funcDef = entry.value as YamlMap?;
      if (funcDef == null) continue;

      result[funcName] = EdgeFunctionModelDef(
        request: _parseFieldDefs(funcDef['request']),
        response: _parseFieldDefs(funcDef['response']),
      );
    }

    return result.isEmpty ? null : result;
  }

  List<EdgeFunctionFieldDef>? _parseFieldDefs(dynamic value) {
    if (value == null || value is! YamlMap) return null;

    final fields = <EdgeFunctionFieldDef>[];
    for (final entry in value.entries) {
      final fieldName = entry.key.toString();
      final fieldDef = entry.value as YamlMap?;
      if (fieldDef == null) continue;

      fields.add(EdgeFunctionFieldDef(
        name: fieldName,
        dataType: fieldDef['type']?.toString() ?? 'text',
        isRequired: fieldDef['required'] == true,
      ));
    }

    return fields.isEmpty ? null : fields;
  }
}

/// RPC configuration
class RpcConfig {
  final bool enabled;
  final String? output;
  final List<String>? include;
  final List<String>? exclude;

  const RpcConfig({
    this.enabled = false,
    this.output,
    this.include,
    this.exclude,
  });

  /// Checks if a function should be included
  bool shouldIncludeFunction(String name) {
    if (include != null && include!.isNotEmpty) {
      return include!.contains(name);
    }
    if (exclude != null && exclude!.isNotEmpty) {
      return !exclude!.contains(name);
    }
    return true;
  }
}

/// Edge Function configuration
class EdgeFunctionConfig {
  final bool enabled;
  final String? output;
  final String functionsPath;
  final List<String>? include;
  final List<String>? exclude;
  final Map<String, EdgeFunctionModelDef>? models;

  const EdgeFunctionConfig({
    this.enabled = false,
    this.output,
    this.functionsPath = 'supabase/functions',
    this.include,
    this.exclude,
    this.models,
  });

  /// Checks if a function should be included
  bool shouldIncludeFunction(String name) {
    if (include != null && include!.isNotEmpty) {
      return include!.contains(name);
    }
    if (exclude != null && exclude!.isNotEmpty) {
      return !exclude!.contains(name);
    }
    return true;
  }
}

/// Configuration for suparepo
class SuparepoConfig extends BaseSupabaseConfig {
  final bool generateBarrel;

  /// Import path for model classes
  final String? modelImportPath;

  /// RPC function generation config
  final RpcConfig rpc;

  /// Edge Function generation config
  final EdgeFunctionConfig edgeFunctions;

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
    this.rpc = const RpcConfig(),
    this.edgeFunctions = const EdgeFunctionConfig(),
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
  rpc.enabled: ${rpc.enabled}
  edgeFunctions.enabled: ${edgeFunctions.enabled}
''';
  }
}
