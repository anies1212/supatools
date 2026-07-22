import 'package:recase/recase.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'config_loader.dart';

/// Dart reserved words that cannot be used as enum value identifiers
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
  // Enum-specific
  'name', 'index', 'values', 'hashCode', 'runtimeType',
};

/// Generates Dart enum code from PostgreSQL enum types
class EnumGenerator {
  /// File extension for generated enum files
  static const String fileExtension = 'supafreeze';

  /// Model format the enums are generated for. Freezed uses a plain enhanced
  /// enum; dart_mappable uses an `@MappableEnum`.
  final ModelFormat format;

  EnumGenerator({this.format = ModelFormat.freezed});

  /// Gets the Dart enum class name from a PostgreSQL enum type name.
  ///
  /// e.g. `campaign_type` → `CampaignType`
  String getEnumClassName(String pgEnumName) =>
      TypeMapper.enumTypeName(pgEnumName);

  /// Gets the generated file name for a PostgreSQL enum type.
  ///
  /// e.g. `campaign_type` → `campaign_type.supafreeze.dart`
  String getEnumFileName(String pgEnumName) =>
      '${ReCase(pgEnumName).snakeCase}.$fileExtension.dart';

  /// Generates a Dart enum file for a single PostgreSQL enum type.
  String generateEnumFile(EnumInfo enumInfo) => switch (format) {
        ModelFormat.freezed => _generateFreezedEnumFile(enumInfo),
        ModelFormat.dartMappable => _generateMappableEnumFile(enumInfo),
      };

  /// Plain enhanced enum with a string `value` and `toJson`/`fromJson`.
  String _generateFreezedEnumFile(EnumInfo enumInfo) {
    final className = getEnumClassName(enumInfo.name);
    final buffer = StringBuffer();

    // Header
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln(
      '// ignore_for_file: public_member_api_docs, '
      'sort_constructors_first, lines_longer_than_80_chars, '
      'directives_ordering',
    );
    buffer.writeln();

    // Enum definition
    buffer.writeln('enum $className {');

    for (var i = 0; i < enumInfo.values.length; i++) {
      final pgValue = enumInfo.values[i];
      final dartName = _sanitizeEnumValue(pgValue);
      final comma = i < enumInfo.values.length - 1 ? ',' : ';';
      buffer.writeln("  $dartName('$pgValue')$comma");
    }

    buffer.writeln();
    buffer.writeln('  const $className(this.value);');
    buffer.writeln('  final String value;');
    buffer.writeln();
    buffer.writeln('  String toJson() => value;');
    buffer.writeln();
    buffer.writeln(
      '  static $className fromJson(String json) =>',
    );
    buffer.writeln(
      '      values.firstWhere((e) => e.value == json);',
    );
    buffer.writeln('}');

    return buffer.toString();
  }

  /// dart_mappable enum annotated with `@MappableEnum`. Values whose Dart
  /// identifier differs from the PostgreSQL value carry a `@MappableValue`
  /// override so the exact database string is preserved.
  String _generateMappableEnumFile(EnumInfo enumInfo) {
    final className = getEnumClassName(enumInfo.name);
    final fileName = ReCase(enumInfo.name).snakeCase;
    final buffer = StringBuffer();

    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln(
      '// ignore_for_file: public_member_api_docs, '
      'constant_identifier_names, lines_longer_than_80_chars, '
      'directives_ordering',
    );
    buffer.writeln();
    buffer.writeln("import 'package:dart_mappable/dart_mappable.dart';");
    buffer.writeln();
    buffer.writeln("part '$fileName.$fileExtension.mapper.dart';");
    buffer.writeln();
    buffer.writeln('@MappableEnum()');
    buffer.writeln('enum $className {');

    for (var i = 0; i < enumInfo.values.length; i++) {
      final pgValue = enumInfo.values[i];
      final dartName = _sanitizeEnumValue(pgValue);
      final comma = i < enumInfo.values.length - 1 ? ',' : ';';
      if (dartName != pgValue) {
        buffer.writeln("  @MappableValue('$pgValue')");
      }
      buffer.writeln('  $dartName$comma');
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates all enum files and returns a map of filename to content.
  Map<String, String> generateAllEnumFiles(List<EnumInfo> enums) {
    final result = <String, String>{};
    for (final enumInfo in enums) {
      final fileName = getEnumFileName(enumInfo.name);
      result[fileName] = generateEnumFile(enumInfo);
    }
    return result;
  }

  /// Generates a barrel file that exports all enum files.
  String generateBarrelFile(List<EnumInfo> enums) {
    final buffer = StringBuffer();
    buffer.writeln('// coverage:ignore-file');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: type=lint, directives_ordering');
    buffer.writeln('// Generated by supafreeze');
    buffer.writeln();

    for (final enumInfo in enums) {
      final fileName = getEnumFileName(enumInfo.name);
      buffer.writeln("export '$fileName';");
    }

    return buffer.toString();
  }

  /// Sanitizes a PostgreSQL enum value to a valid Dart identifier.
  ///
  /// - `in-progress` → `inProgress`
  /// - `123abc` → `$123abc`
  /// - `class` → `class$`
  String _sanitizeEnumValue(String pgValue) => sanitizeEnumValue(pgValue);

  /// Public, stateless variant of [_sanitizeEnumValue] so other generators
  /// (e.g. default-value parsing) can derive the same enum member identifier.
  static String sanitizeEnumValue(String pgValue) {
    // Convert to camelCase (handles hyphens, underscores, spaces)
    var dartName = ReCase(pgValue).camelCase;

    // If empty after conversion, use a fallback
    if (dartName.isEmpty) dartName = 'value';

    // Prefix with $ if starts with a digit
    if (RegExp(r'^[0-9]').hasMatch(dartName)) {
      dartName = '\$$dartName';
    }

    // Suffix with $ if it's a reserved word
    if (_dartReservedWords.contains(dartName)) {
      dartName = '$dartName\$';
    }

    return dartName;
  }
}
