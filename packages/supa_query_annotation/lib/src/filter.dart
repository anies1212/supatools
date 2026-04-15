import 'filter_op.dart';

/// Declares a PostgREST filter to apply in a [SupaQuery].
///
/// Use the named constructors for a concise, readable syntax:
///
/// ```dart
/// @SupaQuery(filters: [
///   Filter.eq('is_active', true),
///   Filter.gte('created_at', Param('startDate')),
/// ])
/// ```
class Filter {
  /// The database column name.
  final String column;

  /// The filter operator.
  final FilterOp operator;

  /// The filter value.
  ///
  /// Can be a literal (`true`, `42`, `'text'`) or a [Param] reference.
  final Object? value;

  /// Creates a filter with the given [column], [operator], and [value].
  const Filter(this.column, this.operator, this.value);

  /// `column = value`
  const Filter.eq(this.column, this.value) : operator = FilterOp.eq;

  /// `column != value`
  const Filter.neq(this.column, this.value) : operator = FilterOp.neq;

  /// `column < value`
  const Filter.lt(this.column, this.value) : operator = FilterOp.lt;

  /// `column <= value`
  const Filter.lte(this.column, this.value) : operator = FilterOp.lte;

  /// `column > value`
  const Filter.gt(this.column, this.value) : operator = FilterOp.gt;

  /// `column >= value`
  const Filter.gte(this.column, this.value) : operator = FilterOp.gte;

  /// `column LIKE value`
  const Filter.like(this.column, this.value) : operator = FilterOp.like;

  /// `column ILIKE value`
  const Filter.ilike(this.column, this.value) : operator = FilterOp.ilike;

  /// `column IS value` (typically `null` or `true`/`false`)
  const Filter.is_(this.column, this.value) : operator = FilterOp.is_;

  /// `column IN value` (value should be a `List`)
  const Filter.in_(this.column, this.value) : operator = FilterOp.in_;

  /// `column @> value` (array contains)
  const Filter.contains(this.column, this.value) : operator = FilterOp.contains;

  /// `column && value` (array overlap)
  const Filter.overlaps(this.column, this.value) : operator = FilterOp.overlaps;
}
