#!/usr/bin/env dart

import 'dart:io';
import 'package:supafreeze/src/config_loader.dart';
import 'package:supafreeze/src/schema_fetcher.dart';
import 'package:supafreeze/src/schema_cache.dart';
import 'package:supafreeze/src/freezed_generator.dart';
import 'package:supafreeze/src/type_mapper.dart';
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

  if (config.fetch == FetchMode.never) {
    print('📦 Using cached schema (fetch: never)...');
    final cachedTables = await cache.loadCachedSchema();
    if (cachedTables == null) {
      print('❌ Error: No cached schema available in offline mode.');
      exit(1);
    }
    tables = cachedTables;
  } else {
    final fetcher = SchemaFetcher(
      supabaseUrl: config.url!,
      supabaseKey: config.secretKey!,
      schema: config.schema,
    );

    try {
      print('🌐 Fetching schema from ${config.url}...');
      tables = await fetcher.fetchTables();

      // Register detected enums
      final detectedEnums = fetcher.detectedEnums;
      if (detectedEnums.isNotEmpty) {
        TypeMapper.clearEnums();
        for (final entry in detectedEnums.entries) {
          TypeMapper.registerEnum(entry.key, entry.value);
        }
        print('📊 Detected ${detectedEnums.length} enum type(s).');
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
  final filteredTables = tables
      .where((t) => config.shouldIncludeTable(t.name))
      .toList();

  if (filteredTables.isEmpty) {
    print('ℹ️  No tables found matching filter criteria.');
    exit(0);
  }

  print('📋 Found ${filteredTables.length} table(s): ${filteredTables.map((t) => t.name).join(', ')}');

  // Compute diff
  final diff = await cache.computeDiff(filteredTables);

  if (!diff.hasChanges && !force) {
    print('✅ Schema unchanged. Models are up to date.');
    exit(0);
  }

  // Generate models
  final generator = FreezedGenerator();
  final outputDir = config.output;

  generator.setAllTables(filteredTables);
  generator.setConfig(config);

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

  // Remove files for deleted tables
  for (final tableName in diff.tablesToRemove) {
    await _removeTableFiles(outputDir, tableName, generator);
    await cache.removeTableHash(tableName);
    print('🗑️  Removed: $tableName');
  }

  // Generate model files
  for (final table in tablesToGenerate) {
    final fileName = generator.getFileName(table.name);
    final filePath = p.join(outputDir, fileName);
    final content = generator.generateModel(table);
    await File(filePath).writeAsString(content);
    print('✨ Generated: $filePath');
  }

  // Update cache
  if (tablesToGenerate.isNotEmpty) {
    await cache.updateTableHashes(tablesToGenerate);
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
  print('🎉 Done! Generated ${tablesToGenerate.length} model(s), removed ${diff.tablesToRemove.length} model(s).');
  print('');
  print('📝 Now run: dart run build_runner build');
}

Future<void> _removeTableFiles(String outputDir, String tableName, FreezedGenerator generator) async {
  final baseName = generator.getFileName(tableName).replaceAll('.dart', '');

  final files = [
    File(p.join(outputDir, '$baseName.dart')),
    File(p.join(outputDir, '$baseName.freezed.dart')),
    File(p.join(outputDir, '$baseName.g.dart')),
  ];

  for (final file in files) {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
