import 'dart:io';
import 'package:yaml/yaml.dart';

/// Fetch mode for schema retrieval
enum FetchMode {
  /// Always fetch from DB (default)
  always,

  /// Only fetch if no cache exists
  ifNoCache,

  /// Never fetch, always use cache (offline mode)
  never,
}

/// Loads and resolves configuration from various sources
class ConfigLoader {
  final Map<String, String> _dartDefines;
  final Map<String, String> _envVars;
  Map<String, String>? _dotEnvVars;

  ConfigLoader({
    Map<String, String>? dartDefines,
    Map<String, String>? envVars,
  })  : _dartDefines = dartDefines ?? const {},
        _envVars = envVars ?? Platform.environment;

  /// Loads configuration from supafreeze.yaml
  Future<SupafreezeConfig?> loadConfig([String configPath = 'supafreeze.yaml']) async {
    final configFile = File(configPath);
    if (!await configFile.exists()) {
      return null;
    }

    // Load .env file if exists
    await _loadDotEnv();

    final content = await configFile.readAsString();
    final yaml = loadYaml(content) as YamlMap?;

    if (yaml == null) return null;

    return SupafreezeConfig(
      url: _resolveValue(yaml['url']?.toString()),
      secretKey: _resolveValue(yaml['secret_key']?.toString()),
      output: yaml['output']?.toString() ?? 'lib/models',
      schema: yaml['schema']?.toString() ?? 'public',
      include: _parseStringList(yaml['include']),
      exclude: _parseStringList(yaml['exclude']),
      fetch: _parseFetchMode(_resolveValue(yaml['fetch']?.toString())),
      generateBarrel: yaml['generate_barrel'] == true,
    );
  }

  /// Loads variables from .env file
  Future<void> _loadDotEnv([String path = '.env']) async {
    final file = File(path);
    if (!await file.exists()) {
      _dotEnvVars = {};
      return;
    }

    final vars = <String, String>{};
    final lines = await file.readAsLines();

    for (final line in lines) {
      final trimmed = line.trim();

      // Skip empty lines and comments
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final eqIndex = trimmed.indexOf('=');
      if (eqIndex == -1) continue;

      final key = trimmed.substring(0, eqIndex).trim();
      final rawValue = trimmed.substring(eqIndex + 1).trim();

      // Remove surrounding quotes if present
      final value = _unquote(rawValue);

      vars[key] = value;
    }

    _dotEnvVars = vars;
  }

  String _unquote(String value) {
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  /// Resolves a value that may contain variable references
  ///
  /// Supports:
  /// - ${VAR_NAME} - environment variable or .env
  /// - $env{VAR_NAME} - explicit environment variable
  /// - $define{VAR_NAME} - dart-define variable
  /// - $dotenv{VAR_NAME} - explicit .env variable
  String? _resolveValue(String? value) {
    if (value == null) return null;

    var result = value;

    // Pattern: ${VAR_NAME} - auto-resolve (dart-define > .env > env)
    result = result.replaceAllMapped(
      RegExp(r'\$\{(\w+)\}'),
      (match) {
        final varName = match.group(1)!;
        return _getValue(varName) ?? '';
      },
    );

    // Pattern: $env{VAR_NAME} - explicit environment variable
    result = result.replaceAllMapped(
      RegExp(r'\$env\{(\w+)\}'),
      (match) {
        final varName = match.group(1)!;
        return _envVars[varName] ?? '';
      },
    );

    // Pattern: $define{VAR_NAME} - dart-define variable
    result = result.replaceAllMapped(
      RegExp(r'\$define\{(\w+)\}'),
      (match) {
        final varName = match.group(1)!;
        return _dartDefines[varName] ?? '';
      },
    );

    // Pattern: $dotenv{VAR_NAME} - explicit .env variable
    result = result.replaceAllMapped(
      RegExp(r'\$dotenv\{(\w+)\}'),
      (match) {
        final varName = match.group(1)!;
        return _dotEnvVars?[varName] ?? '';
      },
    );

    return result.isEmpty ? null : result;
  }

  /// Gets a value with priority: dart-define > .env > environment
  String? _getValue(String name) {
    // 1. Check dart-define first
    if (_dartDefines.containsKey(name)) {
      return _dartDefines[name];
    }

    // 2. Check .env file
    if (_dotEnvVars?.containsKey(name) == true) {
      return _dotEnvVars![name];
    }

    // 3. Check environment variables
    if (_envVars.containsKey(name)) {
      return _envVars[name];
    }

    return null;
  }

  List<String>? _parseStringList(dynamic value) {
    if (value == null) return null;
    if (value is YamlList) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  FetchMode _parseFetchMode(String? value) => switch (value?.toLowerCase()) {
    'always' => FetchMode.always,
    'if_no_cache' || 'ifnocache' => FetchMode.ifNoCache,
    'never' => FetchMode.never,
    _ => FetchMode.always,
  };
}

/// Exception thrown when configuration is invalid
class ConfigException implements Exception {
  final String message;
  final String? field;
  final String? hint;

  const ConfigException(this.message, {this.field, this.hint});

  @override
  String toString() {
    final buffer = StringBuffer('ConfigException: $message');
    if (field != null) {
      buffer.write(' (field: $field)');
    }
    if (hint != null) {
      buffer.write('\nHint: $hint');
    }
    return buffer.toString();
  }
}

/// Configuration for supafreeze
class SupafreezeConfig {
  final String? url;
  final String? secretKey;
  final String output;
  final String schema;
  final List<String>? include;
  final List<String>? exclude;
  final FetchMode fetch;
  final bool generateBarrel;

  const SupafreezeConfig({
    this.url,
    this.secretKey,
    this.output = 'lib/models',
    this.schema = 'public',
    this.include,
    this.exclude,
    this.fetch = FetchMode.always,
    this.generateBarrel = false,
  });

  bool get isValid => url != null && url!.isNotEmpty && secretKey != null && secretKey!.isNotEmpty;

  /// Validates the configuration and returns a list of issues
  List<String> validate() {
    final issues = <String>[];

    if (url == null || url!.isEmpty) {
      issues.add('Supabase URL is not configured. Set SUPABASE_URL in .env or environment.');
    } else if (!url!.startsWith('https://')) {
      issues.add('Supabase URL should start with https://');
    }

    if (secretKey == null || secretKey!.isEmpty) {
      issues.add('Supabase secret key is not configured. Set SUPABASE_SECRET_KEY in .env or environment.');
    } else if (secretKey!.length < 20) {
      issues.add('Supabase secret key appears too short. Make sure you\'re using the service_role key.');
    }

    if (include != null && exclude != null && include!.isNotEmpty && exclude!.isNotEmpty) {
      issues.add('Both include and exclude lists are specified. Use only one.');
    }

    return issues;
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

  /// Checks if a table should be included in generation
  bool shouldIncludeTable(String tableName) {
    // If include list is specified, only include those tables
    if (include != null && include!.isNotEmpty) {
      return include!.contains(tableName);
    }

    // If exclude list is specified, exclude those tables
    if (exclude != null && exclude!.isNotEmpty) {
      return !exclude!.contains(tableName);
    }

    // Include all by default
    return true;
  }
}
