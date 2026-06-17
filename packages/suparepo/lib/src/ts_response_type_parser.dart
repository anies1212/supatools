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

  /// [tableSchemas] enables strategy 3 (select-projection inference): when
  /// provided (keyed by table name), a `jsonResponse` property that spreads a
  /// `<client>.from("t").select("cols")` result is typed from the table's
  /// columns. When null/empty, strategy 3 is off (default, opt-in upstream).
  /// [importedSources] is the concatenated content of the handler's relative
  /// imports (resolved by the loader). It's used only to resolve the return
  /// types of imported helper functions referenced in `jsonResponse({...})`
  /// (e.g. `const allDone = computeAllDone(...)`), never to scan for response
  /// shapes.
  List<EdgeFunctionResponseField>? parse({
    required String functionName,
    required String indexSource,
    String? handlerSource,
    Map<String, List<EfTableColumn>>? tableSchemas,
    String? importedSources,
  }) {
    final source = _stripComments(
      handlerSource != null ? '$indexSource\n$handlerSource' : indexSource,
    );
    final imported =
        importedSources == null ? null : _stripComments(importedSources);

    final interfaces = _parseInterfaces(source);

    // Strategy 1: explicit `<PascalName>Response` interface.
    final responseName = '${ReCase(functionName).pascalCase}Response';
    final rootBody = interfaces[responseName];
    if (rootBody != null) {
      final fields = _parseObjectBody(rootBody, interfaces, {responseName});
      if (fields != null && fields.isNotEmpty) return fields;
    }

    // Strategies 2 & 3: infer from the success `jsonResponse({...})` call(s).
    return _inferFromSuccessResponse(source, interfaces, tableSchemas, imported);
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

    // `Promise<T>` (an awaited async helper's return type) → unwrap to `T`.
    // Lets `await isEntitledUser(): Promise<boolean>` resolve like a sync
    // `: boolean` helper instead of falling back to `dynamic`.
    if (type.startsWith('Promise<') && type.endsWith('>')) {
      final inner = type.substring('Promise<'.length, type.length - 1).trim();
      final innerResolved = _resolveType(inner, interfaces, seen);
      if (innerResolved == null) return null;
      if (!nullable) return innerResolved;
      return _ResolvedType(
        nullable: true,
        isList: innerResolved.isList,
        dartScalarType: innerResolved.dartScalarType,
        objectFields: innerResolved.objectFields,
      );
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
    Map<String, List<EfTableColumn>>? tableSchemas,
    String? importedSources,
  ) {
    final literals = _findSuccessObjectLiterals(source);
    if (literals.isEmpty) return null;

    final symbols = _parseSymbolTypes(source, importedSources);
    final selectVars = (tableSchemas != null && tableSchemas.isNotEmpty)
        ? _parseSelectVars(source)
        : const <String, _SelectInfo>{};

    // Parse every success return, then take the union of their property sets:
    // a key present in only some returns becomes optional (nullable).
    final perReturn = [
      for (final literal in literals)
        _parseSuccessLiteral(
          literal,
          symbols,
          interfaces,
          selectVars,
          tableSchemas,
        ),
    ];

    final merged =
        perReturn.length == 1 ? perReturn.first : _unionFields(perReturn);
    return merged.isEmpty ? null : merged;
  }

  /// Parses a single success object literal into fields (possibly empty).
  List<EdgeFunctionResponseField> _parseSuccessLiteral(
    String objectLiteral,
    Map<String, String> symbols,
    Map<String, String> interfaces,
    Map<String, _SelectInfo> selectVars,
    Map<String, List<EfTableColumn>>? tableSchemas,
  ) {
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

      final resolved = _resolveValueExpr(
        valueExpr,
        key,
        symbols,
        interfaces,
        selectVars,
        tableSchemas,
      );
      fields.add(EdgeFunctionResponseField(
        jsonKey: key,
        nullable: resolved.nullable,
        isList: resolved.isList,
        dartScalarType: resolved.dartScalarType,
        objectFields: resolved.objectFields,
      ));
    }

    return fields;
  }

  /// Unions the field sets of multiple success returns. A key missing from any
  /// return (or nullable in any) becomes nullable. Same-typed occurrences keep
  /// their type (objects merge their nested fields recursively); conflicting
  /// types fall back to `dynamic`.
  List<EdgeFunctionResponseField> _unionFields(
    List<List<EdgeFunctionResponseField>> returns,
  ) {
    final total = returns.length;
    final order = <String>[];
    final byKey = <String, List<EdgeFunctionResponseField>>{};
    for (final fields in returns) {
      for (final f in fields) {
        if (!byKey.containsKey(f.jsonKey)) order.add(f.jsonKey);
        byKey.putIfAbsent(f.jsonKey, () => []).add(f);
      }
    }

    return [
      for (final key in order)
        _mergeOccurrences(
          key,
          byKey[key]!,
          byKey[key]!.any((f) => f.nullable) || byKey[key]!.length < total,
        ),
    ];
  }

  EdgeFunctionResponseField _mergeOccurrences(
    String key,
    List<EdgeFunctionResponseField> occ,
    bool nullable,
  ) {
    final isList = occ.first.isList;
    final sameList = occ.every((f) => f.isList == isList);

    if (sameList && occ.every((f) => f.isObject)) {
      final nested = _unionFields([for (final f in occ) f.objectFields!]);
      if (nested.isNotEmpty) {
        return EdgeFunctionResponseField(
          jsonKey: key,
          nullable: nullable,
          isList: isList,
          objectFields: nested,
        );
      }
    } else if (sameList && occ.every((f) => !f.isObject)) {
      final types = {for (final f in occ) f.dartScalarType};
      if (types.length == 1 && types.first != 'dynamic') {
        return EdgeFunctionResponseField(
          jsonKey: key,
          nullable: nullable,
          isList: isList,
          dartScalarType: types.first,
        );
      }
    }

    // Conflicting or unresolvable across returns → dynamic.
    return EdgeFunctionResponseField(
      jsonKey: key,
      nullable: nullable,
      dartScalarType: 'dynamic',
    );
  }

  /// Finds the object literals of all success (`jsonResponse` / non-error
  /// `JSON.stringify`) responses in [source]. Empty `{}` literals are included
  /// so they count as a return path when unioning.
  List<String> _findSuccessObjectLiterals(String source) {
    final results = <String>[];

    final jsonResponse = RegExp(r'jsonResponse\s*\(\s*\{');
    for (final m in jsonResponse.allMatches(source)) {
      final body = _extractBraces(source, m.end - 1);
      if (body != null) results.add(body);
    }
    if (results.isNotEmpty) return results;

    // Otherwise, `JSON.stringify({ ... })` blocks not inside an error response.
    final stringify = RegExp(r'JSON\.stringify\s*\(\s*\{');
    for (final m in stringify.allMatches(source)) {
      final body = _extractBraces(source, m.end - 1);
      if (body == null) continue;
      if (RegExp('error').hasMatch(body)) continue;
      results.add(body);
    }
    return results;
  }

  /// Builds a map of identifier → declared/return TypeScript type.
  ///
  /// Function return types are collected from both [source] and
  /// [importedSources] (so imported helpers like `computeAllDone(): boolean`
  /// resolve). Variable types are collected from [source] only: explicit
  /// `const x: T =` annotations, and `const x = fn(...)` bound to a known
  /// function (its return type).
  Map<String, String> _parseSymbolTypes(String source, [String? importedSources]) {
    final functions = <String, String>{};

    void collectFunctions(String src) {
      final fn = RegExp(r'function\s+(\w+)\s*\([^)]*\)\s*:\s*([^{]+?)\s*\{');
      for (final m in fn.allMatches(src)) {
        functions.putIfAbsent(m.group(1)!, () => m.group(2)!.trim());
      }
      // Arrow with return type: `const f = (...): T =>`.
      final arrow = RegExp(
        r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*:\s*([^=]+?)\s*=>',
      );
      for (final m in arrow.allMatches(src)) {
        functions.putIfAbsent(m.group(1)!, () => m.group(2)!.trim());
      }
    }

    collectFunctions(source);
    if (importedSources != null) collectFunctions(importedSources);

    final result = <String, String>{...functions};

    // Explicitly typed const: `const x: T = ...`.
    final constTyped = RegExp(r'const\s+(\w+)\s*:\s*([^=]+?)\s*=');
    for (final m in constTyped.allMatches(source)) {
      result.putIfAbsent(m.group(1)!, () => m.group(2)!.trim());
    }

    // Untyped const bound to a known function call: `const x = fn(...)`.
    final constCall = RegExp(
      r'(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(\w+)\s*\(',
    );
    for (final m in constCall.allMatches(source)) {
      final fnName = m.group(2)!;
      if (functions.containsKey(fnName)) {
        result.putIfAbsent(m.group(1)!, () => functions[fnName]!);
      }
    }

    return result;
  }

  _ResolvedType _resolveValueExpr(
    String valueExpr,
    String key,
    Map<String, String> symbols,
    Map<String, String> interfaces,
    Map<String, _SelectInfo> selectVars,
    Map<String, List<EfTableColumn>>? tableSchemas,
  ) {
    final expr = valueExpr.trim();

    // `await <inner>` (awaited async helper) → resolve `<inner>`; its
    // `Promise<T>` return type is unwrapped to `T` in `_resolveType`.
    final awaited = RegExp(r'^await\s+([\s\S]+)$').firstMatch(expr);
    if (awaited != null) {
      return _resolveValueExpr(
        awaited.group(1)!.trim(),
        key,
        symbols,
        interfaces,
        selectVars,
        tableSchemas,
      );
    }

    // Boolean literal.
    if (expr == 'true' || expr == 'false') return _scalar('bool', false);

    // Strategy 3: type from a `.from(table).select(cols)` projection.
    if (tableSchemas != null && tableSchemas.isNotEmpty) {
      // Reshaping with `.map(...)` cannot be typed safely → dynamic.
      if (expr.contains('.map(')) return _scalar('dynamic', false);

      // `{ ...X, extra: ... }` object literal spreading a select result.
      if (expr.startsWith('{') && expr.endsWith('}') && expr.contains('...')) {
        final resolved = _resolveSpreadObjectLiteral(
          expr,
          symbols,
          interfaces,
          selectVars,
          tableSchemas,
        );
        if (resolved != null) return resolved;
      }

      // Bare identifier bound to a select result → object or List<object>.
      if (_identifier.hasMatch(expr) && selectVars.containsKey(expr)) {
        final resolved = _resolveSelectVar(expr, selectVars, tableSchemas);
        if (resolved != null) return resolved;
      }
    }

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

  // --- Strategy 3: select-projection inference ---

  /// Resolves `{ ...X, extra: ... }` where `X` is a single-row select result.
  /// Returns a single object whose fields are the projected columns plus the
  /// extra literal properties. Returns null when `X` is not a resolvable
  /// single-row select (so the caller can fall through to other strategies).
  _ResolvedType? _resolveSpreadObjectLiteral(
    String expr,
    Map<String, String> symbols,
    Map<String, String> interfaces,
    Map<String, _SelectInfo> selectVars,
    Map<String, List<EfTableColumn>> tableSchemas,
  ) {
    final inner = expr.substring(1, expr.length - 1);
    final spreadVars = <String>[];
    final extras = <EdgeFunctionResponseField>[];

    for (final member in _splitMembers(inner)) {
      final trimmed = member.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('...')) {
        final v = trimmed.substring(3).trim();
        if (!_identifier.hasMatch(v)) return null; // `...expr.foo` → bail
        spreadVars.add(v);
        continue;
      }

      final colon = _topLevelColon(trimmed);
      if (colon < 0) {
        if (!_identifier.hasMatch(trimmed)) continue;
        extras.add(EdgeFunctionResponseField(
          jsonKey: trimmed,
          dartScalarType: _heuristicScalar(trimmed, trimmed),
        ));
        continue;
      }
      final k = trimmed
          .substring(0, colon)
          .trim()
          .replaceAll(RegExp(r'''^['"]|['"]$'''), '');
      if (!_identifier.hasMatch(k)) continue;
      final v = trimmed.substring(colon + 1).trim();
      extras.add(EdgeFunctionResponseField(
        jsonKey: k,
        dartScalarType: _heuristicScalar(k, v),
      ));
    }

    // Exactly one spread of a single-row select is supported.
    if (spreadVars.length != 1) return null;
    final info = selectVars[spreadVars.first];
    if (info == null || !info.isSingle) return null;
    final columns = _projectSelect(info, tableSchemas);
    if (columns == null) return null;

    final keys = <String>{for (final c in columns) c.jsonKey};
    final merged = [
      ...columns,
      for (final e in extras)
        if (!keys.contains(e.jsonKey)) e,
    ];
    return _ResolvedType(objectFields: merged);
  }

  /// Resolves a bare identifier bound to a select result into an object (single
  /// row) or `List<object>` (multi row). Returns null when not resolvable.
  _ResolvedType? _resolveSelectVar(
    String varName,
    Map<String, _SelectInfo> selectVars,
    Map<String, List<EfTableColumn>> tableSchemas,
  ) {
    final info = selectVars[varName];
    if (info == null) return null;
    final columns = _projectSelect(info, tableSchemas);
    if (columns == null) return null;
    return _ResolvedType(objectFields: columns, isList: !info.isSingle);
  }

  /// Types a select projection's columns from the table schema. Returns null
  /// (→ dynamic fallback) when the table is unknown, a relation embed is
  /// present, or a selected column can't be resolved.
  List<EdgeFunctionResponseField>? _projectSelect(
    _SelectInfo info,
    Map<String, List<EfTableColumn>> tableSchemas,
  ) {
    final columns = tableSchemas[info.table];
    if (columns == null) return null;
    final byName = {for (final c in columns) c.name: c};

    final selected = info.select.trim();
    if (selected == '*') {
      return [
        for (final c in columns)
          EdgeFunctionResponseField(
            jsonKey: c.name,
            dartScalarType: c.dartType,
            nullable: c.nullable,
          ),
      ];
    }

    final fields = <EdgeFunctionResponseField>[];
    for (final raw in _splitMembers(selected)) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      // Relation embed (`bond:bonds(*)`, `bonds(*)`) → not inferable safely.
      if (token.contains('(')) return null;

      String jsonKey;
      String sourceCol;
      final colon = token.indexOf(':');
      if (colon > 0) {
        jsonKey = token.substring(0, colon).trim();
        sourceCol = token.substring(colon + 1).trim();
      } else {
        jsonKey = token;
        sourceCol = token;
      }
      if (jsonKey == '*' || sourceCol == '*') return null;

      final col = byName[sourceCol];
      if (col == null) return null; // unknown column → bail to dynamic
      fields.add(EdgeFunctionResponseField(
        jsonKey: jsonKey,
        dartScalarType: col.dartType,
        nullable: col.nullable,
      ));
    }
    return fields.isEmpty ? null : fields;
  }

  String _heuristicScalar(String key, String valueExpr) {
    final v = valueExpr.trim();
    if (v == 'true' || v == 'false') return 'bool';
    if (key.startsWith('is_') ||
        key.startsWith('has_') ||
        ReCase(key).camelCase.startsWith('is')) {
      return 'bool';
    }
    return 'dynamic';
  }

  /// Parses variables bound to `<client>.from("table").select("cols")` chains.
  ///
  /// Handles `const { data } = await ...`, `const { data: rows } = await ...`,
  /// and `const rows = await ...` forms. `.maybeSingle()` / `.single()` marks
  /// the result as a single row; otherwise it's treated as a list.
  Map<String, _SelectInfo> _parseSelectVars(String source) {
    final result = <String, _SelectInfo>{};
    final assignment = RegExp(
      r'(?:const|let|var)\s+(\{[^=]*?\}|\w+)\s*=\s*await\s+([\s\S]*?);',
    );

    for (final m in assignment.allMatches(source)) {
      final target = m.group(1)!.trim();
      final rhs = m.group(2)!;

      final fromMatch =
          RegExp('''\\.from\\(\\s*['"`]([^'"`]+)['"`]''').firstMatch(rhs);
      final selectMatch = RegExp(
        '''\\.select\\(\\s*['"`]([\\s\\S]*?)['"`]\\s*,?\\s*\\)''',
      ).firstMatch(rhs);
      // `.select()` with no arguments selects all columns (PostgREST default),
      // e.g. `.insert({...}).select().single()`.
      final emptySelect = RegExp(r'\.select\(\s*\)').hasMatch(rhs);
      if (fromMatch == null || (selectMatch == null && !emptySelect)) continue;

      final table = fromMatch.group(1)!;
      final select = selectMatch?.group(1) ?? '*';
      final isSingle =
          rhs.contains('.maybeSingle(') || rhs.contains('.single(');

      final varName = _selectTargetVar(target);
      if (varName == null) continue;

      result[varName] = _SelectInfo(
        table: table,
        select: select,
        isSingle: isSingle,
      );
    }
    return result;
  }

  /// Extracts the variable that holds the row data from a destructuring (or
  /// plain) assignment target. `{ data }` → `data`, `{ data: rows }` → `rows`,
  /// `rows` → `rows`. Returns null for unsupported targets (array patterns).
  String? _selectTargetVar(String target) {
    if (target.startsWith('{')) {
      final alias = RegExp(r'\bdata\s*:\s*(\w+)').firstMatch(target);
      if (alias != null) return alias.group(1);
      if (RegExp(r'(^|[{,\s])data([},\s]|$)').hasMatch(target)) return 'data';
      return null;
    }
    if (_identifier.hasMatch(target)) return target;
    return null;
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

/// Internal: a variable bound to a `.from(table).select(cols)` chain.
class _SelectInfo {
  final String table;
  final String select;
  final bool isSingle;

  const _SelectInfo({
    required this.table,
    required this.select,
    required this.isSingle,
  });
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
