# Changelog

## [1.10.0] - 2026-06-28

### Fixed

- **OpenAPI spec fetch no longer fails with HTTP 400.** The request appended `?apikey=<key>` to `/rest/v1/`, which PostgREST parsed as a column filter (`PGRST100`). The key is already sent as a header, so the redundant query parameter is dropped. This previously aborted all RPC return-type introspection.
- **Catalog introspection works with an aggregating `execute_sql`.** RPC/enum introspection queries wrap their projection in `json_agg(sub)`; an `execute_sql` that itself aggregates rows with `jsonb_agg(t)` (rather than the README's `EXECUTE ... INTO` single-row form) double-wrapped the result as `[{"json_agg": [...]}]`, throwing `type 'Null' is not a subtype of type 'String'`. Responses are now normalized for both conventions.

### Added

- **`SchemaFetcher.rowsFromAggregatedResponse`** — normalizes a raw `execute_sql` response into the inner `json_agg` row list under either `execute_sql` convention.
- **`SchemaFetcher.applyResultModels`** — merges consumer `result_models` column overrides onto introspected RPC columns (overrides set type/nullability; unmentioned introspected columns are retained).

## [1.9.0] - 2026-06-26

### Added

- **`RpcTableColumn.nullable`** — new field (default `false`) marking whether a `RETURNS TABLE` column may be null in the result row. Introspection cannot infer nullability from `pg_proc`, so it stays `false` for introspected columns and is intended to be overridden via consumers' YAML `result_models` definitions. `toString()` now includes the flag.

## [1.8.0] - 2026-05-19

### Added

- **`SqlMigrationParser`** — pure-Dart parser for local SQL migration files. Extracts RPC return-type info from `CREATE [OR REPLACE] FUNCTION ... RETURNS ...` statements and `CREATE TYPE ... AS (...)` composite types, with no database round-trip. Supports:
  - Scalar returns (`RETURNS BOOLEAN`, `TEXT`, `UUID`, `INTEGER`, `BIGINT`, etc.)
  - `RETURNS TABLE(col1 type1, ...)`
  - `RETURNS SETOF <type>` (including composite types resolved to typed columns)
  - Dollar-quoted bodies (correctly ignores `CREATE FUNCTION` text inside function bodies / `RAISE NOTICE` strings)
  - Line (`--`) and block (`/* */`) comments
  - Trigger functions are skipped (not RPC-callable)
- `SchemaFetcher.mergeSqlMigrationInfo` — merges parser results into the function list, filling in only those still resolved to `void`

### Changed

- The execute_sql failure warning now lists `rpc.migrations_path` as the recommended workaround alongside the existing options

## [1.7.3] - 2026-05-19

### Added

- `SchemaFetcher.warnings` getter that exposes non-fatal diagnostics collected during the last `fetchRpcFunctions()` call (e.g. `execute_sql` introspection failures, suspiciously high ratio of RPC functions resolved to `void`)
- `parseRpcFunctions` now resolves `$ref` schemas against `definitions` / `components.schemas` and falls back to OpenAPI 3.0 `responses.200.content.<mediaType>.schema` when Swagger 2.0 `responses.200.schema` is absent

### Fixed

- When `execute_sql` RPC is not available, `fetchRpcFunctions()` no longer silently degrades to `Future<void>` for every RPC. A clear warning is recorded explaining the failure and pointing to `rpc.return_types` as a workaround (fixes [#2](https://github.com/anies1212/supatools/issues/2))

## [1.7.2] - 2026-04-08

### Fixed

- Fix `_resolveType` order: `coalesce`/`NOT`/`EXISTS` checks now run before `::` cast detection, preventing `::type` inside nested subqueries from being misidentified as the expression type
- Harden `parseJsonBuildObject` and `_tokenizeBuildObjectArgs` to skip SQL string literals during parenthesis depth tracking

## [1.7.1] - 2026-04-08

### Fixed

- Improve `_resolveType` to infer types from complex SQL expressions:
  - `coalesce(..., false/true)` → `bool`
  - `coalesce(..., 0)` → `int4`
  - `NOT expr` → `bool`
  - `EXISTS(...)` → `bool`
  - Boolean operators (`AND`, `OR`, `IS NULL`) → `bool`

## [1.7.0] - 2026-04-08

### Added

- `RpcTableColumn.nestedColumns` and `isArray` fields for nested JSON structure
- `SchemaFetcher.parseNestedJsonColumns()` — parses `json_agg(json_build_object(...))` patterns to extract nested column schemas with alias matching
- `SchemaFetcher._fetchRpcNestedJsonColumns()` — auto-detects nested structures for RETURNS TABLE json columns

## [1.6.0] - 2026-04-08

### Added

- `SchemaFetcher.parseRpcErrorCodes()` — parses PL/pgSQL function source to extract snake_case error code literals from `return query select false, 'code'::text` and `error := 'code'` patterns
- `RpcFunctionInfo.errorCodes` field for detected error codes
- `SchemaFetcher._fetchRpcErrorCodes()` — queries `pg_proc.prosrc` for functions with `error text` columns in `RETURNS TABLE`

## [1.5.2] - 2026-04-08

### Added

- `TypeMapper.isJsonType()` — returns true for `json`/`jsonb` PostgreSQL types, allowing callers to scope `dynamic` mapping to specific contexts (e.g. RPC result models) instead of globally

### Fixed

- Revert `json`/`jsonb` mapping back to `Map<String, dynamic>` in `TypeMapper` — the global `dynamic` change in v1.5.1 was too broad; callers that need `dynamic` should use `isJsonType()` to decide

## [1.5.1] - 2026-04-08

### Fixed

- Map `json` / `jsonb` PostgreSQL types to `dynamic` instead of `Map<String, dynamic>` — JSON values can be arrays (`json_agg`), objects, or scalars, so `dynamic` is the safe Dart type

## [1.5.0] - 2026-04-08

### Added

- Auto-detect JSON column schemas from `json_build_object()` / `jsonb_build_object()` in PL/pgSQL function bodies via `pg_proc.prosrc`
- `SchemaFetcher.parseJsonBuildObject()` — parses function source to extract key names and infer types from variable declarations
- `SchemaFetcher._fetchRpcJsonColumns()` — queries `pg_proc` for `RETURNS json/jsonb` functions and auto-detects column schemas

## [1.4.2] - 2026-04-03

### Added

- `TypeMapper.isDateTimeType()` — checks whether a PostgreSQL type (`date`, `timestamp`, `timestamptz`) maps to Dart `DateTime`
- `TypeMapper.isDateOnlyType()` — checks whether a PostgreSQL type is date-only (`date`) with no time component

## [1.4.1] - 2026-03-11

### Fixed

- Fix `mergeEnumTypes` failing to match OpenAPI-derived enum names (`tableName_columnName` format) to pg_enum names, resulting in `dynamic` type
  - Add `openApiEnums` parameter to retain OpenAPI enum info before TypeMapper is cleared

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
