/// Declares a sort order for a [SupaQuery].
///
/// ```dart
/// @SupaQuery(
///   order: [OrderBy('created_at'), OrderBy.desc('sort_order')],
/// )
/// ```
class OrderBy {
  /// The database column to sort by.
  final String column;

  /// Whether to sort in ascending order. Defaults to `true`.
  final bool ascending;

  /// Whether nulls should appear first. Defaults to `false`.
  final bool nullsFirst;

  /// Creates an ascending order clause for [column].
  const OrderBy(this.column, {this.ascending = true, this.nullsFirst = false});

  /// Creates a descending order clause for [column].
  const OrderBy.desc(this.column, {this.nullsFirst = false})
      : ascending = false;
}
