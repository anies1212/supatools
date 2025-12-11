# Supatools

A monorepo containing Dart packages for Supabase code generation.

## Packages

| Package | Description | pub.dev |
|---------|-------------|---------|
| [supabase_schema_core](packages/supabase_schema_core) | Internal package for schema fetching and type mapping | [![pub](https://img.shields.io/pub/v/supabase_schema_core.svg)](https://pub.dev/packages/supabase_schema_core) |
| [supafreeze](packages/supafreeze) | Generate Freezed models from Supabase schema | [![pub](https://img.shields.io/pub/v/supafreeze.svg)](https://pub.dev/packages/supafreeze) |
| [suparepo](packages/suparepo) | Generate repository/data access code from Supabase schema | [![pub](https://img.shields.io/pub/v/suparepo.svg)](https://pub.dev/packages/suparepo) |

## Quick Start

### Generate Freezed Models

```bash
dart pub add supafreeze
```

See [supafreeze README](packages/supafreeze/README.md) for details.

### Generate Repository Code

```bash
dart pub add suparepo
```

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
