import 'package:recase/recase.dart';

/// Custom method information
class MethodInfo {
  /// Method name
  final String name;

  /// Full source code (including comments and annotations)
  final String source;

  const MethodInfo({required this.name, required this.source});
}

/// Custom method extraction result
class MigrationResult {
  final List<MethodInfo> customMethods;
  final List<String> customImports;

  /// Private fields referenced by custom methods
  final List<MethodInfo> privateFields;

  const MigrationResult({
    required this.customMethods,
    required this.customImports,
    this.privateFields = const [],
  });

  bool get hasCustomCode => customMethods.isNotEmpty;
}

/// Content extracted from .custom.dart file for embedding
class CustomFileContent {
  /// Extension body (contents inside `{ }`)
  final String body;

  /// Import statements to add to the generated file
  final List<String> imports;

  const CustomFileContent({required this.body, required this.imports});
}

/// Merge result with existing extension file
class MergeResult {
  final String mergedCode;
  final List<String> added;
  final List<String> skipped;

  const MergeResult({
    required this.mergedCode,
    required this.added,
    required this.skipped,
  });
}

/// Extracts custom methods from existing repository files
/// and migrates them to extension files
class CustomMethodMigrator {
  /// Standard method name patterns (these are excluded from migration)
  static const _standardMethodNames = {
    'getAll',
    'getById',
    'create',
    'update',
    'delete',
    'count',
    'paginate',
  };

  /// Standard getter names
  static const _standardGetterNames = {
    'tableName',
    'client',
  };

  /// Pattern for getAllWith{Relation}
  static final _relationMethodPattern = RegExp(r'^getAllWith\w+$');

  /// Extract method name from method signature
  /// Detects identifier + `(` or `<` immediately after `>` or whitespace
  static final _methodNamePattern = RegExp(
    r'[\s>]\s*(\w+)\s*[<(]',
  );

  /// Extract getter name from getter signature
  static final _getterPattern = RegExp(
    r'(?:\w+(?:<[^>]*>)?)\s+get\s+(\w+)\b',
  );

  /// Known import patterns for auto-generated files
  static final _generatedImportPatterns = [
    RegExp(r"^import\s+'package:supabase"),
    RegExp(r"^import\s+'package:riverpod_annotation"),
    RegExp(r"^part\s+'"),
  ];

  /// Get the extension file name for custom methods
  String getCustomFileName(String tableName) {
    return '${ReCase(tableName).snakeCase}_repository.custom.dart';
  }

  /// Extract custom methods from existing file
  MigrationResult extractCustomMethods(
    String sourceCode,
    String className,
  ) {
    final imports = _extractImports(sourceCode);
    final customImports = _filterCustomImports(imports);
    final classBody = _extractClassBody(sourceCode, className);

    if (classBody == null) {
      return const MigrationResult(
        customMethods: [],
        customImports: [],
      );
    }

    final members = _extractMembers(classBody);
    final customMethods = <MethodInfo>[];
    final privateFields = <String, String>{}; // name → source

    // Phase 1: Classify members
    for (final member in members) {
      if (_isStandardMember(member, className)) continue;

      // Detect private static field
      final fieldName = _extractPrivateFieldName(member);
      if (fieldName != null) {
        privateFields[fieldName] = member;
        continue;
      }

      final name = _extractMemberName(member);
      if (name == null) continue;
      customMethods.add(MethodInfo(name: name, source: member));
    }

    // Phase 2: Identify private fields referenced by custom methods
    final referencedFields = <MethodInfo>[];
    for (final entry in privateFields.entries) {
      final fieldName = entry.key;
      final isReferenced = customMethods.any(
        (m) => m.source.contains(fieldName),
      );
      if (isReferenced) {
        referencedFields.add(
          MethodInfo(name: fieldName, source: entry.value),
        );
      }
    }

    return MigrationResult(
      customMethods: customMethods,
      customImports: customImports,
      privateFields: referencedFields,
    );
  }

  /// Generate extension file code
  String generateExtensionFile({
    required String className,
    required String repositoryFileName,
    required List<MethodInfo> methods,
    required List<String> customImports,
    required String supabaseImport,
    String? modelImport,
    List<MethodInfo> privateFields = const [],
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      '// Custom methods migrated from $className',
    );
    buffer.writeln(
      '// This file is auto-migrated by suparepo and will NOT '
      'be overwritten.',
    );
    buffer.writeln(
      '// ignore_for_file: type=lint',
    );
    buffer.writeln();

    // Only output imports referenced in method bodies
    final allSources = [
      ...methods.map((m) => m.source),
      ...privateFields.map((f) => f.source),
    ].join('\n');

    if (_isImportReferenced(supabaseImport, allSources)) {
      buffer.writeln("import '$supabaseImport';");
    }
    if (modelImport != null &&
        _isImportReferenced(modelImport, allSources)) {
      buffer.writeln("import '$modelImport';");
    }
    for (final imp in customImports) {
      buffer.writeln(imp);
    }
    buffer.writeln("import '$repositoryFileName';");
    buffer.writeln();

    buffer.writeln('extension ${className}Custom on $className {');

    // Output private fields as static constants
    for (final field in privateFields) {
      buffer.write(field.source);
      buffer.writeln();
      buffer.writeln();
    }

    for (var i = 0; i < methods.length; i++) {
      final migrated = _migrateMethodSource(methods[i].source);
      buffer.write(migrated);
      if (i < methods.length - 1) {
        buffer.writeln();
      }
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Parse top-level method/getter declarations from an extension body.
  ///
  /// Used by the fake repository generator to produce stub implementations
  /// for custom methods that can't be auto-faked. The returned [MethodInfo]
  /// `source` contains the full member text (including doc comments).
  List<MethodInfo> parseExtensionMembers(String extensionBody) {
    final members = _extractMembers(extensionBody);
    final result = <MethodInfo>[];
    for (final m in members) {
      final name = _extractMemberName(m);
      if (name == null) continue;
      result.add(MethodInfo(name: name, source: m));
    }
    return result;
  }

  /// Extract the signature portion of a member source — everything up to
  /// the body start (`{` or `=>`), with `async`/`sync*` modifiers stripped.
  ///
  /// Returns `null` when the signature cannot be recovered.
  String? extractMemberSignature(String memberSource) {
    final parenStart = _findFirstParen(memberSource);
    if (parenStart == -1) {
      return _signatureWithoutBody(memberSource);
    }
    final parenEnd = _findMatchingParen(memberSource, parenStart);
    if (parenEnd == -1) return null;

    var i = parenEnd + 1;
    while (i < memberSource.length) {
      final ch = memberSource[i];
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        i++;
        continue;
      }
      final rest = memberSource.substring(i);
      if (rest.startsWith('async*') ||
          rest.startsWith('sync*')) {
        i += 6;
        continue;
      }
      if (rest.startsWith('async')) {
        i += 5;
        continue;
      }
      break;
    }
    if (i >= memberSource.length) return null;

    final beforeBody = memberSource.substring(0, i);
    return beforeBody
        .replaceAll(RegExp(r'\basync\*?'), '')
        .replaceAll(RegExp(r'\bsync\*'), '')
        .trimRight();
  }

  /// Locate the first `(` that is not inside a generic `<…>` bracket.
  int _findFirstParen(String source) {
    var generic = 0;
    var inString = false;
    String? stringChar;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (inString) {
        if (ch == '\\') {
          i++;
          continue;
        }
        if (ch == stringChar) {
          inString = false;
          stringChar = null;
        }
        continue;
      }
      if (ch == "'" || ch == '"') {
        inString = true;
        stringChar = ch;
        continue;
      }
      if (ch == '<') generic++;
      if (ch == '>' && generic > 0) generic--;
      if (ch == '(' && generic == 0) return i;
    }
    return -1;
  }

  /// Given an opening `(` at [openIndex], return the index of the matching `)`.
  int _findMatchingParen(String source, int openIndex) {
    var depth = 1;
    var inString = false;
    String? stringChar;
    var i = openIndex + 1;
    while (i < source.length) {
      final ch = source[i];
      if (inString) {
        if (ch == '\\') {
          i += 2;
          continue;
        }
        if (ch == stringChar) {
          inString = false;
          stringChar = null;
        }
        i++;
        continue;
      }
      if (ch == "'" || ch == '"') {
        inString = true;
        stringChar = ch;
        i++;
        continue;
      }
      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  /// Fallback signature extractor for members without parameters (getters).
  String? _signatureWithoutBody(String source) {
    final braceIndex = source.indexOf('{');
    final arrowIndex = source.indexOf('=>');
    final ends = [braceIndex, arrowIndex].where((v) => v >= 0).toList();
    if (ends.isEmpty) return null;
    ends.sort();
    return source.substring(0, ends.first).trimRight();
  }

  /// Extract methods and imports from .custom.dart file (extension format).
  /// Used for embedding into the generated repository class.
  CustomFileContent? extractFromCustomFile(
    String customCode,
    String repositoryFileName,
  ) {
    final allImports = _extractImports(customCode);
    final imports = allImports.where((imp) {
      // Exclude self repository import
      if (imp.contains(repositoryFileName)) return false;
      // Exclude standard auto-generated imports
      for (final pattern in _generatedImportPatterns) {
        if (pattern.hasMatch(imp)) return false;
      }
      // Exclude supabaseClientProvider import
      if (imp.contains('supabase_client_provider')) return false;
      // Exclude supabase_flutter import as it is included in generated file
      if (imp.contains('package:supabase')) return false;
      // Exclude model import as it is included in generated file
      if (imp.contains('.supafreeze.dart')) return false;
      return true;
    }).toList();

    final body = _extractExtensionBody(customCode);
    if (body == null || body.trim().isEmpty) return null;

    return CustomFileContent(body: body, imports: imports);
  }

  /// Merge with existing extension file
  MergeResult mergeWithExisting(
    String existingCustomCode,
    List<MethodInfo> newMethods,
  ) {
    final existingNames = _extractExistingMethodNames(existingCustomCode);
    final added = <String>[];
    final skipped = <String>[];
    final methodsToAdd = <MethodInfo>[];

    for (final method in newMethods) {
      if (existingNames.contains(method.name)) {
        skipped.add(method.name);
      } else {
        added.add(method.name);
        methodsToAdd.add(method);
      }
    }

    if (methodsToAdd.isEmpty) {
      return MergeResult(
        mergedCode: existingCustomCode,
        added: added,
        skipped: skipped,
      );
    }

    // Insert new methods before the closing brace of the extension
    final closingIndex = existingCustomCode.lastIndexOf('}');
    if (closingIndex == -1) {
      return MergeResult(
        mergedCode: existingCustomCode,
        added: [],
        skipped: skipped,
      );
    }

    final before = existingCustomCode.substring(0, closingIndex);
    final newMethodsCode = StringBuffer();

    for (final method in methodsToAdd) {
      newMethodsCode.writeln();
      newMethodsCode.write(_migrateMethodSource(method.source));
    }

    final mergedCode = '$before${newMethodsCode.toString()}\n}\n';

    return MergeResult(
      mergedCode: mergedCode,
      added: added,
      skipped: skipped,
    );
  }

  // --- Private helpers ---

  /// Extract all import statements
  List<String> _extractImports(String source) {
    final imports = <String>[];
    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('import ') || trimmed.startsWith('part ')) {
        imports.add(trimmed);
      }
    }
    return imports;
  }

  /// Filter custom imports only
  List<String> _filterCustomImports(List<String> imports) {
    return imports.where((imp) {
      for (final pattern in _generatedImportPatterns) {
        if (pattern.hasMatch(imp)) return false;
      }
      // Skip model imports (containing .supafreeze.dart)
      if (imp.contains('.supafreeze.dart')) return false;
      // Main supabase client import
      if (imp.contains('supabase_client_provider')) return false;
      return true;
    }).toList();
  }

  /// Extract class body (from `class ClassName {` to the matching `}`)
  String? _extractClassBody(String source, String className) {
    final classPattern = RegExp(
      'class\\s+${RegExp.escape(className)}\\s*\\{',
    );
    return _extractBodyAfterBrace(source, classPattern);
  }

  /// Extract extension body
  String? _extractExtensionBody(String source) {
    final pattern = RegExp(r'extension\s+\w+\s+on\s+\w+\s*\{');
    return _extractBodyAfterBrace(source, pattern);
  }

  /// Extract body from the `{` matching the start pattern to its corresponding `}`
  String? _extractBodyAfterBrace(String source, RegExp pattern) {
    final match = pattern.firstMatch(source);
    if (match == null) return null;

    final startIndex = match.end;
    var depth = 1;
    var i = startIndex;
    var inString = false;
    String? stringChar;
    var inLineComment = false;
    var inBlockComment = false;

    while (i < source.length && depth > 0) {
      final char = source[i];
      final nextChar = i + 1 < source.length ? source[i + 1] : '';

      if (inLineComment) {
        if (char == '\n') inLineComment = false;
        i++;
        continue;
      }

      if (inBlockComment) {
        if (char == '*' && nextChar == '/') {
          inBlockComment = false;
          i += 2;
          continue;
        }
        i++;
        continue;
      }

      if (inString) {
        if (char == '\\') {
          i += 2;
          continue;
        }
        if (char == stringChar) {
          inString = false;
          stringChar = null;
        }
        i++;
        continue;
      }

      if (char == '/' && nextChar == '/') {
        inLineComment = true;
        i += 2;
        continue;
      }

      if (char == '/' && nextChar == '*') {
        inBlockComment = true;
        i += 2;
        continue;
      }

      if (char == "'" || char == '"') {
        inString = true;
        stringChar = char;
        i++;
        continue;
      }

      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
      }
      i++;
    }

    if (depth != 0) return null;

    // i is the position after the closing brace. Body is from startIndex to i-1 (before closing brace)
    return source.substring(startIndex, i - 1);
  }

  /// Extract top-level members from class body
  ///
  /// Tracks both braces and parentheses,
  /// correctly handling `{}` in named parameters.
  List<String> _extractMembers(String classBody) {
    final members = <String>[];
    final lines = classBody.split('\n');

    // Phase 1: Annotate each line with metadata
    // Phase 2: Detect member boundaries

    var i = 0;

    while (i < lines.length) {
      final trimmed = lines[i].trim();

      // Skip empty lines
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Accumulate comment and annotation lines
      if (trimmed.startsWith('///') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('@')) {
        // Lookahead: record the start position of comment/annotation block
        final commentStart = i;
        while (i < lines.length) {
          final t = lines[i].trim();
          if (t.startsWith('///') ||
              t.startsWith('//') ||
              t.startsWith('@') ||
              t.isEmpty) {
            i++;
          } else {
            break;
          }
        }
        if (i >= lines.length) break;

        // Process the code line immediately after comments
        final codeLine = lines[i].trim();
        if (_isFieldDeclaration(codeLine) ||
            _isConstructorLine(codeLine)) {
          // Field/constructor -> skip
          i = _skipMemberBlock(lines, i);
          continue;
        }

        // Method/getter start -> collect including comments
        final memberLines = <String>[];
        for (var j = commentStart; j < i; j++) {
          memberLines.add(lines[j]);
        }
        i = _collectMemberBody(lines, i, memberLines);
        final memberStr = memberLines.join('\n').trimRight();
        if (memberStr.isNotEmpty) {
          members.add(memberStr);
        }
        continue;
      }

      // Skip field declarations
      if (_isFieldDeclaration(trimmed)) {
        i++;
        continue;
      }

      // Skip constructors
      if (_isConstructorLine(trimmed)) {
        i = _skipMemberBlock(lines, i);
        continue;
      }

      // Method/getter start
      final memberLines = <String>[];
      i = _collectMemberBody(lines, i, memberLines);
      final memberStr = memberLines.join('\n').trimRight();
      if (memberStr.isNotEmpty) {
        members.add(memberStr);
      }
    }

    return members;
  }

  /// Collect member body and return the line index after completion
  int _collectMemberBody(
    List<String> lines,
    int startIndex,
    List<String> output,
  ) {
    var braceDepth = 0;
    var parenDepth = 0;
    var foundBodyBrace = false;
    var i = startIndex;

    while (i < lines.length) {
      final line = lines[i];
      output.add(line);

      // Track character by character
      final result = _scanLine(
        line,
        braceDepth,
        parenDepth,
        foundBodyBrace,
      );
      braceDepth = result.braceDepth;
      parenDepth = result.parenDepth;
      foundBodyBrace = result.foundBodyBrace;

      i++;

      // Ends with semicolon without body brace (field declarations, arrow functions, etc.)
      final trimmed = line.trim();
      if (!foundBodyBrace && trimmed.endsWith(';')) {
        break;
      }

      // End when body brace is found and closed
      if (foundBodyBrace && braceDepth <= 0) {
        break;
      }
    }

    return i;
  }

  /// Skip member block and return the line index after completion
  int _skipMemberBlock(List<String> lines, int startIndex) {
    var braceDepth = 0;
    var parenDepth = 0;
    var foundBodyBrace = false;
    var i = startIndex;

    while (i < lines.length) {
      final line = lines[i];
      final result = _scanLine(
        line,
        braceDepth,
        parenDepth,
        foundBodyBrace,
      );
      braceDepth = result.braceDepth;
      parenDepth = result.parenDepth;
      foundBodyBrace = result.foundBodyBrace;

      i++;

      final trimmed = line.trim();
      // Single-line case (ends with `;`)
      if (!foundBodyBrace && trimmed.endsWith(';')) break;

      // End when body brace is closed
      if (foundBodyBrace && braceDepth <= 0) break;
    }

    return i;
  }

  /// Scan a line and update brace/parenthesis depth
  _ScanResult _scanLine(
    String line,
    int braceDepth,
    int parenDepth,
    bool foundBodyBrace,
  ) {
    var inString = false;
    String? stringChar;

    for (var ci = 0; ci < line.length; ci++) {
      final char = line[ci];
      final nextChar = ci + 1 < line.length ? line[ci + 1] : '';

      // Inside string
      if (inString) {
        if (char == '\\') {
          ci++;
          continue;
        }
        if (char == stringChar) {
          inString = false;
          stringChar = null;
        }
        continue;
      }

      // Comment start
      if (char == '/' && nextChar == '/') break;
      if (char == '/' && nextChar == '*') {
        // Simple skip block comment to end of line
        break;
      }

      // String start
      if (char == "'" || char == '"') {
        inString = true;
        stringChar = char;
        continue;
      }

      // Parenthesis tracking
      if (char == '(') parenDepth++;
      if (char == ')') parenDepth--;

      // Braces: `{}` inside parentheses are not method body
      if (char == '{') {
        if (parenDepth > 0) {
          // Inside named parameters -> ignore
          continue;
        }
        braceDepth++;
        if (!foundBodyBrace) foundBodyBrace = true;
      }
      if (char == '}') {
        if (parenDepth > 0) continue;
        braceDepth--;
      }
    }

    return _ScanResult(
      braceDepth: braceDepth,
      parenDepth: parenDepth,
      foundBodyBrace: foundBodyBrace,
    );
  }

  /// Whether this is a field declaration
  bool _isFieldDeclaration(String trimmed) {
    if (trimmed.startsWith('final ') && trimmed.endsWith(';')) return true;
    if (trimmed.startsWith('late ') && trimmed.endsWith(';')) return true;
    if (RegExp(r'^\w+(?:<[^>]*>)?\s+_?\w+\s*;$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// Whether this is a constructor line
  bool _isConstructorLine(String trimmed) {
    return RegExp(r'^(?:const\s+)?\w+(?:\._?)?\s*\(').hasMatch(trimmed) &&
        !trimmed.contains('Future') &&
        !trimmed.contains('Stream') &&
        !trimmed.contains('void ') &&
        !trimmed.contains(' get ');
  }

  /// Determine whether a member is a standard member
  bool _isStandardMember(String memberSource, String className) {
    // Get signature line excluding comment and annotation lines
    final signatureLine = _getSignatureLine(memberSource);

    // Getter check
    final getterMatch = _getterPattern.firstMatch(signatureLine);
    if (getterMatch != null) {
      final name = getterMatch.group(1)!;
      return _standardGetterNames.contains(name);
    }

    // Method check
    final methodMatch = _methodNamePattern.firstMatch(signatureLine);
    if (methodMatch != null) {
      final name = methodMatch.group(1)!;
      if (_standardMethodNames.contains(name)) return true;
      if (_relationMethodPattern.hasMatch(name)) return true;
    }

    return false;
  }

  /// Get the signature line (first non-comment, non-annotation line) from member source
  String _getSignatureLine(String memberSource) {
    for (final line in memberSource.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('///')) continue;
      if (trimmed.startsWith('//')) continue;
      if (trimmed.startsWith('@')) continue;
      return trimmed;
    }
    return '';
  }

  /// Extract private field name (field declarations starting with `_`)
  static final _privateFieldPattern = RegExp(
    r'(?:static\s+)?(?:const\s+|final\s+|late\s+)'
    r'(?:\w+(?:<[^>]*>)?\s+)?(_\w+)\s*[=;]',
  );

  /// Extract private field name from member source
  String? _extractPrivateFieldName(String memberSource) {
    final signatureLine = _getSignatureLine(memberSource);
    final match = _privateFieldPattern.firstMatch(signatureLine);
    return match?.group(1);
  }

  /// Extract method/getter name from member source
  String? _extractMemberName(String memberSource) {
    final signatureLine = _getSignatureLine(memberSource);

    final getterMatch = _getterPattern.firstMatch(signatureLine);
    if (getterMatch != null) return getterMatch.group(1);

    final methodMatch = _methodNamePattern.firstMatch(signatureLine);
    if (methodMatch != null) return methodMatch.group(1);

    return null;
  }

  /// Replace `_client` with `client` in method source
  String _migrateMethodSource(String source) {
    return source.replaceAll(RegExp(r'\b_client\b'), 'client');
  }

  /// Determine whether an import path is referenced in the source code.
  ///
  /// Since it is difficult to directly check type names exported by
  /// the imported package, this uses a simple heuristic based on Dart
  /// conventions (e.g., `SupabaseClient` originates from `package:supabase`)
  /// where absence of type names in source ~ import is unnecessary.
  bool _isImportReferenced(String importPath, String source) {
    // supabase-related: check if type names like SupabaseClient, CountOption appear
    if (importPath.contains('package:supabase')) {
      return RegExp(r'\bSupabaseClient\b').hasMatch(source) ||
          RegExp(r'\bCountOption\b').hasMatch(source);
    }
    // supafreeze model: infer class name from file name and check for occurrence
    if (importPath.contains('.supafreeze.dart')) {
      final fileName = importPath.split('/').last;
      final baseName = fileName.replaceAll('.supafreeze.dart', '');
      // snake_case → PascalCase
      final className = ReCase(baseName).pascalCase;
      return RegExp('\\b$className\\b(?!Repository|Custom)').hasMatch(source);
    }
    // All others are considered always necessary
    return true;
  }

  /// Return code from the existing `.custom.dart` file with unused imports
  /// removed. Deletes imports not referenced in method bodies.
  String? cleanupCustomFileImports(String customCode) {
    final body = _extractExtensionBody(customCode);
    if (body == null) return null;

    final lines = customCode.split('\n');
    final cleaned = <String>[];
    var modified = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('import ')) {
        // Always keep the repository self-import
        if (trimmed.contains('_repository.dart')) {
          cleaned.add(line);
          continue;
        }
        // Determine if the import target is referenced in the body
        final pathMatch = RegExp(
          r"import\s+'([^']+)'",
        ).firstMatch(trimmed);
        if (pathMatch != null) {
          final importPath = pathMatch.group(1)!;
          if (!_isImportReferenced(importPath, body)) {
            modified = true;
            continue; // Unused import -> remove
          }
        }
        cleaned.add(line);
      } else {
        cleaned.add(line);
      }
    }

    if (!modified) return null;
    return cleaned.join('\n');
  }

  /// Extract method names from existing extension file
  Set<String> _extractExistingMethodNames(String extensionCode) {
    final names = <String>{};
    for (final line in extensionCode.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('///') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('@') ||
          trimmed.startsWith('extension ') ||
          trimmed.startsWith('import ') ||
          trimmed == '{' ||
          trimmed == '}' ||
          trimmed.isEmpty) {
        continue;
      }

      final getterMatch = _getterPattern.firstMatch(trimmed);
      if (getterMatch != null) {
        names.add(getterMatch.group(1)!);
        continue;
      }

      final methodMatch = _methodNamePattern.firstMatch(trimmed);
      if (methodMatch != null) {
        names.add(methodMatch.group(1)!);
      }
    }
    return names;
  }
}

/// Line scan result
class _ScanResult {
  final int braceDepth;
  final int parenDepth;
  final bool foundBodyBrace;

  const _ScanResult({
    required this.braceDepth,
    required this.parenDepth,
    required this.foundBodyBrace,
  });
}
