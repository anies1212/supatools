import 'dart:convert';
import 'package:http/http.dart' as http;
import 'type_mapper.dart';

/// Represents a foreign key relationship
class ForeignKeyInfo {
  /// The column in this table that holds the foreign key
  final String column;

  /// The referenced table name
  final String referencedTable;

  /// The referenced column (usually 'id')
  final String referencedColumn;

  /// Whether this is a one-to-one or many-to-one relationship
  final bool isOneToOne;

  const ForeignKeyInfo({
    required this.column,
    required this.referencedTable,
    required this.referencedColumn,
    this.isOneToOne = false,
  });

  @override
  String toString() =>
      'ForeignKeyInfo($column -> $referencedTable.$referencedColumn)';
}

/// Represents a column in a database table
class ColumnInfo {
  final String name;
  final String dataType;
  final bool isNullable;
  final String? defaultValue;
  final bool isPrimaryKey;

  /// Foreign key reference if this column is a foreign key
  final ForeignKeyInfo? foreignKey;

  const ColumnInfo({
    required this.name,
    required this.dataType,
    required this.isNullable,
    this.defaultValue,
    this.isPrimaryKey = false,
    this.foreignKey,
  });

  /// Creates a copy with updated foreign key info
  ColumnInfo copyWith({ForeignKeyInfo? foreignKey}) => ColumnInfo(
        name: name,
        dataType: dataType,
        isNullable: isNullable,
        defaultValue: defaultValue,
        isPrimaryKey: isPrimaryKey,
        foreignKey: foreignKey ?? this.foreignKey,
      );

  @override
  String toString() =>
      'ColumnInfo(name: $name, dataType: $dataType, isNullable: $isNullable, isPrimaryKey: $isPrimaryKey, fk: $foreignKey)';
}

/// Represents a database table
class TableInfo {
  final String name;
  final List<ColumnInfo> columns;

  const TableInfo({
    required this.name,
    required this.columns,
  });

  /// Gets all foreign key relationships in this table
  List<ForeignKeyInfo> get foreignKeys => columns
      .where((c) => c.foreignKey != null)
      .map((c) => c.foreignKey!)
      .toList();

  /// Creates a copy with updated columns
  TableInfo copyWith({List<ColumnInfo>? columns}) => TableInfo(
        name: name,
        columns: columns ?? this.columns,
      );

  @override
  String toString() => 'TableInfo(name: $name, columns: $columns)';
}

/// Represents a column in a RETURNS TABLE definition
class RpcTableColumn {
  final String name;
  final String dataType;

  /// For json/jsonb columns: nested column structure detected
  /// from `json_build_object(...)` in the function body.
  final List<RpcTableColumn>? nestedColumns;

  /// True when wrapped in `json_agg(...)`, meaning the value
  /// is a JSON array of objects rather than a single object.
  final bool isArray;

  const RpcTableColumn({
    required this.name,
    required this.dataType,
    this.nestedColumns,
    this.isArray = false,
  });

  @override
  String toString() => 'RpcTableColumn($name: $dataType)';
}

/// Represents a parameter for an RPC function
class RpcParamInfo {
  final String name;
  final String dataType;
  final bool isRequired;

  const RpcParamInfo({
    required this.name,
    required this.dataType,
    this.isRequired = true,
  });

  @override
  String toString() => 'RpcParamInfo($name: $dataType, required: $isRequired)';
}

/// Represents a Supabase RPC (SQL) function
class RpcFunctionInfo {
  final String name;
  final List<RpcParamInfo> params;
  final String returnType;
  final bool returnsSetOf;
  final String? description;

  /// Column definitions for RETURNS TABLE functions.
  /// Non-null when the function uses `RETURNS TABLE(col1 type1, ...)`.
  final List<RpcTableColumn>? tableColumns;

  /// Error codes detected from PL/pgSQL source.
  /// Non-null when the function has an `error text` column and
  /// error code string literals are found in the function body.
  final List<String>? errorCodes;

  const RpcFunctionInfo({
    required this.name,
    required this.params,
    required this.returnType,
    this.returnsSetOf = false,
    this.description,
    this.tableColumns,
    this.errorCodes,
  });

  RpcFunctionInfo copyWith({
    String? returnType,
    bool? returnsSetOf,
    List<RpcTableColumn>? tableColumns,
    List<String>? errorCodes,
  }) =>
      RpcFunctionInfo(
        name: name,
        params: params,
        returnType: returnType ?? this.returnType,
        returnsSetOf: returnsSetOf ?? this.returnsSetOf,
        description: description,
        tableColumns: tableColumns ?? this.tableColumns,
        errorCodes: errorCodes ?? this.errorCodes,
      );

  @override
  String toString() => 'RpcFunctionInfo($name, params: $params, '
      'returns: ${returnsSetOf ? 'setof ' : ''}$returnType)';
}

/// Represents a PostgreSQL enum type
class EnumInfo {
  /// The PostgreSQL type name (e.g. 'campaign_type')
  final String name;

  /// The enum values in sort order
  final List<String> values;

  const EnumInfo({required this.name, required this.values});

  @override
  String toString() => 'EnumInfo($name: $values)';
}

/// Fetches schema information from Supabase
class SchemaFetcher {
  final String supabaseUrl;
  final String supabaseKey;
  final String schema;

  SchemaFetcher({
    required this.supabaseUrl,
    required this.supabaseKey,
    this.schema = 'public',
  });

  /// Fetches all tables and their columns from the database
  Future<List<TableInfo>> fetchTables() async {
    // Try OpenAPI spec first (more reliable for Supabase)
    try {
      return await _fetchViaOpenApi();
    } catch (e) {
      // Fallback to information_schema if OpenAPI fails
      final tables = await _fetchTableNames();
      final result = <TableInfo>[];

      for (final tableName in tables) {
        final columns = await _fetchColumns(tableName);
        result.add(TableInfo(name: tableName, columns: columns));
      }

      return result;
    }
  }

  /// Fetches table names from the database
  Future<List<String>> _fetchTableNames() async {
    final query = '''
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = '$schema'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name
    ''';

    final response = await _executeRawQuery(query);
    return (response as List)
        .map((row) => row['table_name'] as String)
        .toList();
  }

  /// Fetches column information for a specific table
  Future<List<ColumnInfo>> _fetchColumns(String tableName) async {
    final query = '''
      SELECT
        c.column_name,
        c.data_type,
        c.udt_name,
        c.is_nullable,
        c.column_default,
        CASE
          WHEN pk.column_name IS NOT NULL THEN true
          ELSE false
        END as is_primary_key
      FROM information_schema.columns c
      LEFT JOIN (
        SELECT ku.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage ku
          ON tc.constraint_name = ku.constraint_name
          AND tc.table_schema = ku.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_name = '$tableName'
          AND tc.table_schema = '$schema'
      ) pk ON c.column_name = pk.column_name
      WHERE c.table_name = '$tableName'
        AND c.table_schema = '$schema'
      ORDER BY c.ordinal_position
    ''';

    final response = await _executeRawQuery(query);
    return (response as List).map((row) {
      // Use udt_name for more specific type info (e.g., 'int4' instead of 'integer')
      final dataType = row['udt_name'] as String? ?? row['data_type'] as String;

      return ColumnInfo(
        name: row['column_name'] as String,
        dataType: dataType,
        isNullable: (row['is_nullable'] as String) == 'YES',
        defaultValue: row['column_default'] as String?,
        isPrimaryKey: row['is_primary_key'] as bool? ?? false,
      );
    }).toList();
  }

  /// Executes a raw SQL query via Supabase REST API (fallback, may not work on all setups)
  Future<dynamic> _executeRawQuery(String query) async {
    final url = Uri.parse('$supabaseUrl/rest/v1/rpc/execute_sql');

    var response = await http.post(
      url,
      headers: {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'query': query}),
    );

    if (response.statusCode != 200) {
      throw SchemaFetchException(
        'Failed to execute query',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    return jsonDecode(response.body);
  }

  /// Fetches the raw OpenAPI spec JSON from Supabase
  Future<Map<String, dynamic>> _fetchOpenApiSpec() async {
    final url = Uri.parse('$supabaseUrl/rest/v1/');

    final response = await http.get(
      url,
      headers: {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
      },
    );

    if (response.statusCode != 200) {
      throw SchemaFetchException(
        'Failed to fetch schema',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final openApiUrl = Uri.parse('$supabaseUrl/rest/v1/?apikey=$supabaseKey');
    final openApiResponse = await http.get(
      openApiUrl,
      headers: {
        'apikey': supabaseKey,
        'Authorization': 'Bearer $supabaseKey',
        'Accept': 'application/openapi+json',
      },
    );

    if (openApiResponse.statusCode == 200) {
      return jsonDecode(openApiResponse.body) as Map<String, dynamic>;
    }

    throw SchemaFetchException(
      'Failed to fetch OpenAPI spec',
      statusCode: openApiResponse.statusCode,
      responseBody: openApiResponse.body,
    );
  }

  /// Fetches schema via OpenAPI spec (fallback method)
  Future<List<TableInfo>> _fetchViaOpenApi() async {
    final spec = await _fetchOpenApiSpec();
    return _parseOpenApiSpec(spec);
  }

  /// Fetches RPC function definitions from the OpenAPI spec.
  ///
  /// When `execute_sql` RPC is available, corrects return types
  /// by querying `pg_proc` catalog directly.
  Future<List<RpcFunctionInfo>> fetchRpcFunctions() async {
    final spec = await _fetchOpenApiSpec();
    final functions = parseRpcFunctions(spec);

    try {
      final pgReturnTypes = await _fetchRpcReturnTypes();
      var merged = mergeReturnTypes(functions, pgReturnTypes);

      try {
        final tableColumnsMap = await _fetchRpcTableColumns();
        merged = mergeTableColumns(merged, tableColumnsMap);
      } catch (_) {
        // Continue even if TABLE column info fetch fails
      }

      // json_build_object 自動検出 (tableColumns未設定の関数のみ)
      try {
        final jsonColumnsMap = await _fetchRpcJsonColumns();
        merged = merged.map((func) {
          if (func.tableColumns != null &&
              func.tableColumns!.isNotEmpty) {
            return func;
          }
          final columns = jsonColumnsMap[func.name];
          if (columns == null) return func;
          return func.copyWith(tableColumns: columns);
        }).toList();
      } catch (_) {
        // Ignore JSON column auto-detection failure and continue
      }

      // Auto-detect error codes for functions with an error text column
      try {
        final errorCodesMap = await _fetchRpcErrorCodes();
        merged = merged.map((func) {
          final codes = errorCodesMap[func.name];
          if (codes == null) return func;
          // Check if the function has an error text column
          final hasErrorCol = func.tableColumns?.any(
            (c) =>
                (c.name == 'error' || c.name == 'error_code') &&
                c.dataType == 'text',
          );
          if (hasErrorCol != true) return func;
          return func.copyWith(errorCodes: codes);
        }).toList();
      } catch (_) {
        // Ignore error code auto-detection failure and continue
      }

      // Detect nested structure of json columns in RETURNS TABLE
      try {
        final nestedMap = await _fetchRpcNestedJsonColumns();
        merged = merged.map((func) {
          final nestedInfo = nestedMap[func.name];
          if (nestedInfo == null) return func;
          final cols = func.tableColumns;
          if (cols == null) return func;
          final updated = cols.map((col) {
            final nested = nestedInfo[col.name];
            if (nested == null) return col;
            return RpcTableColumn(
              name: col.name,
              dataType: col.dataType,
              nestedColumns: nested.columns,
              isArray: nested.isArray,
            );
          }).toList();
          return func.copyWith(tableColumns: updated);
        }).toList();
      } catch (_) {
        // Ignore nested structure detection failure and continue
      }

      return merged;
    } catch (_) {
      return functions;
    }
  }

  /// Fetches RPC return types from `pg_proc` catalog.
  ///
  /// The query is wrapped with `json_agg` so that `execute_sql`
  /// (which uses `EXECUTE ... INTO`) returns all rows as a single
  /// JSON array instead of only the first row.
  Future<Map<String, ({String typeName, bool returnsSet})>>
      _fetchRpcReturnTypes() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          p.proname AS function_name,
          t.typname AS return_type,
          p.proretset AS returns_set
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        JOIN pg_type t ON p.prorettype = t.oid
        WHERE n.nspname = '$schema'
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final result = <String, ({String typeName, bool returnsSet})>{};

    // response is the json_agg result (a List), or null if no rows
    final rows = response is List ? response : <dynamic>[];
    for (final row in rows) {
      final name = row['function_name'] as String;
      final typeName = row['return_type'] as String;
      final returnsSet = row['returns_set'] as bool;
      result[name] = (
        typeName: typeName,
        returnsSet: returnsSet,
      );
    }

    return result;
  }

  /// Corrects functions whose return type was resolved as `void` by OpenAPI
  /// using `pg_proc` results.
  ///
  /// - Non-void types from OpenAPI are kept as-is
  /// - `record` type from pg_proc is treated as void
  static List<RpcFunctionInfo> mergeReturnTypes(
    List<RpcFunctionInfo> functions,
    Map<String, ({String typeName, bool returnsSet})> pgReturnTypes,
  ) {
    return functions.map((func) {
      if (func.returnType != 'void') return func;

      final pgInfo = pgReturnTypes[func.name];
      if (pgInfo == null) return func;

      // record + returnsSet means RETURNS TABLE(...) → setof jsonb
      if (pgInfo.typeName == 'record' && pgInfo.returnsSet) {
        return func.copyWith(returnType: 'jsonb', returnsSetOf: true);
      }
      // record without setof is equivalent to void; skip correction
      if (pgInfo.typeName == 'record') return func;

      return func.copyWith(
        returnType: pgInfo.typeName,
        returnsSetOf: pgInfo.returnsSet,
      );
    }).toList();
  }

  /// Fetches TABLE column info from `pg_proc` catalog for
  /// functions that use `RETURNS TABLE(...)`.
  Future<Map<String, List<RpcTableColumn>>> _fetchRpcTableColumns() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          p.proname AS function_name,
          p.proargmodes::text[] AS arg_modes,
          p.proargnames::text[] AS arg_names,
          (SELECT json_agg(t2.typname ORDER BY ordinality)
           FROM unnest(p.proallargtypes)
             WITH ORDINALITY AS u(type_oid, ordinality)
           JOIN pg_type t2 ON t2.oid = u.type_oid
          ) AS arg_type_names
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = '$schema'
          AND p.proargmodes IS NOT NULL
          AND 't' = ANY(p.proargmodes)
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final result = <String, List<RpcTableColumn>>{};

    final rows = response is List ? response : <dynamic>[];
    for (final row in rows) {
      final funcName = row['function_name'] as String;
      final argModes = (row['arg_modes'] as List).cast<String>();
      final argNames = (row['arg_names'] as List).cast<String>();
      final argTypeNames = (row['arg_type_names'] as List).cast<String>();

      final columns = <RpcTableColumn>[];
      for (var i = 0; i < argModes.length; i++) {
        if (argModes[i] == 't') {
          columns.add(RpcTableColumn(
            name: argNames[i],
            dataType: argTypeNames[i],
          ));
        }
      }

      if (columns.isNotEmpty) {
        result[funcName] = columns;
      }
    }

    return result;
  }

  /// Fetches column info for `RETURNS json/jsonb` functions by
  /// parsing `json_build_object` / `jsonb_build_object` calls
  /// in the function body (`pg_proc.prosrc`).
  Future<Map<String, List<RpcTableColumn>>>
      _fetchRpcJsonColumns() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          p.proname AS function_name,
          p.prosrc AS source
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        JOIN pg_type t ON p.prorettype = t.oid
        WHERE n.nspname = '$schema'
          AND t.typname IN ('json', 'jsonb')
          AND p.prosrc IS NOT NULL
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final result = <String, List<RpcTableColumn>>{};

    final rows = response is List ? response : <dynamic>[];
    for (final row in rows) {
      final funcName = row['function_name'] as String;
      final source = row['source'] as String;
      final columns = parseJsonBuildObject(source);
      if (columns.isNotEmpty) {
        result[funcName] = columns;
      }
    }

    return result;
  }

  /// Parses `json_build_object` / `jsonb_build_object` calls from
  /// PL/pgSQL function source and extracts column definitions.
  ///
  /// Infers types from variable declarations (`DECLARE v_foo type;`)
  /// or parameter declarations in the function signature.
  static List<RpcTableColumn> parseJsonBuildObject(String source) {
    // Find json_build_object( or jsonb_build_object( start position
    final startPattern = RegExp(
      r'jsonb?_build_object\s*\(',
      caseSensitive: false,
    );
    final startMatch = startPattern.firstMatch(source);
    if (startMatch == null) return [];

    // Manually find matching closing paren (handles nested parens
    // and skips string literals to avoid miscounting)
    final argsStart = startMatch.end;
    var depth = 1;
    var argsEnd = argsStart;
    var inStr = false;
    for (var i = argsStart; i < source.length; i++) {
      if (source[i] == "'" && !inStr) {
        inStr = true;
        continue;
      }
      if (source[i] == "'" && inStr) {
        if (i + 1 < source.length && source[i + 1] == "'") {
          i++;
          continue;
        }
        inStr = false;
        continue;
      }
      if (inStr) continue;
      if (source[i] == '(') depth++;
      if (source[i] == ')') depth--;
      if (depth == 0) {
        argsEnd = i;
        break;
      }
    }

    final argsStr = source.substring(argsStart, argsEnd);

    // Build variable → type map from DECLARE section and params
    final varTypes = _extractVariableTypes(source);

    return _parseBuildObjectColumns(argsStr, varTypes);
  }

  /// Tokenizes the arguments of json_build_object(...) into
  /// alternating key/value strings.
  ///
  /// Handles string literals ('key'), nested function calls,
  /// and comma separation.
  static List<String> _tokenizeBuildObjectArgs(String args) {
    final tokens = <String>[];
    var current = StringBuffer();
    var depth = 0;
    var inString = false;

    for (var i = 0; i < args.length; i++) {
      final ch = args[i];

      if (ch == "'" && !inString) {
        if (depth > 0) {
          // Nested string (inside coalesce, subquery, etc.)
          // Scan to closing quote and add to value buffer.
          current.write(ch);
          i++;
          while (i < args.length) {
            current.write(args[i]);
            if (args[i] == "'") {
              if (i + 1 < args.length && args[i + 1] == "'") {
                i++;
                current.write(args[i]);
                i++;
                continue;
              }
              break; // closing quote found
            }
            i++;
          }
          // i is at closing quote; outer for-loop i++ will
          // advance past it. No further action needed.
          // Fall through to next iteration via outer for-loop.
          continue;
        }
        // Top-level string literal = json_build_object key
        inString = true;
        current = StringBuffer();
        continue;
      }
      if (ch == "'" && inString) {
        // Check for escaped quote ''
        if (i + 1 < args.length && args[i + 1] == "'") {
          current.write("'");
          i++;
          continue;
        }
        inString = false;
        tokens.add(current.toString());
        current = StringBuffer();
        continue;
      }
      if (inString) {
        current.write(ch);
        continue;
      }

      if (ch == '(') depth++;
      if (ch == ')') depth--;

      if (ch == ',' && depth == 0) {
        final value = current.toString().trim();
        if (value.isNotEmpty) {
          tokens.add(value);
        }
        current = StringBuffer();
        continue;
      }

      current.write(ch);
    }

    final remaining = current.toString().trim();
    if (remaining.isNotEmpty) {
      tokens.add(remaining);
    }

    return tokens;
  }

  /// Extracts variable name → type mappings from PL/pgSQL source.
  ///
  /// Parses both DECLARE blocks and function parameter declarations.
  static Map<String, String> _extractVariableTypes(String source) {
    final types = <String, String>{};

    // DECLARE section: v_name type; or v_name type := ...;
    final declarePattern = RegExp(
      r'(\w+)\s+([\w\[\]]+)(?:\s*(?::=|;|DEFAULT))',
      caseSensitive: false,
    );
    for (final m in declarePattern.allMatches(source)) {
      final varName = m.group(1)!.toLowerCase();
      final typeName = m.group(2)!.toLowerCase();
      // Skip PL/pgSQL keywords that look like declarations
      if (_plpgsqlKeywords.contains(varName)) continue;
      types[varName] = typeName;
    }

    return types;
  }

  /// Resolves a value expression to a PostgreSQL type name.
  ///
  /// First tries direct variable lookup, then falls back to
  /// common expression patterns.
  static String _resolveType(
    String expr,
    Map<String, String> varTypes,
  ) {
    final normalized = expr.trim().toLowerCase();

    // Direct variable reference
    final varType = varTypes[normalized];
    if (varType != null) return varType;

    // Boolean literals
    if (normalized == 'true' || normalized == 'false') {
      return 'bool';
    }
    // Numeric literals
    if (RegExp(r'^\d+$').hasMatch(normalized)) return 'int4';
    if (RegExp(r'^\d+\.\d+$').hasMatch(normalized)) {
      return 'float8';
    }
    // String literals
    if (normalized.startsWith("'")) return 'text';

    // coalesce(..., literal) — infer from last argument
    // Must be checked BEFORE :: cast to avoid matching
    // :: inside nested subqueries
    final coalesceMatch = RegExp(
      r'^coalesce\s*\(([\s\S]+)\)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (coalesceMatch != null) {
      final inner = coalesceMatch.group(1)!;
      // Extract the last argument (the fallback value)
      final lastArg = _extractLastArg(inner);
      if (lastArg != null) {
        final inferred = _resolveType(lastArg, varTypes);
        if (inferred != 'text') return inferred;
      }
    }

    // NOT expr → bool
    if (normalized.startsWith('not ') ||
        normalized.startsWith('not(')) {
      return 'bool';
    }
    // EXISTS(...) → bool
    if (normalized.startsWith('exists(') ||
        normalized.startsWith('exists (')) {
      return 'bool';
    }
    // Boolean operators: expr AND/OR expr, expr IS NULL, etc.
    if (RegExp(r'\b(and|or|is\s+null|is\s+not\s+null)\b')
        .hasMatch(normalized)) {
      return 'bool';
    }

    // Type cast: expr::type (checked after coalesce/NOT/EXISTS
    // to avoid matching :: inside nested subqueries)
    if (normalized.contains('::')) {
      final castType = normalized.split('::').last.trim();
      return castType;
    }

    // Fallback
    return 'text';
  }

  /// Extracts the last argument from a comma-separated list,
  /// respecting parenthesis nesting.
  static String? _extractLastArg(String args) {
    var depth = 0;
    var lastComma = -1;
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '(') depth++;
      if (args[i] == ')') depth--;
      if (args[i] == ',' && depth == 0) lastComma = i;
    }
    if (lastComma == -1) return null;
    final last = args.substring(lastComma + 1).trim();
    return last.isEmpty ? null : last;
  }

  /// Fetches nested JSON column structures from function bodies
  /// for RETURNS TABLE functions with json/jsonb columns.
  Future<
          Map<String, Map<String, ({List<RpcTableColumn> columns, bool isArray})>>>
      _fetchRpcNestedJsonColumns() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          p.proname AS function_name,
          p.prosrc AS source
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = '$schema'
          AND p.proargmodes IS NOT NULL
          AND 't' = ANY(p.proargmodes)
          AND p.prosrc IS NOT NULL
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final result =
        <String, Map<String, ({List<RpcTableColumn> columns, bool isArray})>>{};

    final rows = response is List ? response : <dynamic>[];
    for (final row in rows) {
      final funcName = row['function_name'] as String;
      final source = row['source'] as String;
      final nested = parseNestedJsonColumns(source);
      if (nested.isNotEmpty) {
        result[funcName] = nested;
      }
    }

    return result;
  }

  /// Parses PL/pgSQL source to find `json_agg(json_build_object(...))`
  /// patterns and extract nested column structures.
  ///
  /// Returns a map of column alias → nested column info.
  /// The alias is matched against RETURNS TABLE column names.
  static Map<String, ({List<RpcTableColumn> columns, bool isArray})>
      parseNestedJsonColumns(String source) {
    final result =
        <String, ({List<RpcTableColumn> columns, bool isArray})>{};

    // Build variable types map for type resolution
    final varTypes = _extractVariableTypes(source);

    // Find json_agg(json_build_object(...)) patterns.
    // We use a manual scan to handle nested parentheses correctly.
    final aggStartPattern = RegExp(
      r'jsonb?_agg\s*\(\s*jsonb?_build_object\s*\(',
      caseSensitive: false,
    );

    for (final startMatch in aggStartPattern.allMatches(source)) {
      // Find the matching closing paren for json_build_object(
      final argsStart = startMatch.end;
      var depth = 1;
      var argsEnd = argsStart;
      for (var i = argsStart; i < source.length; i++) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') depth--;
        if (depth == 0) {
          argsEnd = i;
          break;
        }
      }

      final argsStr = source.substring(argsStart, argsEnd);
      final columns = _parseBuildObjectColumns(argsStr, varTypes);
      if (columns.isEmpty) continue;

      // Look for "as alias" after the json_agg call
      // (within 300 chars after the outer closing paren)
      // Skip one more ')' for the json_agg closing paren
      var scanPos = argsEnd + 1;
      // Skip whitespace, ORDER BY, and the json_agg closing paren
      while (scanPos < source.length &&
          source[scanPos] != ')') {
        scanPos++;
      }
      scanPos++; // skip json_agg ')'

      final afterEnd = (scanPos + 300).clamp(0, source.length);
      final afterMatch = source.substring(scanPos, afterEnd);
      // Match "as alias" but NOT "as alias(" (which is a
      // table alias like "as g(d)")
      final aliasPattern = RegExp(
        r'\bas\s+(\w+)(?!\s*\()',
        caseSensitive: false,
      );
      final aliasMatch = aliasPattern.firstMatch(afterMatch);
      final rawAlias = aliasMatch?.group(1);

      // Use alias (stripped of v_ prefix) as key
      final key = rawAlias != null
          ? rawAlias.replaceFirst(RegExp(r'^v_'), '')
          : columns.first.name;
      result[key] = (columns: columns, isArray: true);
    }

    return result;
  }

  /// Parses json_build_object arguments into RpcTableColumn list.
  static List<RpcTableColumn> _parseBuildObjectColumns(
    String argsStr,
    Map<String, String> varTypes,
  ) {
    final tokens = _tokenizeBuildObjectArgs(argsStr);
    if (tokens.length < 2) return [];

    final columns = <RpcTableColumn>[];
    for (var i = 0; i + 1 < tokens.length; i += 2) {
      final key = tokens[i];
      final valueExpr = tokens[i + 1].trim();
      final dataType = _resolveType(valueExpr, varTypes);
      columns.add(RpcTableColumn(
        name: key,
        dataType: dataType,
      ));
    }

    return columns;
  }

  /// Fetches error codes from PL/pgSQL function bodies for functions
  /// that have an `error text` column in `RETURNS TABLE`.
  Future<Map<String, List<String>>> _fetchRpcErrorCodes() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          p.proname AS function_name,
          p.prosrc AS source
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = '$schema'
          AND p.proargmodes IS NOT NULL
          AND 't' = ANY(p.proargmodes)
          AND p.prosrc IS NOT NULL
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final result = <String, List<String>>{};

    final rows = response is List ? response : <dynamic>[];
    for (final row in rows) {
      final funcName = row['function_name'] as String;
      final source = row['source'] as String;
      final codes = parseRpcErrorCodes(source);
      if (codes.isNotEmpty) {
        result[funcName] = codes;
      }
    }

    return result;
  }

  /// Parses PL/pgSQL source to extract error code string literals.
  ///
  /// Detects patterns like:
  /// - `return query select false, 'error_code'::text;`
  /// - `return query select false::bool, 'error_code'::text;`
  /// - `error := 'error_code';`
  ///
  /// Only returns snake_case codes (ignores empty strings and
  /// non-code values).
  static List<String> parseRpcErrorCodes(String source) {
    final codes = <String>{};

    // Pattern 1: return query select false, 'code'::text
    final returnQueryPattern = RegExp(
      r"return\s+query\s+select\s+false(?:::bool)?\s*,\s*'([^']+)'",
      caseSensitive: false,
    );
    for (final m in returnQueryPattern.allMatches(source)) {
      final code = m.group(1)!.trim();
      if (_isSnakeCaseCode(code)) codes.add(code);
    }

    // Pattern 2: error := 'code'
    final assignPattern = RegExp(
      r"(?:error|error_code)\s*:=\s*'([^']+)'",
      caseSensitive: false,
    );
    for (final m in assignPattern.allMatches(source)) {
      final code = m.group(1)!.trim();
      if (_isSnakeCaseCode(code)) codes.add(code);
    }

    return codes.toList()..sort();
  }

  /// Returns true if the string looks like a snake_case error code.
  static bool _isSnakeCaseCode(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$').hasMatch(s);
  }

  static const _plpgsqlKeywords = {
    'declare',
    'begin',
    'end',
    'if',
    'then',
    'else',
    'elsif',
    'loop',
    'while',
    'for',
    'return',
    'raise',
    'perform',
    'execute',
    'into',
    'select',
    'insert',
    'update',
    'delete',
    'from',
    'where',
    'and',
    'or',
    'not',
    'in',
    'is',
    'null',
    'exception',
    'when',
    'others',
    'found',
    'strict',
    'query',
    'notice',
    'warning',
    'exit',
    'continue',
    'case',
    'using',
  };

  /// Merges TABLE column info into [RpcFunctionInfo] list.
  ///
  /// For functions whose name appears in [tableColumnsMap],
  /// sets `tableColumns` on the matching [RpcFunctionInfo].
  static List<RpcFunctionInfo> mergeTableColumns(
    List<RpcFunctionInfo> functions,
    Map<String, List<RpcTableColumn>> tableColumnsMap,
  ) {
    return functions.map((func) {
      final columns = tableColumnsMap[func.name];
      if (columns == null) return func;
      return func.copyWith(tableColumns: columns);
    }).toList();
  }

  /// Parses RPC functions from OpenAPI spec paths
  List<RpcFunctionInfo> parseRpcFunctions(
    Map<String, dynamic> spec,
  ) {
    final paths = spec['paths'] as Map<String, dynamic>? ?? {};
    final functions = <RpcFunctionInfo>[];

    for (final entry in paths.entries) {
      final path = entry.key;
      if (!path.startsWith('/rpc/')) continue;

      final funcName = path.substring('/rpc/'.length);
      if (funcName.isEmpty) continue;

      final pathSpec = entry.value as Map<String, dynamic>;
      final postSpec = pathSpec['post'] as Map<String, dynamic>? ?? {};

      final description = postSpec['description'] as String?;

      // Parse parameters
      final params = _parseRpcParams(postSpec);

      // Parse return type
      final (returnType, returnsSetOf) = _parseRpcReturnType(postSpec);

      functions.add(RpcFunctionInfo(
        name: funcName,
        params: params,
        returnType: returnType,
        returnsSetOf: returnsSetOf,
        description: description,
      ));
    }

    return functions;
  }

  /// Parses RPC function parameters from the post spec
  List<RpcParamInfo> _parseRpcParams(
    Map<String, dynamic> postSpec,
  ) {
    final params = <RpcParamInfo>[];
    final parameters = postSpec['parameters'] as List<dynamic>? ?? [];

    for (final param in parameters) {
      final paramMap = param as Map<String, dynamic>;
      final inLocation = paramMap['in'] as String?;

      if (inLocation == 'body') {
        final schema = paramMap['schema'] as Map<String, dynamic>? ?? {};
        final properties = schema['properties'] as Map<String, dynamic>? ?? {};
        final required = (schema['required'] as List?)?.cast<String>() ?? [];

        for (final propEntry in properties.entries) {
          final propSchema = propEntry.value as Map<String, dynamic>;
          final pgType = _openApiTypeToPgType(propSchema);

          params.add(RpcParamInfo(
            name: propEntry.key,
            dataType: pgType,
            isRequired: required.contains(propEntry.key),
          ));
        }
      }
    }

    return params;
  }

  /// Parses RPC function return type from the post spec
  (String, bool) _parseRpcReturnType(
    Map<String, dynamic> postSpec,
  ) {
    final responses = postSpec['responses'] as Map<String, dynamic>? ?? {};
    final okResponse = responses['200'] as Map<String, dynamic>? ?? {};
    final schema = okResponse['schema'] as Map<String, dynamic>? ?? {};

    if (schema.isEmpty) return ('void', false);

    final type = schema['type'] as String?;

    if (type == 'array') {
      final items = schema['items'] as Map<String, dynamic>? ?? {};
      final itemType = _openApiTypeToPgType(items);
      return (itemType, true);
    }

    return (_openApiTypeToPgType(schema), false);
  }

  /// Parses OpenAPI specification to extract table information
  List<TableInfo> _parseOpenApiSpec(Map<String, dynamic> spec) {
    final tables = <TableInfo>[];
    final definitions = spec['definitions'] as Map<String, dynamic>? ??
        spec['components']?['schemas'] as Map<String, dynamic>? ??
        {};

    // Track detected enums for reference
    final detectedEnums = <String, List<String>>{};

    // Extract foreign key relationships from OpenAPI spec
    final foreignKeys = _extractForeignKeys(spec);

    for (final entry in definitions.entries) {
      final tableName = entry.key;
      final tableSchema = entry.value as Map<String, dynamic>;
      final properties =
          tableSchema['properties'] as Map<String, dynamic>? ?? {};
      final required = (tableSchema['required'] as List?)?.cast<String>() ?? [];

      final columns = <ColumnInfo>[];
      for (final propEntry in properties.entries) {
        final columnName = propEntry.key;
        final columnSchema = propEntry.value as Map<String, dynamic>;

        // Detect enum types
        final enumValues = columnSchema['enum'] as List?;
        String dataType;
        if (enumValues != null && enumValues.isNotEmpty) {
          // Store enum info and mark the type
          final enumTypeName = '${tableName}_$columnName';
          detectedEnums[enumTypeName] = enumValues.cast<String>();
          dataType = enumTypeName; // Custom enum type
        } else {
          dataType = _openApiTypeToPgType(columnSchema);
        }

        // Check if this column has a foreign key relationship
        final fkKey = '$tableName.$columnName';
        final foreignKey = foreignKeys[fkKey];

        columns.add(
          ColumnInfo(
            name: columnName,
            dataType: dataType,
            isNullable: !required.contains(columnName),
            defaultValue: columnSchema['default']?.toString(),
            foreignKey: foreignKey,
          ),
        );
      }

      if (columns.isNotEmpty) {
        tables.add(TableInfo(name: tableName, columns: columns));
      }
    }

    // Store detected enums for logging/debugging
    _lastDetectedEnums = detectedEnums;
    _lastDetectedForeignKeys = foreignKeys;

    return tables;
  }

  /// Extracts foreign key relationships from OpenAPI spec
  ///
  /// PostgREST OpenAPI spec includes relationship info in the paths
  /// under the "parameters" section with "in: query" and names like "select"
  /// that reference embedded resources.
  Map<String, ForeignKeyInfo> _extractForeignKeys(Map<String, dynamic> spec) {
    final foreignKeys = <String, ForeignKeyInfo>{};

    // Method 1: Parse from definitions - look for column naming patterns
    final definitions = spec['definitions'] as Map<String, dynamic>? ??
        spec['components']?['schemas'] as Map<String, dynamic>? ??
        {};

    // Build a set of all table names for reference detection
    final tableNames = definitions.keys.toSet();

    for (final entry in definitions.entries) {
      final tableName = entry.key;
      final tableSchema = entry.value as Map<String, dynamic>;
      final properties =
          tableSchema['properties'] as Map<String, dynamic>? ?? {};

      for (final propEntry in properties.entries) {
        final columnName = propEntry.key;
        final columnSchema = propEntry.value as Map<String, dynamic>;

        // Detect FK by column naming convention: xxx_id -> xxx table
        if (columnName.endsWith('_id') && columnName != 'id') {
          final potentialTable = columnName.substring(0, columnName.length - 3);

          // Check if a table with this name exists (singular or plural forms)
          final referencedTable =
              _findReferencedTable(potentialTable, tableNames);

          if (referencedTable != null) {
            final format = columnSchema['format'] as String?;
            final type = columnSchema['type'] as String?;

            // Verify it's likely a foreign key type (uuid, int, bigint)
            if (_isForeignKeyType(type, format)) {
              foreignKeys['$tableName.$columnName'] = ForeignKeyInfo(
                column: columnName,
                referencedTable: referencedTable,
                referencedColumn: 'id',
              );
            }
          }
        }
      }
    }

    return foreignKeys;
  }

  /// Finds a referenced table by name, checking singular/plural forms
  String? _findReferencedTable(String baseName, Set<String> tableNames) {
    // Direct match
    if (tableNames.contains(baseName)) return baseName;

    // Plural forms
    final plurals = [
      '${baseName}s', // user -> users
      '${baseName}es', // box -> boxes
      baseName.endsWith('y')
          ? '${baseName.substring(0, baseName.length - 1)}ies' // category -> categories
          : null,
    ].whereType<String>();

    for (final plural in plurals) {
      if (tableNames.contains(plural)) return plural;
    }

    // Singular from plural (if baseName is already plural)
    if (baseName.endsWith('s')) {
      final singular = baseName.substring(0, baseName.length - 1);
      if (tableNames.contains(singular)) return singular;
    }

    return null;
  }

  /// Checks if a type is typically used for foreign keys
  bool _isForeignKeyType(String? type, String? format) {
    if (format == 'uuid') return true;
    if (format == 'int64' || format == 'bigint') return true;
    if (format == 'int32' || format == 'integer') return true;
    if (type == 'integer') return true;
    if (type == 'string' && format == 'uuid') return true;
    return false;
  }

  /// Last detected foreign keys from OpenAPI parsing
  Map<String, ForeignKeyInfo> _lastDetectedForeignKeys = {};

  /// Gets the foreign keys detected in the last schema fetch
  Map<String, ForeignKeyInfo> get detectedForeignKeys =>
      Map.unmodifiable(_lastDetectedForeignKeys);

  /// Last detected enums from OpenAPI parsing (for debugging)
  Map<String, List<String>> _lastDetectedEnums = {};

  /// Gets the enums detected in the last schema fetch
  Map<String, List<String>> get detectedEnums =>
      Map.unmodifiable(_lastDetectedEnums);

  /// Fetches PostgreSQL enum types from the `pg_enum` catalog.
  ///
  /// Requires `execute_sql` RPC function. Falls back to [detectedEnums]
  /// (OpenAPI-based detection) when `execute_sql` is not available.
  Future<List<EnumInfo>> fetchEnums() async {
    try {
      return await _fetchEnumsFromCatalog();
    } catch (_) {
      // Fallback: convert OpenAPI-detected enums
      return detectedEnums.entries
          .map((e) => EnumInfo(name: e.key, values: e.value))
          .toList();
    }
  }

  /// Queries `pg_enum` + `pg_type` + `pg_namespace` to get enum definitions.
  Future<List<EnumInfo>> _fetchEnumsFromCatalog() async {
    final query = '''
      SELECT json_agg(sub) FROM (
        SELECT
          t.typname AS enum_name,
          json_agg(e.enumlabel ORDER BY e.enumsortorder) AS enum_values
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE n.nspname = '$schema'
        GROUP BY t.typname
        ORDER BY t.typname
      ) sub
    ''';

    final response = await _executeRawQuery(query);
    final rows = response is List ? response : <dynamic>[];
    return rows.map((row) {
      final name = row['enum_name'] as String;
      final values = (row['enum_values'] as List).cast<String>();
      return EnumInfo(name: name, values: values);
    }).toList();
  }

  /// Merges pg_enum type names into table column dataTypes.
  ///
  /// When OpenAPI detects enums as `tableName_columnName`, this method
  /// replaces them with the actual PostgreSQL type name from pg_enum.
  ///
  /// [openApiEnums] is the OpenAPI-detected enum map (key: tableName_columnName,
  /// value: enum values). This is needed because TypeMapper may have been
  /// cleared and re-registered with pg_enum names by the time this is called.
  static List<TableInfo> mergeEnumTypes(
    List<TableInfo> tables,
    List<EnumInfo> pgEnums, {
    Map<String, List<String>> openApiEnums = const {},
  }) {
    if (pgEnums.isEmpty) return tables;

    // Build a reverse lookup: set of enum values -> pg type name
    final enumLookup = <String, String>{};
    for (final pgEnum in pgEnums) {
      final key = pgEnum.values.join(',');
      enumLookup[key] = pgEnum.name;
    }

    return tables.map((table) {
      final newColumns = table.columns.map((col) {
        // Try OpenAPI enums first (key is tableName_columnName),
        // then fall back to TypeMapper (may have been re-registered)
        final enumValues = openApiEnums[col.dataType] ??
            TypeMapper.getEnumValues(col.dataType);
        if (enumValues == null) return col;

        final key = enumValues.join(',');
        final pgName = enumLookup[key];
        if (pgName == null) return col;

        return ColumnInfo(
          name: col.name,
          dataType: pgName,
          isNullable: col.isNullable,
          defaultValue: col.defaultValue,
          isPrimaryKey: col.isPrimaryKey,
          foreignKey: col.foreignKey,
        );
      }).toList();

      return table.copyWith(columns: newColumns);
    }).toList();
  }

  /// Converts OpenAPI type to PostgreSQL type
  String _openApiTypeToPgType(Map<String, dynamic> schema) {
    final type = schema['type'] as String?;
    final format = schema['format'] as String?;

    if (format != null) {
      final pgType = switch (format) {
        // UUID
        'uuid' => 'uuid',
        // Date/Time types
        'date-time' ||
        'timestamp with time zone' ||
        'timestamptz' =>
          'timestamptz',
        'timestamp without time zone' || 'timestamp' => 'timestamp',
        'date' => 'date',
        'time' || 'time with time zone' || 'time without time zone' => 'time',
        // Integer types
        'int64' || 'bigint' => 'int8',
        'int32' || 'integer' => 'int4',
        'int16' || 'smallint' => 'int2',
        // Floating-point types
        'double' || 'float' || 'double precision' => 'float8',
        'real' || 'float4' => 'float4',
        'numeric' || 'decimal' => 'numeric',
        // String types
        'text' ||
        'character varying' ||
        'varchar' ||
        'char' ||
        'character' =>
          'text',
        // Boolean
        'boolean' => 'bool',
        // JSON types
        'json' => 'json',
        'jsonb' => 'jsonb',
        // Binary
        'bytea' => 'bytea',
        _ => null,
      };
      if (pgType != null) return pgType;
    }

    return switch (type) {
      'integer' => 'int4',
      'number' => 'float8',
      'boolean' => 'bool',
      'array' => switch (schema['items']) {
          final Map<String, dynamic> items =>
            '${_openApiTypeToPgType(items)}[]',
          _ => 'jsonb',
        },
      'object' => 'jsonb',
      _ => 'text',
    };
  }
}

/// Exception thrown when schema fetching fails
class SchemaFetchException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  SchemaFetchException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() {
    final buffer = StringBuffer('SchemaFetchException: $message');
    if (statusCode != null) {
      buffer.write(' (HTTP $statusCode)');
    }
    return buffer.toString();
  }

  /// Returns detailed error information for debugging
  String toDetailedString() {
    final buffer = StringBuffer('SchemaFetchException: $message');
    if (statusCode != null) {
      buffer.write('\nHTTP Status: $statusCode');
    }
    if (responseBody != null && responseBody!.isNotEmpty) {
      buffer.write(
          '\nResponse: ${responseBody!.length > 500 ? '${responseBody!.substring(0, 500)}...' : responseBody}');
    }
    buffer.write('\n\nTroubleshooting:');
    buffer.write(
        '\n1. Verify SUPABASE_DATA_API_URL is correct (should be https://xxx.supabase.co)');
    buffer.write(
        '\n2. Verify SUPABASE_SECRET_KEY is the service_role key (not anon key)');
    buffer.write(
        '\n3. Check that your Supabase project is active and accessible');
    return buffer.toString();
  }
}
