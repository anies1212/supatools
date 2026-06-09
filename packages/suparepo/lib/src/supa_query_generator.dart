import 'package:recase/recase.dart';
import 'package:supa_query_annotation/supa_query_annotation.dart';

/// Parsed annotation data for a single `@SupaQuery`-annotated method.
class SupaQueryMethodInfo {
  /// Method name extracted from the stub signature.
  final String methodName;

  /// Inner type of the return (e.g. `HomeBanners` from `Future<List<HomeBanners>>`).
  final String returnTypeName;

  /// Full return type string (e.g. `Future<List<HomeBanners>>`).
  final String fullReturnType;

  /// Parsed select expression (null means `'*'`).
  final String? select;

  /// Parsed filters.
  final List<ParsedFilter> filters;

  /// Parsed order-by clauses.
  final List<ParsedOrderBy> orderClauses;

  /// Limit value (null means no limit).
  final int? limit;

  /// Return mode.
  final ReturnMode returnMode;

  /// Custom result model class name.
  final String? resultModel;

  /// Explicit method parameters from the stub signature.
  final List<MethodParam> explicitParams;

  /// Doc comment lines preceding the annotation.
  final String? docComment;

  const SupaQueryMethodInfo({
    required this.methodName,
    required this.returnTypeName,
    required this.fullReturnType,
    this.select,
    this.filters = const [],
    this.orderClauses = const [],
    this.limit,
    this.returnMode = ReturnMode.list,
    this.resultModel,
    this.explicitParams = const [],
    this.docComment,
  });
}

class ParsedFilter {
  final String column;
  final FilterOp operator;
  final Object? value;
  final bool isParamNow;
  final String? paramName;

  const ParsedFilter({
    required this.column,
    required this.operator,
    this.value,
    this.isParamNow = false,
    this.paramName,
  });
}

class ParsedOrderBy {
  final String column;
  final bool ascending;
  final bool nullsFirst;

  const ParsedOrderBy({
    required this.column,
    this.ascending = true,
    this.nullsFirst = false,
  });
}

class MethodParam {
  final String type;
  final String name;

  const MethodParam({required this.type, required this.name});
}

/// Processes `@SupaQuery`-annotated method stubs in `.custom.dart` files
/// and generates PostgREST query implementations.
class SupaQueryGenerator {
  /// Regex matching a `@SupaQuery(...)` annotation block.
  static final _annotationStart = RegExp(r'@SupaQuery\s*\(');

  /// Processes the source code of a `.custom.dart` file and returns
  /// a new version with `@SupaQuery` stubs replaced by generated
  /// implementations.
  ///
  /// [tableName] is used to derive the default model class name.
  /// Returns `null` if the source has no `@SupaQuery` annotations.
  String? processCustomFile(String source, String tableName) {
    if (!source.contains('@SupaQuery')) return null;

    final methods = parseAnnotatedMethods(source);
    if (methods.isEmpty) return null;

    var result = source;
    // Process in reverse order to preserve offsets.
    for (final method in methods.reversed) {
      result = _replaceStubWithImplementation(result, method, tableName);
    }
    return result;
  }

  /// Extracts all `@SupaQuery`-annotated methods from source code.
  List<SupaQueryMethodInfo> parseAnnotatedMethods(String source) {
    final methods = <SupaQueryMethodInfo>[];
    var searchFrom = 0;

    while (true) {
      final match = _annotationStart.firstMatch(
        source.substring(searchFrom),
      );
      if (match == null) break;

      final annotationStart = searchFrom + match.start;
      final parenStart = searchFrom + match.end - 1;

      // Extract the full annotation arguments
      final annotationEnd = _findMatchingParen(source, parenStart);
      if (annotationEnd == -1) break;

      final annotationArgs = source.substring(parenStart + 1, annotationEnd);

      // Find the method signature after the annotation
      final afterAnnotation = source.substring(annotationEnd + 1).trimLeft();
      final sigEnd = afterAnnotation.indexOf(';');
      final arrowEnd = afterAnnotation.indexOf('=>');

      int methodEnd;
      if (arrowEnd != -1 && (sigEnd == -1 || arrowEnd < sigEnd)) {
        // Arrow function: find the semicolon after =>
        final arrowSemiEnd = afterAnnotation.indexOf(';', arrowEnd);
        methodEnd = arrowSemiEnd != -1 ? arrowSemiEnd : afterAnnotation.length;
      } else if (sigEnd != -1) {
        methodEnd = sigEnd;
      } else {
        // Try to find body with braces
        final braceStart = afterAnnotation.indexOf('{');
        if (braceStart != -1) {
          final braceEnd = _findMatchingBrace(
            afterAnnotation,
            braceStart,
          );
          methodEnd = braceEnd != -1 ? braceEnd : afterAnnotation.length;
        } else {
          searchFrom = annotationEnd + 1;
          continue;
        }
      }

      final signaturePart = afterAnnotation.substring(
        0,
        arrowEnd != -1 && (sigEnd == -1 || arrowEnd < sigEnd)
            ? arrowEnd
            : _findSignatureEnd(afterAnnotation),
      );

      // Extract doc comment before @SupaQuery
      final docComment = _extractDocComment(source, annotationStart);

      // Parse the annotation arguments
      final info = _parseAnnotation(
        annotationArgs,
        signaturePart.trim(),
        docComment,
      );

      if (info != null) {
        methods.add(info);
      }

      searchFrom = annotationEnd + 1 + methodEnd + 1;
    }

    return methods;
  }

  /// Generates the method body for a single annotated method.
  String generateMethodBody(SupaQueryMethodInfo method, String tableName) {
    final modelClass = method.resultModel ?? ReCase(tableName).pascalCase;
    final buffer = StringBuffer();

    // Collect Param-referenced parameters that need to be added
    final paramNames = <String>{};
    for (final p in method.explicitParams) {
      paramNames.add(p.name);
    }

    // Build parameter list
    final allParams = <String>[];
    for (final p in method.explicitParams) {
      allParams.add('${p.type} ${p.name}');
    }

    // Add Param-referenced parameters not already explicit
    for (final filter in method.filters) {
      if (filter.paramName != null && !paramNames.contains(filter.paramName)) {
        allParams.add('dynamic ${filter.paramName}');
        paramNames.add(filter.paramName!);
      }
    }

    final paramStr = allParams.isEmpty ? '' : allParams.join(', ');

    // Method signature
    if (method.docComment != null) {
      buffer.writeln(method.docComment);
    }
    buffer.write('  ${method.fullReturnType} ${method.methodName}');
    if (paramStr.isNotEmpty || method.explicitParams.isNotEmpty) {
      buffer.write('($paramStr)');
    } else {
      buffer.write('()');
    }
    buffer.writeln(' async {');

    // Build the query chain
    final selectExpr = method.select ?? '*';
    if (selectExpr == '*') {
      buffer.writeln('    final response = await client');
      buffer.writeln('        .from(tableName)');
      buffer.write('        .select()');
    } else {
      buffer.writeln('    final response = await client');
      buffer.writeln('        .from(tableName)');
      buffer.write("        .select('$selectExpr')");
    }

    // Filters
    for (final filter in method.filters) {
      buffer.writeln();
      final op = _filterOpToMethod(filter.operator);
      final valueExpr = _filterValueExpr(filter);
      buffer.write("        .$op('${filter.column}', $valueExpr)");
    }

    // Order
    for (final o in method.orderClauses) {
      buffer.writeln();
      if (o.ascending && !o.nullsFirst) {
        buffer.write("        .order('${o.column}')");
      } else {
        final parts = <String>["'${o.column}'"];
        if (!o.ascending) parts.add('ascending: false');
        if (o.nullsFirst) parts.add('nullsFirst: true');
        buffer.write('        .order(${parts.join(', ')})');
      }
    }

    // Limit
    if (method.limit != null) {
      buffer.writeln();
      buffer.write('        .limit(${method.limit})');
    }

    // Return mode-specific ending
    switch (method.returnMode) {
      case ReturnMode.single:
        buffer.writeln();
        buffer.writeln('        .single();');
        buffer.writeln(
          '    return $modelClass.fromJson(response);',
        );

      case ReturnMode.maybeSingle:
        buffer.writeln();
        buffer.writeln('        .maybeSingle();');
        buffer.writeln(
          '    return response != null '
          '? $modelClass.fromJson(response) : null;',
        );

      case ReturnMode.list:
        buffer.writeln(';');
        buffer.writeln(
          '    return response'
          '.map((e) => $modelClass.fromJson(e)).toList();',
        );
    }

    buffer.write('  }');
    return buffer.toString();
  }

  // --- Private helpers ---

  /// Replaces a `@SupaQuery`-annotated stub in [source] with the
  /// generated implementation.
  String _replaceStubWithImplementation(
    String source,
    SupaQueryMethodInfo method,
    String tableName,
  ) {
    // Find the @SupaQuery annotation
    final annotationMatch = _annotationStart.firstMatch(source);
    if (annotationMatch == null) return source;

    // Walk back to include doc comments
    var blockStart = annotationMatch.start;
    final before = source.substring(0, blockStart);
    final beforeLines = before.split('\n');
    for (var i = beforeLines.length - 1; i >= 0; i--) {
      final trimmed = beforeLines[i].trim();
      if (trimmed.startsWith('///')) {
        blockStart -= beforeLines[i].length + 1; // +1 for newline
      } else if (trimmed.isEmpty) {
        continue;
      } else {
        break;
      }
    }

    // Find end of annotation
    final parenStart = annotationMatch.end - 1;
    final annotationEnd = _findMatchingParen(source, parenStart);
    if (annotationEnd == -1) return source;

    // Find end of the method stub after the annotation
    final afterAnnotation = source.substring(annotationEnd + 1);
    final arrowIdx = afterAnnotation.indexOf('=>');
    final semiIdx = afterAnnotation.indexOf(';');
    final braceIdx = afterAnnotation.indexOf('{');

    int blockEnd;
    if (arrowIdx != -1 && (semiIdx == -1 || arrowIdx < semiIdx)) {
      // Arrow function: find semicolon after =>
      final arrowSemi = afterAnnotation.indexOf(';', arrowIdx);
      blockEnd = annotationEnd +
          1 +
          (arrowSemi != -1 ? arrowSemi + 1 : afterAnnotation.length);
    } else if (braceIdx != -1 && (semiIdx == -1 || braceIdx < semiIdx)) {
      final braceEnd = _findMatchingBrace(afterAnnotation, braceIdx);
      blockEnd = annotationEnd +
          1 +
          (braceEnd != -1 ? braceEnd + 1 : afterAnnotation.length);
    } else if (semiIdx != -1) {
      blockEnd = annotationEnd + 1 + semiIdx + 1;
    } else {
      return source;
    }

    final generated = generateMethodBody(method, tableName);
    return source.substring(0, blockStart) +
        generated +
        source.substring(blockEnd);
  }

  /// Finds the matching closing parenthesis.
  int _findMatchingParen(String source, int openIndex) {
    return _findMatchingDelimiter(source, openIndex, '(', ')');
  }

  /// Finds the matching closing brace.
  int _findMatchingBrace(String source, int openIndex) {
    return _findMatchingDelimiter(source, openIndex, '{', '}');
  }

  int _findMatchingDelimiter(
    String source,
    int openIndex,
    String open,
    String close,
  ) {
    var depth = 0;
    var inString = false;
    String? stringChar;

    for (var i = openIndex; i < source.length; i++) {
      final char = source[i];

      if (inString) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == stringChar) {
          inString = false;
          stringChar = null;
        }
        continue;
      }

      if (char == "'" || char == '"') {
        inString = true;
        stringChar = char;
        continue;
      }

      if (char == open) depth++;
      if (char == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// Extracts a doc comment block immediately before [position].
  String? _extractDocComment(String source, int position) {
    final before = source.substring(0, position);
    final lines = before.split('\n');

    final commentLines = <String>[];
    for (var i = lines.length - 1; i >= 0; i--) {
      final trimmed = lines[i].trim();
      if (trimmed.startsWith('///')) {
        commentLines.insert(0, lines[i]);
      } else if (trimmed.isEmpty) {
        continue;
      } else {
        break;
      }
    }

    return commentLines.isEmpty ? null : commentLines.join('\n');
  }

  /// Finds where the method signature ends (before `=>`, `{`, or `)` + `async`).
  int _findSignatureEnd(String source) {
    final parenIdx = source.indexOf('(');
    if (parenIdx == -1) return source.length;
    final closeParen = _findMatchingParen(source, parenIdx);
    return closeParen != -1 ? closeParen + 1 : source.length;
  }

  /// Parses the annotation argument string and method signature into
  /// a [SupaQueryMethodInfo].
  SupaQueryMethodInfo? _parseAnnotation(
    String args,
    String signature,
    String? docComment,
  ) {
    // Parse method name and return type from signature
    final sigMatch = RegExp(
      r'Future<(\w+\??(?:<(\w+)>)?)>\s+(\w+)\s*\(([^)]*)\)',
    ).firstMatch(signature);

    if (sigMatch == null) return null;

    final fullGenericType = sigMatch.group(1)!;
    final innerType = sigMatch.group(2);
    final methodName = sigMatch.group(3)!;
    final paramString = sigMatch.group(4) ?? '';

    // Determine return type name and return mode from signature
    String returnTypeName;
    ReturnMode defaultReturnMode;

    if (fullGenericType.startsWith('List<')) {
      returnTypeName = innerType ?? 'Map<String, dynamic>';
      defaultReturnMode = ReturnMode.list;
    } else if (fullGenericType.endsWith('?')) {
      returnTypeName = fullGenericType.substring(
        0,
        fullGenericType.length - 1,
      );
      defaultReturnMode = ReturnMode.maybeSingle;
    } else {
      returnTypeName = fullGenericType;
      defaultReturnMode = ReturnMode.list;
    }

    // Parse explicit method parameters
    final explicitParams = _parseMethodParams(paramString);

    // Parse annotation fields
    final select = _extractStringField(args, 'select');
    final filters = _parseFilters(args);
    final order = _parseOrderBy(args);
    final limit = _extractIntField(args, 'limit');
    final returnMode = _extractReturnMode(args) ?? defaultReturnMode;
    final resultModel = _extractStringField(args, 'resultModel');

    return SupaQueryMethodInfo(
      methodName: methodName,
      returnTypeName: resultModel ?? returnTypeName,
      fullReturnType: 'Future<${sigMatch.group(1)!}>',
      select: select,
      filters: filters,
      orderClauses: order,
      limit: limit,
      returnMode: returnMode,
      resultModel: resultModel,
      explicitParams: explicitParams,
      docComment: docComment,
    );
  }

  /// Extracts a string field value from annotation args.
  String? _extractStringField(String args, String fieldName) {
    final match = RegExp(
      "$fieldName\\s*:\\s*'([^']*)'",
    ).firstMatch(args);
    return match?.group(1);
  }

  /// Extracts an int field value from annotation args.
  int? _extractIntField(String args, String fieldName) {
    final match = RegExp(
      '$fieldName\\s*:\\s*(\\d+)',
    ).firstMatch(args);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// Extracts the ReturnMode from annotation args.
  ReturnMode? _extractReturnMode(String args) {
    final match = RegExp(
      r'returnMode\s*:\s*ReturnMode\.(\w+)',
    ).firstMatch(args);
    if (match == null) return null;
    return switch (match.group(1)!) {
      'list' => ReturnMode.list,
      'single' => ReturnMode.single,
      'maybeSingle' => ReturnMode.maybeSingle,
      _ => null,
    };
  }

  /// Parses `Filter.*()` calls from the `filters` list in annotation args.
  List<ParsedFilter> _parseFilters(String args) {
    final filtersMatch = RegExp(
      r'filters\s*:\s*\[([^\]]*)\]',
      dotAll: true,
    ).firstMatch(args);
    if (filtersMatch == null) return [];

    final filtersStr = filtersMatch.group(1)!;
    final filters = <ParsedFilter>[];

    // Match Filter.op('column', value) patterns.
    // Value can contain nested parens (e.g. Param('x')), so we
    // match the column, then extract the value by finding the
    // matching closing paren.
    final filterStartPattern = RegExp(
      r"Filter\.(\w+)\(\s*'([^']+)'\s*,\s*",
    );

    for (final m in filterStartPattern.allMatches(filtersStr)) {
      final opStr = m.group(1)!;
      final column = m.group(2)!;
      // Extract value from after the comma to the matching ')'
      final valueStart = m.end;
      final closeParen = _findMatchingFilterEnd(filtersStr, valueStart);
      if (closeParen == -1) continue;
      final valueStr = filtersStr.substring(valueStart, closeParen).trim();

      final op = _parseFilterOp(opStr);
      if (op == null) continue;

      if (valueStr == 'Param.now') {
        filters.add(ParsedFilter(
          column: column,
          operator: op,
          isParamNow: true,
        ));
      } else if (valueStr.startsWith("Param('") ||
          valueStr.startsWith('Param("')) {
        final paramRegex = RegExp(r'''Param\(['"](\w+)['"]\)''');
        final paramName = paramRegex.firstMatch(valueStr)?.group(1);
        filters.add(ParsedFilter(
          column: column,
          operator: op,
          paramName: paramName,
        ));
      } else {
        filters.add(ParsedFilter(
          column: column,
          operator: op,
          value: _parseLiteralValue(valueStr),
        ));
      }
    }

    return filters;
  }

  /// Parses `OrderBy(...)` calls from the `order` list in annotation args.
  List<ParsedOrderBy> _parseOrderBy(String args) {
    final orderMatch = RegExp(
      r'order\s*:\s*\[([^\]]*)\]',
      dotAll: true,
    ).firstMatch(args);
    if (orderMatch == null) return [];

    final orderStr = orderMatch.group(1)!;
    final orders = <ParsedOrderBy>[];

    // Match OrderBy('column') and OrderBy.desc('column')
    final orderPattern = RegExp(
      r"OrderBy(?:\.desc)?\(\s*'([^']+)'"
      r'(?:\s*,\s*(?:ascending\s*:\s*(true|false))?'
      r'(?:\s*,?\s*nullsFirst\s*:\s*(true|false))?)?\s*\)',
    );

    for (final m in orderPattern.allMatches(orderStr)) {
      final column = m.group(1)!;
      final fullMatch = m.group(0)!;
      final isDesc = fullMatch.startsWith('OrderBy.desc');
      final ascending = m.group(2) != null ? m.group(2)! == 'true' : !isDesc;
      final nullsFirst = m.group(3) == 'true';

      orders.add(ParsedOrderBy(
        column: column,
        ascending: ascending,
        nullsFirst: nullsFirst,
      ));
    }

    return orders;
  }

  /// Parses method parameter declarations.
  List<MethodParam> _parseMethodParams(String paramString) {
    if (paramString.trim().isEmpty) return [];

    final params = <MethodParam>[];
    // Remove curly braces for named params
    var cleaned = paramString.trim();
    if (cleaned.startsWith('{')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.endsWith('}')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    for (final part in cleaned.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      // Remove 'required' keyword
      final withoutRequired = trimmed.replaceFirst('required ', '');
      final tokens = withoutRequired.trim().split(RegExp(r'\s+'));
      if (tokens.length >= 2) {
        params.add(MethodParam(
          type: tokens[tokens.length - 2],
          name: tokens.last,
        ));
      }
    }

    return params;
  }

  /// Converts a FilterOp to its Supabase client method name.
  String _filterOpToMethod(FilterOp op) {
    return switch (op) {
      FilterOp.eq => 'eq',
      FilterOp.neq => 'neq',
      FilterOp.lt => 'lt',
      FilterOp.lte => 'lte',
      FilterOp.gt => 'gt',
      FilterOp.gte => 'gte',
      FilterOp.like => 'like',
      FilterOp.ilike => 'ilike',
      FilterOp.is_ => 'isFilter',
      FilterOp.in_ => 'inFilter',
      FilterOp.contains => 'contains',
      FilterOp.overlaps => 'overlaps',
    };
  }

  /// Generates the Dart expression for a filter value.
  String _filterValueExpr(ParsedFilter filter) {
    if (filter.isParamNow) {
      return 'DateTime.now().toUtc().toIso8601String()';
    }
    if (filter.paramName != null) {
      return filter.paramName!;
    }
    final v = filter.value;
    if (v is String) return "'$v'";
    if (v is bool || v is int || v is double) return '$v';
    if (v == null) return 'null';
    return '$v';
  }

  /// Parses a FilterOp name to its enum value.
  FilterOp? _parseFilterOp(String name) {
    return switch (name) {
      'eq' => FilterOp.eq,
      'neq' => FilterOp.neq,
      'lt' => FilterOp.lt,
      'lte' => FilterOp.lte,
      'gt' => FilterOp.gt,
      'gte' => FilterOp.gte,
      'like' => FilterOp.like,
      'ilike' => FilterOp.ilike,
      'is_' => FilterOp.is_,
      'in_' => FilterOp.in_,
      'contains' => FilterOp.contains,
      'overlaps' => FilterOp.overlaps,
      _ => null,
    };
  }

  /// Parses a literal value from annotation source text.
  Object? _parseLiteralValue(String text) {
    final trimmed = text.trim();
    if (trimmed == 'true') return true;
    if (trimmed == 'false') return false;
    if (trimmed == 'null') return null;

    final intVal = int.tryParse(trimmed);
    if (intVal != null) return intVal;

    final doubleVal = double.tryParse(trimmed);
    if (doubleVal != null) return doubleVal;

    // String literal
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
        (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return trimmed.substring(1, trimmed.length - 1);
    }

    return trimmed;
  }

  /// Finds the end of a filter value expression, handling nested parens.
  ///
  /// Starts scanning from [start] and returns the index of the closing
  /// `)` that belongs to the outer `Filter.op(...)` call.
  int _findMatchingFilterEnd(String source, int start) {
    var depth = 1; // Already inside the outer Filter.op(
    var inString = false;
    String? stringChar;

    for (var i = start; i < source.length; i++) {
      final char = source[i];

      if (inString) {
        if (char == '\\') {
          i++;
          continue;
        }
        if (char == stringChar) {
          inString = false;
          stringChar = null;
        }
        continue;
      }

      if (char == "'" || char == '"') {
        inString = true;
        stringChar = char;
        continue;
      }

      if (char == '(') depth++;
      if (char == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}
