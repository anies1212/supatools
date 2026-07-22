# supafreeze

Generate [Freezed](https://pub.dev/packages/freezed) models from your Supabase database schema automatically.

## Features

- Fetches table schema directly from Supabase PostgreSQL database
- Generates type-safe models with `fromJson`/`toJson` — **Freezed** or **dart_mappable** (`model_format`)
- **CLI tool** for syncing schema changes
- **Smart caching** - only regenerates when DB schema changes
- **Relation embedding** - auto-detects foreign keys and embeds related models
- **Enum generation** - auto-generates Dart enum types from PostgreSQL enums via `pg_enum` catalog
- **Flexible configuration** - supports `.env`, environment variables, and dart-define
- Automatic PostgreSQL to Dart type mapping
- Handles nullable fields, primary keys, and default values
- snake_case to camelCase conversion with `@JsonKey` annotations
- Include/exclude specific tables

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0

dev_dependencies:
  supafreeze: ^2.0.0
  build_runner: ^2.4.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
```

## Quick Start

### 1. Create configuration files

Create `supafreeze.yaml` in your project root:

```yaml
# supafreeze.yaml (commit this to git)
url: ${SUPABASE_DATA_API_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
schema: public
```

Create `.env` file for your credentials:

```bash
# .env (add to .gitignore!)
SUPABASE_DATA_API_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=your-secret-key
```

### 2. Generate models

```bash
# Step 1: Fetch schema from Supabase and generate .supafreeze.dart files
dart run supafreeze:supafreeze

# Step 2: Run freezed/json_serializable to generate .freezed.dart and .g.dart files
dart run build_runner build
```

That's it! supafreeze will:
1. Connect to your Supabase database
2. Fetch the schema for all tables
3. Generate `*.supafreeze.dart` files in `lib/models/`
4. Then build_runner generates `.freezed.dart` and `.g.dart` files

### 3. Use the generated models

```dart
import 'package:your_app/models/users.supafreeze.dart';

final user = Users(id: '123', name: 'John', createdAt: DateTime.now());
final json = user.toJson();
```

### 4. When you modify the database schema

Whenever you add, modify, or delete tables in Supabase:

```bash
# Sync latest schema from Supabase
dart run supafreeze:supafreeze

# Regenerate freezed/json_serializable code
dart run build_runner build
```

## CLI Tool

The CLI tool is the primary way to sync your models with Supabase:

```bash
# Sync schema from Supabase (only generates changed models)
dart run supafreeze:supafreeze

# Force regenerate ALL models (ignores cache)
dart run supafreeze:supafreeze --force
dart run supafreeze:supafreeze -f
```

### How it works

1. **Fetches schema** from Supabase via the OpenAPI spec endpoint
2. **Compares** with locally cached schema to detect changes
3. **Generates** only the modified `*.supafreeze.dart` files
4. **Updates** the local cache

After running the CLI, always run `dart run build_runner build` to generate the `.freezed.dart` and `.g.dart` files.

### Why use the CLI tool?

- **Explicit control**: You decide when to sync with Supabase
- **Fast**: Only regenerates changed models
- **Works offline**: Use cached schema when Supabase is unavailable
- **CI/CD friendly**: Commit generated files and skip API calls in CI

## Configuration

### supafreeze.yaml

```yaml
# Required
url: ${SUPABASE_DATA_API_URL}           # Supabase Data API URL
secret_key: ${SUPABASE_SECRET_KEY}  # Supabase service role key

# Optional
output: lib/models             # Output directory (default: lib/models)
schema: public                 # PostgreSQL schema (default: public)
fetch: always                  # Fetch mode: always | if_no_cache | never
model_format: freezed          # Model style: freezed | dart_mappable (default: freezed)
generate_barrel: false         # Generate models.dart barrel file
embed_relations: false         # Auto-embed related models via FK

# Table filtering (use one or the other, not both)
include:                       # Only generate these tables
  - users
  - posts
exclude:                       # Skip these tables
  - _migrations
  - audit_logs
```

### Variable Resolution

supafreeze supports multiple ways to reference sensitive values:

```yaml
# Auto-resolve: checks dart-define > .env > environment variables
url: ${SUPABASE_DATA_API_URL}

# Explicit environment variable
url: $env{SUPABASE_DATA_API_URL}

# Explicit .env file variable
secret_key: $dotenv{SUPABASE_SECRET_KEY}
```

**Priority order** (highest first):
1. dart-define (`--dart-define=SUPABASE_SECRET_KEY=xxx`)
2. `.env` file
3. Environment variables

### Fetch Mode

| Mode | Description |
|------|-------------|
| `always` | Always fetch from database (default) |
| `if_no_cache` | Only fetch if no cache exists |
| `never` | Never fetch, always use cache (offline mode) |

### Model Format

By default supafreeze generates [Freezed](https://pub.dev/packages/freezed)
models. Set `model_format: dart_mappable` to generate
[dart_mappable](https://pub.dev/packages/dart_mappable) models instead.

```yaml
model_format: dart_mappable
```

Both formats expose the **same JSON API** —
`factory X.fromJson(Map<String, dynamic>)` and a `Map<String, dynamic> toJson()`
— so [suparepo](https://pub.dev/packages/suparepo) repositories work unchanged
with either format. The dart_mappable models omit the mixin's `toJson`/`toMap`
(via `generateMethods`) and provide their own `Map`-returning `toJson()`, while
still inheriting `copyWith`, `==`, `hashCode`, and `toString` from
dart_mappable.

Update your dependencies for the dart_mappable toolchain:

```yaml
dependencies:
  dart_mappable: ^4.2.0

dev_dependencies:
  supafreeze: ^2.3.0
  build_runner: ^2.4.0
  dart_mappable_builder: ^4.2.0
```

The generation workflow is identical (`dart run supafreeze:supafreeze` then
`dart run build_runner build`); build_runner emits `*.mapper.dart` part files
instead of `*.freezed.dart` / `*.g.dart`. When `generate_enums` is enabled the
enums are generated as `@MappableEnum` types.

## GitHub Actions

### Recommended: Commit generated files

The simplest approach is to commit the generated `*.supafreeze.dart` files to your repository:

```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'

      - run: flutter pub get

      # Generated .supafreeze.dart files are already in the repo
      # Just run build_runner for freezed/json_serializable
      - name: Run build_runner
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Run tests
        run: flutter test
```

**Local workflow:**
```bash
# When you change the database schema:
dart run supafreeze:supafreeze
dart run build_runner build
git add lib/models/
git commit -m "Update models from Supabase schema"
git push
```

### Alternative: Fetch from Supabase in CI

If you want CI to fetch the latest schema:

```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'

      - run: flutter pub get

      # Fetch schema from Supabase
      - name: Sync Supabase schema
        run: dart run supafreeze:supafreeze
        env:
          SUPABASE_DATA_API_URL: ${{ secrets.SUPABASE_DATA_API_URL }}
          SUPABASE_SECRET_KEY: ${{ secrets.SUPABASE_SECRET_KEY }}

      # Generate freezed/json_serializable code
      - name: Run build_runner
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Run tests
        run: flutter test
```

**Required secrets:**
- `SUPABASE_DATA_API_URL`: Your Supabase Data API URL
- `SUPABASE_SECRET_KEY`: Your Supabase service role key

### Alternative: Use cached schema in CI

If you don't want to expose Supabase credentials in CI:

```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'

      # Cache supafreeze schema
      - name: Cache supafreeze schema
        uses: actions/cache@v4
        with:
          path: .dart_tool/supafreeze
          key: supafreeze-${{ hashFiles('lib/models/*.supafreeze.dart') }}
          restore-keys: |
            supafreeze-

      - run: flutter pub get

      # Use cached schema (no API call)
      - name: Sync schema (from cache)
        run: dart run supafreeze:supafreeze
        env:
          SUPAFREEZE_FETCH: never

      - name: Run build_runner
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Run tests
        run: flutter test
```

**Setup:**
1. Run `dart run supafreeze:supafreeze` locally first
2. Commit the `.dart_tool/supafreeze/` directory, or let the CI cache it after the first successful run

To commit the cache:
```bash
# .gitignore
.dart_tool/
!.dart_tool/supafreeze/
```

## Relation Embedding

supafreeze can auto-detect foreign key relationships from `*_id` columns and embed related models. **Disabled by default.**

### Enable relation embedding

```yaml
url: ${SUPABASE_DATA_API_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
embed_relations: true
```

### Generated output

When enabled, if a `posts` table has a `user_id` column and a `users` table exists:

```dart
// posts.supafreeze.dart (auto-generated)
import 'users.supafreeze.dart';

@freezed
class Posts with _$Posts {
  const factory Posts({
    required String id,
    required String title,
    @JsonKey(name: 'user_id') required String userId,
    Users? user,  // ← Auto-embedded from user_id FK
  }) = _Posts;
}
```

### Using with Supabase queries

```dart
// Fetch posts with embedded user
final response = await supabase
  .from('posts')
  .select('*, user:users(*)');

final posts = (response as List)
  .map((json) => Posts.fromJson(json))
  .toList();

// Access the embedded user
print(posts.first.user?.name);
```

### Disable specific relations

```yaml
embed_relations: true
relations:
  posts:
    user: false      # Disable user embedding for posts table
  comments:
    author: false    # Disable author embedding for comments table
```

## Generated Output

For a table like:

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

supafreeze generates:

**`lib/models/users.supafreeze.dart`**
```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:freezed_annotation/freezed_annotation.dart';

part 'users.supafreeze.freezed.dart';
part 'users.supafreeze.g.dart';

@freezed
class Users with _$Users {
  const factory Users({
    required String id,
    required String name,
    String? email,
    @Default(true) bool isActive,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Users;

  factory Users.fromJson(Map<String, dynamic> json) => _$UsersFromJson(json);
}
```

## PostgreSQL Enum Generation

supafreeze can automatically generate Dart enum types from PostgreSQL enum types. This provides type-safe enum fields in your Freezed models instead of raw `String` values.

### Prerequisites

Requires the `execute_sql` RPC function in your Supabase project (see [suparepo README](https://pub.dev/packages/suparepo) for setup instructions). Without it, supafreeze falls back to OpenAPI spec detection, which may use `tableName_columnName` as enum type names instead of the actual PostgreSQL type name.

### Configuration

```yaml
# supafreeze.yaml
url: ${SUPABASE_DATA_API_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
generate_enums: true                    # Enable enum generation
enum_output: lib/models/enums           # Optional (default: {output}/enums)
```

### Example

For a PostgreSQL enum:

```sql
CREATE TYPE campaign_type AS ENUM ('normal', 'trial');

CREATE TABLE campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type campaign_type NOT NULL
);
```

supafreeze generates:

**`lib/models/enums/campaign_type.supafreeze.dart`**
```dart
enum CampaignType {
  normal('normal'),
  trial('trial');

  const CampaignType(this.value);
  final String value;

  String toJson() => value;
  static CampaignType fromJson(String json) =>
      values.firstWhere((e) => e.value == json);
}
```

**`lib/models/campaigns.supafreeze.dart`**
```dart
import 'enums/campaign_type.supafreeze.dart';

@freezed
abstract class Campaigns with _$Campaigns {
  const factory Campaigns({
    required String id,
    required CampaignType type,  // ← Dart enum, not String
  }) = _Campaigns;

  factory Campaigns.fromJson(Map<String, dynamic> json) =>
      _$CampaignsFromJson(json);
}
```

### Special enum values

supafreeze handles special characters in enum values:

| PostgreSQL value | Dart identifier |
|---|---|
| `in-progress` | `inProgress('in-progress')` |
| `123abc` | `$123abc('123abc')` |
| `class` (reserved word) | `class$('class')` |

### Generated files

When `generate_enums: true`:
- Enum files: `{enum_output}/{enum_name}.supafreeze.dart`
- Barrel file: `{enum_output}/enums.dart`

A barrel file `enums.dart` is always generated for convenience.

## Type Mapping

| PostgreSQL | Dart |
|------------|------|
| `int2`, `int4`, `int8`, `serial` | `int` |
| `float4`, `float8`, `numeric` | `double` |
| `text`, `varchar`, `char` | `String` |
| `bool`, `boolean` | `bool` |
| `timestamp`, `timestamptz`, `date` | `DateTime` |
| `uuid` | `String` |
| `json`, `jsonb` | `Map<String, dynamic>` |
| `text[]`, `int4[]`, etc. | `List<T>` |

## Caching

supafreeze stores per-table hashes in `.dart_tool/supafreeze/`:
- `table_hashes.json` - SHA256 hash for each table
- `schema_cache.json` - Full schema data

When you run `dart run supafreeze:supafreeze`:
1. Fetches current schema from Supabase
2. Computes hash for each table
3. Compares with cached hashes
4. Generates only changed/new tables
5. Removes files for deleted tables
6. Updates cache

## Troubleshooting

### Schema fetch fails

If supafreeze can't connect to Supabase, it will attempt to use the cached schema. If no cache exists, generation will fail.

```bash
# Use cached schema when offline
SUPAFREEZE_FETCH=never dart run supafreeze:supafreeze
```

### Force regeneration

```bash
# Force regenerate all models
dart run supafreeze:supafreeze --force
dart run build_runner build
```

Or delete the cache:

```bash
rm -rf .dart_tool/supafreeze
dart run supafreeze:supafreeze
dart run build_runner build
```

### Environment variables not working

Make sure your `.env` file:
- Is in the project root directory
- Has no spaces around `=` signs
- Values with spaces are quoted: `KEY="value with spaces"`

### Models out of sync with Supabase

Always run the CLI tool when you change your database schema:

```bash
dart run supafreeze:supafreeze
dart run build_runner build
```

## License

MIT
