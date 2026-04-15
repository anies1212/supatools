# supa_query_annotation

Dart annotations for declarative Supabase custom queries. Used with [suparepo](https://pub.dev/packages/suparepo) for code generation.

## Installation

```yaml
dependencies:
  supa_query_annotation: ^0.1.0
```

## Usage

Annotate method stubs in `.custom.dart` extension files:

```dart
import 'package:supa_query_annotation/supa_query_annotation.dart';

extension HomeBannersRepositoryCustom on HomeBannersRepository {
  @SupaQuery(
    filters: [
      Filter.eq('is_active', true),
      Filter.lte('started_at', Param.now),
      Filter.gt('ended_at', Param.now),
    ],
    order: [OrderBy('sort_order')],
  )
  Future<List<HomeBanners>> getActive() =>
      throw UnimplementedError();
}
```

Run `dart run suparepo` to generate the implementation.

## Annotations

| Annotation | Description |
|---|---|
| `@SupaQuery` | Main annotation with `filters`, `order`, `limit`, `select`, `returnMode`, `resultModel` |
| `Filter.eq(col, val)` | PostgREST filter operators (`eq`, `neq`, `lt`, `lte`, `gt`, `gte`, `like`, `ilike`, `is_`, `in_`, `contains`, `overlaps`) |
| `Param('name')` | Runtime method parameter injection |
| `Param.now` | Runtime `DateTime.now().toUtc().toIso8601String()` |
| `OrderBy('col')` / `OrderBy.desc('col')` | Sort clause with optional `nullsFirst` |
| `ReturnMode.list` / `.single` / `.maybeSingle` | Return type control |

## License

MIT
