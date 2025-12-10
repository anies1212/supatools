# supafreeze

Generate [Freezed](https://pub.dev/packages/freezed) models from your Supabase database schema automatically.

## Features

- Fetches table schema directly from Supabase PostgreSQL database
- Generates type-safe Freezed models with `fromJson`/`toJson`
- **build_runner integration** - runs before freezed/json_serializable
- **Smart caching** - only regenerates when DB schema changes
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
  supafreeze: ^0.1.0
  build_runner: ^2.4.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
```

## Quick Start

### 1. Create configuration files

Create `supafreeze.yaml` in your project root:

```yaml
# supafreeze.yaml (commit this to git)
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
schema: public
```

Create `.env` file for your credentials:

```bash
# .env (add to .gitignore!)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=your-secret-key
```

### 2. Run build_runner

```bash
dart run build_runner build
```

That's it! supafreeze will:
1. Detect `supafreeze.yaml` and fetch your Supabase schema
2. Generate individual model files in `lib/models/` (one file per table)
3. Then freezed/json_serializable will generate `.freezed.dart` and `.g.dart` files

### 3. Use the generated models

```dart
import 'package:your_app/models/users.supafreeze.dart';

final user = Users(id: '123', name: 'John', createdAt: DateTime.now());
final json = user.toJson();
```

### 4. Subsequent builds

On subsequent runs, supafreeze checks if the DB schema has changed:
- **No changes**: Skips code generation (fast!)
- **Schema changed**: Regenerates models with new schema

```bash
# This will be fast if schema hasn't changed
dart run build_runner build
```

## Configuration

### Variable References

supafreeze supports multiple ways to reference sensitive values:

```yaml
# supafreeze.yaml

# Auto-resolve: checks dart-define > .env > environment variables
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}

# Explicit environment variable
url: $env{SUPABASE_URL}

# Explicit .env file variable
secret_key: $dotenv{SUPABASE_SECRET_KEY}
```

### Priority Order

Values are resolved in this order (highest priority first):
1. dart-define (`--dart-define=SUPABASE_SECRET_KEY=xxx`)
2. `.env` file
3. Environment variables

### Fetch Mode

Control when supafreeze connects to Supabase:

```yaml
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models

# Options: always | if_no_cache | never
fetch: if_no_cache
```

| Mode | Description |
|------|-------------|
| `always` | Always fetch from database (default) |
| `if_no_cache` | Only fetch if no cache exists, otherwise use cache |
| `never` | Never fetch, always use cache (offline mode) |

**Use cases:**
- `always`: Development with frequently changing schema
- `if_no_cache`: CI/CD pipelines where schema is stable
- `never`: Offline development or when Supabase is unavailable

**Environment-based fetch mode:**

You can use environment variables to switch fetch mode between local and CI:

```yaml
# supafreeze.yaml
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
fetch: ${SUPAFREEZE_FETCH}
```

```bash
# .env (local development)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SECRET_KEY=your-secret-key
SUPAFREEZE_FETCH=always
```

```yaml
# CI environment variables
SUPAFREEZE_FETCH=never
```

This allows you to fetch from DB locally while using cached schema in CI/CD.

### Table Filtering

Include only specific tables:

```yaml
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models

include:
  - users
  - posts
  - comments
```

Or exclude tables:

```yaml
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models

exclude:
  - _migrations
  - schema_versions
  - audit_logs
```

### Barrel File

By default, supafreeze generates individual model files without a barrel file. If you want a barrel file that exports all models, enable it:

```yaml
url: ${SUPABASE_URL}
secret_key: ${SUPABASE_SECRET_KEY}
output: lib/models
generate_barrel: true
```

This will generate `lib/models/models.dart`:

```dart
export 'users.supafreeze.dart';
export 'posts.supafreeze.dart';
```

## Generated Output

For tables like:

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  user_id UUID NOT NULL
);
```

supafreeze generates individual files in `lib/models/`:

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

**`lib/models/posts.supafreeze.dart`**
```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:freezed_annotation/freezed_annotation.dart';

part 'posts.supafreeze.freezed.dart';
part 'posts.supafreeze.g.dart';

@freezed
class Posts with _$Posts {
  const factory Posts({
    required String id,
    required String title,
    @JsonKey(name: 'user_id') required String userId,
  }) = _Posts;

  factory Posts.fromJson(Map<String, dynamic> json) => _$PostsFromJson(json);
}
```

## How Caching Works

supafreeze stores per-table hashes in `.dart_tool/supafreeze/`:
- `table_hashes.json` - SHA256 hash for each table
- `schema_cache.json` - Cached schema data

### Per-Table Incremental Generation

supafreeze tracks each table individually. When schema changes:
- Only modified tables are regenerated
- Unchanged tables are skipped
- Deleted tables have their files automatically removed

When you run build_runner with `fetch: always` (default):
1. Fetches current schema from Supabase
2. Computes hash for each table and compares with cached hashes
3. Generates only changed/new tables, removes deleted tables
4. Updates cache for affected tables

**Important:** With `fetch: always`, API request occurs every time. To skip API requests entirely, use `fetch: if_no_cache` or `fetch: never`.

### Using Cache in CI/CD (GitHub Actions)

To use cached schema in CI without hitting Supabase API:

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
          key: supafreeze-${{ hashFiles('.dart_tool/supafreeze/table_hashes.json') }}
          restore-keys: |
            supafreeze-

      - run: flutter pub get

      # Use fetch: never in CI to skip API requests
      - name: Run build_runner
        run: dart run build_runner build --delete-conflicting-outputs
        env:
          SUPAFREEZE_FETCH: never
```

**Workflow:**
1. First, run `dart run build_runner build` locally with `fetch: always` to generate cache
2. Commit `.dart_tool/supafreeze/` to your repository, or let CI cache it after the first run
3. CI restores the cache and uses `fetch: never` to skip API requests

**Alternative: Commit cache to repository**

If you prefer not to rely on CI cache, you can commit the schema cache directly:

```bash
# .gitignore
.dart_tool/

# But keep supafreeze cache
!.dart_tool/supafreeze/
```

This ensures CI always has access to the cached schema without needing Supabase credentials.

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

## Troubleshooting

### Schema fetch fails

If supafreeze can't connect to Supabase, it will attempt to use the cached schema. If no cache exists, generation will be skipped.

### Force regeneration

Delete the cache directory to force regeneration:

```bash
rm -rf .dart_tool/supafreeze
dart run build_runner build
```

### Environment variables not working

Make sure your `.env` file:
- Is in the project root directory
- Has no spaces around `=` signs
- Values with spaces are quoted: `KEY="value with spaces"`

## License

MIT
