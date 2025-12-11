import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/freezed_generator.dart';
import 'package:supafreeze/src/config_loader.dart';

void main() {
  group('ForeignKeyInfo', () {
    test('creates FK info correctly', () {
      const fk = ForeignKeyInfo(
        column: 'user_id',
        referencedTable: 'users',
        referencedColumn: 'id',
      );

      expect(fk.column, 'user_id');
      expect(fk.referencedTable, 'users');
      expect(fk.referencedColumn, 'id');
      expect(fk.isOneToOne, false);
    });
  });

  group('ColumnInfo with FK', () {
    test('holds foreign key reference', () {
      final column = ColumnInfo(
        name: 'user_id',
        dataType: 'int8',
        isNullable: false,
        foreignKey: const ForeignKeyInfo(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
        ),
      );

      expect(column.foreignKey, isNotNull);
      expect(column.foreignKey!.referencedTable, 'users');
    });

    test('copyWith preserves FK', () {
      final original = ColumnInfo(
        name: 'user_id',
        dataType: 'int8',
        isNullable: false,
        foreignKey: const ForeignKeyInfo(
          column: 'user_id',
          referencedTable: 'users',
          referencedColumn: 'id',
        ),
      );

      final copy = original.copyWith();
      expect(copy.foreignKey, isNotNull);
      expect(copy.foreignKey!.referencedTable, 'users');
    });
  });

  group('TableInfo foreignKeys', () {
    test('returns all FKs in table', () {
      final table = TableInfo(
        name: 'posts',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'author_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'author_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ),
          ColumnInfo(
            name: 'category_id',
            dataType: 'int8',
            isNullable: true,
            foreignKey: const ForeignKeyInfo(
              column: 'category_id',
              referencedTable: 'categories',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      expect(table.foreignKeys.length, 2);
      expect(table.foreignKeys[0].referencedTable, 'users');
      expect(table.foreignKeys[1].referencedTable, 'categories');
    });
  });

  group('FreezedGenerator with relations', () {
    late FreezedGenerator generator;

    setUp(() {
      generator = FreezedGenerator();
    });

    test('generates relation import when FK exists', () {
      final users = TableInfo(
        name: 'users',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          const ColumnInfo(name: 'name', dataType: 'text', isNullable: false),
        ],
      );

      final wallet = TableInfo(
        name: 'wallet',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'user_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      generator.setAllTables([users, wallet]);
      generator.setConfig(const SupafreezeConfig(embedRelations: true));

      final result = generator.generateModel(wallet);

      expect(result, contains("import 'users.supafreeze.dart'"));
      expect(result, contains('Users? user,'));
    });

    test('does not generate relation when embedRelations is false', () {
      final users = TableInfo(
        name: 'users',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
        ],
      );

      final wallet = TableInfo(
        name: 'wallet',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'user_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      generator.setAllTables([users, wallet]);
      generator.setConfig(const SupafreezeConfig(embedRelations: false));

      final result = generator.generateModel(wallet);

      expect(result, isNot(contains("import 'users.supafreeze.dart'")));
      expect(result, isNot(contains('Users? user,')));
    });

    test('respects relation override to disable', () {
      final users = TableInfo(
        name: 'users',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
        ],
      );

      final wallet = TableInfo(
        name: 'wallet',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'user_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      generator.setAllTables([users, wallet]);
      generator.setConfig(SupafreezeConfig(
        embedRelations: true,
        relations: {
          'wallet': RelationConfig(
            overrides: {'user': RelationOverride.disabled()},
          ),
        },
      ));

      final result = generator.generateModel(wallet);

      expect(result, isNot(contains('Users? user,')));
    });

    test('does not generate relation when referenced table not found', () {
      final wallet = TableInfo(
        name: 'wallet',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'user_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'user_id',
              referencedTable: 'users', // users table doesn't exist
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      // Only wallet table, no users table
      generator.setAllTables([wallet]);
      generator.setConfig(const SupafreezeConfig(embedRelations: true));

      final result = generator.generateModel(wallet);

      expect(result, isNot(contains('Users? user,')));
    });

    test('handles multiple FK relations', () {
      final users = TableInfo(
        name: 'users',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
        ],
      );

      final categories = TableInfo(
        name: 'categories',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
        ],
      );

      final posts = TableInfo(
        name: 'posts',
        columns: [
          const ColumnInfo(name: 'id', dataType: 'int8', isNullable: false),
          ColumnInfo(
            name: 'author_id',
            dataType: 'int8',
            isNullable: false,
            foreignKey: const ForeignKeyInfo(
              column: 'author_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ),
          ColumnInfo(
            name: 'category_id',
            dataType: 'int8',
            isNullable: true,
            foreignKey: const ForeignKeyInfo(
              column: 'category_id',
              referencedTable: 'categories',
              referencedColumn: 'id',
            ),
          ),
        ],
      );

      generator.setAllTables([users, categories, posts]);
      generator.setConfig(const SupafreezeConfig(embedRelations: true));

      final result = generator.generateModel(posts);

      expect(result, contains("import 'users.supafreeze.dart'"));
      expect(result, contains("import 'categories.supafreeze.dart'"));
      expect(result, contains('Users? author,'));
      expect(result, contains('Categories? category,'));
    });
  });

  group('RelationConfig', () {
    test('isEnabled returns true by default', () {
      const config = RelationConfig();
      expect(config.isEnabled('user'), true);
      expect(config.isEnabled('any_relation'), true);
    });

    test('isEnabled returns false when disabled', () {
      final config = RelationConfig(
        overrides: {'user': RelationOverride.disabled()},
      );
      expect(config.isEnabled('user'), false);
      expect(config.isEnabled('other'), true);
    });
  });

  group('SupafreezeConfig relations', () {
    test('shouldEmbedRelation returns false by default', () {
      const config = SupafreezeConfig();
      expect(config.shouldEmbedRelation('wallet', 'user'), false);
    });

    test('shouldEmbedRelation returns true when embedRelations is true', () {
      const config = SupafreezeConfig(embedRelations: true);
      expect(config.shouldEmbedRelation('wallet', 'user'), true);
    });

    test('shouldEmbedRelation respects per-table config', () {
      final config = SupafreezeConfig(
        embedRelations: true,
        relations: {
          'wallet': RelationConfig(
            overrides: {'user': RelationOverride.disabled()},
          ),
        },
      );
      expect(config.shouldEmbedRelation('wallet', 'user'), false);
      expect(config.shouldEmbedRelation('wallet', 'other'), true);
      expect(config.shouldEmbedRelation('posts', 'user'), true);
    });
  });
}
