/// Generate repository/data access layer code from Supabase database schema.
///
/// This package provides tools to automatically generate type-safe repository
/// classes with CRUD operations from your Supabase PostgreSQL database schema.
///
/// ## Quick Start
///
/// 1. Create `suparepo.yaml` in your project root:
/// ```yaml
/// url: ${SUPABASE_DATA_API_URL}
/// secret_key: ${SUPABASE_SECRET_KEY}
/// output: lib/repositories
/// ```
///
/// 2. Create `.env` file with your credentials:
/// ```
/// SUPABASE_DATA_API_URL=https://your-project.supabase.co
/// SUPABASE_SECRET_KEY=your-secret-key
/// ```
///
/// 3. Run the generator:
/// ```bash
/// dart run suparepo
/// ```
///
/// ## Features
///
/// - Automatic CRUD operation generation
/// - Type-safe query builders
/// - Pagination support
/// - Relation handling
/// - Filter and sort operations
library;

// Re-export core types from supabase_schema_core
export 'package:supabase_schema_core/supabase_schema_core.dart'
    show
        SchemaFetcher,
        TableInfo,
        ColumnInfo,
        ForeignKeyInfo,
        SchemaFetchException,
        TypeMapper,
        FetchMode,
        ConfigException,
        BaseSupabaseConfig,
        RpcFunctionInfo,
        RpcParamInfo,
        RpcTableColumn;

// Suparepo-specific exports
export 'src/config_loader.dart'
    show SuparepoConfigLoader, SuparepoConfig, RpcConfig, EdgeFunctionConfig;
export 'src/repository_generator.dart' show RepositoryGenerator;
export 'src/rpc_generator.dart' show RpcGenerator;
export 'src/rpc_result_model_generator.dart' show RpcResultModelGenerator;
export 'src/edge_function_detector.dart' show EdgeFunctionDetector;
export 'src/edge_function_generator.dart' show EdgeFunctionGenerator;
export 'src/edge_function_response_generator.dart'
    show EdgeFunctionResponseGenerator;
export 'src/edge_function_info.dart'
    show
        EdgeFunctionInfo,
        EdgeFunctionFieldDef,
        EdgeFunctionModelDef,
        EdgeFunctionResponseField;
export 'src/ts_type_extractor.dart' show TsTypeExtractor, TsTypeExtractorLoader;
export 'src/ts_response_type_parser.dart' show TsResponseTypeParser;
export 'src/supa_query_generator.dart'
    show SupaQueryGenerator, SupaQueryMethodInfo;
