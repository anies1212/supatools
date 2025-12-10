import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents a column in a database table
class ColumnInfo {
  final String name;
  final String dataType;
  final bool isNullable;
  final String? defaultValue;
  final bool isPrimaryKey;

  const ColumnInfo({
    required this.name,
    required this.dataType,
    required this.isNullable,
    this.defaultValue,
    this.isPrimaryKey = false,
  });

  @override
  String toString() =>
      'ColumnInfo(name: $name, dataType: $dataType, isNullable: $isNullable, isPrimaryKey: $isPrimaryKey)';
}

/// Represents a database table
class TableInfo {
  final String name;
  final List<ColumnInfo> columns;

  const TableInfo({
    required this.name,
    required this.columns,
  });

  @override
  String toString() => 'TableInfo(name: $name, columns: $columns)';
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

  /// Fetches schema via OpenAPI spec (fallback method)
  Future<List<TableInfo>> _fetchViaOpenApi() async {
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

    // Parse OpenAPI response to extract table info
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
      return _parseOpenApiSpec(jsonDecode(openApiResponse.body));
    }

    throw SchemaFetchException(
      'Failed to fetch OpenAPI spec',
      statusCode: openApiResponse.statusCode,
      responseBody: openApiResponse.body,
    );
  }

  /// Parses OpenAPI specification to extract table information
  List<TableInfo> _parseOpenApiSpec(Map<String, dynamic> spec) {
    final tables = <TableInfo>[];
    final definitions =
        spec['definitions'] as Map<String, dynamic>? ??
        spec['components']?['schemas'] as Map<String, dynamic>? ??
        {};

    // Track detected enums for reference
    final detectedEnums = <String, List<String>>{};

    for (final entry in definitions.entries) {
      final tableName = entry.key;
      final tableSchema = entry.value as Map<String, dynamic>;
      final properties =
          tableSchema['properties'] as Map<String, dynamic>? ?? {};
      final required =
          (tableSchema['required'] as List?)?.cast<String>() ?? [];

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

        columns.add(
          ColumnInfo(
            name: columnName,
            dataType: dataType,
            isNullable: !required.contains(columnName),
            defaultValue: columnSchema['default']?.toString(),
          ),
        );
      }

      if (columns.isNotEmpty) {
        tables.add(TableInfo(name: tableName, columns: columns));
      }
    }

    // Store detected enums for logging/debugging
    _lastDetectedEnums = detectedEnums;

    return tables;
  }

  /// Last detected enums from OpenAPI parsing (for debugging)
  Map<String, List<String>> _lastDetectedEnums = {};

  /// Gets the enums detected in the last schema fetch
  Map<String, List<String>> get detectedEnums => Map.unmodifiable(_lastDetectedEnums);

  /// Converts OpenAPI type to PostgreSQL type
  String _openApiTypeToPgType(Map<String, dynamic> schema) {
    final type = schema['type'] as String?;
    final format = schema['format'] as String?;

    if (format != null) {
      final pgType = switch (format) {
        // UUID
        'uuid' => 'uuid',
        // Date/Time types
        'date-time' || 'timestamp with time zone' || 'timestamptz' => 'timestamptz',
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
        'text' || 'character varying' || 'varchar' || 'char' || 'character' => 'text',
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
        final Map<String, dynamic> items => '${_openApiTypeToPgType(items)}[]',
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
      buffer.write('\nResponse: ${responseBody!.length > 500 ? '${responseBody!.substring(0, 500)}...' : responseBody}');
    }
    buffer.write('\n\nTroubleshooting:');
    buffer.write('\n1. Verify SUPABASE_URL is correct (should be https://xxx.supabase.co)');
    buffer.write('\n2. Verify SUPABASE_SECRET_KEY is the service_role key (not anon key)');
    buffer.write('\n3. Check that your Supabase project is active and accessible');
    return buffer.toString();
  }
}
