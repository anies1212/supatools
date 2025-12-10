import 'package:recase/recase.dart';
import 'schema_fetcher.dart';
import 'type_mapper.dart';

/// Dart reserved words that cannot be used as identifiers
/// https://dart.dev/language/keywords
const Set<String> _dartReservedWords = {
  // Reserved words
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
  'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
  'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
  'var', 'void', 'while', 'with',
  // Built-in identifiers (contextual keywords that should be avoided)
  'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export',
  'extension', 'external', 'factory', 'function', 'get', 'implements',
  'import', 'interface', 'late', 'library', 'mixin', 'operator',
  'part', 'required', 'set', 'static', 'typedef',
  // Async support
  'async', 'await', 'yield',
  // Common Dart types/functions to avoid collision
  'int', 'double', 'String', 'bool', 'List', 'Map', 'Set', 'Object',
  'Type', 'Function', 'Null', 'Never', 'Future', 'Stream',
};

/// Generates Freezed model code from table information
class FreezedGenerator {
  /// File extension for generated files (without leading dot)
  static const String fileExtension = 'supafreeze';

  /// Generates a Freezed model file content for a single table
  String generateModel(TableInfo table) {
    final rawClassName = ReCase(table.name).pascalCase;
    final className = _escapeClassName(rawClassName);
    final fileName = ReCase(table.name).snakeCase;

    final buffer = StringBuffer();

    // Header comment
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln('// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark');
    buffer.writeln();

    // Imports
    buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
    buffer.writeln();
    buffer.writeln("part '$fileName.$fileExtension.freezed.dart';");
    buffer.writeln("part '$fileName.$fileExtension.g.dart';");
    buffer.writeln();

    // Class definition
    buffer.writeln('@freezed');
    buffer.writeln('class $className with _\$$className {');
    buffer.writeln('  const factory $className({');

    // Fields (sorted: required first, then grouped by type)
    final sortedColumns = _sortColumns(table.columns);
    for (final column in sortedColumns) {
      final fieldLine = _generateField(column);
      buffer.writeln('    $fieldLine');
    }

    buffer.writeln('  }) = _$className;');
    buffer.writeln();

    // fromJson factory
    buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);',
    );

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Sorts columns: required fields first, then grouped by Dart type
  List<ColumnInfo> _sortColumns(List<ColumnInfo> columns) {
    // Determine if each column is required
    bool isRequired(ColumnInfo col) {
      final hasDefault = col.defaultValue != null && !col.isPrimaryKey;
      return !col.isNullable && !hasDefault;
    }

    // Get Dart type for sorting
    String getDartType(ColumnInfo col) => TypeMapper.mapType(col.dataType);

    // Sort: required first, then by type, then by name
    final sorted = List<ColumnInfo>.from(columns);
    sorted.sort((a, b) {
      final aRequired = isRequired(a);
      final bRequired = isRequired(b);

      // Required fields come first
      if (aRequired != bRequired) {
        return aRequired ? -1 : 1;
      }

      // Within same required/optional group, sort by type
      final aType = getDartType(a);
      final bType = getDartType(b);
      if (aType != bType) {
        return aType.compareTo(bType);
      }

      // Same type, sort by name
      return a.name.compareTo(b.name);
    });

    return sorted;
  }

  /// Escapes a field name if it's a Dart reserved word
  String _escapeFieldName(String name) {
    if (_dartReservedWords.contains(name)) {
      return '$name\$'; // Append $ to avoid conflict
    }
    return name;
  }

  /// Escapes a class name if it starts with a number or is a reserved word
  String _escapeClassName(String name) {
    // If starts with number, prefix with underscore
    if (name.isNotEmpty && RegExp(r'^[0-9]').hasMatch(name)) {
      return 'Table$name';
    }
    // If reserved word, append Model suffix
    if (_dartReservedWords.contains(name.toLowerCase())) {
      return '${name}Model';
    }
    return name;
  }

  /// Generates a single field definition
  String _generateField(ColumnInfo column) {
    final rawFieldName = ReCase(column.name).camelCase;
    final fieldName = _escapeFieldName(rawFieldName);
    final dartType = TypeMapper.mapType(column.dataType);
    final annotations = <String>[];

    // Add JsonKey if field name differs from column name (including escaped names)
    if (fieldName != column.name || rawFieldName != fieldName) {
      annotations.add("@JsonKey(name: '${column.name}')");
    }

    // Handle nullable types and defaults
    final hasDefault = column.defaultValue != null && !column.isPrimaryKey;
    final isNullable = column.isNullable && !hasDefault;

    // Build the field type
    String fieldType;
    if (isNullable) {
      fieldType = '$dartType?';
    } else {
      fieldType = dartType;
    }

    // Build the field declaration
    final buffer = StringBuffer();

    // Add annotations
    for (final annotation in annotations) {
      buffer.write('$annotation ');
    }

    // Add default value annotation if applicable
    if (hasDefault && !column.isNullable) {
      final defaultValue = _parseDefaultValue(column.defaultValue!, dartType);
      if (defaultValue != null) {
        buffer.write('@Default($defaultValue) ');
      } else {
        // If we can't parse the default, make it required
        buffer.write('required ');
      }
    } else if (!isNullable) {
      buffer.write('required ');
    }

    buffer.write('$fieldType $fieldName,');

    return buffer.toString();
  }

  /// Parses a PostgreSQL default value to a Dart literal
  String? _parseDefaultValue(String pgDefault, String dartType) {
    // Handle common default patterns
    final trimmed = pgDefault.trim();

    // Remove type casts like ::text, ::integer
    final withoutCast = trimmed.replaceAll(RegExp(r'::\w+'), '');

    // Boolean defaults
    if (dartType == 'bool') {
      if (withoutCast == 'true' || withoutCast == "'t'") return 'true';
      if (withoutCast == 'false' || withoutCast == "'f'") return 'false';
    }

    // Numeric defaults
    if (dartType == 'int' || dartType == 'double') {
      final numMatch = RegExp(r'^-?\d+\.?\d*$').firstMatch(withoutCast);
      if (numMatch != null) {
        return withoutCast;
      }
    }

    // String defaults (quoted)
    if (dartType == 'String') {
      final stringMatch = RegExp(r"^'(.*)'$").firstMatch(withoutCast);
      if (stringMatch != null) {
        return "'${stringMatch.group(1)}'";
      }
    }

    // Empty array/list
    if (dartType.startsWith('List<')) {
      if (withoutCast == "'{}'" || withoutCast == '{}') {
        return 'const []';
      }
    }

    // Empty map/object
    if (dartType == 'Map<String, dynamic>') {
      if (withoutCast == "'{}'" || withoutCast == '{}') {
        return 'const {}';
      }
    }

    // Functions like now(), gen_random_uuid() - can't use as default
    if (withoutCast.contains('(') && withoutCast.contains(')')) {
      return null;
    }

    return null;
  }

  /// Generates all models and returns a map of filename to content
  Map<String, String> generateAllModels(List<TableInfo> tables) {
    final result = <String, String>{};

    for (final table in tables) {
      final fileName = getFileName(table.name);
      result[fileName] = generateModel(table);
    }

    // Generate barrel file
    result['models.dart'] = generateBarrelFile(tables, '');

    return result;
  }

  /// Gets the generated file name for a table
  String getFileName(String tableName) {
    return '${ReCase(tableName).snakeCase}.$fileExtension.dart';
  }

  /// Generates a barrel file that exports all models
  String generateBarrelFile(List<TableInfo> tables, String outputDir) {
    final buffer = StringBuffer();
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by supafreeze');
    buffer.writeln();

    for (final table in tables) {
      final fileName = ReCase(table.name).snakeCase;
      final exportPath = outputDir.isEmpty
          ? '$fileName.$fileExtension.dart'
          : '$outputDir/$fileName.$fileExtension.dart';
      buffer.writeln("export '$exportPath';");
    }

    return buffer.toString();
  }

  /// Generates a single combined file containing all models
  ///
  /// This approach works better with build_runner's asset management
  /// since it outputs a single file per input file.
  String generateCombinedFile(List<TableInfo> tables) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln('// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark');
    buffer.writeln();
    buffer.writeln("import 'package:freezed_annotation/freezed_annotation.dart';");
    buffer.writeln();

    // Part directives - fixed output filename
    buffer.writeln("part 'supafreeze.models.freezed.dart';");
    buffer.writeln("part 'supafreeze.models.g.dart';");
    buffer.writeln();

    // Generate each model class
    for (final table in tables) {
      buffer.writeln(_generateModelClass(table));
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Generates just the class definition (without imports/parts)
  String _generateModelClass(TableInfo table) {
    final rawClassName = ReCase(table.name).pascalCase;
    final className = _escapeClassName(rawClassName);
    final buffer = StringBuffer();

    buffer.writeln('@freezed');
    buffer.writeln('class $className with _\$$className {');
    buffer.writeln('  const factory $className({');

    final sortedColumns = _sortColumns(table.columns);
    for (final column in sortedColumns) {
      final fieldLine = _generateField(column);
      buffer.writeln('    $fieldLine');
    }

    buffer.writeln('  }) = _$className;');
    buffer.writeln();
    buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) => _\$${className}FromJson(json);',
    );
    buffer.write('}');

    return buffer.toString();
  }
}
