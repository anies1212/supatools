import 'dart:io';
import 'package:path/path.dart' as p;
import 'edge_function_info.dart';
import 'ts_response_type_parser.dart';

/// Infers Edge Function request/response types from TypeScript source
class TsTypeExtractor {
  const TsTypeExtractor();

  /// Extracts model definitions from TypeScript source
  ///
  /// When [inferRequestFromUsage] is true and no explicit `body as { ... }`
  /// annotation is found, request fields are inferred from handler usage:
  /// `req.json() as { ... }` casts and `body.<field>` access patterns with
  /// `typeof body.<field> === "..."` type guards. This is heuristic and
  /// opt-in, since the inferred shape may not be perfectly precise.
  EdgeFunctionModelDef? extract({
    required String indexSource,
    String? handlerSource,
    bool inferRequestFromUsage = false,
    String? functionName,
    Map<String, List<EfTableColumn>>? tableSchemas,
  }) {
    final source = _removeComments(
      handlerSource != null ? '$indexSource\n$handlerSource' : indexSource,
    );

    var request = _extractRequestFields(source);
    if (request == null && inferRequestFromUsage) {
      request = _inferRequestFieldsFromUsage(source);
    }
    final response = _extractResponseFields(source);
    final errors = _extractErrorCodes(source);

    // Rich success-response DTO recovered from exported interfaces (preferred)
    // or the jsonResponse({...}) call (fallback). Requires the function name
    // to resolve the `<PascalName>Response` interface convention.
    final responseObject = functionName == null
        ? null
        : const TsResponseTypeParser().parse(
            functionName: functionName,
            indexSource: indexSource,
            handlerSource: handlerSource,
            tableSchemas: tableSchemas,
          );

    if (request == null &&
        response == null &&
        errors == null &&
        responseObject == null) {
      return null;
    }

    return EdgeFunctionModelDef(
      request: request,
      response: response,
      errors: errors,
      responseObject: responseObject,
    );
  }

  /// Extracts request fields from an explicit `body as { ... }` annotation.
  List<EdgeFunctionFieldDef>? _extractRequestFields(String source) {
    final bodyMatch = _bodyAsPattern.firstMatch(source);
    if (bodyMatch == null) return null;
    return _parseTypeBlock(bodyMatch.group(1)!, source);
  }

  /// Parses a TypeScript type block (`{ name?: type; ... }`) into field defs.
  List<EdgeFunctionFieldDef>? _parseTypeBlock(String block, String source) {
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

  /// Heuristically infers request fields from handler usage (opt-in).
  ///
  /// Strategy 1: an explicit `req.json() as { ... }` cast.
  /// Strategy 2: `body.<field>` accesses on the `await req.json()` result,
  /// with types inferred from `typeof body.<field> === "..."` guards and
  /// optionality inferred from ternary/nullish defaults.
  List<EdgeFunctionFieldDef>? _inferRequestFieldsFromUsage(String source) {
    final castMatch = _jsonCastPattern.firstMatch(source);
    if (castMatch != null) {
      final fields = _parseTypeBlock(castMatch.group(1)!, source);
      if (fields != null) return fields;
    }
    return _inferRequestFieldsFromBodyAccess(source);
  }

  /// Infers request fields from `body.<field>` access patterns.
  List<EdgeFunctionFieldDef>? _inferRequestFieldsFromBodyAccess(String source) {
    final assignMatch = _jsonAssignPattern.firstMatch(source);
    if (assignMatch == null) return null;
    final varName = assignMatch.group(1)!;

    final accessPattern = RegExp('$varName\\.([a-zA-Z_]\\w*)');
    final ordered = <String>[];
    final seen = <String>{};
    for (final match in accessPattern.allMatches(source)) {
      final field = match.group(1)!;
      if (seen.add(field)) ordered.add(field);
    }
    if (ordered.isEmpty) return null;

    return [
      for (final name in ordered)
        EdgeFunctionFieldDef(
          name: name,
          dataType: _inferBodyFieldType(source, varName, name),
          isRequired: !_isBodyFieldOptional(source, varName, name),
        ),
    ];
  }

  /// Infers a body field's type from handler usage.
  ///
  /// `typeof body.<field> === "string|number|boolean"` guards are precise.
  /// A `body.<field> === true|false` comparison implies a boolean. Numeric
  /// fields without a `typeof === "number"` guard cannot be recovered and
  /// fall back to `text` — define `models:` in config to override these.
  String _inferBodyFieldType(String source, String varName, String field) {
    final typeofMatch = RegExp(
      'typeof\\s+$varName\\.$field\\s*===?\\s*"(string|number|boolean)"',
    ).firstMatch(source);
    if (typeofMatch != null) {
      return switch (typeofMatch.group(1)) {
        'number' => 'integer',
        'boolean' => 'bool',
        _ => 'text',
      };
    }
    if (RegExp('$varName\\.$field\\s*===?\\s*(?:true|false)\\b')
        .hasMatch(source)) {
      return 'bool';
    }
    return 'text';
  }

  /// A body field is optional when its absence is explicitly handled, e.g.
  /// `typeof body.x === "string" ? body.x : null`, `body.x ?? ...`,
  /// `if (body.x !== undefined)`, or a `body.x === true` boolean flag.
  bool _isBodyFieldOptional(String source, String varName, String field) {
    final ternary = RegExp(
      'typeof\\s+$varName\\.$field\\s*===?\\s*"[a-z]+"\\s*\\?',
    ).hasMatch(source);
    final nullish = RegExp('$varName\\.$field\\s*\\?\\?').hasMatch(source);
    final undefinedGuard = RegExp(
      '$varName\\.$field\\s*[!=]==\\s*undefined',
    ).hasMatch(source);
    final boolFlag = RegExp(
      '$varName\\.$field\\s*===?\\s*(?:true|false)\\b',
    ).hasMatch(source);
    return ternary || nullish || undefinedGuard || boolFlag;
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
  /// and statusMap / `Record<string, number>` patterns.
  List<EdgeFunctionErrorDef>? _extractErrorCodes(String source) {
    final errors = <EdgeFunctionErrorDef>[];
    final seen = <String>{};

    // Pattern 1: Literal error codes in new Response(JSON.stringify({ error: "..." }))
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

    // Pattern 2: statusMap / Record<string, number> = { key: statusCode }
    _extractStatusMapErrorCodes(source, errors, seen);

    return errors.isEmpty ? null : errors;
  }

  /// Extracts error codes from statusMap patterns like:
  /// ```
  /// const statusMap: Record<string, number> = {
  ///   campaign_not_found: 404,
  ///   campaign_inactive: 400,
  /// };
  /// ```
  void _extractStatusMapErrorCodes(
    String source,
    List<EdgeFunctionErrorDef> errors,
    Set<String> seen,
  ) {
    for (final match in _statusMapPattern.allMatches(source)) {
      final body = match.group(1)!;
      for (final entry in _statusMapEntryPattern.allMatches(body)) {
        final code = entry.group(1)!;
        final statusCode = int.tryParse(entry.group(2)!);

        if (!_snakeCasePattern.hasMatch(code)) continue;
        if (seen.contains(code)) continue;

        seen.add(code);
        errors.add(EdgeFunctionErrorDef(
          code: code,
          statusCode: statusCode,
        ));
      }
    }
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

  /// `req.json() as { ... }` cast block (used by usage-based inference)
  static final _jsonCastPattern = RegExp(
    r'req\.json\(\)\s+as\s*\{([^}]+)\}',
    dotAll: true,
  );

  /// `<var> = await req.json()` — captures the body variable name
  static final _jsonAssignPattern = RegExp(
    r'(\w+)\s*=\s*await\s+req\.json\(\)',
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

  /// `Record<string, number>` or `{ key: number }` status map pattern
  static final _statusMapPattern = RegExp(
    r'(?:Record<string,\s*number>|:\s*\{[^}]*\})\s*=\s*\{([^}]+)\}',
    dotAll: true,
  );

  /// Entry pattern inside statusMap: key: number
  static final _statusMapEntryPattern = RegExp(
    r'(\w+)\s*:\s*(\d+)',
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
    String functionDirPath, {
    bool inferRequestFromUsage = false,
    Map<String, List<EfTableColumn>>? tableSchemas,
  }) async {
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
      inferRequestFromUsage: inferRequestFromUsage,
      functionName: p.basename(functionDirPath),
      tableSchemas: tableSchemas,
    );
  }
}
