import 'package:recase/recase.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'config_loader.dart';
import 'enum_generator.dart';
import 'model_generator.dart';

/// Dart reserved words that cannot be used as identifiers.
/// https://dart.dev/language/keywords
const Set<String> _dartReservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final',
  'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
  'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
  'var', 'void', 'while', 'with',
  'abstract', 'as', 'covariant', 'deferred', 'dynamic', 'export',
  'extension', 'external', 'factory', 'function', 'get', 'implements',
  'import', 'interface', 'late', 'library', 'mixin', 'operator',
  'part', 'required', 'set', 'static', 'typedef',
  'async', 'await', 'yield',
  'int', 'double', 'String', 'bool', 'List', 'Map', 'Set', 'Object',
  'Type', 'Function', 'Null', 'Never', 'Future', 'Stream',
};

/// `generateMethods` argument used on every generated model.
///
/// `encode` is intentionally omitted so the generated mixin does *not* declare
/// `toJson()`/`toMap()`. This frees us to declare our own `Map`-returning
/// `toJson()` (matching the Freezed models and the suparepo repository
/// contract) while still inheriting `copyWith`, `==`, `hashCode` and
/// `toString` from dart_mappable.
const String _generateMethods =
    'generateMethods: GenerateMethods.decode | GenerateMethods.copy | '
    'GenerateMethods.equals | GenerateMethods.stringify';

/// Generates dart_mappable model code from table information.
///
/// The output is a drop-in replacement for the Freezed models: every model
/// exposes `factory X.fromJson(Map<String, dynamic>)` and a
/// `Map<String, dynamic> toJson()`, so generated suparepo repositories keep
/// working unchanged.
class DartMappableGenerator implements ModelGenerator {
  /// File extension for generated files (without leading dot).
  static const String fileExtension = 'supafreeze';

  final Map<String, TableInfo> _allTables = {};
  SupafreezeConfig? _config;

  @override
  String? enumImportPrefix;

  @override
  void setAllTables(List<TableInfo> tables) {
    _allTables.clear();
    for (final table in tables) {
      _allTables[table.name] = table;
    }
  }

  @override
  void setConfig(SupafreezeConfig config) {
    _config = config;
  }

  @override
  String getClassName(String tableName) =>
      _escapeClassName(ReCase(tableName).pascalCase);

  @override
  String getFileName(String tableName) =>
      '${ReCase(tableName).snakeCase}.$fileExtension.dart';

  @override
  List<String> outputFileNames(String tableName) {
    final base = '${ReCase(tableName).snakeCase}.$fileExtension';
    return ['$base.dart', '$base.mapper.dart'];
  }

  @override
  String generateModel(TableInfo table) {
    final className = getClassName(table.name);
    final fileName = ReCase(table.name).snakeCase;

    final buffer = StringBuffer();
    _writeHeader(buffer);

    buffer.writeln("import 'package:dart_mappable/dart_mappable.dart';");
    for (final import in _getEnumImports(table)) {
      buffer.writeln("import '$import';");
    }
    for (final import in _getRelatedImports(table)) {
      buffer.writeln("import '$import';");
    }
    buffer.writeln();
    buffer.writeln("part '$fileName.$fileExtension.mapper.dart';");
    buffer.writeln();

    _writeClass(buffer, table, className);

    if (_config?.generateInsertModels == true) {
      buffer.writeln();
      _writeInsertClass(buffer, table, className);
    }

    return buffer.toString();
  }

  void _writeHeader(StringBuffer buffer) {
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln(
        '// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, unnecessary_const, avoid_init_to_null, invalid_annotation_target, unnecessary_question_mark');
    buffer.writeln(
        '// ignore_for_file: public_member_api_docs, sort_constructors_first, lines_longer_than_80_chars, directives_ordering');
    buffer.writeln();
  }

  void _writeClass(StringBuffer buffer, TableInfo table, String className) {
    buffer.writeln('@MappableClass($_generateMethods)');
    buffer.writeln('class $className with ${className}Mappable {');

    final columns = _sortColumns(table.columns);

    // Constructor.
    buffer.writeln('  const $className({');
    for (final column in columns) {
      buffer.writeln('    ${_constructorParam(column)}');
    }
    for (final relation in _relations(table)) {
      buffer.writeln('    this.${relation.fieldName},');
    }
    buffer.writeln('  });');
    buffer.writeln();

    // Fields.
    for (final column in columns) {
      buffer.write(_fieldDeclaration(column));
    }
    for (final relation in _relations(table)) {
      buffer.writeln('  final ${relation.className}? ${relation.fieldName};');
    }
    buffer.writeln();

    // JSON interop compatible with the Freezed models / suparepo repositories.
    buffer.writeln(
      '  factory $className.fromJson(Map<String, dynamic> json) =>',
    );
    buffer.writeln('      ${className}Mapper.fromMap(json);');
    buffer.writeln();
    buffer.writeln('  Map<String, dynamic> toJson() =>');
    buffer.writeln(
      '      ${className}Mapper.ensureInitialized().encodeMap<$className>(this);',
    );
    buffer.writeln('}');
  }

  /// Insert model where NOT NULL columns with a database default become
  /// optional. `ignoreNull: true` drops omitted (null) fields from the encoded
  /// map so the database default applies.
  void _writeInsertClass(
    StringBuffer buffer,
    TableInfo table,
    String className,
  ) {
    final insertClass = '${className}Insert';

    buffer.writeln('/// Insert model for `${table.name}`.');
    buffer.writeln('///');
    buffer.writeln(
      '/// NOT NULL columns with a database default are optional here so the '
      'database',
    );
    buffer.writeln('/// default applies when the field is omitted.');
    buffer.writeln('@MappableClass(ignoreNull: true, $_generateMethods)');
    buffer.writeln('class $insertClass with ${insertClass}Mappable {');

    final columns = _sortColumns(table.columns);

    buffer.writeln('  const $insertClass({');
    for (final column in columns) {
      final isRequired = !column.isNullable && column.defaultValue == null;
      final rawFieldName = ReCase(column.name).camelCase;
      final fieldName = _escapeFieldName(rawFieldName);
      buffer.writeln(
        isRequired
            ? '    required this.$fieldName,'
            : '    this.$fieldName,',
      );
    }
    buffer.writeln('  });');
    buffer.writeln();

    for (final column in columns) {
      buffer.write(_insertFieldDeclaration(column));
    }
    buffer.writeln();

    buffer.writeln(
      '  factory $insertClass.fromJson(Map<String, dynamic> json) =>',
    );
    buffer.writeln('      ${insertClass}Mapper.fromMap(json);');
    buffer.writeln();
    buffer.writeln('  Map<String, dynamic> toJson() =>');
    buffer.writeln(
      '      ${insertClass}Mapper.ensureInitialized().encodeMap<$insertClass>(this);',
    );
    buffer.writeln('}');
  }

  /// Constructor parameter for a column, e.g. `required this.id,`,
  /// `this.isActive = true,` or `this.note,`.
  String _constructorParam(ColumnInfo column) {
    final fieldName = _escapeFieldName(ReCase(column.name).camelCase);
    final dartType = TypeMapper.mapType(column.dataType);
    final hasDefault = column.defaultValue != null && !column.isPrimaryKey;
    final isNullable = column.isNullable && !hasDefault;

    if (hasDefault && !column.isNullable) {
      final defaultValue = _parseDefaultValue(
        column.defaultValue!,
        dartType,
        column.dataType,
      );
      if (defaultValue != null) {
        return 'this.$fieldName = $defaultValue,';
      }
      return 'required this.$fieldName,';
    }
    if (!isNullable) {
      return 'required this.$fieldName,';
    }
    return 'this.$fieldName,';
  }

  /// Field declaration for a column, including a `@MappableField` key override
  /// when the Dart name diverges from the database column name.
  String _fieldDeclaration(ColumnInfo column) {
    final rawFieldName = ReCase(column.name).camelCase;
    final fieldName = _escapeFieldName(rawFieldName);
    final dartType = TypeMapper.mapType(column.dataType);
    final hasDefault = column.defaultValue != null && !column.isPrimaryKey;
    final isNullable = column.isNullable && !hasDefault;
    final fieldType = isNullable ? '$dartType?' : dartType;

    final buffer = StringBuffer();
    if (fieldName != column.name || rawFieldName != fieldName) {
      buffer.writeln("  @MappableField(key: '${column.name}')");
    }
    buffer.writeln('  final $fieldType $fieldName;');
    return buffer.toString();
  }

  /// Field declaration for the insert model: NOT NULL columns without a
  /// database default stay non-null, everything else is nullable.
  String _insertFieldDeclaration(ColumnInfo column) {
    final rawFieldName = ReCase(column.name).camelCase;
    final fieldName = _escapeFieldName(rawFieldName);
    final dartType = TypeMapper.mapType(column.dataType);
    final isRequired = !column.isNullable && column.defaultValue == null;
    final fieldType = isRequired ? dartType : '$dartType?';

    final buffer = StringBuffer();
    if (fieldName != column.name || rawFieldName != fieldName) {
      buffer.writeln("  @MappableField(key: '${column.name}')");
    }
    buffer.writeln('  final $fieldType $fieldName;');
    return buffer.toString();
  }

  /// Embedded relation descriptors for a table.
  List<_Relation> _relations(TableInfo table) {
    final relations = <_Relation>[];
    if (_config?.embedRelations != true) return relations;

    for (final column in table.columns) {
      final fk = column.foreignKey;
      if (fk == null) continue;

      final relationName = _getRelationName(column.name);
      if (_config?.shouldEmbedRelation(table.name, relationName) != true) {
        continue;
      }
      if (!_allTables.containsKey(fk.referencedTable)) continue;

      relations.add(_Relation(
        className: getClassName(fk.referencedTable),
        fieldName: _escapeFieldName(relationName),
      ));
    }
    return relations;
  }

  Set<String> _getEnumImports(TableInfo table) {
    final imports = <String>{};
    if (!TypeMapper.useEnumTypes) return imports;

    final enumGen = EnumGenerator();
    for (final column in table.columns) {
      final baseType = column.dataType.endsWith('[]')
          ? column.dataType.substring(0, column.dataType.length - 2)
          : column.dataType;
      if (TypeMapper.isCustomEnum(baseType)) {
        final fileName = enumGen.getEnumFileName(baseType);
        final prefix = enumImportPrefix ?? 'enums/';
        imports.add('$prefix$fileName');
      }
    }
    return imports;
  }

  Set<String> _getRelatedImports(TableInfo table) {
    final imports = <String>{};
    if (_config?.embedRelations != true) return imports;

    for (final column in table.columns) {
      final fk = column.foreignKey;
      if (fk == null) continue;

      final relationName = _getRelationName(column.name);
      if (_config?.shouldEmbedRelation(table.name, relationName) != true) {
        continue;
      }
      if (!_allTables.containsKey(fk.referencedTable)) continue;

      final relatedFileName = ReCase(fk.referencedTable).snakeCase;
      imports.add('$relatedFileName.$fileExtension.dart');
    }
    return imports;
  }

  String _getRelationName(String columnName) {
    if (columnName.endsWith('_id')) {
      return ReCase(columnName.substring(0, columnName.length - 3)).camelCase;
    }
    return ReCase(columnName).camelCase;
  }

  List<ColumnInfo> _sortColumns(List<ColumnInfo> columns) {
    if (_config?.preserveColumnOrder == true) {
      return List<ColumnInfo>.from(columns);
    }

    bool isRequired(ColumnInfo col) {
      final hasDefault = col.defaultValue != null && !col.isPrimaryKey;
      return !col.isNullable && !hasDefault;
    }

    String getDartType(ColumnInfo col) => TypeMapper.mapType(col.dataType);

    final sorted = List<ColumnInfo>.from(columns);
    sorted.sort((a, b) {
      final aRequired = isRequired(a);
      final bRequired = isRequired(b);
      if (aRequired != bRequired) {
        return aRequired ? -1 : 1;
      }
      final aType = getDartType(a);
      final bType = getDartType(b);
      if (aType != bType) {
        return aType.compareTo(bType);
      }
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  String _escapeFieldName(String name) {
    if (_dartReservedWords.contains(name)) {
      return '$name\$';
    }
    return name;
  }

  String _escapeClassName(String name) {
    if (name.isNotEmpty && RegExp(r'^[0-9]').hasMatch(name)) {
      return 'Table$name';
    }
    if (_dartReservedWords.contains(name.toLowerCase())) {
      return '${name}Model';
    }
    return name;
  }

  /// Parses a PostgreSQL default value to a Dart literal. Mirrors the Freezed
  /// generator so both formats classify defaults identically.
  String? _parseDefaultValue(String pgDefault, String dartType,
      [String? pgType]) {
    final trimmed = pgDefault.trim();

    if (pgType != null) {
      final enumDefault = _parseEnumDefault(trimmed, pgType);
      if (enumDefault != null) return enumDefault;
    }

    final withoutCast = trimmed.replaceAll(RegExp(r'::\w+'), '');

    if (dartType == 'bool') {
      if (withoutCast == 'true' || withoutCast == "'t'") return 'true';
      if (withoutCast == 'false' || withoutCast == "'f'") return 'false';
    }

    if (dartType == 'int' || dartType == 'double') {
      final numMatch = RegExp(r'^-?\d+\.?\d*$').firstMatch(withoutCast);
      if (numMatch != null) {
        return withoutCast;
      }
    }

    if (dartType == 'String') {
      final stringMatch = RegExp(r"^'(.*)'$").firstMatch(withoutCast);
      if (stringMatch != null) {
        return "'${stringMatch.group(1)}'";
      }
    }

    if (dartType.startsWith('List<')) {
      if (withoutCast == "'{}'" || withoutCast == '{}') {
        return 'const []';
      }
    }

    if (dartType == 'Map<String, dynamic>') {
      if (withoutCast == "'{}'" || withoutCast == '{}') {
        return 'const {}';
      }
    }

    if (withoutCast.contains('(') && withoutCast.contains(')')) {
      return null;
    }

    return null;
  }

  String? _parseEnumDefault(String pgDefault, String pgType) {
    if (!TypeMapper.useEnumTypes) return null;
    final base =
        pgType.endsWith('[]') ? pgType.substring(0, pgType.length - 2) : pgType;
    if (!TypeMapper.isCustomEnum(base)) return null;

    final match = RegExp(r"'([^']*)'").firstMatch(pgDefault);
    if (match == null) return null;
    final value = match.group(1)!;

    final values = TypeMapper.getEnumValues(base);
    if (values == null || !values.contains(value)) return null;

    final enumClass = TypeMapper.enumTypeName(base);
    final member = EnumGenerator.sanitizeEnumValue(value);
    return '$enumClass.$member';
  }

  @override
  String generateBarrelFile(List<TableInfo> tables, String outputDir) {
    final buffer = StringBuffer();
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint, directives_ordering');
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
}

/// Embedded relation descriptor.
class _Relation {
  const _Relation({required this.className, required this.fieldName});

  final String className;
  final String fieldName;
}
