import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/models/stock_move.dart';
import 'package:ideal_store_pos/screens/shared/product_detail_screen.dart';
import 'package:ideal_store_pos/services/supplier_return_service.dart';

Product _p(double stock, {int alert = 10}) =>
    Product(id: 'x', name: 'Soap', stock: stock, lowStockAlert: alert, sellingPrice: 10, purchasePrice: 8);

void main() {
  group('stock status (one colour and word per state)', () {
    test('an empty product is "Out of stock", never a green tick', () {
      expect(stockStatus(_p(0)).label, 'Out of stock');
    });
    test('below zero is "Purchase pending"', () {
      expect(stockStatus(_p(-12)).label, 'Purchase pending');
    });
    test('at or under the alert is "Low"; above it "In stock"', () {
      expect(stockStatus(_p(10)).label, 'Low');
      expect(stockStatus(_p(11)).label, 'In stock');
      expect(stockStatus(_p(3, alert: 0)).label, 'In stock');
    });
  });

  group('stock history rows', () {
    test('read from the database', () {
      final m = StockMove.fromJson({
        'at': '2026-10-23T10:00:00Z',
        'kind': 'Returned to supplier',
        'qty': -10,
        'stock_after': 40,
        'ref': 'Agency D #70000000',
        'note': 'Expired',
      });
      expect(m.kind, 'Returned to supplier');
      expect(m.qty, -10);
      expect(m.isIn, isFalse);
      expect(m.stockAfter, 40);
      expect(m.note, 'Expired');
    });
  });

  group('return to supplier', () {
    test('a line is sent in stock units with its value', () {
      final l = SupplierReturnLine(productId: 'p1', name: 'Soap', qty: 10, price: 8);
      expect(l.total, 80);
      expect(l.toJson(), {'product_id': 'p1', 'name': 'Soap', 'qty': 10.0, 'price': 8.0, 'stock_factor': 1});
    });
    test('a saved return: what came off the dues and what came back', () {
      final r = SupplierReturn.fromJson({
        'id': 'r1',
        'supplier_name': 'Agency D',
        'items': [
          {'name': 'Soap', 'qty': 40},
        ],
        'total_amount': 360,
        'credit_amount': 320,
        'refund_amount': 40,
        'refund_method': 'upi',
        'created_at': '2026-10-23T10:00:00Z',
      });
      expect(r.credit + r.refund, r.total);
      expect(r.refundMethod, 'upi');
      expect(r.items.single['name'], 'Soap');
    });
  });
}
