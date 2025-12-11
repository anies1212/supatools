import 'dart:io';
import 'package:yaml/yaml.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';

/// Loads and resolves configuration from various sources
class ConfigLoader extends BaseConfigLoader {
  ConfigLoader({
    super.dartDefines,
    super.envVars,
  });

  /// Loads configuration from supafreeze.yaml
  Future<SupafreezeConfig?> loadConfig(
      [String configPath = 'supafreeze.yaml']) async {
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      return null;
    }

    // Load .env file if exists
    await loadDotEnv();

    final content = await configFile.readAsString();
    final yaml = loadYaml(content) as YamlMap?;

    if (yaml == null) return null;

    return SupafreezeConfig(
      url: resolveValue(yaml['url']?.toString()),
      secretKey: resolveValue(yaml['secret_key']?.toString()),
      output: yaml['output']?.toString() ?? 'lib/models',
      schema: yaml['schema']?.toString() ?? 'public',
      include: parseStringList(yaml['include']),
      exclude: parseStringList(yaml['exclude']),
      fetch: parseFetchMode(resolveValue(yaml['fetch']?.toString())),
      generateBarrel: yaml['generate_barrel'] == true,
      embedRelations: yaml['embed_relations'] == true,
      relations: _parseRelationsConfig(yaml['relations']),
    );
  }

  /// Parses the relations configuration from YAML
  Map<String, RelationConfig>? _parseRelationsConfig(dynamic value) {
    if (value == null) return null;
    if (value is! YamlMap) return null;

    final result = <String, RelationConfig>{};

    for (final entry in value.entries) {
      final tableName = entry.key.toString();
      final tableConfig = entry.value;

      if (tableConfig is YamlMap) {
        final relationOverrides = <String, RelationOverride>{};

        for (final relEntry in tableConfig.entries) {
          final relationName = relEntry.key.toString();
          final relConfig = relEntry.value;

          if (relConfig == false) {
            // Disable this relation
            relationOverrides[relationName] = RelationOverride.disabled();
          } else if (relConfig is YamlMap) {
            // Custom relation config
            relationOverrides[relationName] = RelationOverride(
              enabled: relConfig['enabled'] != false,
              table: relConfig['table']?.toString(),
              foreignKey: relConfig['foreign_key']?.toString(),
              referencedColumn: relConfig['referenced_column']?.toString(),
            );
          }
        }

        result[tableName] = RelationConfig(overrides: relationOverrides);
      }
    }

    return result.isEmpty ? null : result;
  }
}

/// Configuration for relation overrides on a specific relation
class RelationOverride {
  /// Whether this relation should be embedded
  final bool enabled;

  /// Override the target table name
  final String? table;

  /// Override the foreign key column name
  final String? foreignKey;

  /// Override the referenced column name
  final String? referencedColumn;

  const RelationOverride({
    this.enabled = true,
    this.table,
    this.foreignKey,
    this.referencedColumn,
  });

  /// Creates a disabled relation override
  factory RelationOverride.disabled() => const RelationOverride(enabled: false);
}

/// Configuration for relations on a specific table
class RelationConfig {
  /// Overrides for specific relations (key is relation name derived from FK column)
  final Map<String, RelationOverride> overrides;

  const RelationConfig({this.overrides = const {}});

  /// Gets the override for a specific relation, or null if none
  RelationOverride? getOverride(String relationName) => overrides[relationName];

  /// Checks if a relation is enabled (true by default unless explicitly disabled)
  bool isEnabled(String relationName) {
    final override = overrides[relationName];
    return override?.enabled ?? true;
  }
}

/// Configuration for supafreeze
class SupafreezeConfig extends BaseSupabaseConfig {
  final bool generateBarrel;

  /// Whether to automatically embed related objects based on FK detection
  final bool embedRelations;

  /// Per-table relation configuration overrides
  final Map<String, RelationConfig>? relations;

  const SupafreezeConfig({
    super.url,
    super.secretKey,
    super.output = 'lib/models',
    super.schema = 'public',
    super.include,
    super.exclude,
    super.fetch = FetchMode.always,
    this.generateBarrel = false,
    this.embedRelations = false,
    this.relations,
  });

  /// Gets the relation config for a specific table
  RelationConfig? getRelationConfig(String tableName) => relations?[tableName];

  /// Checks if a specific relation should be embedded
  bool shouldEmbedRelation(String tableName, String relationName) {
    if (!embedRelations) return false;

    final tableConfig = relations?[tableName];
    if (tableConfig == null) return true; // Default: embed

    return tableConfig.isEnabled(relationName);
  }

  /// Returns detailed configuration status for debugging
  String toDebugString() {
    return '''
SupafreezeConfig:
  url: ${url != null ? '${url!.substring(0, 30)}...' : 'NOT SET'}
  secretKey: ${secretKey != null ? '***${secretKey!.substring(secretKey!.length - 4)}' : 'NOT SET'}
  output: $output
  schema: $schema
  fetch: $fetch
  include: ${include ?? 'none'}
  exclude: ${exclude ?? 'none'}
  generateBarrel: $generateBarrel
''';
  }
}
