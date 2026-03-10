# Changelog

## [1.4.0] - 2026-03-11

### Added

- `EnumInfo` class for representing PostgreSQL enum types (name + values)
- `SchemaFetcher.fetchEnums()` — queries `pg_enum` + `pg_type` + `pg_namespace` catalog to fetch PostgreSQL enum definitions; falls back to OpenAPI-detected enums when `execute_sql` is not available
- `SchemaFetcher.mergeEnumTypes()` static method — replaces OpenAPI-derived enum type names (`tableName_columnName`) with actual PostgreSQL type names in table column definitions
- `TypeMapper.useEnumTypes` static flag — when `true`, `mapType()` returns PascalCase Dart enum type names instead of `String` for registered enum types
- `TypeMapper.enumTypeName()` — converts PostgreSQL enum type name to Dart enum type name (e.g. `campaign_type` → `CampaignType`)

## [1.3.0] - 2026-03-03

### Added

- `RpcTableColumn` class for representing columns in `RETURNS TABLE(...)` definitions
- `RpcFunctionInfo.tableColumns` field — non-null when the function uses `RETURNS TABLE(col1 type1, ...)`
- `SchemaFetcher._fetchRpcTableColumns()` — queries `pg_proc` catalog (`proargmodes`, `proargnames`, `proallargtypes`) to extract TABLE column names and types
- `SchemaFetcher.mergeTableColumns()` static method to merge TABLE column info into `RpcFunctionInfo` list
- `fetchRpcFunctions()` now calls `mergeTableColumns` after `mergeReturnTypes` to populate `tableColumns` for RETURNS TABLE functions

## [1.2.2] - 2026-03-03

### Fixed

- `mergeReturnTypes()` now correctly handles `RETURNS TABLE(...)` functions — previously treated as `void` because `pg_proc` reports them as `record` type, now detected as `setof jsonb` when `proretset = true`

## [1.2.1] - 2026-02-23

### Fixed

- `_fetchRpcReturnTypes()` now wraps the `pg_proc` query with `json_agg` so that `execute_sql` (which uses `EXECUTE ... INTO`) returns all rows as a single JSON array instead of only the first row

## [1.2.0] - 2026-02-23

### Added

- `RpcFunctionInfo.copyWith()` method for updating return type fields
- `SchemaFetcher.mergeReturnTypes()` static method to correct `void` return types using `pg_proc` catalog
- `SchemaFetcher._fetchRpcReturnTypes()` to query `pg_proc` for accurate return type information

### Changed

- `fetchRpcFunctions()` now queries `pg_proc` catalog to correct scalar return types (e.g. `bool`, `int4`) that PostgREST OpenAPI spec reports as empty schema (void)
  - Only active when `execute_sql` RPC function is available
  - Falls back to OpenAPI-only behavior when `execute_sql` is not configured

## [1.1.0] - 2026-02-11

### Added

- `RpcParamInfo` class for representing RPC function parameters
- `RpcFunctionInfo` class for representing RPC function metadata
- `SchemaFetcher.fetchRpcFunctions()` to fetch RPC function definitions from OpenAPI spec
- `SchemaFetcher.parseRpcFunctions()` to parse RPC functions from OpenAPI JSON

### Changed

- Extracted `_fetchOpenApiSpec()` as a shared method for both table and RPC fetching

## [1.0.0] - 2025-12-11

### Added

- Initial release
- Schema fetching from Supabase OpenAPI spec
- PostgreSQL to Dart type mapping
- Base configuration loader with environment variable support
- Foreign key detection from column naming conventions
