/// A reference to a runtime value in a [SupaQuery] filter.
///
/// Use [Param] as a filter value to indicate that the actual value
/// will be provided as a method parameter at call time.
///
/// ```dart
/// @SupaQuery(filters: [
///   Filter.eq('user_id', Param('userId')),
///   Filter.lte('started_at', Param.now),
/// ])
/// Future<List<MyModel>> getByUser();
/// ```
///
/// The generator adds `String userId` (or the appropriate type) as
/// a method parameter automatically.
class Param {
  /// The parameter name, which becomes the Dart method parameter name.
  final String name;

  /// Creates a parameter reference with the given [name].
  const Param(this.name);

  /// A special parameter that resolves to `DateTime.now().toUtc().toIso8601String()`
  /// at call time. No method parameter is generated for this.
  static const now = Param('__now__');
}
