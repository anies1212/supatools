/// How a [SupaQuery] method returns its result.
enum ReturnMode {
  /// Returns `List<T>` (default).
  list,

  /// Returns `T` (throws if not found).
  single,

  /// Returns `T?` (null if not found).
  maybeSingle,
}
