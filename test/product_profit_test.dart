import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/utils/product_profit.dart';

/// QA test 8 Oct 2026, findings 42/43/46: profit per product cut decimal
/// quantities to whole numbers and ignored returns.
void main() {
  group('ProductProfit', () {
    test('decimal quantities and a partial return (QA TEST Rice)', () {
      final sales = [
        {
          'items': [
            {'product_id': 'rice', 'name': 'Rice', 'qty': 1.5, 'total': 75, 'purchase_price': 40},
          ],
        },
        {
          'items': [
            {'product_id': 'rice', 'name': 'Rice', 'qty': 2, 'total': 100, 'purchase_price': 40},
          ],
        },
      ];
      final returns = [
        {'product_id': 'rice', 'product_name': 'Rice', 'quantity': 0.5, 'return_amount': 25, 'cost_amount': 20},
      ];
      final p = ProductProfit.compute(sales: sales, returns: returns).single;
      expect(p.qty, closeTo(3.0, 1e-9));
      expect(p.revenue, closeTo(150, 1e-9));
      expect(p.cost, closeTo(120, 1e-9));
      expect(p.profit, closeTo(30, 1e-9));
      expect(p.margin, closeTo(20, 1e-9));
    });

    test('FIFO cost_total wins over purchase_price', () {
      final p = ProductProfit.compute(sales: [
        {
          'items': [
            {'product_id': 'a', 'name': 'A', 'qty': 2, 'total': 30, 'purchase_price': 10, 'cost_total': 17},
          ],
        },
      ]).single;
      expect(p.cost, 17);
      expect(p.profit, 13);
    });

    test('line without a cost falls back to the product cost', () {
      final p = ProductProfit.compute(
        sales: [
          {
            'items': [
              {'product_id': 'a', 'name': 'A', 'qty': 0.25, 'total': 20, 'purchase_price': 0},
            ],
          },
        ],
        costMap: {'a': 60},
      ).single;
      expect(p.cost, closeTo(15, 1e-9));
    });

    test('same product id under two names is one row; old lines without id group by name', () {
      final rows = ProductProfit.compute(sales: [
        {
          'items': [
            {'product_id': 'a', 'name': 'Soap', 'qty': 1, 'total': 10, 'purchase_price': 8},
            {'product_id': 'a', 'name': 'Soap (renamed)', 'qty': 2, 'total': 20, 'purchase_price': 8},
            {'name': 'Loose item', 'qty': 1, 'total': 5, 'purchase_price': 3},
          ],
        },
      ]);
      expect(rows, hasLength(2));
      expect(rows.firstWhere((r) => r.productId == 'a').qty, 3);
    });

    test('a return of something sold before the period is ignored', () {
      final rows = ProductProfit.compute(sales: const [], returns: [
        {'product_id': 'x', 'product_name': 'X', 'quantity': 1, 'return_amount': 10, 'cost_amount': 8},
      ]);
      expect(rows, isEmpty);
    });

    test('fully returned product drops out of the list', () {
      final rows = ProductProfit.compute(sales: [
        {
          'items': [
            {'product_id': 'a', 'name': 'A', 'qty': 1, 'total': 10, 'purchase_price': 8},
          ],
        },
      ], returns: [
        {'product_id': 'a', 'product_name': 'A', 'quantity': 1, 'return_amount': 10, 'cost_amount': 8},
      ]);
      expect(rows, isEmpty);
    });

    test('map keeps the keys the screens read', () {
      final m = ProductProfit.compute(sales: [
        {
          'items': [
            {'product_id': 'a', 'name': 'A', 'qty': 1.5, 'total': 15, 'purchase_price': 8},
          ],
        },
      ]).single.toMap();
      expect(m['qtySold'], isA<double>());
      for (final k in ['name', 'tamilName', 'totalSold', 'revenue', 'totalCost', 'cost', 'profit', 'margin']) {
        expect(m.containsKey(k), isTrue, reason: k);
      }
    });
  });
}
