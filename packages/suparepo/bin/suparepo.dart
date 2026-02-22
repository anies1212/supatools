#!/usr/bin/env dart

import 'dart:io';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/config_loader.dart';
import 'package:suparepo/src/repository_generator.dart';
import 'package:suparepo/src/rpc_generator.dart';
import 'package:suparepo/src/edge_function_detector.dart';
import 'package:suparepo/src/edge_function_generator.dart';
import 'package:suparepo/src/ts_type_extractor.dart';
import 'package:suparepo/src/edge_function_info.dart';
import 'package:path/path.dart' as p;

/// CLI tool for suparepo code generation
///
/// Usage:
///   dart run suparepo              # All enabled generators
///   dart run suparepo --repo       # Table repositories only
///   dart run suparepo --rpc        # RPC client only
///   dart run suparepo --edge       # Edge Function client only
///   dart run suparepo --force      # Force regenerate all
void main(List<String> args) async {
  final force = args.contains('--force') || args.contains('-f');
  final repoOnly = args.contains('--repo');
  final rpcOnly = args.contains('--rpc');
  final edgeOnly = args.contains('--edge');
  final hasFilter = repoOnly || rpcOnly || edgeOnly;

  print('🔄 Suparepo: Generating code...');

  final configLoader = SuparepoConfigLoader();
  final config = await configLoader.loadConfig();

  if (config == null) {
    print('❌ Error: suparepo.yaml not found.');
    exit(1);
  }

  final runRepo = !hasFilter || repoOnly;
  final runRpc = !hasFilter || rpcOnly;
  final runEdge = !hasFilter || edgeOnly;

  // Validate config for repo/rpc (need Supabase connection)
  if ((runRepo || (runRpc && config.rpc.enabled)) && !config.isValid) {
    final issues = config.validate();
    print('❌ Error: Configuration incomplete:');
    for (final issue in issues) {
      print('   - $issue');
    }
    exit(1);
  }

  final outputDir = config.output;
  final dir = Directory(outputDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  var totalGenerated = 0;

  // --- Table Repositories ---
  if (runRepo) {
    totalGenerated += await _generateRepositories(config, force);
  }

  // --- RPC Client ---
  if (runRpc && config.rpc.enabled) {
    totalGenerated += await _generateRpcClient(config);
  }

  // --- Edge Function Client ---
  if (runEdge && config.edgeFunctions.enabled) {
    totalGenerated += await _generateEdgeFunctionClient(config);
  }

  // --- SupabaseClient provider ---
  if (config.generateProviders && config.clientProviderOutput != null) {
    totalGenerated += await _generateClientProvider(config);
  }

  // --- RPC/EdgeFunction client providers (separate file) ---
  if (config.generateProviders && config.clientProvidersOutput != null) {
    totalGenerated += await _generateClientProviders(config);
  }

  if (totalGenerated == 0) {
    print('ℹ️  Nothing to generate.');
  } else {
    print('');
    print('🎉 Done! Generated $totalGenerated file(s).');
  }
}

Future<int> _generateRepositories(
  SuparepoConfig config,
  bool force,
) async {
  final fetcher = SchemaFetcher(
    supabaseUrl: config.url!,
    supabaseKey: config.secretKey!,
    schema: config.schema,
  );

  List<TableInfo> tables;
  try {
    print('🌐 Fetching schema...');
    tables = await fetcher.fetchTables();
  } on SchemaFetchException catch (e) {
    print('❌ Failed to fetch schema: $e');
    return 0;
  }

  final filtered =
      tables.where((t) => config.shouldIncludeTable(t.name)).toList();

  if (filtered.isEmpty) {
    print('ℹ️  No tables found matching filter criteria.');
    return 0;
  }

  print(
    '📋 Found ${filtered.length} table(s): '
    '${filtered.map((t) => t.name).join(', ')}',
  );

  final generator = RepositoryGenerator();
  generator.setConfig(config);

  final files = generator.generateAllRepositories(filtered);
  final outputDir = config.output;

  for (final entry in files.entries) {
    final filePath = p.join(outputDir, entry.key);
    await File(filePath).writeAsString(entry.value);
    print('✨ Generated: $filePath');
  }

  return files.length;
}

Future<int> _generateRpcClient(SuparepoConfig config) async {
  final fetcher = SchemaFetcher(
    supabaseUrl: config.url!,
    supabaseKey: config.secretKey!,
    schema: config.schema,
  );

  List<RpcFunctionInfo> functions;
  try {
    print('🌐 Fetching RPC functions...');
    functions = await fetcher.fetchRpcFunctions();
  } on SchemaFetchException catch (e) {
    print('❌ Failed to fetch RPC functions: $e');
    return 0;
  }

  // YAML return_types で上書き（YAML最優先）
  final returnTypes = config.rpc.returnTypes;
  if (returnTypes != null) {
    functions = applyReturnTypeOverrides(functions, returnTypes);
    print('📝 Applied return_types overrides: ${returnTypes.keys.join(', ')}');
  }

  // Apply filters (execute_sql is internal infrastructure, always exclude)
  final filtered = functions
      .where((f) =>
          f.name != 'execute_sql' && config.rpc.shouldIncludeFunction(f.name))
      .toList();

  if (filtered.isEmpty) {
    print('ℹ️  No RPC functions found.');
    return 0;
  }

  print(
    '📋 Found ${filtered.length} RPC function(s): '
    '${filtered.map((f) => f.name).join(', ')}',
  );

  final generator = RpcGenerator();
  final content = generator.generateRpcClient(
    filtered,
    supabaseImport: config.supabaseImport,
  );

  final outputPath =
      config.rpc.output ?? p.join(config.output, 'rpc_client.dart');

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: $outputPath');

  return 1;
}

Future<int> _generateEdgeFunctionClient(
  SuparepoConfig config,
) async {
  final detector = EdgeFunctionDetector();
  final functions = await detector.detect(
    config.edgeFunctions.functionsPath,
  );

  // Apply filters
  final filtered = functions
      .where(
        (f) => config.edgeFunctions.shouldIncludeFunction(f.name),
      )
      .toList();

  if (filtered.isEmpty) {
    print('ℹ️  No Edge Functions found.');
    return 0;
  }

  print(
    '📋 Found ${filtered.length} Edge Function(s): '
    '${filtered.map((f) => f.name).join(', ')}',
  );

  // Build modelDefs: YAML definitions + TS auto-detection
  var modelDefs =
      config.edgeFunctions.models ?? <String, EdgeFunctionModelDef>{};

  if (config.edgeFunctions.autoDetectTypes) {
    final loader = TsTypeExtractorLoader();
    final autoDetected = <String, EdgeFunctionModelDef>{};

    for (final func in filtered) {
      // Skip functions already defined in YAML
      if (modelDefs.containsKey(func.name)) continue;

      final funcDir = p.join(
        config.edgeFunctions.functionsPath,
        func.name,
      );
      final modelDef = await loader.extractFromDirectory(funcDir);
      if (modelDef != null) {
        autoDetected[func.name] = modelDef;
        print('🔍 Auto-detected types: ${func.name}');
      }
    }

    modelDefs = {...modelDefs, ...autoDetected};
  }

  final generator = EdgeFunctionGenerator();
  final content = generator.generateEdgeFunctionClient(
    filtered,
    modelDefs: modelDefs.isEmpty ? null : modelDefs,
    supabaseImport: config.supabaseImport,
  );

  final outputPath = config.edgeFunctions.output ??
      p.join(config.output, 'edge_function_client.dart');

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: $outputPath');

  return 1;
}

/// Generates `supabase_client_provider.dart`.
///
/// When [clientProvidersOutput] is NOT set, RPC/EdgeFunction providers are
/// embedded in this file (unified mode).
/// When [clientProvidersOutput] IS set, only supabaseClient is generated here
/// and RPC/EdgeFunction providers go to the separate file.
Future<int> _generateClientProvider(SuparepoConfig config) async {
  final modelImportPrefix = config.modelImportPrefix;
  final separateProviders = config.clientProvidersOutput != null;

  String? rpcClientImport;
  if (config.rpc.enabled && !separateProviders) {
    final rpcOutput = config.rpc.output;
    if (rpcOutput != null && modelImportPrefix != null) {
      rpcClientImport = '$modelImportPrefix${p.basename(rpcOutput)}';
    } else if (modelImportPrefix != null) {
      rpcClientImport = '${modelImportPrefix}rpc_client.dart';
    } else {
      rpcClientImport = 'rpc_client.dart';
    }
  }

  String? edgeFunctionClientImport;
  if (config.edgeFunctions.enabled && !separateProviders) {
    final edgeOutput = config.edgeFunctions.output;
    if (edgeOutput != null && modelImportPrefix != null) {
      edgeFunctionClientImport = '$modelImportPrefix${p.basename(edgeOutput)}';
    } else if (modelImportPrefix != null) {
      edgeFunctionClientImport =
          '${modelImportPrefix}edge_function_client.dart';
    } else {
      edgeFunctionClientImport = 'edge_function_client.dart';
    }
  }

  final generator = RepositoryGenerator();
  generator.setConfig(config);

  final content = generator.generateSupabaseClientProvider(
    rpcClientImport: rpcClientImport,
    edgeFunctionClientImport: edgeFunctionClientImport,
  );

  final outputFile = File(config.clientProviderOutput!);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: ${config.clientProviderOutput}');

  return 1;
}

/// Generates `client_providers.dart` containing RPC/EdgeFunction providers.
/// This file is written to [clientProvidersOutput] (typically in the data
/// package) and imports supabaseClient from [clientProviderImport].
Future<int> _generateClientProviders(SuparepoConfig config) async {
  final clientProviderImport = config.clientProviderImport;
  if (clientProviderImport == null) {
    print(
      '⚠️  client_providers_output requires client_provider_import. Skipping.',
    );
    return 0;
  }

  final outputPath = config.clientProvidersOutput!;

  // Resolve RPC client import relative to output
  String? rpcClientImport;
  if (config.rpc.enabled) {
    final rpcOutput = config.rpc.output;
    if (rpcOutput != null) {
      rpcClientImport = _relativeImport(outputPath, rpcOutput);
    } else {
      rpcClientImport = _relativeImport(
        outputPath,
        p.join(config.output, 'rpc_client.dart'),
      );
    }
  }

  // Resolve EdgeFunction client import relative to output
  String? edgeFunctionClientImport;
  if (config.edgeFunctions.enabled) {
    final edgeOutput = config.edgeFunctions.output;
    if (edgeOutput != null) {
      edgeFunctionClientImport = _relativeImport(outputPath, edgeOutput);
    } else {
      edgeFunctionClientImport = _relativeImport(
        outputPath,
        p.join(config.output, 'edge_function_client.dart'),
      );
    }
  }

  if (rpcClientImport == null && edgeFunctionClientImport == null) {
    return 0;
  }

  final generator = RepositoryGenerator();
  generator.setConfig(config);

  final content = generator.generateClientProviders(
    clientProviderImport: clientProviderImport,
    rpcClientImport: rpcClientImport,
    edgeFunctionClientImport: edgeFunctionClientImport,
  );

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: $outputPath');

  return 1;
}

/// Computes a relative import path from [from] file to [to] file.
String _relativeImport(String from, String to) {
  final fromDir = p.dirname(from);
  return p.relative(to, from: fromDir);
}
