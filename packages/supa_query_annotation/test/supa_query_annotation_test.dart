import 'package:supa_query_annotation/supa_query_annotation.dart';
import 'package:test/test.dart';

void main() {
  group('Filter', () {
    test('eq creates a const filter', () {
      const f = Filter.eq('is_active', true);
      expect(f.column, 'is_active');
      expect(f.operator, FilterOp.eq);
      expect(f.value, true);
    });

    test('neq creates a const filter', () {
      const f = Filter.neq('status', 'deleted');
      expect(f.column, 'status');
      expect(f.operator, FilterOp.neq);
      expect(f.value, 'deleted');
    });

    test('lte creates a const filter', () {
      const f = Filter.lte('started_at', 'now');
      expect(f.operator, FilterOp.lte);
    });

    test('gt creates a const filter', () {
      const f = Filter.gt('ended_at', 'now');
      expect(f.operator, FilterOp.gt);
    });

    test('is_ creates a const filter', () {
      const f = Filter.is_('deleted_at', null);
      expect(f.operator, FilterOp.is_);
      expect(f.value, null);
    });

    test('in_ creates a const filter with a list value', () {
      const f = Filter.in_('status', ['active', 'pending']);
      expect(f.operator, FilterOp.in_);
      expect(f.value, ['active', 'pending']);
    });

    test('generic constructor works', () {
      const f = Filter('col', FilterOp.contains, [1, 2]);
      expect(f.column, 'col');
      expect(f.operator, FilterOp.contains);
      expect(f.value, [1, 2]);
    });
  });

  group('Param', () {
    test('named param is const-constructible', () {
      const p = Param('userId');
      expect(p.name, 'userId');
    });

    test('Param.now has sentinel name', () {
      expect(Param.now.name, '__now__');
    });
  });

  group('OrderBy', () {
    test('default is ascending', () {
      const o = OrderBy('sort_order');
      expect(o.column, 'sort_order');
      expect(o.ascending, true);
      expect(o.nullsFirst, false);
    });

    test('desc constructor', () {
      const o = OrderBy.desc('created_at');
      expect(o.ascending, false);
    });

    test('nullsFirst option', () {
      const o = OrderBy('rank', nullsFirst: true);
      expect(o.nullsFirst, true);
    });
  });

  group('ReturnMode', () {
    test('has all values', () {
      expect(ReturnMode.values, hasLength(3));
      expect(ReturnMode.values, contains(ReturnMode.list));
      expect(ReturnMode.values, contains(ReturnMode.single));
      expect(ReturnMode.values, contains(ReturnMode.maybeSingle));
    });
  });

  group('SupaQuery', () {
    test('default values', () {
      const q = SupaQuery();
      expect(q.select, isNull);
      expect(q.filters, isEmpty);
      expect(q.order, isEmpty);
      expect(q.limit, isNull);
      expect(q.returnMode, ReturnMode.list);
      expect(q.resultModel, isNull);
    });

    test('full annotation is const-constructible', () {
      const q = SupaQuery(
        select: 'id, name, products(image_url)',
        filters: [
          Filter.eq('is_active', true),
          Filter.lte('started_at', Param.now),
        ],
        order: [OrderBy('sort_order')],
        limit: 10,
        returnMode: ReturnMode.maybeSingle,
        resultModel: 'CustomResult',
      );
      expect(q.select, 'id, name, products(image_url)');
      expect(q.filters, hasLength(2));
      expect(q.order, hasLength(1));
      expect(q.limit, 10);
      expect(q.returnMode, ReturnMode.maybeSingle);
      expect(q.resultModel, 'CustomResult');
    });
  });
}
