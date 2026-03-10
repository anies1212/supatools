import 'package:recase/recase.dart';

/// カスタムメソッドの情報
class MethodInfo {
  /// メソッド名
  final String name;

  /// ソースコード全文（コメント・アノテーション含む）
  final String source;

  const MethodInfo({required this.name, required this.source});
}

/// カスタムメソッド抽出結果
class MigrationResult {
  final List<MethodInfo> customMethods;
  final List<String> customImports;

  /// カスタムメソッドが参照するprivate field
  final List<MethodInfo> privateFields;

  const MigrationResult({
    required this.customMethods,
    required this.customImports,
    this.privateFields = const [],
  });

  bool get hasCustomCode => customMethods.isNotEmpty;
}

/// .custom.dartファイルから抽出した埋め込み用コンテンツ
class CustomFileContent {
  /// extension本体（`{ }` の中身）
  final String body;

  /// 生成ファイルに追加するimport文
  final List<String> imports;

  const CustomFileContent({required this.body, required this.imports});
}

/// 既存extensionファイルとのマージ結果
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

/// 既存リポジトリファイルからカスタムメソッドを抽出し、
/// extensionファイルへ移行するクラス
class CustomMethodMigrator {
  /// 標準メソッド名のパターン（これらは移行対象外）
  static const _standardMethodNames = {
    'getAll',
    'getById',
    'create',
    'update',
    'delete',
    'count',
    'paginate',
  };

  /// 標準getter名
  static const _standardGetterNames = {
    'tableName',
    'client',
  };

  /// getAllWith{Relation}のパターン
  static final _relationMethodPattern = RegExp(r'^getAllWith\w+$');

  /// メソッドシグネチャからメソッド名を抽出
  /// `>` or whitespace の直後にある identifier + `(` or `<` を検出
  static final _methodNamePattern = RegExp(
    r'[\s>]\s*(\w+)\s*[<(]',
  );

  /// getterシグネチャからgetter名を抽出
  static final _getterPattern = RegExp(
    r'(?:\w+(?:<[^>]*>)?)\s+get\s+(\w+)\b',
  );

  /// 自動生成ファイルの既知importパターン
  static final _generatedImportPatterns = [
    RegExp(r"^import\s+'package:supabase"),
    RegExp(r"^import\s+'package:riverpod_annotation"),
    RegExp(r"^part\s+'"),
  ];

  /// カスタムメソッド用の拡張ファイル名を取得
  String getCustomFileName(String tableName) {
    return '${ReCase(tableName).snakeCase}_repository.custom.dart';
  }

  /// 既存ファイルからカスタムメソッドを抽出
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

    // Phase 1: メンバーを分類
    for (final member in members) {
      if (_isStandardMember(member, className)) continue;

      // private static field の検出
      final fieldName = _extractPrivateFieldName(member);
      if (fieldName != null) {
        privateFields[fieldName] = member;
        continue;
      }

      final name = _extractMemberName(member);
      if (name == null) continue;
      customMethods.add(MethodInfo(name: name, source: member));
    }

    // Phase 2: カスタムメソッドが参照するprivate fieldを特定
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

  /// extensionファイルのコードを生成
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

    buffer.writeln("import '$supabaseImport';");
    if (modelImport != null) {
      buffer.writeln("import '$modelImport';");
    }
    for (final imp in customImports) {
      buffer.writeln(imp);
    }
    buffer.writeln("import '$repositoryFileName';");
    buffer.writeln();

    buffer.writeln('extension ${className}Custom on $className {');

    // private fieldsをstatic定数として出力
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

  /// .custom.dartファイル（extension形式）からメソッドとimportを抽出。
  /// 生成されたリポジトリクラスに埋め込むために使用する。
  CustomFileContent? extractFromCustomFile(
    String customCode,
    String repositoryFileName,
  ) {
    final allImports = _extractImports(customCode);
    final imports = allImports.where((imp) {
      // 自身のリポジトリimportを除外
      if (imp.contains(repositoryFileName)) return false;
      // 標準的な自動生成importを除外
      for (final pattern in _generatedImportPatterns) {
        if (pattern.hasMatch(imp)) return false;
      }
      // supabaseClientProviderのimportを除外
      if (imp.contains('supabase_client_provider')) return false;
      // supabase_flutter importは生成ファイルに含まれるため除外
      if (imp.contains('package:supabase')) return false;
      return true;
    }).toList();

    final body = _extractExtensionBody(customCode);
    if (body == null || body.trim().isEmpty) return null;

    return CustomFileContent(body: body, imports: imports);
  }

  /// 既存のextensionファイルとマージ
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

    // extensionの閉じ括弧の前に新規メソッドを挿入
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

  /// import文をすべて抽出
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

  /// カスタムimportのみフィルタリング
  List<String> _filterCustomImports(List<String> imports) {
    return imports.where((imp) {
      for (final pattern in _generatedImportPatterns) {
        if (pattern.hasMatch(imp)) return false;
      }
      // モデルimportもスキップ（.supafreeze.dartを含む）
      if (imp.contains('.supafreeze.dart')) return false;
      // メインのsupabaseクライアントimport
      if (imp.contains('supabase_client_provider')) return false;
      return true;
    }).toList();
  }

  /// クラス本体を抽出（`class ClassName {` から対応する `}` まで）
  String? _extractClassBody(String source, String className) {
    final classPattern = RegExp(
      'class\\s+${RegExp.escape(className)}\\s*\\{',
    );
    return _extractBodyAfterBrace(source, classPattern);
  }

  /// extension本体を抽出
  String? _extractExtensionBody(String source) {
    final pattern = RegExp(r'extension\s+\w+\s+on\s+\w+\s*\{');
    return _extractBodyAfterBrace(source, pattern);
  }

  /// 開始パターンにマッチする `{` から対応する `}` までの本体を抽出
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

    // iは閉じ括弧の次の位置。本体は startIndex から i-1(閉じ括弧)の手前まで
    return source.substring(startIndex, i - 1);
  }

  /// クラス本体からトップレベルメンバーを抽出
  ///
  /// 波括弧と括弧の両方をトラッキングし、
  /// 名前付きパラメータの`{}`を正しく処理する。
  List<String> _extractMembers(String classBody) {
    final members = <String>[];
    final lines = classBody.split('\n');

    // Phase 1: 行ごとにメタ情報を付与
    // Phase 2: メンバー境界を検出

    var i = 0;

    while (i < lines.length) {
      final trimmed = lines[i].trim();

      // 空行スキップ
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // コメント・アノテーション行の蓄積
      if (trimmed.startsWith('///') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('@')) {
        // 先読み: コメント/アノテーションブロックの開始位置を記録
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

        // コメント直後のコード行の処理
        final codeLine = lines[i].trim();
        if (_isFieldDeclaration(codeLine) ||
            _isConstructorLine(codeLine)) {
          // フィールド/コンストラクタ → スキップ
          i = _skipMemberBlock(lines, i);
          continue;
        }

        // メソッド/getterの開始 → コメントごと収集
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

      // フィールド宣言のスキップ
      if (_isFieldDeclaration(trimmed)) {
        i++;
        continue;
      }

      // コンストラクタのスキップ
      if (_isConstructorLine(trimmed)) {
        i = _skipMemberBlock(lines, i);
        continue;
      }

      // メソッド/getterの開始
      final memberLines = <String>[];
      i = _collectMemberBody(lines, i, memberLines);
      final memberStr = memberLines.join('\n').trimRight();
      if (memberStr.isNotEmpty) {
        members.add(memberStr);
      }
    }

    return members;
  }

  /// メンバーの本体を収集し、終了後の行インデックスを返す
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

      // 文字単位でトラッキング
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

      // 本体波括弧なしでセミコロン終了（フィールド宣言、アロー関数等）
      final trimmed = line.trim();
      if (!foundBodyBrace && trimmed.endsWith(';')) {
        break;
      }

      // 本体の波括弧が見つかって閉じたら終了
      if (foundBodyBrace && braceDepth <= 0) {
        break;
      }
    }

    return i;
  }

  /// メンバーブロックをスキップし、終了後の行インデックスを返す
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
      // 1行で完結する場合（`;`で終わる）
      if (!foundBodyBrace && trimmed.endsWith(';')) break;

      // 本体の波括弧が閉じたら終了
      if (foundBodyBrace && braceDepth <= 0) break;
    }

    return i;
  }

  /// 行をスキャンして波括弧・括弧の深さを更新
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

      // 文字列内
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

      // コメント開始
      if (char == '/' && nextChar == '/') break;
      if (char == '/' && nextChar == '*') {
        // ブロックコメントは行末まで簡易スキップ
        break;
      }

      // 文字列開始
      if (char == "'" || char == '"') {
        inString = true;
        stringChar = char;
        continue;
      }

      // 括弧トラッキング
      if (char == '(') parenDepth++;
      if (char == ')') parenDepth--;

      // 波括弧: 括弧内の`{}`はメソッド本体ではない
      if (char == '{') {
        if (parenDepth > 0) {
          // 名前付きパラメータ内 → 無視
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

  /// フィールド宣言かどうか
  bool _isFieldDeclaration(String trimmed) {
    if (trimmed.startsWith('final ') && trimmed.endsWith(';')) return true;
    if (trimmed.startsWith('late ') && trimmed.endsWith(';')) return true;
    if (RegExp(r'^\w+(?:<[^>]*>)?\s+_?\w+\s*;$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  /// コンストラクタ行かどうか
  bool _isConstructorLine(String trimmed) {
    return RegExp(r'^(?:const\s+)?\w+(?:\._?)?\s*\(').hasMatch(trimmed) &&
        !trimmed.contains('Future') &&
        !trimmed.contains('Stream') &&
        !trimmed.contains('void ') &&
        !trimmed.contains(' get ');
  }

  /// メンバーが標準メンバーかどうか判定
  bool _isStandardMember(String memberSource, String className) {
    // コメント・アノテーション行を除いたシグネチャ行を取得
    final signatureLine = _getSignatureLine(memberSource);

    // getterチェック
    final getterMatch = _getterPattern.firstMatch(signatureLine);
    if (getterMatch != null) {
      final name = getterMatch.group(1)!;
      return _standardGetterNames.contains(name);
    }

    // メソッドチェック
    final methodMatch = _methodNamePattern.firstMatch(signatureLine);
    if (methodMatch != null) {
      final name = methodMatch.group(1)!;
      if (_standardMethodNames.contains(name)) return true;
      if (_relationMethodPattern.hasMatch(name)) return true;
    }

    return false;
  }

  /// メンバーソースからシグネチャ行（最初の非コメント・非アノテーション行）を取得
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

  /// private fieldの名前を抽出（`_`で始まるフィールド宣言）
  static final _privateFieldPattern = RegExp(
    r'(?:static\s+)?(?:const\s+|final\s+|late\s+)'
    r'(?:\w+(?:<[^>]*>)?\s+)?(_\w+)\s*[=;]',
  );

  /// メンバーソースからprivate field名を抽出
  String? _extractPrivateFieldName(String memberSource) {
    final signatureLine = _getSignatureLine(memberSource);
    final match = _privateFieldPattern.firstMatch(signatureLine);
    return match?.group(1);
  }

  /// メンバーソースからメソッド/getter名を抽出
  String? _extractMemberName(String memberSource) {
    final signatureLine = _getSignatureLine(memberSource);

    final getterMatch = _getterPattern.firstMatch(signatureLine);
    if (getterMatch != null) return getterMatch.group(1);

    final methodMatch = _methodNamePattern.firstMatch(signatureLine);
    if (methodMatch != null) return methodMatch.group(1);

    return null;
  }

  /// メソッドソースの `_client` を `client` に置換
  String _migrateMethodSource(String source) {
    return source.replaceAll(RegExp(r'\b_client\b'), 'client');
  }

  /// 既存extensionファイルからメソッド名を抽出
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

/// 行スキャン結果
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
