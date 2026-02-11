# Changelog

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
