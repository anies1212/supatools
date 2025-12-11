import 'dart:async';
import 'dart:io';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'config_loader.dart';
import 'schema_cache.dart';
import 'freezed_generator.dart';

/// Builder that fetches Supabase schema and outputs intermediate JSON
///
/// This builder is triggered by `supafreeze.yaml` in the project root.
/// It generates an intermediate JSON file that PostProcessBuilder uses
/// to generate individual model files.
class SupafreezeBuilder implements Builder {
  final BuilderOptions options;

  SupafreezeBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': ['supafreeze.intermediate.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    final configLoader = ConfigLoader();
    final config = await configLoader.loadConfig();

    if (config == null) {
      log.warning('supafreeze.yaml not found or invalid. Skipping generation.');
      await _writeEmptyOutput(buildStep, inputId);
      return;
    }

    if (!config.isValid && config.fetch != FetchMode.never) {
      final issues = config.validate();
      log.warning('Configuration incomplete. Skipping generation.');
      for (final issue in issues) {
        log.warning('  - $issue');
      }
      await _writeEmptyOutput(buildStep, inputId);
      return;
    }

    final cache = SchemaCache();
    final fetcher = config.isValid
        ? SchemaFetcher(
            supabaseUrl: config.url!,
            supabaseKey: config.secretKey!,
            schema: config.schema,
          )
        : null;

    final diff = await _fetchAndComputeDiff(fetcher, cache, config);
    if (diff == null || !diff.hasChanges) {
      await _writeEmptyOutput(buildStep, inputId);
      return;
    }

    await _processSchemaChanges(buildStep, inputId, diff, config, cache);
  }

  Future<void> _writeEmptyOutput(BuildStep buildStep, AssetId inputId) async {
    final outputId =
        AssetId(inputId.package, 'lib/supafreeze.intermediate.json');
    await buildStep.writeAsString(
        outputId, '// No tables found or schema unchanged\n');
  }

  Future<SchemaDiff?> _fetchAndComputeDiff(
    SchemaFetcher? fetcher,
    SchemaCache cache,
    SupafreezeConfig config,
  ) =>
      switch (config.fetch) {
        FetchMode.never => _loadFromCacheOnly(cache, config),
        FetchMode.ifNoCache => _handleIfNoCache(fetcher, cache, config),
        FetchMode.always => _fetchFromDatabase(fetcher!, cache, config),
      };

  Future<SchemaDiff?> _handleIfNoCache(
    SchemaFetcher? fetcher,
    SchemaCache cache,
    SupafreezeConfig config,
  ) async {
    final cachedTables = await cache.loadCachedSchema();
    if (cachedTables != null) {
      log.info('Using cached schema (fetch: if_no_cache).');
      final filteredTables =
          cachedTables.where((t) => config.shouldIncludeTable(t.name)).toList();

      if (filteredTables.isEmpty) {
        log.info('No tables in cache match the filter criteria.');
        return null;
      }

      final diff = await cache.computeDiff(filteredTables);
      if (!diff.hasChanges) {
        log.info('Schema unchanged. Skipping generation.');
        return null;
      }

      return diff;
    }
    log.info('No cache found. Fetching from database...');
    return _fetchFromDatabase(fetcher!, cache, config);
  }

  Future<SchemaDiff?> _loadFromCacheOnly(
    SchemaCache cache,
    SupafreezeConfig config,
  ) async {
    log.info('Offline mode (fetch: never). Using cached schema only.');

    final cachedTables = await cache.loadCachedSchema();
    if (cachedTables == null) {
      log.severe(
          'No cached schema available. Cannot generate models in offline mode.');
      return null;
    }

    final filteredTables =
        cachedTables.where((t) => config.shouldIncludeTable(t.name)).toList();

    if (filteredTables.isEmpty) {
      log.info('No tables in cache match the filter criteria.');
      return null;
    }

    final diff = await cache.computeDiff(filteredTables);
    if (!diff.hasChanges) {
      log.info('Schema unchanged. Skipping generation.');
      return null;
    }

    log.info('Using cached schema with ${filteredTables.length} tables.');
    return diff;
  }

  Future<SchemaDiff?> _fetchFromDatabase(
    SchemaFetcher fetcher,
    SchemaCache cache,
    SupafreezeConfig config,
  ) async {
    try {
      final fetchedTables = await fetcher.fetchTables();

      // Register detected enums with TypeMapper
      final detectedEnums = fetcher.detectedEnums;
      if (detectedEnums.isNotEmpty) {
        TypeMapper.clearEnums();
        for (final entry in detectedEnums.entries) {
          TypeMapper.registerEnum(entry.key, entry.value);
          log.fine('Detected enum: ${entry.key} = ${entry.value}');
        }
        log.info('Detected ${detectedEnums.length} enum type(s).');
      }

      final filteredTables = fetchedTables
          .where((t) => config.shouldIncludeTable(t.name))
          .toList();

      if (filteredTables.isEmpty) {
        log.info('No tables found in schema "${config.schema}"');
        // Check if there are tables to remove
        final diff = await cache.computeDiff([]);
        return diff.hasChanges ? diff : null;
      }

      final diff = await cache.computeDiff(filteredTables);
      if (!diff.hasChanges) {
        log.info('Schema unchanged. Using cached models.');
        return null;
      }

      if (diff.tablesToGenerate.isNotEmpty) {
        log.info(
            'Tables to generate: ${diff.tablesToGenerate.map((t) => t.name).join(', ')}');
      }
      if (diff.tablesToRemove.isNotEmpty) {
        log.info('Tables to remove: ${diff.tablesToRemove.join(', ')}');
      }

      return diff;
    } on SchemaFetchException catch (e) {
      log.warning('Failed to fetch schema: $e');
      log.info('Attempting to use cached schema...');

      final cachedTables = await cache.loadCachedSchema();
      if (cachedTables == null) {
        log.severe('No cached schema available. Cannot generate models.');
        return null;
      }

      final filteredCachedTables =
          cachedTables.where((t) => config.shouldIncludeTable(t.name)).toList();
      log.info(
          'Using cached schema with ${filteredCachedTables.length} tables.');

      // Return diff with all cached tables to generate
      return SchemaDiff(
        tablesToGenerate: filteredCachedTables,
        tablesToRemove: [],
      );
    }
  }

  Future<void> _processSchemaChanges(
    BuildStep buildStep,
    AssetId inputId,
    SchemaDiff diff,
    SupafreezeConfig config,
    SchemaCache cache,
  ) async {
    final generator = FreezedGenerator();
    final outputDir = config.output;

    // Get all current tables for relation lookup
    final allTables = await _getAllCurrentTables(outputDir, diff, cache);

    // Configure generator with all tables and config for relation embedding
    generator.setAllTables(allTables);
    generator.setConfig(config);

    // Log detected foreign keys if any
    if (config.embedRelations) {
      final fkCount = allTables.fold<int>(
        0,
        (sum, table) => sum + table.foreignKeys.length,
      );
      if (fkCount > 0) {
        log.info('Detected $fkCount foreign key relationship(s).');
      }
    }

    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Remove files for deleted tables
    for (final tableName in diff.tablesToRemove) {
      await _removeTableFiles(outputDir, tableName);
      await cache.removeTableHash(tableName);
    }

    // Generate model files only for changed tables
    for (final table in diff.tablesToGenerate) {
      final fileName = generator.getFileName(table.name);
      final filePath = p.join(outputDir, fileName);
      final content = generator.generateModel(table);
      await File(filePath).writeAsString(content);
      log.info('Generated: $filePath');
    }

    // Update cache for generated tables
    if (diff.tablesToGenerate.isNotEmpty) {
      await cache.updateTableHashes(diff.tablesToGenerate);
    }

    // Update full schema cache
    await cache.cacheSchema(allTables);

    // Generate barrel file if enabled
    if (config.generateBarrel) {
      final barrelContent = generator.generateBarrelFile(allTables, '');
      final barrelPath = p.join(outputDir, 'models.dart');
      await File(barrelPath).writeAsString(barrelContent);
      log.info('Generated: $barrelPath');
    }

    log.info(
        'Generated ${diff.tablesToGenerate.length} model(s), removed ${diff.tablesToRemove.length} model(s)');

    // Write a marker file to satisfy build_runner output requirements
    final outputId =
        AssetId(inputId.package, 'lib/supafreeze.intermediate.json');
    await buildStep.writeAsString(
      outputId,
      '// Generated ${diff.tablesToGenerate.length}, removed ${diff.tablesToRemove.length}',
    );
  }

  /// Gets all current tables (cached + newly generated - removed)
  Future<List<TableInfo>> _getAllCurrentTables(
    String outputDir,
    SchemaDiff diff,
    SchemaCache cache,
  ) async {
    final cachedTables = await cache.loadCachedSchema() ?? [];
    final removedNames = diff.tablesToRemove.toSet();
    final generatedNames = diff.tablesToGenerate.map((t) => t.name).toSet();

    // Keep cached tables that weren't removed or regenerated
    final result = cachedTables
        .where((t) =>
            !removedNames.contains(t.name) && !generatedNames.contains(t.name))
        .toList();

    // Add newly generated tables
    result.addAll(diff.tablesToGenerate);

    return result;
  }

  /// Removes model files for a specific table
  Future<void> _removeTableFiles(String outputDir, String tableName) async {
    final baseName =
        '${ReCase(tableName).snakeCase}.${FreezedGenerator.fileExtension}';

    final files = [
      File(p.join(outputDir, '$baseName.dart')),
      File(p.join(outputDir, '$baseName.freezed.dart')),
      File(p.join(outputDir, '$baseName.g.dart')),
    ];

    for (final file in files) {
      if (await file.exists()) {
        await file.delete();
        log.info('Removed: ${file.path}');
      }
    }
  }
}

/// Builder factory for build_runner
Builder supafreezeBuilder(BuilderOptions options) => SupafreezeBuilder(options);
