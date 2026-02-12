#!/usr/bin/env dart

import 'dart:io';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/config_loader.dart';
import 'package:suparepo/src/repository_generator.dart';
import 'package:suparepo/src/rpc_generator.dart';
import 'package:suparepo/src/edge_function_detector.dart';
import 'package:suparepo/src/edge_function_generator.dart';
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
  if ((runRepo || (runRpc && config.rpc.enabled)) &&
      !config.isValid) {
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

  final filtered = tables
      .where((t) => config.shouldIncludeTable(t.name))
      .toList();

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

  // Apply filters
  final filtered = functions
      .where((f) => config.rpc.shouldIncludeFunction(f.name))
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

  final generator = EdgeFunctionGenerator();
  final content = generator.generateEdgeFunctionClient(
    filtered,
    modelDefs: config.edgeFunctions.models,
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
