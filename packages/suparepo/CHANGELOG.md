# Changelog

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

- `client_provider_output` — カスタム出力パスで `supabase_client_provider.dart` を任意の場所に生成可能に
- `client_provider_import` — 生成コード内のプロバイダー import パスをカスタマイズ可能に

## [1.3.2] - 2026-02-18

### Fixed

- RPC client: void 戻り値の関数で未使用の `response` 変数を除去
- RPC client: `rpc()` に明示的な型引数を追加し `inference_failure_on_function_invocation` を解消

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
