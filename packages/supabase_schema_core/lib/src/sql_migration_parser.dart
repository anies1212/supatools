import 'schema_fetcher.dart';

/// Return-type metadata extracted from a `CREATE FUNCTION` statement
/// in a SQL migration file.
class SqlFunctionInfo {
  /// PG type name when the function returns a scalar (e.g. `bool`,
  /// `text`, `uuid`), or the composite/table type when applicable.
  /// `void` for functions that don't return anything useful.
  final String returnType;

  /// True when the function uses `SETOF` or `RETURNS TABLE(...)`.
  final bool returnsSetOf;

  /// Column definitions for `RETURNS TABLE(col1 t1, ...)` and for
  /// `RETURNS SETOF <composite_type>` once the composite type has
  /// been resolved.
  final List<RpcTableColumn>? tableColumns;

  const SqlFunctionInfo({
    required this.returnType,
    this.returnsSetOf = false,
    this.tableColumns,
  });

  @override
  String toString() => 'SqlFunctionInfo(returnType: $returnType, '
      'returnsSetOf: $returnsSetOf, '
      'tableColumns: $tableColumns)';
}

/// Parses PostgreSQL migration SQL files to extract RPC return-type
/// information.
///
/// Designed as a fallback for environments where the `execute_sql`
/// RPC isn't installed and PostgREST's OpenAPI doesn't expose schema
/// info for the project's RPC functions.
///
/// Supported patterns:
///   - `CREATE [OR REPLACE] FUNCTION [schema.]name(args) RETURNS <type>`
///   - `RETURNS BOOLEAN | TEXT | UUID | INTEGER | BIGINT | ...`
///   - `RETURNS SETOF <type>`
///   - `RETURNS TABLE(col1 type1, col2 type2, ...)`
///   - `RETURNS [schema.]<custom_composite_type>` (resolved if a
///     matching `CREATE TYPE name AS (...)` is present)
///   - `RETURNS SETOF [schema.]<custom_composite_type>`
///
/// Type aliases (BOOLEAN → bool, INTEGER → int4, etc.) are
/// normalized to match the PG type names used by [TypeMapper].
class SqlMigrationParser {
  /// Parses all `CREATE [OR REPLACE] FUNCTION` statements from [sql].
  ///
  /// [compositeTypes] is consulted when a function returns a
  /// composite type — the type's column list is attached as
  /// `tableColumns` so the same downstream codegen path used for
  /// `RETURNS TABLE` can produce a typed result model.
  static Map<String, SqlFunctionInfo> parseFunctions(
    String sql, {
    Map<String, List<RpcTableColumn>> compositeTypes = const {},
  }) {
    final result = <String, SqlFunctionInfo>{};
    final clean = _stripComments(sql);

    final funcStartPattern = RegExp(
      r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:(\w+)\.)?(\w+)\s*\(',
      caseSensitive: false,
    );

    for (final match in funcStartPattern.allMatches(clean)) {
      final funcName = match.group(2)!;
      final argsStart = match.end;

      // Skip past the argument list (balanced parens, respecting
      // SQL string literals and dollar-quoted strings).
      final argsEnd = _findMatchingParen(clean, argsStart);
      if (argsEnd == -1) continue;

      // Look for RETURNS clause between the args and the next AS / $$
      final afterArgs = clean.substring(argsEnd + 1);
      final returnsInfo = _parseReturnsClause(afterArgs, compositeTypes);
      if (returnsInfo == null) continue;

      // Skip trigger functions — they aren't RPCs the client calls.
      if (returnsInfo.returnType == 'trigger' ||
          returnsInfo.returnType == 'event_trigger') {
        continue;
      }

      result[funcName] = returnsInfo;
    }

    return result;
  }

  /// Parses `CREATE TYPE <name> AS (col1 type1, col2 type2, ...)`
  /// statements (composite types only — `CREATE TYPE ... AS ENUM` is
  /// ignored).
  static Map<String, List<RpcTableColumn>> parseCompositeTypes(String sql) {
    final result = <String, List<RpcTableColumn>>{};
    final clean = _stripComments(sql);

    final typePattern = RegExp(
      r'CREATE\s+TYPE\s+(?:(\w+)\.)?(\w+)\s+AS\s*\(',
      caseSensitive: false,
    );

    for (final match in typePattern.allMatches(clean)) {
      final typeName = match.group(2)!;
      final argsStart = match.end;
      final argsEnd = _findMatchingParen(clean, argsStart);
      if (argsEnd == -1) continue;

      final columnsStr = clean.substring(argsStart, argsEnd);
      final columns = _parseColumnList(columnsStr);
      if (columns.isNotEmpty) {
        result[typeName] = columns;
      }
    }

    return result;
  }

  /// Strips single-line `--` comments and `/* */` block comments
  /// from SQL while preserving string literals and dollar-quoted
  /// bodies (which may contain `--` text).
  static String _stripComments(String sql) {
    final buf = StringBuffer();
    var i = 0;
    while (i < sql.length) {
      // Dollar-quoted body: $tag$ ... $tag$
      //
      // Function bodies (and anything else dollar-quoted) can contain
      // arbitrary text that looks like CREATE FUNCTION declarations
      // (e.g. inside RAISE NOTICE 'CREATE FUNCTION ...'). We want
      // the parser to NEVER see body contents, so replace them with
      // just the two tags. This also means downstream helpers don't
      // need to handle dollar quoting themselves.
      if (sql[i] == r'$') {
        final tagMatch = RegExp(r'\$(\w*)\$').matchAsPrefix(sql, i);
        if (tagMatch != null) {
          final tag = tagMatch.group(0)!;
          final endIdx = sql.indexOf(tag, i + tag.length);
          if (endIdx != -1) {
            buf.write(tag);
            buf.write(tag);
            i = endIdx + tag.length;
            continue;
          }
        }
      }

      // Standard string literal: '...' with '' escape
      if (sql[i] == "'") {
        buf.write(sql[i]);
        i++;
        while (i < sql.length) {
          buf.write(sql[i]);
          if (sql[i] == "'") {
            if (i + 1 < sql.length && sql[i + 1] == "'") {
              i++;
              buf.write(sql[i]);
              i++;
              continue;
            }
            i++;
            break;
          }
          i++;
        }
        continue;
      }

      // Line comment: --
      if (i + 1 < sql.length && sql[i] == '-' && sql[i + 1] == '-') {
        while (i < sql.length && sql[i] != '\n') {
          i++;
        }
        continue;
      }

      // Block comment: /* */
      if (i + 1 < sql.length && sql[i] == '/' && sql[i + 1] == '*') {
        i += 2;
        while (i + 1 < sql.length &&
            !(sql[i] == '*' && sql[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }

      buf.write(sql[i]);
      i++;
    }
    return buf.toString();
  }

  /// Finds the index of the closing paren matching the `(` that
  /// immediately precedes [startIdx]. Skips over SQL string literals
  /// and dollar-quoted bodies. Returns `-1` when no match is found.
  static int _findMatchingParen(String sql, int startIdx) {
    var depth = 1;
    var i = startIdx;
    while (i < sql.length) {
      final ch = sql[i];

      if (ch == r'$') {
        final tagMatch = RegExp(r'\$(\w*)\$').matchAsPrefix(sql, i);
        if (tagMatch != null) {
          final tag = tagMatch.group(0)!;
          final endIdx = sql.indexOf(tag, i + tag.length);
          if (endIdx != -1) {
            i = endIdx + tag.length;
            continue;
          }
        }
      }

      if (ch == "'") {
        i++;
        while (i < sql.length) {
          if (sql[i] == "'") {
            if (i + 1 < sql.length && sql[i + 1] == "'") {
              i += 2;
              continue;
            }
            i++;
            break;
          }
          i++;
        }
        continue;
      }

      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  /// Parses the chunk of SQL between the argument list and the
  /// function body to extract the `RETURNS <type>` clause.
  static SqlFunctionInfo? _parseReturnsClause(
    String afterArgs,
    Map<String, List<RpcTableColumn>> compositeTypes,
  ) {
    final returnsMatch = RegExp(
      r'\bRETURNS\s+',
      caseSensitive: false,
    ).firstMatch(afterArgs);
    if (returnsMatch == null) return null;

    final tail = afterArgs.substring(returnsMatch.end);

    // RETURNS TABLE(...)
    final tableMatch = RegExp(
      r'^TABLE\s*\(',
      caseSensitive: false,
    ).firstMatch(tail);
    if (tableMatch != null) {
      final argsStart = tableMatch.end;
      final argsEnd = _findMatchingParen(tail, argsStart);
      if (argsEnd == -1) return null;
      final columnsStr = tail.substring(argsStart, argsEnd);
      final columns = _parseColumnList(columnsStr);
      return SqlFunctionInfo(
        returnType: 'record',
        returnsSetOf: true,
        tableColumns: columns,
      );
    }

    // RETURNS SETOF <type>
    final setofMatch = RegExp(
      r'^SETOF\s+(?:(\w+)\.)?(\w+)',
      caseSensitive: false,
    ).firstMatch(tail);
    if (setofMatch != null) {
      final rawType = setofMatch.group(2)!;
      final normalized = _normalizeType(rawType);
      final compositeCols = compositeTypes[rawType];
      return SqlFunctionInfo(
        returnType: compositeCols != null ? 'record' : normalized,
        returnsSetOf: true,
        tableColumns: compositeCols,
      );
    }

    // RETURNS <scalar or composite type>
    // Capture up to whitespace, semicolon, or LANGUAGE/AS keyword
    final scalarMatch = RegExp(
      r'^(?:(\w+)\.)?(\w+(?:\s*\[\s*\])?)',
      caseSensitive: false,
    ).firstMatch(tail);
    if (scalarMatch == null) return null;

    final rawType = scalarMatch.group(2)!.replaceAll(RegExp(r'\s+'), '');
    final compositeCols = compositeTypes[rawType.replaceAll('[]', '')];

    if (compositeCols != null) {
      return SqlFunctionInfo(
        returnType: 'record',
        returnsSetOf: false,
        tableColumns: compositeCols,
      );
    }

    return SqlFunctionInfo(
      returnType: _normalizeType(rawType),
      returnsSetOf: false,
    );
  }

  /// Parses a comma-separated list of `name type` pairs (used for
  /// both `RETURNS TABLE(...)` and `CREATE TYPE name AS (...)`).
  static List<RpcTableColumn> _parseColumnList(String columnsStr) {
    final columns = <RpcTableColumn>[];
    final entries = _splitTopLevelCommas(columnsStr);
    for (final entry in entries) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;

      // Strip trailing inline comments
      final clean = trimmed
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'--.*'), '')
          .trim();
      if (clean.isEmpty) continue;

      // <name> <type>  (may include parens for varchar(255), etc.)
      final m = RegExp(r'^(\w+)\s+(.+)$', dotAll: true).firstMatch(clean);
      if (m == null) continue;
      final colName = m.group(1)!;
      var typeStr = m.group(2)!.trim();

      // Drop parenthesized modifiers like (255) and any default
      // clause; keep only the leading type token + optional []
      typeStr = typeStr
          .replaceFirst(RegExp(r'\s*DEFAULT\s+.*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*NOT\s+NULL.*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*\(.*$'), '')
          .trim();

      columns.add(RpcTableColumn(
        name: colName,
        dataType: _normalizeType(typeStr),
      ));
    }
    return columns;
  }

  /// Splits a string at commas that are at depth 0 (i.e. not inside
  /// parens). Used to break up a TABLE/composite column list.
  static List<String> _splitTopLevelCommas(String src) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < src.length; i++) {
      final ch = src[i];
      if (ch == '(') depth++;
      if (ch == ')') depth--;
      if (ch == ',' && depth == 0) {
        parts.add(src.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(src.substring(start));
    return parts;
  }

  /// Normalizes common PG type aliases to the canonical names used
  /// by the rest of suparepo's type system. Unknown types are
  /// passed through lowercase.
  static String _normalizeType(String rawType) {
    final isArray = rawType.endsWith('[]');
    final base = (isArray
            ? rawType.substring(0, rawType.length - 2)
            : rawType)
        .trim()
        .toLowerCase();

    final normalized = switch (base) {
      'boolean' => 'bool',
      'integer' || 'int' => 'int4',
      'bigint' => 'int8',
      'smallint' => 'int2',
      'real' => 'float4',
      'double precision' || 'double' => 'float8',
      'character varying' || 'varchar' => 'text',
      'character' || 'char' => 'text',
      'timestamp with time zone' => 'timestamptz',
      'timestamp without time zone' => 'timestamp',
      _ => base,
    };

    return isArray ? '$normalized[]' : normalized;
  }
}
