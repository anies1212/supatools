import 'package:recase/recase.dart';
import 'edge_function_info.dart';

/// Parses an Edge Function's success-response shape from TypeScript source.
///
/// Two strategies, in priority order:
///
/// 1. **Exported interface** — an `export interface <PascalName>Response { ... }`
///    is parsed directly. Nested objects, `T | null`, `string[]`, and
///    references to other interfaces declared in the same file are resolved
///    recursively.
/// 2. **`jsonResponse({...})` inference (fallback)** — when no `Response`
///    interface exists, the success `jsonResponse({...})` (or non-error
///    `JSON.stringify({...})`) call is parsed. Each property's type is
///    recovered from referenced functions/variables whose return/declared type
///    points at an interface, falling back to a name/value heuristic.
///
/// Returns `null` when neither strategy recovers a non-empty object shape, so
/// functions that don't export a response type are skipped (backward compat).
class TsResponseTypeParser {
  const TsResponseTypeParser();

  List<EdgeFunctionResponseField>? parse({
    required String functionName,
    required String indexSource,
    String? handlerSource,
  }) {
    final source = _stripComments(
      handlerSource != null ? '$indexSource\n$handlerSource' : indexSource,
    );

    final interfaces = _parseInterfaces(source);

    // Strategy 1: explicit `<PascalName>Response` interface.
    final responseName = '${ReCase(functionName).pascalCase}Response';
    final rootBody = interfaces[responseName];
    if (rootBody != null) {
      final fields = _parseObjectBody(rootBody, interfaces, {responseName});
      if (fields != null && fields.isNotEmpty) return fields;
    }

    // Strategy 2: infer from the success `jsonResponse({...})` call.
    return _inferFromSuccessResponse(source, interfaces);
  }

  // --- Interface parsing ---

  /// Parses all `interface <Name> { ... }` blocks into name → inner body.
  Map<String, String> _parseInterfaces(String source) {
    final result = <String, String>{};
    final header = RegExp(r'interface\s+(\w+)[^{]*\{');
    for (final m in header.allMatches(source)) {
      final name = m.group(1)!;
      final body = _extractBraces(source, m.end - 1);
      if (body != null) result[name] = body;
    }
    return result;
  }

  /// Given [source] and the index of an opening `{`, returns the content
  /// between it and its matching `}` (exclusive). Returns null if unbalanced.
  String? _extractBraces(String source, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < source.length; i++) {
      final c = source[i];
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return source.substring(openIndex + 1, i);
      }
    }
    return null;
  }

  /// Parses an object body (`name: type; other?: type; ...`) into fields.
  List<EdgeFunctionResponseField>? _parseObjectBody(
    String body,
    Map<String, String> interfaces,
    Set<String> seen,
  ) {
    final fields = <EdgeFunctionResponseField>[];

    for (final member in _splitMembers(body)) {
      final trimmed = member.trim();
      if (trimmed.isEmpty) continue;

      final colon = _topLevelColon(trimmed);
      if (colon < 0) continue;

      var rawName = trimmed.substring(0, colon).trim();
      final optional = rawName.endsWith('?');
      if (optional) rawName = rawName.substring(0, rawName.length - 1).trim();
      rawName = rawName.replaceFirst(RegExp(r'^readonly\s+'), '').trim();
      // Strip quotes from quoted keys ("card_date" / 'card_date').
      rawName = rawName.replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      if (!_identifier.hasMatch(rawName)) continue;

      final typeStr = trimmed.substring(colon + 1).trim();
      final resolved = _resolveType(typeStr, interfaces, seen);
      if (resolved == null) continue;

      fields.add(EdgeFunctionResponseField(
        jsonKey: rawName,
        nullable: resolved.nullable || optional,
        isList: resolved.isList,
        dartScalarType: resolved.dartScalarType,
        objectFields: resolved.objectFields,
      ));
    }

    return fields.isEmpty ? null : fields;
  }

  /// Resolves a TypeScript type expression into a (partial) response field.
  _ResolvedType? _resolveType(
    String typeExpr,
    Map<String, String> interfaces,
    Set<String> seen,
  ) {
    var type = typeExpr.trim();
    if (type.endsWith(';')) type = type.substring(0, type.length - 1).trim();

    // Union with null/undefined → nullable; strip those members.
    var nullable = false;
    if (type.contains('|')) {
      final members = type.split('|').map((m) => m.trim()).toList();
      final kept = <String>[];
      for (final m in members) {
        if (m == 'null' || m == 'undefined') {
          nullable = true;
        } else {
          kept.add(m);
        }
      }
      if (kept.isEmpty) return null;
      // Use the first non-null member (best effort for unions).
      type = kept.first;
    }

    // Array forms: `Array<X>` and `X[]`.
    if (type.startsWith('Array<') && type.endsWith('>')) {
      final inner = type.substring(6, type.length - 1).trim();
      final innerResolved = _resolveType(inner, interfaces, seen);
      if (innerResolved == null) return null;
      return innerResolved.asList(nullable: nullable);
    }
    if (type.endsWith('[]')) {
      final inner = type.substring(0, type.length - 2).trim();
      final innerResolved = _resolveType(inner, interfaces, seen);
      if (innerResolved == null) return null;
      return innerResolved.asList(nullable: nullable);
    }

    // Inline object literal.
    if (type.startsWith('{') && type.endsWith('}')) {
      final inner = type.substring(1, type.length - 1);
      final objFields = _parseObjectBody(inner, interfaces, seen);
      if (objFields == null) return _scalar('Map<String, dynamic>', nullable);
      return _ResolvedType(objectFields: objFields, nullable: nullable);
    }

    // Reference to another interface in the same file.
    if (interfaces.containsKey(type) && !seen.contains(type)) {
      final objFields = _parseObjectBody(
        interfaces[type]!,
        interfaces,
        {...seen, type},
      );
      if (objFields != null) {
        return _ResolvedType(objectFields: objFields, nullable: nullable);
      }
    }

    // Scalars and fallthrough.
    return _scalar(_tsScalarToDart(type), nullable);
  }

  _ResolvedType _scalar(String dartType, bool nullable) =>
      _ResolvedType(dartScalarType: dartType, nullable: nullable);

  /// Maps a TypeScript scalar type to a Dart type.
  String _tsScalarToDart(String type) {
    final t = type.trim();
    if (t.startsWith('Record<') || t == 'object') return 'Map<String, dynamic>';
    return switch (t) {
      'string' => 'String',
      'number' => 'int',
      'boolean' => 'bool',
      'any' || 'unknown' => 'dynamic',
      _ => 'dynamic',
    };
  }

  // --- Fallback: infer from jsonResponse({...}) ---

  List<EdgeFunctionResponseField>? _inferFromSuccessResponse(
    String source,
    Map<String, String> interfaces,
  ) {
    final objectLiteral = _findSuccessObjectLiteral(source);
    if (objectLiteral == null) return null;

    final symbols = _parseSymbolTypes(source);
    final fields = <EdgeFunctionResponseField>[];

    for (final member in _splitMembers(objectLiteral)) {
      final trimmed = member.trim();
      if (trimmed.isEmpty) continue;

      final colon = _topLevelColon(trimmed);
      final String key;
      final String valueExpr;
      if (colon < 0) {
        // Shorthand `{ foo }` → key and value are the same identifier.
        if (!_identifier.hasMatch(trimmed)) continue;
        key = trimmed;
        valueExpr = trimmed;
      } else {
        key = trimmed.substring(0, colon).trim().replaceAll(
              RegExp(r'''^['"]|['"]$'''),
              '',
            );
        valueExpr = trimmed.substring(colon + 1).trim();
      }
      if (!_identifier.hasMatch(key)) continue;

      final resolved = _resolveValueExpr(valueExpr, key, symbols, interfaces);
      fields.add(EdgeFunctionResponseField(
        jsonKey: key,
        nullable: resolved.nullable,
        isList: resolved.isList,
        dartScalarType: resolved.dartScalarType,
        objectFields: resolved.objectFields,
      ));
    }

    return fields.isEmpty ? null : fields;
  }

  /// Finds the object literal of the first success (`jsonResponse` /
  /// non-error `JSON.stringify`) response in [source].
  String? _findSuccessObjectLiteral(String source) {
    // Prefer an explicit `jsonResponse({ ... })` helper call.
    final jsonResponse = RegExp(r'jsonResponse\s*\(\s*\{');
    for (final m in jsonResponse.allMatches(source)) {
      final body = _extractBraces(source, m.end - 1);
      if (body != null && body.trim().isNotEmpty) return body;
    }

    // Otherwise, a `JSON.stringify({ ... })` not inside an error response.
    final stringify = RegExp(r'JSON\.stringify\s*\(\s*\{');
    for (final m in stringify.allMatches(source)) {
      final body = _extractBraces(source, m.end - 1);
      if (body == null) continue;
      if (RegExp('error').hasMatch(body)) continue;
      if (body.trim().isNotEmpty) return body;
    }
    return null;
  }

  /// Builds a map of identifier → declared/return TypeScript type from
  /// `function f(...): T` and `const x: T =` declarations.
  Map<String, String> _parseSymbolTypes(String source) {
    final result = <String, String>{};

    final fn = RegExp(r'function\s+(\w+)\s*\([^)]*\)\s*:\s*([^\{]+?)\s*\{');
    for (final m in fn.allMatches(source)) {
      result[m.group(1)!] = m.group(2)!.trim();
    }

    final constTyped = RegExp(r'const\s+(\w+)\s*:\s*([^=]+?)\s*=');
    for (final m in constTyped.allMatches(source)) {
      result.putIfAbsent(m.group(1)!, () => m.group(2)!.trim());
    }

    return result;
  }

  _ResolvedType _resolveValueExpr(
    String valueExpr,
    String key,
    Map<String, String> symbols,
    Map<String, String> interfaces,
  ) {
    final expr = valueExpr.trim();

    // Boolean literal.
    if (expr == 'true' || expr == 'false') return _scalar('bool', false);

    // Function call `ident(...)` → resolve the function's return type.
    final call = RegExp(r'^(\w+)\s*\(').firstMatch(expr);
    if (call != null) {
      final type = symbols[call.group(1)!];
      if (type != null) {
        final resolved = _resolveType(type, interfaces, {});
        if (resolved != null) return resolved;
      }
    }

    // Bare identifier → resolve its declared type.
    if (_identifier.hasMatch(expr) && symbols.containsKey(expr)) {
      final resolved = _resolveType(symbols[expr]!, interfaces, {});
      if (resolved != null) return resolved;
    }

    // Name-based heuristic fallback.
    if (key.startsWith('is_') ||
        key.startsWith('has_') ||
        ReCase(key).camelCase.startsWith('is')) {
      return _scalar('bool', false);
    }
    return _scalar('dynamic', false);
  }

  // --- Low-level helpers ---

  /// Splits an object/interface body into top-level members, respecting
  /// nested braces/brackets/angle brackets. Members are separated by `;` or
  /// `,` at depth 0.
  List<String> _splitMembers(String body) {
    final members = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == '{' || c == '[' || c == '<' || c == '(') depth++;
      if (c == '}' || c == ']' || c == '>' || c == ')') depth--;
      if ((c == ';' || c == ',') && depth == 0) {
        members.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) members.add(buffer.toString());
    return members;
  }

  /// Returns the index of the first `:` at brace/bracket/angle depth 0, or -1.
  int _topLevelColon(String s) {
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '{' || c == '[' || c == '<' || c == '(') depth++;
      if (c == '}' || c == ']' || c == '>' || c == ')') depth--;
      if (c == ':' && depth == 0) return i;
    }
    return -1;
  }

  String _stripComments(String source) {
    source = source.replaceAll(RegExp(r'//[^\n]*'), '');
    source = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    return source;
  }

  static final _identifier = RegExp(r'^\w+$');
}

/// Internal: a resolved type before a json key is attached.
class _ResolvedType {
  final bool nullable;
  final bool isList;
  final String? dartScalarType;
  final List<EdgeFunctionResponseField>? objectFields;

  const _ResolvedType({
    this.nullable = false,
    this.isList = false,
    this.dartScalarType,
    this.objectFields,
  });

  _ResolvedType asList({required bool nullable}) => _ResolvedType(
        nullable: nullable,
        isList: true,
        dartScalarType: dartScalarType,
        objectFields: objectFields,
      );
}
