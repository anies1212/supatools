import 'dart:io';
import 'package:path/path.dart' as p;
import 'edge_function_info.dart';

/// Infers Edge Function request/response types from TypeScript source
class TsTypeExtractor {
  const TsTypeExtractor();

  /// Extracts model definitions from TypeScript source
  EdgeFunctionModelDef? extract({
    required String indexSource,
    String? handlerSource,
  }) {
    final source = _removeComments(
      handlerSource != null ? '$indexSource\n$handlerSource' : indexSource,
    );

    final request = _extractRequestFields(source);
    final response = _extractResponseFields(source);
    final errors = _extractErrorCodes(source);

    if (request == null && response == null && errors == null) {
      return null;
    }

    return EdgeFunctionModelDef(
      request: request,
      response: response,
      errors: errors,
    );
  }

  /// Extracts request fields from `body as { ... }` pattern
  List<EdgeFunctionFieldDef>? _extractRequestFields(String source) {
    final bodyMatch = _bodyAsPattern.firstMatch(source);
    if (bodyMatch == null) return null;

    final block = bodyMatch.group(1)!;
    final fields = <EdgeFunctionFieldDef>[];
    final requiredFields = _extractRequiredFields(source);

    for (final match in _fieldPattern.allMatches(block)) {
      final name = match.group(1)!;
      final hasQuestionMark = match.group(2) != null;
      final tsType = match.group(3)!;

      final isRequired = !hasQuestionMark || requiredFields.contains(name);

      fields.add(EdgeFunctionFieldDef(
        name: name,
        dataType: _tsTypeToDartType(tsType),
        isRequired: isRequired,
      ));
    }

    return fields.isEmpty ? null : fields;
  }

  /// Extracts response fields from success `JSON.stringify({ ... })`
  List<EdgeFunctionFieldDef>? _extractResponseFields(String source) {
    for (final match in _newResponsePattern.allMatches(source)) {
      final block = match.group(0)!;

      // Skip error responses (status 4xx/5xx)
      if (_errorStatusPattern.hasMatch(block)) continue;

      final stringifyMatch = _jsonStringifyFieldsPattern.firstMatch(block);
      if (stringifyMatch == null) continue;

      final jsonBody = stringifyMatch.group(1)!;
      final fields = <EdgeFunctionFieldDef>[];

      // Split by comma and parse each field
      for (final part in jsonBody.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;

        final colonIndex = trimmed.indexOf(':');
        if (colonIndex > 0) {
          // key: value pattern
          final name = trimmed.substring(0, colonIndex).trim();
          final valueExpr = trimmed.substring(colonIndex + 1).trim();
          if (!_identifierPattern.hasMatch(name)) continue;
          fields.add(EdgeFunctionFieldDef(
            name: name,
            dataType: _inferResponseFieldType(
              name,
              valueExpr,
            ),
            isRequired: true,
          ));
        } else if (_identifierPattern.hasMatch(trimmed)) {
          // Shorthand property (variable name only)
          fields.add(EdgeFunctionFieldDef(
            name: trimmed,
            dataType: _inferResponseFieldType(trimmed, ''),
            isRequired: true,
          ));
        }
      }

      if (fields.isNotEmpty) return fields;
    }

    return null;
  }

  /// Extracts required fields from validation if-statements
  Set<String> _extractRequiredFields(String source) {
    final required = <String>{};

    // !field pattern
    for (final match in _bangCheckPattern.allMatches(source)) {
      required.add(match.group(1)!);
    }

    // typeof field !== "type" pattern
    for (final match in _typeofCheckPattern.allMatches(source)) {
      required.add(match.group(1)!);
    }

    return required;
  }

  /// Maps TypeScript type to PostgreSQL-compatible type name
  /// (converted to Dart type by existing _pgTypeToDartType)
  String _tsTypeToDartType(String tsType) {
    return switch (tsType.toLowerCase()) {
      'string' => 'text',
      'number' => 'integer',
      'boolean' => 'bool',
      'object' => 'jsonb',
      'any' => 'jsonb',
      _ => 'text',
    };
  }

  /// Infers response field type using heuristics
  String _inferResponseFieldType(String name, String valueExpr) {
    // Value-based inference
    if (valueExpr == 'true' || valueExpr == 'false') {
      return 'bool';
    }
    // Name-based inference
    if (name.startsWith('is_') || name.startsWith('has_')) {
      return 'bool';
    }
    if (name.contains('points') ||
        name.contains('amount') ||
        name.contains('count')) {
      return 'integer';
    }
    return 'text';
  }

  /// Extracts error codes from error responses (4xx/5xx)
  List<EdgeFunctionErrorDef>? _extractErrorCodes(String source) {
    final errors = <EdgeFunctionErrorDef>[];
    final seen = <String>{};

    for (final match in _newResponsePattern.allMatches(source)) {
      final block = match.group(0)!;

      // Only error responses
      final statusMatch = _errorStatusPattern.firstMatch(block);
      if (statusMatch == null) continue;

      final statusCode = int.tryParse(
        RegExp(r'status:\s*(\d+)').firstMatch(block)!.group(1)!,
      );

      final stringifyMatch = _jsonStringifyFieldsPattern.firstMatch(block);
      if (stringifyMatch == null) continue;

      final jsonBody = stringifyMatch.group(1)!;

      // Extract error field value
      final errorFieldMatch = _errorFieldPattern.firstMatch(jsonBody);
      if (errorFieldMatch == null) continue;

      final code = errorFieldMatch.group(1)!;

      // Only snake_case error codes
      if (!_snakeCasePattern.hasMatch(code)) continue;
      if (seen.contains(code)) continue;

      seen.add(code);
      errors.add(EdgeFunctionErrorDef(
        code: code,
        statusCode: statusCode,
      ));
    }

    return errors.isEmpty ? null : errors;
  }

  /// Removes comments as a preprocessing step
  String _removeComments(String source) {
    // Single-line comments
    source = source.replaceAll(RegExp(r'//[^\n]*'), '');
    // Multi-line comments
    source = source.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      '',
    );
    return source;
  }

  // --- Regex patterns ---

  /// `body as { ... }` block
  static final _bodyAsPattern = RegExp(
    r'body\s+as\s*\{([^}]+)\}',
    dotAll: true,
  );

  /// TypeScript field definition: name?: type;
  static final _fieldPattern = RegExp(
    r'(\w+)(\?)?:\s*(\w+)',
  );

  /// `!field` validation check
  static final _bangCheckPattern = RegExp(
    r'!\s*(\w+)(?:\s*\|\||[^=])',
  );

  /// `typeof field !== "type"` validation check
  static final _typeofCheckPattern = RegExp(
    r'typeof\s+(\w+)\s*!==?\s*["\x27](\w+)["\x27]',
  );

  /// `new Response(...)` block (non-greedy)
  static final _newResponsePattern = RegExp(
    r'new\s+Response\s*\([^;]+?\{[^;]*?status:\s*\d+',
    dotAll: true,
  );

  /// Error status (4xx/5xx)
  static final _errorStatusPattern = RegExp(
    r'status:\s*[45]\d{2}',
  );

  /// Extracts fields inside `JSON.stringify({ ... })`
  static final _jsonStringifyFieldsPattern = RegExp(
    r'JSON\.stringify\s*\(\s*\{([^}]+)\}',
    dotAll: true,
  );

  /// Identifier pattern (for variable name check)
  static final _identifierPattern = RegExp(r'^\w+$');

  /// Extracts `error: "..."` field value from JSON.stringify body
  static final _errorFieldPattern = RegExp(
    r'''error:\s*["']([^"']+)["']''',
  );

  /// snake_case pattern (at least one underscore, lowercase + digits)
  static final _snakeCasePattern = RegExp(
    r'^[a-z][a-z0-9]*(_[a-z0-9]+)+$',
  );
}

/// Loads TypeScript source from filesystem and extracts types
class TsTypeExtractorLoader {
  final TsTypeExtractor _extractor;

  const TsTypeExtractorLoader([
    this._extractor = const TsTypeExtractor(),
  ]);

  /// Extracts model definitions from the given function directory
  Future<EdgeFunctionModelDef?> extractFromDirectory(
    String functionDirPath,
  ) async {
    final indexFile = File(p.join(functionDirPath, 'index.ts'));
    if (!await indexFile.exists()) return null;

    final indexSource = await indexFile.readAsString();

    // Read handler.ts if it exists
    String? handlerSource;
    final handlerFile = File(p.join(functionDirPath, 'handler.ts'));
    if (await handlerFile.exists()) {
      handlerSource = await handlerFile.readAsString();
    }

    return _extractor.extract(
      indexSource: indexSource,
      handlerSource: handlerSource,
    );
  }
}
