import 'dart:io';
import 'package:test/test.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';
import 'package:supafreeze/src/schema_cache.dart';

void main() {
  group('SchemaCache', () {
    late Directory tempDir;
    late SchemaCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('supafreeze_cache_test_');
      cache = SchemaCache(cacheDir: tempDir.path);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    group('cacheSchema', () {
      test('saves schema to cache file', () async {
        final tables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
              ColumnInfo(name: 'name', dataType: 'text', isNullable: false),
            ],
          ),
        ];

        await cache.cacheSchema(tables);

        final cacheFile = File('${tempDir.path}/schema_cache.json');
        expect(await cacheFile.exists(), isTrue);
      });
    });

    group('loadCachedSchema', () {
      test('returns null when cache does not exist', () async {
        final result = await cache.loadCachedSchema();
        expect(result, isNull);
      });

      test('loads cached schema correctly', () async {
        final tables = [
          TableInfo(
            name: 'posts',
            columns: [
              ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
              ColumnInfo(name: 'title', dataType: 'text', isNullable: false),
              ColumnInfo(
                name: 'content',
                dataType: 'text',
                isNullable: true,
                defaultValue: "''",
              ),
            ],
          ),
        ];

        await cache.cacheSchema(tables);
        final loaded = await cache.loadCachedSchema();

        expect(loaded, isNotNull);
        expect(loaded!.length, 1);
        expect(loaded[0].name, 'posts');
        expect(loaded[0].columns.length, 3);
        expect(loaded[0].columns[0].name, 'id');
        expect(loaded[0].columns[0].dataType, 'int4');
        expect(loaded[0].columns[0].isNullable, false);
      });
    });

    group('computeDiff', () {
      test('detects new tables', () async {
        final tables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
        ];

        final diff = await cache.computeDiff(tables);

        expect(diff.hasChanges, isTrue);
        expect(diff.tablesToGenerate.length, 1);
        expect(diff.tablesToGenerate[0].name, 'users');
        expect(diff.tablesToRemove, isEmpty);
      });

      test('detects no changes when tables unchanged', () async {
        final tables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
        ];

        // First save
        await cache.cacheSchema(tables);
        await cache.updateTableHashes(tables);

        // Check diff with same tables
        final diff = await cache.computeDiff(tables);

        expect(diff.hasChanges, isFalse);
        expect(diff.tablesToGenerate, isEmpty);
        expect(diff.tablesToRemove, isEmpty);
      });

      test('detects modified tables', () async {
        final originalTables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
        ];

        // First save
        await cache.cacheSchema(originalTables);
        await cache.updateTableHashes(originalTables);

        // Modified tables (new column)
        final modifiedTables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
              ColumnInfo(name: 'email', dataType: 'text', isNullable: true),
            ],
          ),
        ];

        final diff = await cache.computeDiff(modifiedTables);

        expect(diff.hasChanges, isTrue);
        expect(diff.tablesToGenerate.length, 1);
        expect(diff.tablesToGenerate[0].name, 'users');
      });

      test('detects removed tables', () async {
        final originalTables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
          TableInfo(
            name: 'posts',
            columns: [
              ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
            ],
          ),
        ];

        await cache.cacheSchema(originalTables);
        await cache.updateTableHashes(originalTables);

        // Only users table remains
        final newTables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
        ];

        final diff = await cache.computeDiff(newTables);

        expect(diff.hasChanges, isTrue);
        expect(diff.tablesToRemove, contains('posts'));
      });
    });

    group('removeTableHash', () {
      test('removes hash for specific table', () async {
        final tables = [
          TableInfo(
            name: 'users',
            columns: [
              ColumnInfo(name: 'id', dataType: 'uuid', isNullable: false),
            ],
          ),
          TableInfo(
            name: 'posts',
            columns: [
              ColumnInfo(name: 'id', dataType: 'int4', isNullable: false),
            ],
          ),
        ];

        await cache.updateTableHashes(tables);
        await cache.removeTableHash('posts');

        // Now posts should be detected as new
        final diff = await cache.computeDiff([tables[1]]);
        expect(diff.tablesToGenerate.any((t) => t.name == 'posts'), isTrue);
      });
    });
  });

  group('SchemaDiff', () {
    test('hasChanges returns true when tables to generate', () {
      final diff = SchemaDiff(
        tablesToGenerate: [
          TableInfo(name: 'users', columns: []),
        ],
        tablesToRemove: [],
      );

      expect(diff.hasChanges, isTrue);
    });

    test('hasChanges returns true when tables to remove', () {
      final diff = SchemaDiff(
        tablesToGenerate: [],
        tablesToRemove: ['old_table'],
      );

      expect(diff.hasChanges, isTrue);
    });

    test('hasChanges returns false when no changes', () {
      final diff = SchemaDiff(
        tablesToGenerate: [],
        tablesToRemove: [],
      );

      expect(diff.hasChanges, isFalse);
    });
  });
}
