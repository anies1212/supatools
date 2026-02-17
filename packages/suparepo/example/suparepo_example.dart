// ignore_for_file: avoid_print

/// Example: Using suparepo-generated repository code.
///
/// suparepo generates repository classes from your Supabase schema.
/// Run `dart run suparepo` to generate repositories, then use them:
///
/// ```yaml
/// # suparepo.yaml
/// url: ${SUPABASE_DATA_API_URL}
/// secret_key: ${SUPABASE_SECRET_KEY}
/// output: lib/repositories
/// model_import_prefix: package:myapp/
/// generate_providers: true
/// rpc:
///   enabled: true
/// ```
///
/// ```bash
/// dart run suparepo
/// ```
library;

// After running suparepo, generated code looks like:
//
// class UsersRepository {
//   final SupabaseClient _client;
//   UsersRepository(this._client);
//
//   Future<List<Users>> getAll() async { ... }
//   Future<Users?> getById(String id) async { ... }
//   Future<Users> create(Users data) async { ... }
//   Future<Users> update(String id, Users data) async { ... }
//   Future<void> delete(String id) async { ... }
//   Future<int> count() async { ... }
//   Future<List<Users>> paginate({int page, int perPage}) async { ... }
// }
//
// // With generate_providers: true
// @Riverpod(keepAlive: true)
// UsersRepository usersRepository(Ref ref) {
//   final client = ref.watch(supabaseClientProvider);
//   return UsersRepository(client);
// }

void main() {
  print('See README.md for usage instructions.');
  print('Run `dart run suparepo` to generate repositories.');
}
