# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-12-10

### Added

- Initial release
- Fetch table schema from Supabase via OpenAPI spec
- Generate Freezed models with `fromJson`/`toJson`
- build_runner integration (runs before freezed/json_serializable)
- Per-table incremental caching with SHA256 hashes
- Automatic file cleanup when tables are deleted
- Configuration via `supafreeze.yaml`
- Variable resolution from dart-define, .env, and environment variables
- Fetch modes: `always`, `if_no_cache`, `never`
- Table filtering with `include`/`exclude` options
- Optional barrel file generation
- Comprehensive PostgreSQL to Dart type mapping
- Property sorting (required first, grouped by type)
- snake_case to camelCase conversion with `@JsonKey` annotations
- Support for nullable fields, primary keys, and default values
- **Relation embedding** - Auto-detect FK from `*_id` columns and embed related models
- Per-table relation configuration with `relations` option
- Dart reserved word escaping for field and class names
- Custom enum type detection from OpenAPI spec
- **CLI tool** (`dart run supafreeze:supafreeze`) for manual schema sync
- `--force` flag to regenerate all models regardless of cache
