import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/utils/stock_health.dart';

Product _p(String id, {double stock = 10, double cost = 8, double price = 10}) =>
    Product(id: id, name: 'P$id', stock: stock, purchasePrice: cost, sellingPrice: price);

final _now = DateTime(2026, 10, 18, 12);

StockCount _count(String id, double system, double counted, {int daysAgo = 1}) => StockCount(
      productId: id,
      systemQty: system,
      countedQty: counted,
      at: _now.subtract(Duration(days: daysAgo)),
      reason: 'Counting correction',
    );

void main() {
  group('stock health', () {
    test('ABC: the products making 80% of sales value are A, then B to 95%, the rest C', () {
      final products = [for (var i = 1; i <= 5; i++) _p('$i')];
      final h = StockHealth.compute(
        products: products,
        counts: const [],
        batchTotals: const {},
        // value: 1 = 700, 2 = 150, 3 = 100, 4 = 50, 5 = nothing
        salesValue30d: const {'1': 700, '2': 150, '3': 100, '4': 50},
        now: _now,
      );
      expect(h.classes['1'], CountClass.a); // 0-70%
      expect(h.classes['2'], CountClass.a); // starts at 70% (< 80)
      expect(h.classes['3'], CountClass.b); // starts at 85%
      expect(h.classes['4'], CountClass.c); // starts at 95%
      expect(h.classes['5'], CountClass.c); // did not sell
    });

    test('today: A items first, never counted first, at most 20; counted recently are not due', () {
      final products = [for (var i = 1; i <= 30; i++) _p('$i')];
      final h = StockHealth.compute(
        products: products,
        counts: [
          _count('1', 10, 10, daysAgo: 2), // A counted 2 days ago: not due (weekly)
          _count('2', 10, 10, daysAgo: 8), // A counted 8 days ago: due
        ],
        batchTotals: const {},
        salesValue30d: {for (var i = 1; i <= 30; i++) '$i': (31 - i) * 10.0},
        now: _now,
      );
      expect(h.dueToday, hasLength(StockHealth.dailyListSize));
      expect(h.dueToday.map((c) => c.product.id), isNot(contains('1')));
      expect(h.dueToday.first.cls, CountClass.a);
      // never-counted A items come before the one counted 8 days ago
      expect(h.dueToday.first.lastCounted, isNull);
    });

    test('accuracy: counts of the last 30 days that matched the shelf', () {
      final h = StockHealth.compute(
        products: [_p('1'), _p('2'), _p('3')],
        counts: [
          _count('1', 10, 10),
          _count('2', 10, 7),
          _count('3', 5, 5),
          _count('3', 9, 2, daysAgo: 40), // too old: not counted in accuracy
        ],
        batchTotals: const {},
        salesValue30d: const {},
        now: _now,
      );
      expect(h.countsLast30, 3);
      expect(h.matchedLast30, 2);
      expect(h.accuracyPercent, closeTo(66.7, 0.1));
      expect(h.bigDifferences.single.productId, '2');
      expect(h.bigDifferences.single.difference, -3);
    });

    test('purchase pending (below zero), no cost price, not counted in 30 days', () {
      final h = StockHealth.compute(
        products: [_p('1', stock: -12), _p('2', stock: -3), _p('3', cost: 0), _p('4', stock: 0)],
        counts: [_count('3', 10, 10)],
        batchTotals: const {'3': 10},
        salesValue30d: const {'3': 100},
        now: _now,
      );
      expect(h.belowZero.map((p) => p.id).toList(), ['1', '2']); // most below first
      expect(h.noCost.single.id, '3');
      expect(h.notCounted.map((p) => p.id), containsAll(['1', '2']));
      expect(h.notCounted.map((p) => p.id), isNot(contains('3'))); // counted yesterday
      expect(h.notCounted.map((p) => p.id), isNot(contains('4'))); // nothing there, no sales
      // below zero: enter the purchase first, so not on today's list
      expect(h.dueToday.map((c) => c.product.id), isNot(anyOf(contains('1'), contains('2'))));
    });

    test('batches must equal the stock (below zero: no batches left)', () {
      final h = StockHealth.compute(
        products: [_p('1', stock: 10), _p('2', stock: -5), _p('3', stock: 8)],
        batchTotals: const {'1': 10, '3': 12},
        counts: const [],
        salesValue30d: const {},
        now: _now,
      );
      expect(h.batchMismatches.map((m) => m.product.id).toList(), ['3']);
      expect(h.batchMismatches.single.difference, 4);
    });

    test('hidden products (empty for 30 days) are on no list', () {
      final hidden = Product(id: 'h', name: 'Hidden', stock: 0, purchasePrice: 0, sellingPrice: 10, hiddenAt: _now);
      final h = StockHealth.compute(
        products: [hidden, _p('1')],
        counts: const [],
        batchTotals: const {'h': 2, '1': 10},
        salesValue30d: const {'h': 50, '1': 100},
        now: _now,
      );
      expect(h.classes.containsKey('h'), isFalse);
      expect(h.noCost, isEmpty);
      expect(h.notCounted.map((p) => p.id), ['1']);
      expect(h.batchMismatches, isEmpty);
      expect(h.dueToday.map((c) => c.product.id), ['1']);
    });

    test('the October upgrade notes are not counts', () {
      final h = StockHealth.compute(
        products: [_p('1')],
        counts: [
          StockCount(productId: '1', systemQty: 1747, countedQty: 979, at: _now.subtract(const Duration(days: 5)),
              reason: '2026-10 upgrade: removed 768.000 batch unit(s) already sold by the old app'),
        ],
        batchTotals: const {},
        salesValue30d: const {'1': 100},
        now: _now,
      );
      expect(h.countsLast30, 0);
      expect(h.accuracyPercent, isNull);
      expect(h.bigDifferences, isEmpty);
      expect(h.notCounted.single.id, '1'); // still never really counted
    });
  });
}
