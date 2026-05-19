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
      modelImportPrefix: yaml['model_import_prefix']?.toString(),
      supabaseImport:
          yaml['supabase_import']?.toString() ?? defaultSupabaseImport,
      generateProviders: yaml['generate_providers'] == true,
      clientProviderOutput: yaml['client_provider_output']?.toString(),
      clientProviderImport: yaml['client_provider_import']?.toString(),
      clientProvidersOutput: yaml['client_providers_output']?.toString(),
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
      returnTypes: _parseReturnTypes(value['return_types']),
      generateResultModels: value['generate_result_models'] == true,
      resultModelsOutput: value['result_models_output']?.toString(),
      resultModels: _parseResultModels(value['result_models']),
      migrationsPath: value['migrations_path']?.toString(),
    );
  }

  /// Parses `result_models` YAML section into column definitions.
  ///
  /// ```yaml
  /// result_models:
  ///   get_membership_rank_info:
  ///     rank: { type: text }
  ///     upload_days: { type: int4 }
  /// ```
  Map<String, List<RpcTableColumn>>? _parseResultModels(dynamic value) {
    if (value == null || value is! YamlMap) return null;

    final result = <String, List<RpcTableColumn>>{};
    for (final entry in value.entries) {
      final funcName = entry.key.toString();
      final fieldsDef = entry.value;
      if (fieldsDef == null || fieldsDef is! YamlMap) continue;

      final columns = <RpcTableColumn>[];
      for (final field in fieldsDef.entries) {
        final fieldName = field.key.toString();
        final fieldDef = field.value;
        final dataType = fieldDef is YamlMap
            ? (fieldDef['type']?.toString() ?? 'text')
            : fieldDef?.toString() ?? 'text';
        columns.add(RpcTableColumn(
          name: fieldName,
          dataType: dataType,
        ));
      }

      if (columns.isNotEmpty) {
        result[funcName] = columns;
      }
    }

    return result.isEmpty ? null : result;
  }

  Map<String, String>? _parseReturnTypes(dynamic value) {
    if (value == null || value is! YamlMap) return null;

    final result = <String, String>{};
    for (final entry in value.entries) {
      result[entry.key.toString()] = entry.value.toString();
    }
    return result.isEmpty ? null : result;
  }

  EdgeFunctionConfig _parseEdgeFunctionConfig(dynamic value) {
    if (value == null || value is! YamlMap) {
      return const EdgeFunctionConfig();
    }

    return EdgeFunctionConfig(
      enabled: value['enabled'] == true,
      output: value['output']?.toString(),
      functionsPath:
          value['functions_path']?.toString() ?? 'supabase/functions',
      include: parseStringList(value['include']),
      exclude: parseStringList(value['exclude']),
      models: _parseEdgeFunctionModels(value['models']),
      autoDetectTypes: value['auto_detect_types'] != false,
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

  /// Manual return type overrides: function name → PG type name.
  /// e.g. `{'get_my_invite_code': 'text', 'get_items': 'setof jsonb'}`
  /// `setof` prefix sets `returnsSetOf: true`.
  final Map<String, String>? returnTypes;

  /// When true, generates Freezed result model classes for
  /// RETURNS TABLE functions and YAML-defined result_models.
  final bool generateResultModels;

  /// Output directory for result model files.
  /// If null, models are written next to the RPC client file.
  final String? resultModelsOutput;

  /// YAML-defined column schemas for functions that return json/jsonb.
  /// Maps function name → list of column definitions.
  /// These are merged into `RpcFunctionInfo.tableColumns` during generation.
  final Map<String, List<RpcTableColumn>>? resultModels;

  /// Path to a directory containing SQL migration files. When set
  /// (or when a default such as `../supabase/migrations` exists),
  /// suparepo parses `CREATE FUNCTION` statements locally to recover
  /// RPC return types — useful when `execute_sql` is not installed
  /// or PostgREST's OpenAPI omits response schemas.
  final String? migrationsPath;

  const RpcConfig({
    this.enabled = false,
    this.output,
    this.include,
    this.exclude,
    this.returnTypes,
    this.generateResultModels = false,
    this.resultModelsOutput,
    this.resultModels,
    this.migrationsPath,
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

  /// Whether to auto-detect request/response types from TypeScript source.
  /// Enabled by default. Functions with YAML model definitions take precedence.
  final bool autoDetectTypes;

  const EdgeFunctionConfig({
    this.enabled = false,
    this.output,
    this.functionsPath = 'supabase/functions',
    this.include,
    this.exclude,
    this.models,
    this.autoDetectTypes = true,
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

/// Default Supabase import for Flutter projects
const defaultSupabaseImport = 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase import for pure Dart projects
const pureDartSupabaseImport = 'package:supabase/supabase.dart';

/// Configuration for suparepo
class SuparepoConfig extends BaseSupabaseConfig {
  final bool generateBarrel;

  /// Import path for model classes (barrel file).
  /// If set, all repositories import this single path.
  final String? modelImportPath;

  /// Import prefix for individual model files.
  /// When set, each repository imports `{prefix}{table_name}.supafreeze.dart`.
  /// Takes precedence over [modelImportPath].
  final String? modelImportPrefix;

  /// Supabase package import path used in generated code.
  /// Defaults to 'package:supabase_flutter/supabase_flutter.dart'.
  /// Use 'package:supabase/supabase.dart' for pure Dart packages.
  final String supabaseImport;

  /// Whether to generate Riverpod providers for repositories and RPC client.
  /// When enabled, each repository file includes a `@Riverpod(keepAlive: true)`
  /// provider function, and a `supabase_client_provider.dart` is generated.
  final bool generateProviders;

  /// Custom output path for `supabase_client_provider.dart`.
  /// When set, the file is written to this path instead of `{output}/`.
  /// Example: `../gateway/lib/supabase/supabase_client_provider.dart`
  final String? clientProviderOutput;

  /// Custom import path for `supabase_client_provider.dart` in generated code.
  /// When set, repositories and RPC client use this import instead of
  /// a relative import.
  /// Example: `package:gateway/supabase/supabase_client_provider.dart`
  final String? clientProviderImport;

  /// Custom output path for `client_providers.dart`.
  /// When set, RPC/EdgeFunction providers are generated in a separate file
  /// at this path (inside the data package), instead of being embedded in
  /// `supabase_client_provider.dart`.
  /// Example: `lib/client_providers.dart`
  final String? clientProvidersOutput;

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
    this.modelImportPrefix,
    this.supabaseImport = defaultSupabaseImport,
    this.generateProviders = false,
    this.clientProviderOutput,
    this.clientProviderImport,
    this.clientProvidersOutput,
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
  modelImportPrefix: ${modelImportPrefix ?? 'none'}
  generateProviders: $generateProviders
  clientProviderOutput: ${clientProviderOutput ?? 'none'}
  clientProviderImport: ${clientProviderImport ?? 'none'}
  clientProvidersOutput: ${clientProvidersOutput ?? 'none'}
  rpc.enabled: ${rpc.enabled}
  edgeFunctions.enabled: ${edgeFunctions.enabled}
''';
  }
}
