/// Maps PostgreSQL types to Dart types
/// Reference: https://www.postgresql.org/docs/current/datatype.html
class TypeMapper {
  /// Custom enum types registered from the schema
  /// Key: enum type name, Value: list of enum values
  static final Map<String, List<String>> _customEnums = {};

  /// Registers a custom PostgreSQL enum type
  static void registerEnum(String enumName, List<String> values) {
    _customEnums[enumName.toLowerCase()] = values;
  }

  /// Clears all registered custom enums
  static void clearEnums() {
    _customEnums.clear();
  }

  /// Checks if a type is a registered custom enum
  static bool isCustomEnum(String pgType) {
    return _customEnums.containsKey(pgType.toLowerCase());
  }

  /// Gets the enum values for a custom enum type
  static List<String>? getEnumValues(String pgType) {
    return _customEnums[pgType.toLowerCase()];
  }

  /// Maps a PostgreSQL data type to a Dart type
  static String mapType(String pgType) {
    // Remove array suffix if present
    final isArray = pgType.endsWith('[]');
    final baseType = isArray ? pgType.substring(0, pgType.length - 2) : pgType;

    // Check for custom enum first
    if (isCustomEnum(baseType)) {
      // Custom enums are stored as strings in JSON, user can create Dart enums separately
      return isArray ? 'List<String>' : 'String';
    }

    final dartType = _typeMap[baseType.toLowerCase()] ?? 'dynamic';

    return isArray ? 'List<$dartType>' : dartType;
  }

  // https://www.postgresql.org/docs/current/datatype.html
  static const Map<String, String> _typeMap = {
    // ===================
    // Numeric Types
    // ===================
    // Integer types
    'int2': 'int',
    'int4': 'int',
    'int8': 'int',
    'smallint': 'int',
    'integer': 'int',
    'int': 'int',
    'bigint': 'int',

    // Serial types (auto-incrementing)
    'serial2': 'int',
    'serial4': 'int',
    'serial8': 'int',
    'smallserial': 'int',
    'serial': 'int',
    'bigserial': 'int',

    // Floating-point types
    'float4': 'double',
    'float8': 'double',
    'float': 'double',
    'real': 'double',
    'double precision': 'double',

    // Arbitrary precision types
    'numeric': 'double',
    'decimal': 'double',

    // ===================
    // Monetary Type
    // ===================
    'money': 'String',

    // ===================
    // Character Types
    // ===================
    'text': 'String',
    'varchar': 'String',
    'character varying': 'String',
    'char': 'String',
    'character': 'String',
    'bpchar': 'String', // blank-padded char (internal name)
    'name': 'String', // internal type for identifiers
    'citext': 'String', // case-insensitive text (extension)

    // ===================
    // Binary Data Type
    // ===================
    'bytea': 'List<int>',

    // ===================
    // Date/Time Types
    // ===================
    'date': 'DateTime',
    'timestamp': 'DateTime',
    'timestamptz': 'DateTime',
    'timestamp without time zone': 'DateTime',
    'timestamp with time zone': 'DateTime',
    'time': 'String',
    'timetz': 'String',
    'time without time zone': 'String',
    'time with time zone': 'String',
    'interval': 'String',

    // ===================
    // Boolean Type
    // ===================
    'bool': 'bool',
    'boolean': 'bool',

    // ===================
    // Enumerated Types
    // ===================
    // Note: User-defined enums will fall through to 'dynamic'
    // Users should handle enums manually or extend the type map

    // ===================
    // Geometric Types
    // ===================
    'point': 'String',
    'line': 'String',
    'lseg': 'String',
    'box': 'String',
    'path': 'String',
    'polygon': 'String',
    'circle': 'String',

    // ===================
    // Network Address Types
    // ===================
    'inet': 'String',
    'cidr': 'String',
    'macaddr': 'String',
    'macaddr8': 'String',

    // ===================
    // Bit String Types
    // ===================
    'bit': 'String',
    'bit varying': 'String',
    'varbit': 'String',

    // ===================
    // Text Search Types
    // ===================
    'tsvector': 'String',
    'tsquery': 'String',

    // ===================
    // UUID Type
    // ===================
    'uuid': 'String',

    // ===================
    // XML Type
    // ===================
    'xml': 'String',

    // ===================
    // JSON Types
    // ===================
    'json': 'Map<String, dynamic>',
    'jsonb': 'Map<String, dynamic>',

    // ===================
    // Range Types
    // ===================
    'int4range': 'String',
    'int8range': 'String',
    'numrange': 'String',
    'tsrange': 'String',
    'tstzrange': 'String',
    'daterange': 'String',

    // ===================
    // Multirange Types (PostgreSQL 14+)
    // ===================
    'int4multirange': 'String',
    'int8multirange': 'String',
    'nummultirange': 'String',
    'tsmultirange': 'String',
    'tstzmultirange': 'String',
    'datemultirange': 'String',

    // ===================
    // Object Identifier Types
    // ===================
    'oid': 'int',
    'regclass': 'String',
    'regcollation': 'String',
    'regconfig': 'String',
    'regdictionary': 'String',
    'regnamespace': 'String',
    'regoper': 'String',
    'regoperator': 'String',
    'regproc': 'String',
    'regprocedure': 'String',
    'regrole': 'String',
    'regtype': 'String',

    // ===================
    // pg_lsn Type
    // ===================
    'pg_lsn': 'String',

    // ===================
    // Pseudo-Types (commonly encountered)
    // ===================
    'void': 'void',
    'record': 'Map<String, dynamic>',

    // ===================
    // Extensions (commonly used)
    // ===================
    // pgvector extension
    'vector': 'List<double>',

    // PostGIS extension
    'geometry': 'String',
    'geography': 'String',

    // ltree extension
    'ltree': 'String',
    'lquery': 'String',
    'ltxtquery': 'String',

    // hstore extension
    'hstore': 'Map<String, String>',
  };

  /// Check if the type needs a JsonKey annotation for proper serialization
  static bool needsJsonKey(String pgType) {
    final baseType =
        pgType.endsWith('[]') ? pgType.substring(0, pgType.length - 2) : pgType;
    return ['json', 'jsonb'].contains(baseType.toLowerCase());
  }
}
