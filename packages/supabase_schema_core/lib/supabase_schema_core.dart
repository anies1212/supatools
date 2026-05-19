/// Internal package for Supabase schema fetching and type mapping.
///
/// This package is used by supafreeze and suparepo.
/// Not intended for direct use.
library;

export 'src/schema_fetcher.dart';
export 'src/sql_migration_parser.dart';
export 'src/type_mapper.dart';
export 'src/config_loader.dart';

// Re-export key types for convenience
// EnumInfo is exported from schema_fetcher.dart
