import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:supabase_schema_core/supabase_schema_core.dart';

/// Result of comparing current schema with cached schema.
///
/// Contains information about which tables need to be regenerated
/// and which should be removed.
///
/// Example:
/// ```dart
/// final cache = SchemaCache();
/// final diff = await cache.computeDiff(currentTables);
///
/// if (diff.hasChanges) {
///   for (final table in diff.tablesToGenerate) {
///     // Generate model for modified/new table
///   }
///   for (final tableName in diff.tablesToRemove) {
///     // Delete model files for removed table
///   }
/// }
/// ```
class SchemaDiff {
  /// Tables that need to be regenerated (new or modified)
  final List<TableInfo> tablesToGenerate;

  /// Table names that were removed and need cleanup
  final List<String> tablesToRemove;

  /// Whether any changes were detected
  bool get hasChanges =>
      tablesToGenerate.isNotEmpty || tablesToRemove.isNotEmpty;

  const SchemaDiff({
    required this.tablesToGenerate,
    required this.tablesToRemove,
  });
}

/// Manages schema caching with per-table hash tracking.
///
/// Uses SHA256 hashes to detect changes at the table level,
/// enabling incremental generation where only modified tables
/// are regenerated.
///
/// Cache files are stored in `.dart_tool/supafreeze/`:
/// - `table_hashes.json` - Per-table SHA256 hashes
/// - `schema_cache.json` - Full schema data
///
/// Example:
/// ```dart
/// final cache = SchemaCache();
///
/// // Check what needs to be regenerated
/// final diff = await cache.computeDiff(currentTables);
/// if (!diff.hasChanges) {
///   print('No changes detected');
///   return;
/// }
///
/// // After generating models, update the cache
/// await cache.updateTableHashes(diff.tablesToGenerate);
/// await cache.cacheSchema(allTables);
/// ```
class SchemaCache {
  /// Directory where cache files are stored.
  final String cacheDir;

  /// Creates a new [SchemaCache] instance.
  ///
  /// [cacheDir] defaults to `.dart_tool/supafreeze`.
  SchemaCache({this.cacheDir = '.dart_tool/supafreeze'});

  String get _tableHashesFilePath => '$cacheDir/table_hashes.json';
  String get _schemaFilePath => '$cacheDir/schema_cache.json';

  /// Computes a hash for a single table
  String _computeTableHash(TableInfo table) {
    final buffer = StringBuffer();
    buffer.writeln('table:${table.name}');
    for (final column in table.columns) {
      buffer.writeln(
        '  column:${column.name}|${column.dataType}|${column.isNullable}|${column.isPrimaryKey}|${column.defaultValue}',
      );
    }
    final bytes = utf8.encode(buffer.toString());
    return sha256.convert(bytes).toString();
  }

  /// Compares current tables with cached hashes and returns a diff.
  ///
  /// Returns a [SchemaDiff] containing:
  /// - [SchemaDiff.tablesToGenerate] - New or modified tables
  /// - [SchemaDiff.tablesToRemove] - Tables that no longer exist
  ///
  /// This is the primary method for determining what needs to be regenerated.
  Future<SchemaDiff> computeDiff(List<TableInfo> currentTables) async {
    final cachedHashes = await _loadTableHashes();
    final tablesToGenerate = <TableInfo>[];
    final tablesToRemove = <String>[];

    // Check for new or modified tables
    for (final table in currentTables) {
      final currentHash = _computeTableHash(table);
      final cachedHash = cachedHashes[table.name];

      if (cachedHash == null || cachedHash != currentHash) {
        tablesToGenerate.add(table);
      }
    }

    // Check for removed tables
    final currentTableNames = currentTables.map((t) => t.name).toSet();
    for (final cachedTableName in cachedHashes.keys) {
      if (!currentTableNames.contains(cachedTableName)) {
        tablesToRemove.add(cachedTableName);
      }
    }

    return SchemaDiff(
      tablesToGenerate: tablesToGenerate,
      tablesToRemove: tablesToRemove,
    );
  }

  /// Checks if the schema has changed (any table modified, added, or removed)
  Future<bool> hasSchemaChanged(List<TableInfo> tables) async {
    final diff = await computeDiff(tables);
    return diff.hasChanges;
  }

  /// Loads per-table hashes from cache
  Future<Map<String, String>> _loadTableHashes() async {
    final file = File(_tableHashesFilePath);
    if (!await file.exists()) {
      return {};
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  /// Saves per-table hashes to cache
  Future<void> _saveTableHashes(Map<String, String> hashes) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(_tableHashesFilePath).writeAsString(jsonEncode(hashes));
  }

  /// Updates cache for specific tables (after generation)
  Future<void> updateTableHashes(List<TableInfo> tables) async {
    final currentHashes = await _loadTableHashes();

    for (final table in tables) {
      currentHashes[table.name] = _computeTableHash(table);
    }

    await _saveTableHashes(currentHashes);
  }

  /// Removes table hash from cache (after table deletion)
  Future<void> removeTableHash(String tableName) async {
    final currentHashes = await _loadTableHashes();
    currentHashes.remove(tableName);
    await _saveTableHashes(currentHashes);
  }

  /// Clears all table hashes (forces regeneration of all tables)
  Future<void> clearTableHashes() async {
    await _saveTableHashes({});
  }

  /// Caches the full schema for later use
  Future<void> cacheSchema(List<TableInfo> tables) async {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final data = tables
        .map(
          (t) => {
            'name': t.name,
            'columns': t.columns
                .map(
                  (c) => {
                    'name': c.name,
                    'dataType': c.dataType,
                    'isNullable': c.isNullable,
                    'defaultValue': c.defaultValue,
                    'isPrimaryKey': c.isPrimaryKey,
                  },
                )
                .toList(),
          },
        )
        .toList();

    await File(_schemaFilePath).writeAsString(jsonEncode(data));

    // Update all table hashes
    final hashes = <String, String>{};
    for (final table in tables) {
      hashes[table.name] = _computeTableHash(table);
    }
    await _saveTableHashes(hashes);
  }

  /// Loads cached schema if available
  Future<List<TableInfo>?> loadCachedSchema() async {
    final file = File(_schemaFilePath);
    if (!await file.exists()) {
      return null;
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as List;

      return data.map((tableData) {
        final columns = (tableData['columns'] as List).map((colData) {
          return ColumnInfo(
            name: colData['name'] as String,
            dataType: colData['dataType'] as String,
            isNullable: colData['isNullable'] as bool,
            defaultValue: colData['defaultValue'] as String?,
            isPrimaryKey: colData['isPrimaryKey'] as bool? ?? false,
          );
        }).toList();

        return TableInfo(
          name: tableData['name'] as String,
          columns: columns,
        );
      }).toList();
    } catch (e) {
      return null;
    }
  }

  /// Clears the cache
  Future<void> clearCache() async {
    final dir = Directory(cacheDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
