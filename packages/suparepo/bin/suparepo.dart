#!/usr/bin/env dart

import 'dart:io';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:suparepo/src/config_loader.dart';
import 'package:recase/recase.dart';
import 'package:suparepo/src/custom_method_migrator.dart';
import 'package:suparepo/src/repository_generator.dart';
import 'package:suparepo/src/supa_query_generator.dart';
import 'package:suparepo/src/rpc_generator.dart';
import 'package:suparepo/src/rpc_result_model_generator.dart';
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
///   dart run suparepo --no-migrate # Skip custom method migration
void main(List<String> args) async {
  final force = args.contains('--force') || args.contains('-f');
  final noMigrate = args.contains('--no-migrate');
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
    totalGenerated += await _generateRepositories(
      config,
      force,
      migrate: !noMigrate,
    );
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
  bool force, {
  bool migrate = true,
}) async {
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
  final outputDir = config.output;

  var generatedCount = 0;

  // Migrate custom methods: inspect existing files before overwrite
  if (migrate) {
    final migrator = CustomMethodMigrator();

    for (final table in filtered) {
      final repoFileName = generator.getFileName(table.name);
      final repoFilePath = p.join(outputDir, repoFileName);
      final existingFile = File(repoFilePath);

      if (!await existingFile.exists()) continue;

      final existingCode = await existingFile.readAsString();
      final className = generator.getRepositoryClassName(table.name);
      final result = migrator.extractCustomMethods(
        existingCode,
        className,
      );

      if (!result.hasCustomCode) continue;

      final customFileName = migrator.getCustomFileName(table.name);
      final customFilePath = p.join(outputDir, customFileName);
      final customFile = File(customFilePath);

      // Resolve model import path
      String? modelImport;
      if (config.modelImportPrefix != null) {
        final modelFile = '${ReCase(table.name).snakeCase}.supafreeze.dart';
        modelImport = '${config.modelImportPrefix}$modelFile';
      } else if (config.modelImportPath != null) {
        modelImport = config.modelImportPath;
      }

      if (await customFile.exists()) {
        // Merge with existing extension file
        final existingCustomCode = await customFile.readAsString();
        final mergeResult = migrator.mergeWithExisting(
          existingCustomCode,
          result.customMethods,
        );

        if (mergeResult.added.isNotEmpty) {
          await customFile.writeAsString(mergeResult.mergedCode);
          for (final name in mergeResult.added) {
            print('🔀 Migrated: $name → $customFileName');
          }
          generatedCount++;
        }
        for (final name in mergeResult.skipped) {
          print(
            '⚠️  Skipped: $name '
            '(already in $customFileName)',
          );
        }
      } else {
        // Generate new extension file
        final extensionCode = migrator.generateExtensionFile(
          className: className,
          repositoryFileName: repoFileName,
          methods: result.customMethods,
          customImports: result.customImports,
          supabaseImport: config.supabaseImport,
          modelImport: modelImport,
          privateFields: result.privateFields,
        );

        await customFile.writeAsString(extensionCode);
        for (final method in result.customMethods) {
          print('🔀 Migrated: ${method.name} → $customFileName');
        }
        generatedCount++;
      }
    }
  }

  // Process @SupaQuery annotations in .custom.dart files
  final queryGenerator = SupaQueryGenerator();

  for (final table in filtered) {
    final customFileName =
        '${ReCase(table.name).snakeCase}_repository.custom.dart';
    final customFilePath = p.join(outputDir, customFileName);
    final customFile = File(customFilePath);

    if (!await customFile.exists()) continue;

    final customCode = await customFile.readAsString();
    final processed = queryGenerator.processCustomFile(
      customCode,
      table.name,
    );

    if (processed != null) {
      await customFile.writeAsString(processed);
      print('⚡ Generated @SupaQuery methods: $customFileName');
      generatedCount++;
    }
  }

  // Read .custom.dart files and embed custom methods into generated
  // repository classes
  final customContents = <String, CustomFileContent>{};
  final embedMigrator = CustomMethodMigrator();

  for (final table in filtered) {
    final customFileName = embedMigrator.getCustomFileName(table.name);
    final customFilePath = p.join(outputDir, customFileName);
    final customFile = File(customFilePath);

    if (!await customFile.exists()) continue;

    final customCode = await customFile.readAsString();
    final repoFileName = generator.getFileName(table.name);
    final content = embedMigrator.extractFromCustomFile(
      customCode,
      repoFileName,
    );

    if (content != null) {
      customContents[table.name] = content;
      print('📎 Embedding custom methods: $customFileName');
    }

    // Clean up unused imports in .custom.dart
    final cleaned = embedMigrator.cleanupCustomFileImports(customCode);
    if (cleaned != null) {
      await customFile.writeAsString(cleaned);
      print('🧹 Cleaned imports: $customFileName');
      generatedCount++;
    }
  }

  // Generate repositories (overwrite)
  final files = generator.generateAllRepositories(
    filtered,
    customContents: customContents,
  );

  for (final entry in files.entries) {
    final filePath = p.join(outputDir, entry.key);
    await File(filePath).writeAsString(entry.value);
    print('✨ Generated: $filePath');
  }

  return files.length + generatedCount;
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

  // Surface non-fatal warnings (e.g. execute_sql introspection failures)
  for (final warning in fetcher.warnings) {
    print('⚠️  $warning');
  }

  // SQL migration fallback: fill in return types from local *.sql files
  // when introspection couldn't resolve them. Auto-detect common
  // locations or honor `rpc.migrations_path` when set explicitly.
  functions = await _applySqlMigrationFallback(functions, config);

  // Override with YAML return_types (YAML takes highest priority)
  final returnTypes = config.rpc.returnTypes;
  if (returnTypes != null) {
    functions = applyReturnTypeOverrides(functions, returnTypes);
    print('📝 Applied return_types overrides: ${returnTypes.keys.join(', ')}');
  }

  // Apply filters (execute_sql is internal infrastructure, always exclude)
  var filtered = functions
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

  // Merge YAML result_models into tableColumns
  final resultModels = config.rpc.resultModels;
  if (resultModels != null) {
    filtered = filtered.map((func) {
      final columns = resultModels[func.name];
      if (columns == null) return func;
      return func.copyWith(tableColumns: columns);
    }).toList();
    print(
      '📝 Applied result_models: '
      '${resultModels.keys.join(', ')}',
    );
  }

  var generated = 0;

  // Generate result models if enabled
  final generateModels = config.rpc.generateResultModels;
  String? resultModelsImportPrefix;

  if (generateModels) {
    final modelGenerator = RpcResultModelGenerator();
    final modelFiles = modelGenerator.generateAllResultModels(filtered);

    if (modelFiles.isNotEmpty) {
      final rpcOutputPath =
          config.rpc.output ?? p.join(config.output, 'rpc_client.dart');
      final rpcDir = p.dirname(rpcOutputPath);
      final modelsDir = config.rpc.resultModelsOutput ?? rpcDir;

      final modelsDirectory = Directory(modelsDir);
      if (!await modelsDirectory.exists()) {
        await modelsDirectory.create(recursive: true);
      }

      for (final entry in modelFiles.entries) {
        final modelPath = p.join(modelsDir, entry.key);
        await File(modelPath).writeAsString(entry.value);
        print('✨ Generated: $modelPath');
        generated++;
      }

      // Compute import prefix for RPC client
      if (modelsDir != rpcDir) {
        resultModelsImportPrefix = '${p.relative(modelsDir, from: rpcDir)}/';
      }
    }

    // Generate error classes for functions with detected error codes
    final errorFiles = modelGenerator.generateAllErrorClasses(filtered);
    if (errorFiles.isNotEmpty) {
      final rpcOutputPath =
          config.rpc.output ?? p.join(config.output, 'rpc_client.dart');
      final rpcDir = p.dirname(rpcOutputPath);
      final modelsDir = config.rpc.resultModelsOutput ?? rpcDir;

      final modelsDirectory = Directory(modelsDir);
      if (!await modelsDirectory.exists()) {
        await modelsDirectory.create(recursive: true);
      }

      for (final entry in errorFiles.entries) {
        final errorPath = p.join(modelsDir, entry.key);
        await File(errorPath).writeAsString(entry.value);
        print('✨ Generated: $errorPath');
        generated++;
      }
    }
  }

  final generator = RpcGenerator();
  final content = generator.generateRpcClient(
    filtered,
    supabaseImport: config.supabaseImport,
    generateResultModels: generateModels,
    resultModelsImportPrefix: resultModelsImportPrefix,
  );

  final outputPath =
      config.rpc.output ?? p.join(config.output, 'rpc_client.dart');

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: $outputPath');

  return generated + 1;
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
    flattenRequestParams: config.edgeFunctions.flattenRequestParams,
  );

  final outputPath = config.edgeFunctions.output ??
      p.join(config.output, 'edge_function_client.dart');

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(content);
  print('✨ Generated: $outputPath');

  var generated = 1;

  // Generate error class files
  if (modelDefs.isNotEmpty) {
    final errorFiles = generator.generateErrorClasses(
      modelDefs,
      supabaseImport: config.supabaseImport,
    );

    final outputDir = p.dirname(outputPath);
    for (final entry in errorFiles.entries) {
      final errorPath = p.join(outputDir, entry.key);
      final errorFile = File(errorPath);
      await errorFile.parent.create(recursive: true);
      await errorFile.writeAsString(entry.value);
      print('✨ Generated: $errorPath');
      generated++;
    }
  }

  return generated;
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

/// Default migration directories to probe when [RpcConfig.migrationsPath]
/// is not set explicitly. Relative to the current working directory.
const _defaultMigrationsPaths = <String>[
  '../supabase/migrations',
  '../../supabase/migrations',
  'supabase/migrations',
];

/// Fills in `void` return types from local SQL migration files when
/// PostgREST/execute_sql introspection couldn't resolve them.
///
/// This is a pure read-only operation against project files — it
/// never modifies the migrations and only touches functions that
/// would otherwise be emitted as `Future<void>`.
Future<List<RpcFunctionInfo>> _applySqlMigrationFallback(
  List<RpcFunctionInfo> functions,
  SuparepoConfig config,
) async {
  final voidCount = functions.where((f) => f.returnType == 'void').length;
  if (voidCount == 0) return functions;

  final migrationsDir = await _resolveMigrationsDir(config.rpc.migrationsPath);
  if (migrationsDir == null) return functions;

  final sqlFiles = <File>[];
  await for (final entry in migrationsDir.list(recursive: true)) {
    if (entry is File && entry.path.toLowerCase().endsWith('.sql')) {
      sqlFiles.add(entry);
    }
  }
  if (sqlFiles.isEmpty) return functions;

  sqlFiles.sort((a, b) => a.path.compareTo(b.path));

  final compositeTypes = <String, List<RpcTableColumn>>{};
  for (final f in sqlFiles) {
    final sql = await f.readAsString();
    compositeTypes.addAll(SqlMigrationParser.parseCompositeTypes(sql));
  }

  final sqlFns = <String, SqlFunctionInfo>{};
  for (final f in sqlFiles) {
    final sql = await f.readAsString();
    sqlFns.addAll(SqlMigrationParser.parseFunctions(
      sql,
      compositeTypes: compositeTypes,
    ));
  }

  final result = SchemaFetcher.mergeSqlMigrationInfo(functions, sqlFns);
  if (result.resolvedCount > 0) {
    print(
      '📄 SQL migrations fallback: resolved ${result.resolvedCount}/'
      '$voidCount missing return type(s) from '
      '${p.relative(migrationsDir.path)}',
    );
  }
  return result.functions;
}

/// Resolves the migrations directory from explicit config or by
/// probing common defaults. Returns null when no directory exists.
Future<Directory?> _resolveMigrationsDir(String? explicitPath) async {
  if (explicitPath != null && explicitPath.isNotEmpty) {
    final dir = Directory(explicitPath);
    if (await dir.exists()) return dir;
    print(
      '⚠️  rpc.migrations_path set to "$explicitPath" but the '
      'directory does not exist. Skipping SQL migration fallback.',
    );
    return null;
  }
  for (final candidate in _defaultMigrationsPaths) {
    final dir = Directory(candidate);
    if (await dir.exists()) return dir;
  }
  return null;
}
