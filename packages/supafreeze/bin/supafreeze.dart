#!/usr/bin/env dart

import 'dart:io';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/config_loader.dart';
import 'package:supafreeze/src/schema_cache.dart';
import 'package:supafreeze/src/model_generator.dart';
import 'package:supafreeze/src/enum_generator.dart';
import 'package:path/path.dart' as p;

/// CLI tool for manual schema sync
///
/// Usage:
///   dart run supafreeze:supafreeze
///   dart run supafreeze:supafreeze --force
void main(List<String> args) async {
  final force = args.contains('--force') || args.contains('-f');

  print('🔄 Supafreeze: Syncing schema from Supabase...');

  final configLoader = ConfigLoader();
  final config = await configLoader.loadConfig();

  if (config == null) {
    print('❌ Error: supafreeze.yaml not found.');
    exit(1);
  }

  if (!config.isValid && config.fetch != FetchMode.never) {
    final issues = config.validate();
    print('❌ Error: Configuration incomplete:');
    for (final issue in issues) {
      print('   - $issue');
    }
    exit(1);
  }

  final cache = SchemaCache();

  // Clear table hashes if force flag is set
  if (force) {
    print('🗑️  Force mode: clearing cached hashes...');
    await cache.clearTableHashes();
  }

  List<TableInfo> tables;
  List<EnumInfo> pgEnums = [];
  SchemaFetcher? fetcher;

  if (config.fetch == FetchMode.never) {
    print('📦 Using cached schema (fetch: never)...');
    final cachedTables = await cache.loadCachedSchema();
    if (cachedTables == null) {
      print('❌ Error: No cached schema available in offline mode.');
      exit(1);
    }
    tables = cachedTables;
  } else {
    fetcher = SchemaFetcher(
      supabaseUrl: config.url!,
      supabaseKey: config.secretKey!,
      schema: config.schema,
    );

    try {
      print('🌐 Fetching schema from ${config.url}...');
      tables = await fetcher.fetchTables();

      // Register detected enums from OpenAPI
      final detectedEnums = fetcher.detectedEnums;
      if (detectedEnums.isNotEmpty) {
        TypeMapper.clearEnums();
        for (final entry in detectedEnums.entries) {
          TypeMapper.registerEnum(entry.key, entry.value);
        }
        print('📊 Detected ${detectedEnums.length} enum type(s).');
      }

      // Fetch PostgreSQL enums if generate_enums is enabled
      if (config.generateEnums) {
        pgEnums = await fetcher.fetchEnums();
        if (pgEnums.isNotEmpty) {
          // Save OpenAPI enums before clearing
          final openApiEnums = Map<String, List<String>>.from(detectedEnums);

          // Re-register with pg_enum names
          TypeMapper.clearEnums();
          for (final pgEnum in pgEnums) {
            TypeMapper.registerEnum(pgEnum.name, pgEnum.values);
          }
          TypeMapper.useEnumTypes = true;

          // Merge enum type names into table columns
          tables = SchemaFetcher.mergeEnumTypes(
            tables,
            pgEnums,
            openApiEnums: openApiEnums,
          );

          print(
            '🔖 Found ${pgEnums.length} PostgreSQL enum(s): '
            '${pgEnums.map((e) => e.name).join(', ')}',
          );
        }
      }
    } on SchemaFetchException catch (e) {
      print('⚠️  Failed to fetch schema: $e');
      print('📦 Attempting to use cached schema...');
      final cachedTables = await cache.loadCachedSchema();
      if (cachedTables == null) {
        print('❌ Error: No cached schema available.');
        exit(1);
      }
      tables = cachedTables;
    }
  }

  // Apply filters
  final filteredTables =
      tables.where((t) => config.shouldIncludeTable(t.name)).toList();

  if (filteredTables.isEmpty) {
    print('ℹ️  No tables found matching filter criteria.');
    exit(0);
  }

  print(
    '📋 Found ${filteredTables.length} table(s): '
    '${filteredTables.map((t) => t.name).join(', ')}',
  );

  // Compute diff
  final diff = await cache.computeDiff(filteredTables);

  if (!diff.hasChanges && !force && pgEnums.isEmpty) {
    print('✅ Schema unchanged. Models are up to date.');
    exit(0);
  }

  // Generate enum files if enabled
  if (config.generateEnums && pgEnums.isNotEmpty) {
    final enumGen = EnumGenerator(format: config.modelFormat);
    final enumDir = Directory(config.resolvedEnumOutput);
    if (!await enumDir.exists()) {
      await enumDir.create(recursive: true);
    }

    final enumFiles = enumGen.generateAllEnumFiles(pgEnums);
    for (final entry in enumFiles.entries) {
      final filePath = p.join(config.resolvedEnumOutput, entry.key);
      await File(filePath).writeAsString(entry.value);
      print('✨ Generated enum: $filePath');
    }

    // Generate enum barrel file
    final barrelContent = enumGen.generateBarrelFile(pgEnums);
    final barrelPath = p.join(config.resolvedEnumOutput, 'enums.dart');
    await File(barrelPath).writeAsString(barrelContent);
    print('✨ Generated: $barrelPath');
  }

  // Generate models
  final generator = createModelGenerator(config);
  final outputDir = config.output;

  generator.setAllTables(filteredTables);

  // Set enum import prefix for FreezedGenerator
  if (config.generateEnums && TypeMapper.useEnumTypes) {
    generator.enumImportPrefix = 'enums/';
  }

  // Log FK info
  if (config.embedRelations) {
    final fkCount = filteredTables.fold<int>(
      0,
      (sum, table) => sum + table.foreignKeys.length,
    );
    if (fkCount > 0) {
      print('🔗 Detected $fkCount foreign key relationship(s).');
    }
  }

  final dir = Directory(outputDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  // Determine tables to generate
  final tablesToGenerate = force ? filteredTables : diff.tablesToGenerate;

  // If enums changed, regenerate all tables that use enum types
  final effectiveTablesToGenerate =
      config.generateEnums && pgEnums.isNotEmpty && !force
          ? _addTablesWithEnums(tablesToGenerate, filteredTables)
          : tablesToGenerate;

  // Remove files for deleted tables
  for (final tableName in diff.tablesToRemove) {
    await _removeTableFiles(outputDir, tableName, generator);
    await cache.removeTableHash(tableName);
    print('🗑️  Removed: $tableName');
  }

  // Generate model files
  for (final table in effectiveTablesToGenerate) {
    final fileName = generator.getFileName(table.name);
    final filePath = p.join(outputDir, fileName);
    final content = generator.generateModel(table);
    await File(filePath).writeAsString(content);
    print('✨ Generated: $filePath');
  }

  // Update cache
  if (effectiveTablesToGenerate.isNotEmpty) {
    await cache.updateTableHashes(effectiveTablesToGenerate);
  }
  await cache.cacheSchema(filteredTables);

  // Generate barrel file if enabled
  if (config.generateBarrel) {
    final barrelContent = generator.generateBarrelFile(filteredTables, '');
    final barrelPath = p.join(outputDir, 'models.dart');
    await File(barrelPath).writeAsString(barrelContent);
    print('✨ Generated: $barrelPath');
  }

  print('');
  print(
    '🎉 Done! Generated ${effectiveTablesToGenerate.length} model(s), '
    'removed ${diff.tablesToRemove.length} model(s).',
  );
  if (pgEnums.isNotEmpty) {
    print('   Generated ${pgEnums.length} enum(s).');
  }
  print('');
  print('📝 Now run: dart run build_runner build');
}

/// Adds tables that use enum types to the generation list.
List<TableInfo> _addTablesWithEnums(
  List<TableInfo> tablesToGenerate,
  List<TableInfo> allTables,
) {
  final names = tablesToGenerate.map((t) => t.name).toSet();
  final result = [...tablesToGenerate];

  for (final table in allTables) {
    if (names.contains(table.name)) continue;
    final hasEnum = table.columns.any(
      (c) => TypeMapper.isCustomEnum(
        c.dataType.endsWith('[]')
            ? c.dataType.substring(0, c.dataType.length - 2)
            : c.dataType,
      ),
    );
    if (hasEnum) {
      result.add(table);
      names.add(table.name);
    }
  }

  return result;
}

Future<void> _removeTableFiles(
  String outputDir,
  String tableName,
  ModelGenerator generator,
) async {
  for (final fileName in generator.outputFileNames(tableName)) {
    final file = File(p.join(outputDir, fileName));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
