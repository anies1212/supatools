# Changelog

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

- `_isImportReferenced` で `.supafreeze.dart` のクラス名が `Repository`/`Custom` サフィックス付きの識別子に部分一致してしまうバグを修正
  - 例: `TentameProjects` が `TentameProjectsRepository` に誤マッチし、未使用importが除去されなかった

## [1.11.2] - 2026-03-11

### Fixed

- `.custom.dart` ファイルの未使用 import（supabase, supafreeze）を自動クリーンアップする機能を追加
- `generateExtensionFile()` でメソッドが実際に参照する型のみ import するよう改善

## [1.11.1] - 2026-03-11

### Fixed

- `.custom.dart` から埋め込み時に `.supafreeze.dart` import を除外漏れしていたバグを修正
- 生成リポジトリファイルで custom import が既存 import と重複するバグを修正

## [1.11.0] - 2026-03-11

### Changed

- `.custom.dart` のカスタムメソッドを生成されるリポジトリクラスに**インスタンスメソッドとして埋め込む**方式に変更
  - extension メソッドは Dart の静的ディスパッチにより、テストでサブクラスから override できない問題を解決
  - `.custom.dart` ファイル自体は extension 形式のまま保持（IDE サポート・編集用）
  - suparepo 実行時に `.custom.dart` を読み取り、生成クラスに直接埋め込む
  - use_case 側で `.custom.dart` の import が不要に
  - テストの fake リポジトリでカスタムメソッドを正常に override 可能

## [1.10.1] - 2026-03-11

### Fixed

- 複数行フィールド宣言（`static const _x =\n '...';`）の後のカスタムメソッドが移行されないバグを修正
- カスタムメソッドが参照する private static field を extension に自動移行するよう対応

## [1.10.0] - 2026-03-11

### Added

- カスタムメソッド自動移行機能
  - 再生成時に既存リポジトリファイルのカスタムメソッドを検出
  - `*_repository.custom.dart` に extension として自動移行
  - `_client` → `client` の参照を自動置換
  - 既存 `.custom.dart` ファイルとのマージ対応（重複スキップ）
  - カスタム import も自動移行
  - `--no-migrate` フラグで移行スキップ可能

## [1.9.0] - 2026-03-11

### Added

- リポジトリクラスに `client` getter を追加（extension でカスタムメソッドを追加可能に）
  - 再生成時にカスタムコードが消える問題を解消
  - カスタムメソッドは `*_repository.custom.dart` に extension として記述

### Fixed

- TS型抽出器が `statusMap: Record<string, number>` パターンからエラーコードを検出できないバグを修正
  - `error: data.error` のような変数参照＋statusMap経由のエラーコードに対応
  - 既存のリテラル `error: "..."` パターンとマージして重複排除

## [1.8.4] - 2026-03-11

### Changed

- Bumped `supabase_schema_core` dependency to `^1.4.0` (enum type support)

## [1.8.3] - 2026-03-05

### Fixed

- Edge Function エラークラスの `fromFunctionException` で `e.details` が `Map<String, dynamic>` の場合に `as String` キャストで実行時エラーになるバグを修正
  - Supabase SDK が JSON レスポンスを自動デコードし `Map<String, dynamic>` を返す場合に対応
  - `e.details` の実際の型を switch 式で判定し、`String`（未デコード）と `Map<String, dynamic>`（デコード済み）の両方に対応

## [1.8.2] - 2026-03-04

### Fixed

- Edge Function クライアントの `response.data` 型キャストエラーを修正
  - Supabase SDK が `Content-Type: application/json` のレスポンスを自動デコードし `Map<String, dynamic>` を返す場合、`as List<int>` キャストで実行時エラーが発生していた
  - `response.data` の実際の型を動的に判定し、`List<int>`（バイト列）と `Map<String, dynamic>`（デコード済み）の両方に対応

## [1.8.1] - 2026-03-03

### Fixed

- `fromRow()` の DateTime 型フィールドで `as DateTime` キャストが実行時エラーになるバグを修正
  - Supabase RPC の JSON レスポンスではタイムスタンプが文字列として返されるため、`DateTime.parse(row['col'] as String)` に変更

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

- READMEのエラー型生成セクションのコード例を汎用的な例に修正

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
