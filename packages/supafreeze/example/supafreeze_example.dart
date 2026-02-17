// ignore_for_file: avoid_print

/// Example: Using supafreeze to generate Freezed models from Supabase.
///
/// supafreeze generates Freezed model classes from your Supabase schema.
///
/// ```yaml
/// # supafreeze.yaml
/// url: ${SUPABASE_DATA_API_URL}
/// secret_key: ${SUPABASE_SECRET_KEY}
/// output: lib/models
/// ```
///
/// ```bash
/// dart run supafreeze:supafreeze
/// dart run build_runner build
/// ```
library;

// After running supafreeze + build_runner, generated code looks like:
//
// @freezed
// class Users with _$Users {
//   const factory Users({
//     required String id,
//     required String name,
//     String? email,
//     @Default(true) bool isActive,
//     @JsonKey(name: 'created_at') required DateTime createdAt,
//   }) = _Users;
//
//   factory Users.fromJson(Map<String, dynamic> json) =>
//       _$UsersFromJson(json);
// }

void main() {
  print('See README.md for usage instructions.');
  print('Run `dart run supafreeze:supafreeze` to generate models.');
}
