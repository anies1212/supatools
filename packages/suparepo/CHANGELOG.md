# Changelog

## [1.20.1] - 2026-06-10

### Fixed

- **YAML `models:` now merge with auto-detection instead of replacing it.** Previously, defining a `models:` entry for an Edge Function suppressed auto-detection for that function entirely — so overriding only `request` would drop its auto-detected error/response classes. Now YAML wins per field group (`request`/`response`/`errors`) and auto-detection fills in any group the YAML omits. This lets you override just the request types (e.g. to fix numeric/boolean fields the usage-based inference can't recover) while keeping the auto-generated `XError` sealed classes.

## [1.20.0] - 2026-06-10

### Added

- **Usage-based Edge Function request inference** (`edge_functions.infer_request_from_usage: true`) — recovers request models for handlers that don't declare an explicit `body as { ... }` type. Opt-in (default `false`) because inference is heuristic. When enabled, request fields are inferred from:
  - `req.json() as { ... }` cast annotations
  - `body.<field>` access patterns, with types from `typeof body.<field> === "string" | "number" | "boolean"` guards (and `body.<field> === true | false` for booleans)
  - optionality from ternary/nullish defaults (`typeof body.x === "string" ? ... : null`, `body.x ?? ...`), `if (body.x !== undefined)` guards, and boolean flag comparisons
  - This makes auto-detection (and `flatten_request_params`) work for Deno Edge Functions that destructure the body field-by-field. Numeric fields without a `typeof === "number"` guard fall back to `text` — define `models:` to override these. YAML `models:` always take precedence over inference.

## [1.19.0] - 2026-06-10

### Added

- **Flattened Edge Function request parameters** (`edge_functions.flatten_request_params: true`) — typed Edge Function methods can now expand request-model fields into named method parameters instead of taking a single `request:` wrapper object. The JSON body is built inside the generated method, so callers never hardcode JSON string keys:
  - Before: `client.sendEmail(request: SendEmailRequest(to: 'a@x.com', subject: 'Hi'))`
  - After: `client.sendEmail(to: 'a@x.com', subject: 'Hi')`
  - Required fields are emitted before optional ones to satisfy Dart's parameter ordering
  - The `XRequest` model class is still generated for backward compatibility
  - Opt-in (default `false`); requires a request model (auto-detected from TypeScript or defined via YAML `models`)

## [1.18.1] - 2026-05-20

### Fixed

- Edge Function client generator no longer emits an unused `import 'dart:convert';` when all functions have request-only models (no typed response). The import is now only added when at least one function declares a typed response, since `jsonDecode` / `utf8.decode` are only used inside the response-decoding path. This eliminates `unused_import` warnings in downstream projects that run `dart analyze --fatal-infos`.

## [1.18.0] - 2026-05-20

### Added

- **In-memory fake repository generation** (`generate_fakes: true`) — emits `{table}_repository.fake.dart` alongside each real repository. The generated `Fake{Table}Repository` class `implements` the real repository so it can be substituted via Riverpod overrides in tests:
  - CRUD methods (`getAll`/`getById`/`create`/`update`/`delete`/`count`/`paginate`) operate on an in-memory `Map<dynamic, Model>` keyed by primary key
  - `seed(records)` helper to populate the store
  - Relation methods (`getAllWith*`) fall back to `getAll()` since relations can't be auto-embedded in memory
  - Custom methods from `.custom.dart` are stubbed with `UnimplementedError` so callers can override them in a subclass for test-specific behavior

## [1.17.0] - 2026-05-19

### Added

- **SQL migrations fallback for RPC return-type introspection** — When `execute_sql` is not installed or PostgREST's OpenAPI omits response schemas, suparepo now parses local `*.sql` migration files to recover return types. This makes the RPC client generation work out of the box for projects that don't (or can't) install the `execute_sql` helper RPC.
  - New config option `rpc.migrations_path` for explicit paths
  - Auto-detects common locations (`../supabase/migrations`, `../../supabase/migrations`, `./supabase/migrations`) when the option is unset
  - Composite types (`CREATE TYPE foo AS (...)`) referenced by `RETURNS SETOF foo` are fully resolved to typed column lists
  - Resolution count is reported in the CLI output: `📄 SQL migrations fallback: resolved N/M missing return type(s)`

### Changed

- Bump `supabase_schema_core` dependency to `^1.8.0`

## [1.16.1] - 2026-05-19

### Fixed

- Surface diagnostic warnings when `execute_sql` RPC introspection fails so that users no longer get an entire `rpc_client.dart` of `Future<void>` methods with no indication why. The CLI now prints actionable guidance (install `execute_sql` or use `rpc.return_types` in `suparepo.yaml`) when a high ratio of RPC functions cannot be resolved (fixes [#2](https://github.com/anies1212/supatools/issues/2))
- OpenAPI parsing now resolves `$ref` response schemas and supports OpenAPI 3.0 `responses.200.content.<mediaType>.schema`, recovering return types in more PostgREST output shapes

### Changed

- Bump `supabase_schema_core` dependency to `^1.7.3`

## [1.16.0] - 2026-04-15

### Added

- **`@SupaQuery` annotation support** — Annotate method stubs in `.custom.dart` extension files with `@SupaQuery(...)` and suparepo auto-generates PostgREST query implementations. Supports:
  - Filter operators: `eq`, `neq`, `lt`, `lte`, `gt`, `gte`, `like`, `ilike`, `is_`, `in_`, `contains`, `overlaps`
  - `Param.now` for runtime `DateTime.now()` injection
  - `Param('name')` for method parameter injection
  - `OrderBy` / `OrderBy.desc` with `nullsFirst` option
  - `limit`, `returnMode` (list/single/maybeSingle), custom `select`, `resultModel`
- New dependency: `supa_query_annotation ^0.1.0`

### Changed

- Translate all code comments, doc strings, test descriptions, and CHANGELOG entries to English (OSS)

## [1.15.2] - 2026-04-08

### Fixed

- Fix `coalesce` type inference failing when subqueries contain `::` type casts (e.g. `coalesce((select true from t where (x)::date = y::date), false)`) — the `::` check was evaluated before `coalesce`, causing `::date` inside the subquery to be mistakenly used as the return type
- Harden `_tokenizeBuildObjectArgs` to correctly handle SQL string literals (e.g. `'Asia/Tokyo'`) nested inside subqueries within `json_build_object` arguments

## [1.15.1] - 2026-04-08

### Fixed

- Fix `json_build_object` type inference for complex expressions — `coalesce(..., false)` now infers `bool`, `coalesce(..., 0)` infers `int4`, `NOT expr` and `EXISTS(...)` infer `bool`, instead of falling back to `String`

## [1.15.0] - 2026-04-08

### Added

- **Auto-generate nested Freezed models for json columns in `RETURNS TABLE`** — When a `RETURNS TABLE` function has `json`/`jsonb` columns, suparepo parses `json_agg(json_build_object(...))` patterns in the function body to detect the inner structure and generates typed nested models (e.g. `List<CalendarItem>` instead of `dynamic`).
- Nested models are generated in the same result file with `fromRow()` factory
- Supports multiple json columns per function, each with independent nested structure detection
- Column alias matching: `json_agg(...) as v_calendar` maps to `calendar` column in `RETURNS TABLE`

## [1.14.0] - 2026-04-08

### Added

- **Auto-generate error code sealed classes from PL/pgSQL** — For `RETURNS TABLE(success bool, error text)` functions, suparepo parses the function body to detect error code string literals (e.g. `'daily_limit_exceeded'`) and generates a Freezed sealed class with `fromErrorCode()` factory.
- Result model `error` field is automatically typed with the generated error class instead of `String`.
- Supported PL/pgSQL patterns:
  - `return query select false, 'error_code'::text;`
  - `error := 'error_code';`

## [1.13.2] - 2026-04-08

### Fixed

- Revert global `json`/`jsonb` → `dynamic` mapping; restore `Map<String, dynamic>` in TypeMapper for general use (repositories, etc.)
- Scope `dynamic` mapping to **RPC result models only** — `json`/`jsonb` columns in `RETURNS TABLE` are `dynamic` in generated Freezed models (safe for both `json_agg` arrays and `json_build_object` objects), while repositories keep `Map<String, dynamic>`

## [1.13.1] - 2026-04-08

### Fixed

- Fix `RETURNS TABLE` single-row RPC causing `type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>'` error — PostgREST may return a single object instead of an array; generated code now normalizes the response with `rawResponse is List ? rawResponse : [rawResponse]`
- Fix `json` / `jsonb` column type mapping in RPC result models to `dynamic` — `json_agg()` returns a JSON array (`List<dynamic>`), not a Map
- Fix `fromRow()` generation for `dynamic` fields — no longer emits redundant `as dynamic` cast

## [1.13.0] - 2026-04-08

### Added

- **Auto-detect JSON column schemas** — For `RETURNS json/jsonb` RPC functions, suparepo now automatically parses `json_build_object()` / `jsonb_build_object()` calls in the function body to detect field names and types, then generates Freezed result models without any YAML configuration.
  - Types are inferred from PL/pgSQL variable declarations (`DECLARE v_rank text;`)
  - Type cast expressions (`expr::int4`) are also recognized
  - `RETURNS TABLE` auto-detection takes precedence; JSON auto-detection only applies to functions without existing `tableColumns`
  - Requires `execute_sql` RPC function for `pg_proc.prosrc` access

## [1.12.0] - 2026-04-08

### Added

- **YAML-defined result models for `RETURNS json/jsonb` RPC functions** — You can now define column schemas in `suparepo.yaml` via `result_models` to generate Freezed result model classes for functions that return `json` or `jsonb`, without changing the SQL to `RETURNS TABLE(...)`.
- Single-object return support: functions with `result_models` and `returnsSetOf: false` generate `Future<Model>` instead of `Future<List<Model>>`.
- Shorthand syntax support in `result_models` (e.g. `rank: text` instead of `rank: { type: text }`).

### Example

```yaml
rpc:
  enabled: true
  generate_result_models: true
  result_models:
    get_membership_rank_info:
      rank: { type: text }
      upload_days: { type: int4 }
      is_active: { type: bool }
```

Generates `GetMembershipRankInfoResult` Freezed class and the RPC client returns `Future<GetMembershipRankInfoResult>` instead of `Future<Map<String, dynamic>>`.

## [1.11.5] - 2026-04-03

### Fixed

- Remove unnecessary null-aware operator (`?.`) on non-null DateTime params that caused `invalid_null_aware_operator` warning with `dart analyze --fatal-infos`

## [1.11.4] - 2026-04-03

### Fixed

- Fix `DateTime` parameters in RPC functions failing with `jsonEncode` error ("Converting object to an encodable object failed: Instance of 'DateTime'")
  - `date` params are now serialized as `YYYY-MM-DD` via `.toIso8601String().split('T').first`
  - `timestamp` / `timestamptz` params are serialized as full ISO8601 via `.toIso8601String()`

## [1.11.3] - 2026-03-11

### Fixed

- Fix `_isImportReferenced` incorrectly matching `.supafreeze.dart` class names as substrings of identifiers with `Repository`/`Custom` suffixes
  - e.g. `TentameProjects` falsely matched `TentameProjectsRepository`, preventing removal of unused imports

## [1.11.2] - 2026-03-11

### Fixed

- Add automatic cleanup of unused imports (supabase, supafreeze) in `.custom.dart` files
- Improve `generateExtensionFile()` to only import types actually referenced by methods

## [1.11.1] - 2026-03-11

### Fixed

- Fix `.supafreeze.dart` imports not being excluded when embedding from `.custom.dart`
- Fix duplicate custom imports in generated repository files

## [1.11.0] - 2026-03-11

### Changed

- Embed custom methods from `.custom.dart` as **instance methods** in generated repository classes
  - Resolves issue where extension methods could not be overridden from subclasses in tests due to Dart's static dispatch
  - `.custom.dart` files remain in extension format for IDE support and editing
  - suparepo reads `.custom.dart` at generation time and embeds directly into the generated class
  - No longer need to import `.custom.dart` from use_case layer
  - Custom methods can now be properly overridden in fake repositories for testing

## [1.10.1] - 2026-03-11

### Fixed

- Fix custom methods not being migrated when preceded by multi-line field declarations (`static const _x =\n '...';`)
- Auto-migrate private static fields referenced by custom methods into the extension

## [1.10.0] - 2026-03-11

### Added

- Automatic custom method migration
  - Detect custom methods in existing repository files during regeneration
  - Auto-migrate to `*_repository.custom.dart` as extensions
  - Auto-replace `_client` references with `client`
  - Merge with existing `.custom.dart` files (skip duplicates)
  - Auto-migrate custom imports
  - `--no-migrate` flag to skip migration

## [1.9.0] - 2026-03-11

### Added

- Add `client` getter to repository classes (enables adding custom methods via extensions)
  - Resolves issue of custom code being lost during regeneration
  - Custom methods are written as extensions in `*_repository.custom.dart`

### Fixed

- Fix TS type extractor failing to detect error codes from `statusMap: Record<string, number>` patterns
  - Support error codes via variable references like `error: data.error` + statusMap lookup
  - Merge with existing literal `error: "..."` patterns and deduplicate

## [1.8.4] - 2026-03-11

### Changed

- Bumped `supabase_schema_core` dependency to `^1.4.0` (enum type support)

## [1.8.3] - 2026-03-05

### Fixed

- Fix Edge Function error class `fromFunctionException` crashing with `as String` cast when `e.details` is `Map<String, dynamic>`
  - Handle cases where Supabase SDK auto-decodes JSON responses to `Map<String, dynamic>`
  - Use switch expression on actual type of `e.details` to support both `String` (raw) and `Map<String, dynamic>` (decoded)

## [1.8.2] - 2026-03-04

### Fixed

- Fix Edge Function client `response.data` type cast error
  - Supabase SDK auto-decodes `Content-Type: application/json` responses to `Map<String, dynamic>`, causing `as List<int>` cast to fail at runtime
  - Dynamically check actual type of `response.data` to support both `List<int>` (raw bytes) and `Map<String, dynamic>` (decoded)

## [1.8.1] - 2026-03-03

### Fixed

- Fix `fromRow()` DateTime field crashing with `as DateTime` cast at runtime
  - Supabase RPC JSON responses return timestamps as strings, changed to `DateTime.parse(row['col'] as String)`

## [1.8.0] - 2026-03-03

### Added

- **Freezed result model generation for RETURNS TABLE functions** (`generate_result_models`)
  - Automatically generates `@freezed` result model classes with `fromRow()` factory for RPC functions using `RETURNS TABLE(col1 type1, ...)`
  - Column names and types are fetched from `pg_proc` catalog (`proargmodes`, `proargnames`, `proallargtypes`)
  - RPC client methods return typed `List<GetMyInviteCodeResult>` instead of `List<Map<String, dynamic>>`
  - Model file per function: e.g. `get_my_invite_code_result.dart`
  - Configurable output directory via `result_models_output`
  - Requires `execute_sql` RPC function and `build_runner` for Freezed code generation

### Changed

- Bumped `supabase_schema_core` dependency to `^1.3.0`
- `RpcGenerator.generateRpcClient()` accepts `generateResultModels` and `resultModelsImportPrefix` parameters

## [1.7.2] - 2026-03-03

### Fixed

- RPC functions using `RETURNS TABLE(...)` are now correctly generated as `Future<List<Map<String, dynamic>>>` instead of `Future<void>`
  - PostgreSQL internally represents `RETURNS TABLE` as `record` + `proretset = true`, which was previously treated as void

### Changed

- Bumped `supabase_schema_core` dependency to `^1.2.2`

## [1.7.1] - 2026-02-23

### Fixed

- Fix error type generation code examples in README to use generic examples

## [1.7.0] - 2026-02-23

### Added

- **Edge Function error type generation** (Freezed sealed class)
  - Automatically detects error responses (status 4xx/5xx) from TypeScript source
  - Extracts `snake_case` error codes from `JSON.stringify({ error: "..." })` patterns
  - Generates Freezed sealed class per Edge Function with named constructors for each error code
  - Includes `unknown` variant for unrecognized error codes
  - Includes `fromFunctionException` factory for easy `FunctionException` parsing
  - Error class files are output alongside the Edge Function client (e.g., `submit_campaign_receipt_error.dart`)

## [1.6.2] - 2026-02-23

### Changed

- RPC client now uses typed generics on `rpc<T>()` calls instead of `rpc<dynamic>()` with manual casts
  - Scalar: `return await _client.rpc<bool>(...)` (was `_client.rpc<dynamic>(...)` + `response as bool`)
  - setof: `_client.rpc<List<dynamic>>(...)` + `response.cast<T>()`
  - void: unchanged (`_client.rpc<void>(...)`)

## [1.6.1] - 2026-02-23

### Fixed

- `execute_sql` via `pg_proc` now returns all function rows (was only returning the first row due to `EXECUTE ... INTO` limitation; fixed by wrapping query with `json_agg`)
- `execute_sql` is now automatically excluded from generated RPC client (internal infrastructure, not a user-facing function)

### Changed

- Bumped `supabase_schema_core` dependency to `^1.2.1`

## [1.6.0] - 2026-02-23

### Added

- YAML `return_types` for manual RPC return type overrides
  - Specify PostgreSQL type names per function (e.g. `text`, `bool`, `setof jsonb`)
  - Takes highest priority over `pg_proc` auto-correction and OpenAPI spec
  - No `execute_sql` function needed — ideal for projects without it
- Comprehensive README documentation for return type correction
  - `execute_sql` setup guide with SQL snippet and security notes
  - Type mapping reference table
  - Priority order explanation

## [1.5.0] - 2026-02-23

### Added

- Accurate RPC return type resolution via `pg_proc` catalog
  - Fixes boolean and other scalar functions being generated as `Future<void>` instead of `Future<bool>`, `Future<int>`, etc.
  - Requires `execute_sql` RPC function; gracefully falls back to OpenAPI spec when unavailable

### Changed

- Bumped `supabase_schema_core` dependency to `^1.2.0`

## [1.4.6] - 2026-02-23

### Fixed

- Fixed `argument_type_not_assignable` error in generated Edge Function client
  - `response.data` is `dynamic`, added explicit `as List<int>` cast for `utf8.decode()`

## [1.4.5] - 2026-02-23

### Fixed

- Restored RPC/EdgeFunction provider generation in `supabase_client_provider.dart` (unified mode)
  - 1.4.3 accidentally removed RPC/Edge providers from the unified file
  - Now: without `client_providers_output`, providers are embedded in `supabase_client_provider.dart` (default)
  - With `client_providers_output`, providers go to a separate file

## [1.4.4] - 2026-02-23

### Fixed

- Added `ignore_for_file` directives to `edge_function_client.dart` generated code
  - Suppresses `public_member_api_docs`, `sort_constructors_first`, `lines_longer_than_80_chars` lint warnings

## [1.4.3] - 2026-02-23

### Changed

- Split RPC/EdgeFunction providers into separate `client_providers.dart` file
  - `supabase_client_provider.dart` now contains only `supabaseClient` provider
  - New `client_providers_output` setting generates `client_providers.dart` with `supabaseRpcClient` and `supabaseEdgeFunctionClient` providers
  - Fixes `InvalidTypeException` when gateway package does not depend on data package

## [1.4.2] - 2026-02-22

### Changed

- Moved RPC and Edge Function client providers to unified `client_provider_output` file
  - `supabase_client_provider.dart` now contains `supabaseClient`, `supabaseRpcClient`, and `supabaseEdgeFunctionClient` providers
  - Removed inline provider generation from `rpc_client.dart` and `edge_function_client.dart`

## [1.4.1] - 2026-02-22

### Fixed

- Added CHANGELOG.md entry for 1.4.0 (fixes pub.dev scoring)

## [1.4.0] - 2026-02-22

### Added

- **Automatic TypeScript type inference** for Edge Functions
  - Extracts request types from `body as { ... }` patterns
  - Extracts response types from `JSON.stringify({ ... })` in success responses
  - Detects required/optional fields from validation if-statements (`!field`, `typeof` checks)
  - Supports `handler.ts` delegation pattern
  - Type mapping: `string` → `String`, `number` → `int`, `boolean` → `bool`
  - Enabled by default (`auto_detect_types: true`), YAML model definitions take precedence
- **Riverpod provider generation for Edge Function client**
  - Generates `@Riverpod(keepAlive: true)` provider for `SupabaseEdgeFunctionClient`
  - Consistent with existing RPC client provider pattern

## [1.3.3] - 2026-02-18

### Added

- `client_provider_output` — generate `supabase_client_provider.dart` at a custom output path
- `client_provider_import` — customize the provider import path in generated code

## [1.3.2] - 2026-02-18

### Fixed

- RPC client: remove unused `response` variable for void return type functions
- RPC client: add explicit type arguments to `rpc()` to resolve `inference_failure_on_function_invocation`

## [1.3.1] - 2026-02-18

### Fixed

- Tightened `supabase_schema_core` lower bound to `^1.1.0` (fixes downgrade analysis)
- Added example file for pub.dev scoring
- Updated README with `generate_providers` and `model_import_prefix` documentation

## [1.3.0] - 2026-02-18

### Added

- **Riverpod provider generation** (`generate_providers`)
  - Optionally generates `@Riverpod(keepAlive: true)` providers for each repository and RPC client
  - Generates `supabase_client_provider.dart` for SupabaseClient DI
  - Controlled by `generate_providers: true` in `suparepo.yaml`
- **Individual model import prefix** (`model_import_prefix`)
  - Import each model file individually instead of a barrel file
  - e.g. `model_import_prefix: package:data/` imports `package:data/categories.supafreeze.dart`

### Fixed

- Fixed `count()` method to use correct Supabase SDK API (`.select().count(CountOption.exact)`)
- Added `ignore_for_file` directives to suppress lint warnings in generated code
- Fixed required parameters ordering in RPC client methods

## [1.2.0] - 2026-02-12

### Added

- **Configurable Supabase import** (`supabase_import`)
  - Allows switching between `package:supabase_flutter/supabase_flutter.dart` (default) and `package:supabase/supabase.dart` for pure Dart packages
  - Applied to all generators: repository, RPC client, and Edge Function client

## [1.1.0] - 2026-02-11

### Added

- **RPC client generation** (`RpcGenerator`)
  - Detects RPC functions from OpenAPI spec and generates type-safe Dart methods
  - Automatic snake_case to camelCase conversion with reserved word escaping
- **Edge Function client generation**
  - `EdgeFunctionDetector` — scans local `supabase/functions/` directory
  - `EdgeFunctionGenerator` — generates clients with or without typed models
  - YAML-based request/response model definitions
- **Configuration extensions** (`RpcConfig`, `EdgeFunctionConfig`)
  - RPC: enabled, output, include/exclude filters
  - Edge Functions: enabled, output, functions_path, include/exclude, model definitions
- **CLI** (`bin/suparepo.dart`)
  - `dart run suparepo` — generate all enabled outputs
  - `--repo` / `--rpc` / `--edge` — generate specific targets
  - `--force` — force regenerate all

### Changed

- Added `rpc` and `edgeFunctions` fields to `SuparepoConfig`

## [1.0.0] - 2025-12-11

### Added

- Initial release
- Repository code generation from Supabase schema
- CRUD operations (getAll, getById, create, update, delete)
- Pagination support
- Count queries
- Relation embedding with foreign key detection
- Type-safe mode when used with supafreeze models
