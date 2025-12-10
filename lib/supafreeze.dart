/// Generate Freezed models from Supabase database schema.
///
/// This package provides tools to automatically generate type-safe Freezed
/// models from your Supabase PostgreSQL database schema.
///
/// ## Quick Start
///
/// 1. Create `supafreeze.yaml` in your project root:
/// ```yaml
/// url: ${SUPABASE_DATA_API_URL}
/// secret_key: ${SUPABASE_SECRET_KEY}
/// output: lib/models
/// ```
///
/// 2. Create `.env` file with your credentials:
/// ```
/// SUPABASE_DATA_API_URL=https://your-project.supabase.co
/// SUPABASE_SECRET_KEY=your-secret-key
/// ```
///
/// 3. Run build_runner:
/// ```bash
/// dart run build_runner build
/// ```
///
/// ## Features
///
/// - Automatic schema fetching from Supabase
/// - Per-table incremental generation
/// - Smart caching with SHA256 hashes
/// - PostgreSQL to Dart type mapping
/// - Reserved word handling
/// - Configurable fetch modes (always, if_no_cache, never)
///
/// ## Main Classes
///
/// - [ConfigLoader] - Loads configuration from YAML and environment
/// - [SchemaFetcher] - Fetches schema from Supabase
/// - [FreezedGenerator] - Generates Freezed model code
/// - [SchemaCache] - Manages schema caching for incremental builds
/// - [TypeMapper] - Maps PostgreSQL types to Dart types
library;

export 'src/config_loader.dart'
    show
        ConfigLoader,
        SupafreezeConfig,
        FetchMode,
        ConfigException,
        RelationConfig,
        RelationOverride;
export 'src/schema_fetcher.dart'
    show
        SchemaFetcher,
        TableInfo,
        ColumnInfo,
        ForeignKeyInfo,
        SchemaFetchException;
export 'src/type_mapper.dart' show TypeMapper;
export 'src/freezed_generator.dart' show FreezedGenerator;
export 'src/schema_cache.dart' show SchemaCache, SchemaDiff;
