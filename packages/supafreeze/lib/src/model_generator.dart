import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'config_loader.dart';
import 'dart_mappable_generator.dart';
import 'freezed_generator.dart';

/// Common interface implemented by every model code generator so the CLI and
/// builders can stay agnostic to the selected [ModelFormat].
abstract class ModelGenerator {
  /// Registers every table in the schema for relation lookups.
  void setAllTables(List<TableInfo> tables);

  /// Sets the resolved configuration.
  void setConfig(SupafreezeConfig config);

  /// Import prefix (relative to the model output dir) for generated enum
  /// files, e.g. `enums/`.
  set enumImportPrefix(String? value);

  /// The current enum import prefix, if any.
  String? get enumImportPrefix;

  /// Dart class name generated for [tableName].
  String getClassName(String tableName);

  /// Primary generated file name for [tableName], e.g.
  /// `users.supafreeze.dart`.
  String getFileName(String tableName);

  /// Generates the model source for a single [table].
  String generateModel(TableInfo table);

  /// Generates a barrel file that exports every model in [tables].
  String generateBarrelFile(List<TableInfo> tables, String outputDir);

  /// Every file name this generator produces for [tableName], including the
  /// build_runner part outputs, used to clean up removed tables.
  List<String> outputFileNames(String tableName);
}

/// Builds the [ModelGenerator] matching the configured [ModelFormat].
ModelGenerator createModelGenerator(SupafreezeConfig config) {
  final generator = switch (config.modelFormat) {
    ModelFormat.freezed => FreezedGenerator(),
    ModelFormat.dartMappable => DartMappableGenerator(),
  };
  generator.setConfig(config);
  return generator;
}
