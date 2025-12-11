import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'freezed_generator.dart';

/// PostProcessBuilder that generates individual model files from cached schema
///
/// This builder runs after the main builder and uses direct File I/O
/// to generate separate files for each database table.
class SupafreezePostBuilder implements PostProcessBuilder {
  @override
  Iterable<String> get inputExtensions => ['.supafreeze.json'];

  @override
  Future<void> build(PostProcessBuildStep buildStep) async {
    // Read the intermediate JSON data
    final content = await buildStep.readInputAsString();
    if (content.isEmpty || content.startsWith('//')) {
      return;
    }

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      log.warning('Failed to parse intermediate data: $e');
      return;
    }

    final outputDir = data['outputDir'] as String? ?? 'lib/models';
    final generateBarrel = data['generateBarrel'] as bool? ?? false;
    final tablesJson = data['tables'] as List<dynamic>?;

    if (tablesJson == null || tablesJson.isEmpty) {
      log.info('No tables to generate.');
      return;
    }

    // Parse tables from JSON
    final tables = tablesJson.map((t) {
      final tableMap = t as Map<String, dynamic>;
      final columnsJson = tableMap['columns'] as List<dynamic>;
      final columns = columnsJson.map((c) {
        final colMap = c as Map<String, dynamic>;
        return ColumnInfo(
          name: colMap['name'] as String,
          dataType: colMap['dataType'] as String,
          isNullable: colMap['isNullable'] as bool,
          isPrimaryKey: colMap['isPrimaryKey'] as bool,
          defaultValue: colMap['defaultValue'] as String?,
        );
      }).toList();

      return TableInfo(
        name: tableMap['name'] as String,
        columns: columns,
      );
    }).toList();

    // Generate individual model files
    final generator = FreezedGenerator();
    final dir = Directory(outputDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    for (final table in tables) {
      final fileName = generator.getFileName(table.name);
      final filePath = p.join(outputDir, fileName);
      final content = generator.generateModel(table);
      await File(filePath).writeAsString(content);
      log.info('Generated: $filePath');
    }

    // Generate barrel file if enabled
    if (generateBarrel) {
      final barrelContent = generator.generateBarrelFile(tables, '');
      final barrelPath = p.join(outputDir, 'models.dart');
      await File(barrelPath).writeAsString(barrelContent);
      log.info('Generated: $barrelPath');
    }

    log.info('Generated ${tables.length} model files in $outputDir');

    // Delete the intermediate file
    buildStep.deletePrimaryInput();
  }
}

/// Builder factory for PostProcessBuilder
PostProcessBuilder supafreezePostBuilder(BuilderOptions options) =>
    SupafreezePostBuilder();
