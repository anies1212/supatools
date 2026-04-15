import 'package:supa_query_annotation/supa_query_annotation.dart';
import 'package:test/test.dart';
import 'package:suparepo/src/supa_query_generator.dart';

void main() {
  late SupaQueryGenerator generator;

  setUp(() {
    generator = SupaQueryGenerator();
  });

  group('parseAnnotatedMethods', () {
    test('parses a simple filter query', () {
      const source = '''
extension TestRepositoryCustom on TestRepository {
  @SupaQuery(
    filters: [Filter.eq('is_active', true)],
    order: [OrderBy('sort_order')],
  )
  Future<List<TestModel>> getActive() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods, hasLength(1));

      final m = methods.first;
      expect(m.methodName, 'getActive');
      expect(m.filters, hasLength(1));
      expect(m.filters.first.column, 'is_active');
      expect(m.filters.first.operator, FilterOp.eq);
      expect(m.filters.first.value, true);
      expect(m.orderClauses, hasLength(1));
      expect(m.orderClauses.first.column, 'sort_order');
      expect(m.returnMode, ReturnMode.list);
    });

    test('parses Param.now filter', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    filters: [Filter.lte('started_at', Param.now)],
  )
  Future<List<MyModel>> getRecent() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods, hasLength(1));
      expect(methods.first.filters.first.isParamNow, true);
    });

    test('parses named Param reference', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    filters: [Filter.eq('user_id', Param('userId'))],
  )
  Future<List<MyModel>> getByUser() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods, hasLength(1));
      expect(methods.first.filters.first.paramName, 'userId');
    });

    test('parses select and resultModel', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    select: 'id, name, products(image_url)',
    resultModel: 'CustomResult',
  )
  Future<List<CustomResult>> getWithProducts() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods, hasLength(1));
      expect(methods.first.select, 'id, name, products(image_url)');
      expect(methods.first.resultModel, 'CustomResult');
    });

    test('parses limit', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    limit: 10,
  )
  Future<List<MyModel>> getTop10() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods.first.limit, 10);
    });

    test('parses returnMode', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    filters: [Filter.eq('id', Param('id'))],
    returnMode: ReturnMode.maybeSingle,
  )
  Future<MyModel?> getById() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods.first.returnMode, ReturnMode.maybeSingle);
    });

    test('parses OrderBy.desc', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    order: [OrderBy.desc('created_at')],
  )
  Future<List<MyModel>> getLatest() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods.first.orderClauses.first.ascending, false);
    });

    test('parses multiple filters', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    filters: [
      Filter.eq('is_active', true),
      Filter.lte('started_at', Param.now),
      Filter.gt('ended_at', Param.now),
    ],
  )
  Future<List<MyModel>> getActive() =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods.first.filters, hasLength(3));
      expect(methods.first.filters[0].operator, FilterOp.eq);
      expect(methods.first.filters[1].operator, FilterOp.lte);
      expect(methods.first.filters[2].operator, FilterOp.gt);
    });

    test('parses explicit method parameters', () {
      const source = '''
extension X on Y {
  @SupaQuery(
    filters: [Filter.eq('user_id', Param('userId'))],
  )
  Future<List<MyModel>> getByUser(String userId) =>
      throw UnimplementedError();
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods.first.explicitParams, hasLength(1));
      expect(methods.first.explicitParams.first.type, 'String');
      expect(methods.first.explicitParams.first.name, 'userId');
    });

    test('returns empty list when no annotations', () {
      const source = '''
extension X on Y {
  Future<List<MyModel>> getAll() async {
    return [];
  }
}
''';
      final methods = generator.parseAnnotatedMethods(source);
      expect(methods, isEmpty);
    });
  });

  group('generateMethodBody', () {
    test('generates a simple list query', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getActive',
        returnTypeName: 'HomeBanners',
        fullReturnType: 'Future<List<HomeBanners>>',
        filters: [
          ParsedFilter(column: 'is_active', operator: FilterOp.eq, value: true),
        ],
        orderClauses: [ParsedOrderBy(column: 'sort_order')],
      );

      final body = generator.generateMethodBody(method, 'home_banners');
      expect(body, contains('.from(tableName)'));
      expect(body, contains('.select()'));
      expect(body, contains(".eq('is_active', true)"));
      expect(body, contains(".order('sort_order')"));
      expect(body, contains('HomeBanners.fromJson'));
      expect(body, contains('.toList()'));
    });

    test('generates Param.now as DateTime expression', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getRecent',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<List<MyModel>>',
        filters: [
          ParsedFilter(
            column: 'started_at',
            operator: FilterOp.lte,
            isParamNow: true,
          ),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('DateTime.now().toUtc().toIso8601String()'));
    });

    test('generates maybeSingle return mode', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getById',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<MyModel?>',
        returnMode: ReturnMode.maybeSingle,
        filters: [
          ParsedFilter(
            column: 'id',
            operator: FilterOp.eq,
            paramName: 'id',
          ),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('.maybeSingle()'));
      expect(body, contains('response != null'));
    });

    test('generates single return mode', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getOne',
        returnTypeName: 'MyTable',
        fullReturnType: 'Future<MyTable>',
        returnMode: ReturnMode.single,
        filters: [
          ParsedFilter(
            column: 'id',
            operator: FilterOp.eq,
            paramName: 'id',
          ),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('.single()'));
      expect(body, contains('MyTable.fromJson(response)'));
    });

    test('generates custom select', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getWithProducts',
        returnTypeName: 'CustomResult',
        fullReturnType: 'Future<List<CustomResult>>',
        select: 'id, name, products(image_url)',
        resultModel: 'CustomResult',
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains("select('id, name, products(image_url)')"));
      expect(body, contains('CustomResult.fromJson'));
    });

    test('generates limit', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getTop',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<List<MyModel>>',
        limit: 5,
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('.limit(5)'));
    });

    test('generates descending order with nullsFirst', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getLatest',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<List<MyModel>>',
        orderClauses: [
          ParsedOrderBy(
            column: 'created_at',
            ascending: false,
            nullsFirst: true,
          ),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains("order('created_at', ascending: false, nullsFirst: true)"));
    });

    test('generates Param reference as method parameter', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getByUser',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<List<MyModel>>',
        filters: [
          ParsedFilter(
            column: 'user_id',
            operator: FilterOp.eq,
            paramName: 'userId',
          ),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('dynamic userId'));
      expect(body, contains(".eq('user_id', userId)"));
    });

    test('does not duplicate explicit params', () {
      final method = SupaQueryMethodInfo(
        methodName: 'getByUser',
        returnTypeName: 'MyModel',
        fullReturnType: 'Future<List<MyModel>>',
        filters: [
          ParsedFilter(
            column: 'user_id',
            operator: FilterOp.eq,
            paramName: 'userId',
          ),
        ],
        explicitParams: [
          MethodParam(type: 'String', name: 'userId'),
        ],
      );

      final body = generator.generateMethodBody(method, 'my_table');
      expect(body, contains('String userId'));
      // Should NOT have 'dynamic userId'
      expect(body, isNot(contains('dynamic userId')));
    });
  });

  group('processCustomFile', () {
    test('returns null when no annotations', () {
      const source = '''
extension X on Y {
  Future<List<MyModel>> getAll() async {
    return [];
  }
}
''';
      final result = generator.processCustomFile(source, 'my_table');
      expect(result, isNull);
    });

    test('replaces stub with generated implementation', () {
      const source = '''
extension TestRepositoryCustom on TestRepository {
  @SupaQuery(
    filters: [Filter.eq('is_active', true)],
  )
  Future<List<TestModel>> getActive() =>
      throw UnimplementedError();
}
''';
      final result = generator.processCustomFile(source, 'test');
      expect(result, isNotNull);
      expect(result, contains('.from(tableName)'));
      expect(result, contains('.select()'));
      expect(result, contains(".eq('is_active', true)"));
      expect(result, contains('Test.fromJson'));
      // Stub should be gone
      expect(result, isNot(contains('UnimplementedError')));
    });
  });
}
