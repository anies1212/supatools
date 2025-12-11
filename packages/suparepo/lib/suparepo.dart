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
        BaseSupabaseConfig;

// Suparepo-specific exports
export 'src/config_loader.dart' show SuparepoConfigLoader, SuparepoConfig;
export 'src/repository_generator.dart' show RepositoryGenerator;
