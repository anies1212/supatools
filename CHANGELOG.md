# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [suparepo 1.22.0] - 2026-06-17

### Added

- **suparepo**: Infer Edge Function response object types from `.from(table).select(cols)` projections (`edge_functions.infer_response_from_select: true`, default `false`). A `jsonResponse` property that spreads a select result (`{ ...data, extra: ... }`) or is a bare select variable is typed from the introspected table schema — only the selected columns, with their nullability, plus extra literal properties. `.maybeSingle()`/`.single()` → single object, otherwise `List<...>`; aliases and `select("*")` supported. Reshaped (`.map(...)`), relation-embedded, or unresolvable cases fall back to `dynamic`. Strategy 1 (`export interface`) still wins; with the flag off, output is identical to 1.21.0.

## [suparepo 1.21.0 / supafreeze 2.2.0] - 2026-06-17

### Added

- **suparepo**: Generate Freezed success-response DTOs for Edge Functions from
  the handler's exported TypeScript interface. A `<PascalName>Response`
  interface is parsed directly; otherwise the success `jsonResponse({...})`
  call is parsed and property types are recovered from referenced
  functions/variables (`viewSavedCards(...): SavedDailyCardView[]` →
  `List<...>`). Nested objects become nested Freezed classes, `T | null`
  becomes nullable, `string[]` becomes `List<String>`, and snake_case keys map
  via `@JsonKey`. Files are written to `edge_functions.response_models_output`
  (default: next to the client), and the typed client method returns the
  generated `<Name>Response`. Functions without a recoverable response shape are
  skipped (backward compatible).
- **supafreeze**: `generate_insert_models` option emits a `<Class>Insert`
  Freezed model alongside each table model. NOT NULL columns that carry a
  database default (e.g. a primary key's `gen_random_uuid()`, `created_at`'s
  `now()`, or an enum/literal default) are optional there (omitted from JSON
  when null), while the fetch model keeps them required.
- **supafreeze**: `preserve_column_order` option keeps generated field order
  aligned to the physical database column order, avoiding churn when a column's
  required-ness or mapped type changes.

### Fixed

- **supafreeze**: Enum columns with a literal default (e.g.
  `status DEFAULT 'pending'::bond_story_status`) now generate
  `@Default(BondStoryStatus.pending)` instead of falling back to `required`,
  restoring optional construction for insert. Handles schema-qualified casts;
  unknown values still fall back to `required`.

## [suparepo 1.16.0 / supa_query_annotation 0.1.0] - 2026-04-15

### Added

- **supa_query_annotation**: New lightweight annotation package for declarative Supabase custom queries (`@SupaQuery`, `Filter`, `Param`, `OrderBy`, `ReturnMode`)
- **suparepo**: Process `@SupaQuery` annotations in `.custom.dart` files to auto-generate PostgREST query implementations

### Changed

- Translate all code comments, doc strings, test descriptions, and CHANGELOG entries to English (OSS)

## [suparepo 1.15.2 / supabase_schema_core 1.7.2] - 2026-04-08

### Fixed

- **supabase_schema_core**: Fix `coalesce` type inference with nested `::` casts in subqueries; harden string literal handling in parenthesis tracking

## [suparepo 1.15.1 / supabase_schema_core 1.7.1] - 2026-04-08

### Fixed

- **supabase_schema_core**: Fix type inference for `coalesce(...)`, `NOT`, `EXISTS`, boolean operators in `json_build_object` expressions

## [suparepo 1.15.0 / supabase_schema_core 1.7.0] - 2026-04-08

### Added

- **suparepo**: Auto-generate nested Freezed models for json columns in `RETURNS TABLE` (e.g. `List<CalendarItem>` instead of `dynamic`)
- **supabase_schema_core**: `parseNestedJsonColumns()` for `json_agg(json_build_object(...))` structure detection

## [suparepo 1.14.0 / supabase_schema_core 1.6.0] - 2026-04-08

### Added

- **suparepo**: Auto-generate Freezed sealed error classes from PL/pgSQL `RETURNS TABLE(success bool, error text)` functions
- **supabase_schema_core**: `parseRpcErrorCodes()` for PL/pgSQL error code extraction

## [suparepo 1.13.2 / supabase_schema_core 1.5.2] - 2026-04-08

### Fixed

- **supabase_schema_core**: Revert `json`/`jsonb` → `Map<String, dynamic>` globally; add `TypeMapper.isJsonType()` helper
- **suparepo**: Scope `json`/`jsonb` → `dynamic` to RPC result models only (repositories keep `Map<String, dynamic>`)

## [suparepo 1.13.1 / supabase_schema_core 1.5.1] - 2026-04-08

### Fixed

- **suparepo**: Fix `RETURNS TABLE` single-row RPC crash (`Map` not subtype of `List`) by normalizing response
- **supabase_schema_core**: Map `json`/`jsonb` to `dynamic` in RPC result models (fixes `json_agg` cast errors)

## [suparepo 1.13.0 / supabase_schema_core 1.5.0] - 2026-04-08

### Added

- **suparepo**: Auto-detect JSON column schemas from `json_build_object()` in PL/pgSQL function bodies — no YAML configuration needed
- **supabase_schema_core**: `parseJsonBuildObject()` parser for `pg_proc.prosrc` source analysis

## [suparepo 1.12.0] - 2026-04-08

### Added

- **suparepo**: YAML-defined `result_models` for `RETURNS json/jsonb` RPC functions — generate Freezed result models without changing SQL to `RETURNS TABLE(...)`

## [suparepo 1.8.2] - 2026-03-04

### Fixed

- Fix Edge Function client `response.data` type cast error
  - Support both `Map<String, dynamic>` and `List<int>` response types

## [1.0.6] - 2025-12-10

### Fixed

- Added CHANGELOG.md entries for all versions to satisfy pub.dev validation

## [1.0.5] - 2025-12-10

### Fixed

- Fixed Dart formatting issues for pub.dev static analysis compliance
- All source files now pass `dart format` check

## [1.0.4] - 2025-12-10

### Fixed

- Formatted Dart sources to satisfy pub.dev static analysis checks
- Bumped package version to align with latest release tag

## [1.0.3] - 2025-12-10

### Fixed

- Fixed analyzer compatibility for build_runner integration

## [1.0.2] - 2025-12-10

### Fixed

- Loosened analyzer range to stay compatible with build_runner/freezed toolchains while still allowing latest releases
- Updated example dependencies to resolve build_runner formatting errors caused by analyzer incompatibility

## [1.0.1] - 2025-12-10

### Changed

- Renamed Supabase environment variable to `SUPABASE_DATA_API_URL` in docs and validations for clarity

## [1.0.0] - 2024-12-10

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
