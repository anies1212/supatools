# supabase_schema_core

Internal package for Supabase schema fetching and type mapping.

> **Note**: This package is used internally by [supafreeze](https://pub.dev/packages/supafreeze) and [suparepo](https://pub.dev/packages/suparepo). It is not intended for direct use.

## Features

- Schema fetching from Supabase OpenAPI spec
- PostgreSQL to Dart type mapping (`TypeMapper`)
- PostgreSQL enum type fetching from `pg_enum` catalog (`EnumInfo`)
- RPC function detection and return type correction via `pg_proc`
- Foreign key detection from column naming conventions
- Base configuration loader with environment variable support

## Usage

If you want to generate Freezed models from Supabase, use [supafreeze](https://pub.dev/packages/supafreeze).

If you want to generate repository/data access code, use [suparepo](https://pub.dev/packages/suparepo).
