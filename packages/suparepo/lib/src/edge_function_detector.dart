import 'dart:io';
import 'package:path/path.dart' as p;
import 'edge_function_info.dart';

/// Detects Edge Functions from the local filesystem
class EdgeFunctionDetector {
  /// Detects Edge Functions by scanning the functions directory
  ///
  /// Looks for `supabase/functions/*/index.ts` patterns.
  /// Directories starting with `_` are excluded (shared modules).
  Future<List<EdgeFunctionInfo>> detect([
    String basePath = 'supabase/functions',
  ]) async {
    final dir = Directory(basePath);
    if (!await dir.exists()) return [];

    final functions = <EdgeFunctionInfo>[];

    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;

      final dirName = p.basename(entity.path);

      // Skip hidden/shared directories
      if (dirName.startsWith('_') || dirName.startsWith('.')) {
        continue;
      }

      // Check for index.ts
      final indexFile = File(p.join(entity.path, 'index.ts'));
      if (await indexFile.exists()) {
        functions.add(EdgeFunctionInfo(name: dirName));
      }
    }

    // Sort by name for deterministic output
    functions.sort((a, b) => a.name.compareTo(b.name));
    return functions;
  }
}
