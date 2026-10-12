import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/purchase.dart';

Purchase _p({
  bool isCredit = false,
  String method = 'cash',
  double cash = 0,
  double upi = 0,
  double due = 0,
}) =>
    Purchase(
      id: '11111111-1111-4111-8111-111111111111',
      items: [PurchaseItem(productId: 'p1', name: 'Soap', price: 10, qty: 30, unit: 'pcs')],
      totalAmount: 300,
      createdBy: '',
      createdAt: DateTime(2026, 10, 12),
      isCredit: isCredit,
      paymentMethod: method,
      cashAmount: cash,
      digitalAmount: upi,
      dueAmount: due,
    );

void main() {
  group('purchase split payment', () {
    test('a split sends its cash and UPI parts', () {
      final json = _p(method: 'split', cash: 100, upi: 200).toInsertJson();
      expect(json['cash_amount'], 100);
      expect(json['digital_amount'], 200);
    });

    test('a plain purchase sends no split columns (works before the SQL update)', () {
      final json = _p(method: 'upi').toInsertJson();
      expect(json.containsKey('cash_amount'), isFalse);
      expect(json.containsKey('digital_amount'), isFalse);
    });

    test('labels for the history list', () {
      expect(_p(method: 'cash').paymentLabel, 'CASH');
      expect(_p(method: 'upi').paymentLabel, 'UPI');
      expect(_p(method: 'cash', cash: 100, upi: 200).paymentLabel, 'SPLIT');
      expect(_p(isCredit: true, due: 300).paymentLabel, 'CREDIT');
      // part paid by split, rest on credit: still shown as a split
      expect(_p(isCredit: true, cash: 50, upi: 100, due: 150).paymentLabel, 'SPLIT');
    });

    test('split amounts come back from the database row', () {
      final p = Purchase.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'items': [],
        'total_amount': 300,
        'payment_method': 'cash',
        'cash_amount': 100,
        'digital_amount': 200,
      });
      expect(p.isSplit, isTrue);
      expect(p.digitalAmount, 200);
    });

    test('an old row without the columns is not a split', () {
      final p = Purchase.fromJson({
        'id': '11111111-1111-4111-8111-111111111111',
        'items': [],
        'total_amount': 300,
        'payment_method': 'upi',
      });
      expect(p.isSplit, isFalse);
      expect(p.paymentLabel, 'UPI');
    });
  });
}
