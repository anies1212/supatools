# Supatools

A monorepo containing Dart packages for Supabase code generation.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [supabase_schema_core](packages/supabase_schema_core) | Internal package for schema fetching and type mapping | [![pub](https://img.shields.io/pub/v/supabase_schema_core.svg)](https://pub.dev/packages/supabase_schema_core) |
| [supafreeze](packages/supafreeze) | Generate Freezed or dart_mappable models from Supabase schema | [![pub](https://img.shields.io/pub/v/supafreeze.svg)](https://pub.dev/packages/supafreeze) |
| [suparepo](packages/suparepo) | Generate repositories, RPC clients, and Edge Function clients | [![pub](https://img.shields.io/pub/v/suparepo.svg)](https://pub.dev/packages/suparepo) |

## Quick Start

### Generate Models (Freezed or dart_mappable)

```bash
dart pub add supafreeze
```

Generates Freezed models by default; set `model_format: dart_mappable` in
`supafreeze.yaml` to generate dart_mappable models instead. See the
[supafreeze README](packages/supafreeze/README.md) for details.

### Generate Repositories, RPC & Edge Function Clients

```bash
dart pub add suparepo
```

suparepo generates:
- **Table repositories** — CRUD operations, pagination, relation queries
- **RPC clients** — Type-safe methods for Supabase SQL functions
- **Edge Function clients** — Typed or untyped clients for Edge Functions

See [suparepo README](packages/suparepo/README.md) for details.

## Development

This repository uses [melos](https://pub.dev/packages/melos) for managing the monorepo.

### Setup

```bash
dart pub global activate melos
melos bootstrap
```

### Common Commands

```bash
# Analyze all packages
melos exec -- dart analyze .

# Format all packages
melos exec -- dart format .

# Run tests in all packages
melos exec -- dart test
```

## License

MIT
