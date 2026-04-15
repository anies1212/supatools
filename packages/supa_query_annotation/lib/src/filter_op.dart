/// Supported PostgREST filter operators.
enum FilterOp {
  /// Equal (`=`)
  eq,

  /// Not equal (`!=`)
  neq,

  /// Less than (`<`)
  lt,

  /// Less than or equal (`<=`)
  lte,

  /// Greater than (`>`)
  gt,

  /// Greater than or equal (`>=`)
  gte,

  /// Pattern match (`LIKE`)
  like,

  /// Case-insensitive pattern match (`ILIKE`)
  ilike,

  /// Identity check (`IS`)
  is_,

  /// Inclusion check (`IN`)
  in_,

  /// Array contains (`@>`)
  contains,

  /// Array overlap (`&&`)
  overlaps,
}
