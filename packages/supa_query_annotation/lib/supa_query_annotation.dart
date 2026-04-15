/// Dart annotations for declarative Supabase custom queries.
///
/// This package provides annotations that suparepo uses to generate
/// PostgREST query implementations from method stubs in `.custom.dart`
/// extension files.
///
/// ## Quick Start
///
/// 1. Add this package as a dependency:
/// ```yaml
/// dependencies:
///   supa_query_annotation: ^0.1.0
/// ```
///
/// 2. Annotate method stubs in your `.custom.dart` file:
/// ```dart
/// import 'package:supa_query_annotation/supa_query_annotation.dart';
///
/// extension HomeBannersRepositoryCustom on HomeBannersRepository {
///   @SupaQuery(
///     filters: [
///       Filter.eq('is_active', true),
///       Filter.lte('started_at', Param.now),
///       Filter.gt('ended_at', Param.now),
///     ],
///     order: [OrderBy('sort_order')],
///   )
///   Future<List<HomeBanners>> getActive() =>
///       throw UnimplementedError();
/// }
/// ```
///
/// 3. Run suparepo to generate the implementation:
/// ```bash
/// dart run suparepo
/// ```
library;

export 'src/filter.dart';
export 'src/filter_op.dart';
export 'src/order_by.dart';
export 'src/param.dart';
export 'src/return_mode.dart';
export 'src/supa_query.dart';
