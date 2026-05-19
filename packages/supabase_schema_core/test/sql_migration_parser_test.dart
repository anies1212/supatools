import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:test/test.dart';

void main() {
  group('SqlMigrationParser.parseFunctions', () {
    test('parses RETURNS BOOLEAN scalar function', () {
      const sql = '''
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS \$\$
BEGIN
  RETURN false;
END;
\$\$ LANGUAGE plpgsql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, contains('is_admin'));
      expect(result['is_admin']!.returnType, 'bool');
      expect(result['is_admin']!.returnsSetOf, isFalse);
      expect(result['is_admin']!.tableColumns, isNull);
    });

    test('parses RETURNS TEXT scalar function', () {
      const sql = '''
CREATE OR REPLACE FUNCTION ingest_event_atomic(
  p_event_id UUID,
  p_payload JSONB
) RETURNS TEXT
LANGUAGE plpgsql AS \$\$
BEGIN
  RETURN 'ok';
END;
\$\$;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, contains('ingest_event_atomic'));
      expect(result['ingest_event_atomic']!.returnType, 'text');
      expect(result['ingest_event_atomic']!.returnsSetOf, isFalse);
    });

    test('parses RETURNS TABLE with multiple columns', () {
      const sql = '''
CREATE OR REPLACE FUNCTION public.register_auth_user(
  p_provider TEXT,
  p_provider_user_id TEXT,
  p_intent TEXT
)
RETURNS TABLE (
  user_id UUID,
  auth_identity_id UUID,
  is_new_user BOOLEAN
) AS \$\$
BEGIN
END;
\$\$ LANGUAGE plpgsql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, contains('register_auth_user'));
      final info = result['register_auth_user']!;
      expect(info.returnsSetOf, isTrue);
      expect(info.tableColumns, hasLength(3));
      expect(info.tableColumns![0].name, 'user_id');
      expect(info.tableColumns![0].dataType, 'uuid');
      expect(info.tableColumns![1].name, 'auth_identity_id');
      expect(info.tableColumns![1].dataType, 'uuid');
      expect(info.tableColumns![2].name, 'is_new_user');
      expect(info.tableColumns![2].dataType, 'bool');
    });

    test('parses RETURNS SETOF composite type', () {
      const sql = '''
CREATE TYPE public.register_auth_user_result AS (
  user_id UUID,
  auth_identity_id UUID,
  is_new_user BOOLEAN
);

CREATE OR REPLACE FUNCTION public.register_auth_user(
  p_provider TEXT
)
RETURNS SETOF public.register_auth_user_result
LANGUAGE plpgsql AS \$\$
BEGIN
END;
\$\$;
''';

      final compositeTypes = SqlMigrationParser.parseCompositeTypes(sql);
      expect(compositeTypes, contains('register_auth_user_result'));
      expect(compositeTypes['register_auth_user_result'], hasLength(3));

      final result = SqlMigrationParser.parseFunctions(
        sql,
        compositeTypes: compositeTypes,
      );

      expect(result, contains('register_auth_user'));
      final info = result['register_auth_user']!;
      expect(info.returnsSetOf, isTrue);
      expect(info.tableColumns, hasLength(3));
      expect(info.tableColumns![0].name, 'user_id');
      expect(info.tableColumns![2].name, 'is_new_user');
      expect(info.tableColumns![2].dataType, 'bool');
    });

    test('parses multiple functions in one SQL file', () {
      const sql = '''
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS \$\$ BEGIN RETURN false; END; \$\$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.is_blocked(target_user_id UUID)
RETURNS BOOLEAN AS \$\$ BEGIN RETURN false; END; \$\$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.has_role(role_name TEXT)
RETURNS BOOLEAN AS \$\$ BEGIN RETURN false; END; \$\$ LANGUAGE plpgsql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, hasLength(3));
      expect(result.keys, containsAll(['is_admin', 'is_blocked', 'has_role']));
      expect(result['is_blocked']!.returnType, 'bool');
    });

    test('handles dollar-quoted bodies that contain semicolons', () {
      const sql = '''
CREATE OR REPLACE FUNCTION public.tricky(p UUID)
RETURNS UUID AS \$\$
BEGIN
  -- inline ; semicolons and -- comments inside dollar-quoted body
  RETURN p;
END;
\$\$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.next_func()
RETURNS TEXT AS \$\$ SELECT 'a' \$\$ LANGUAGE sql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, hasLength(2));
      expect(result['tricky']!.returnType, 'uuid');
      expect(result['next_func']!.returnType, 'text');
    });

    test('skips trigger functions', () {
      const sql = '''
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS \$\$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
\$\$ LANGUAGE plpgsql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, isEmpty);
    });

    test('ignores SQL comments and string literals', () {
      const sql = '''
-- CREATE OR REPLACE FUNCTION fake_in_comment() RETURNS BOOLEAN
/* CREATE OR REPLACE FUNCTION other_fake() RETURNS TEXT */
CREATE OR REPLACE FUNCTION real_one()
RETURNS BOOLEAN AS \$\$
BEGIN
  RAISE NOTICE 'CREATE OR REPLACE FUNCTION inside_string() RETURNS TEXT';
  RETURN false;
END;
\$\$ LANGUAGE plpgsql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, hasLength(1));
      expect(result, contains('real_one'));
    });

    test('normalizes type aliases', () {
      const sql = '''
CREATE OR REPLACE FUNCTION fa() RETURNS INTEGER AS \$\$ SELECT 1 \$\$ LANGUAGE sql;
CREATE OR REPLACE FUNCTION fb() RETURNS BIGINT AS \$\$ SELECT 1 \$\$ LANGUAGE sql;
CREATE OR REPLACE FUNCTION fc() RETURNS BOOLEAN AS \$\$ SELECT false \$\$ LANGUAGE sql;
CREATE OR REPLACE FUNCTION fd() RETURNS CHARACTER VARYING AS \$\$ SELECT '' \$\$ LANGUAGE sql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result['fa']!.returnType, 'int4');
      expect(result['fb']!.returnType, 'int8');
      expect(result['fc']!.returnType, 'bool');
      expect(result['fd']!.returnType, 'text');
    });

    test('handles function with no leading schema prefix', () {
      const sql = '''
CREATE OR REPLACE FUNCTION my_func() RETURNS UUID AS \$\$ SELECT gen_random_uuid() \$\$ LANGUAGE sql;
''';

      final result = SqlMigrationParser.parseFunctions(sql);

      expect(result, contains('my_func'));
      expect(result['my_func']!.returnType, 'uuid');
    });
  });

  group('SqlMigrationParser.parseCompositeTypes', () {
    test('parses simple composite type', () {
      const sql = '''
CREATE TYPE my_result AS (
  id UUID,
  count INTEGER,
  active BOOLEAN
);
''';

      final result = SqlMigrationParser.parseCompositeTypes(sql);

      expect(result, contains('my_result'));
      final cols = result['my_result']!;
      expect(cols, hasLength(3));
      expect(cols[0].name, 'id');
      expect(cols[0].dataType, 'uuid');
      expect(cols[1].name, 'count');
      expect(cols[1].dataType, 'int4');
      expect(cols[2].name, 'active');
      expect(cols[2].dataType, 'bool');
    });

    test('skips CREATE TYPE AS ENUM', () {
      const sql = '''
CREATE TYPE auth_provider AS ENUM ('apple', 'google', 'line');
CREATE TYPE composite_result AS (
  field_a TEXT
);
''';

      final result = SqlMigrationParser.parseCompositeTypes(sql);

      expect(result, hasLength(1));
      expect(result, contains('composite_result'));
      expect(result, isNot(contains('auth_provider')));
    });

    test('handles schema-prefixed type names', () {
      const sql = '''
CREATE TYPE public.my_result AS (
  id UUID,
  flag BOOLEAN
);
''';

      final result = SqlMigrationParser.parseCompositeTypes(sql);

      // Implementation keys by the unqualified name
      expect(result, contains('my_result'));
      expect(result['my_result'], hasLength(2));
    });
  });
}
