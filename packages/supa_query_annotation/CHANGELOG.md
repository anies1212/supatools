# Changelog

## [0.1.0] - 2026-04-15

### Added

- Initial release
- `@SupaQuery` annotation for declarative Supabase custom queries
- `Filter` class with named constructors for all PostgREST operators (`eq`, `neq`, `lt`, `lte`, `gt`, `gte`, `like`, `ilike`, `is_`, `in_`, `contains`, `overlaps`)
- `Param` class for runtime value injection (`Param('name')` and `Param.now`)
- `OrderBy` / `OrderBy.desc` for sort clauses with `nullsFirst` option
- `ReturnMode` enum (`list`, `single`, `maybeSingle`)
