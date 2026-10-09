import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/utils/money_flow.dart';

/// QA test 8 Oct 2026, finding 14: QA TEST Supplier showed "Bal ₹1,150"
/// when nothing was due.
void main() {
  test('QA TEST Supplier: cash purchase and part-paid credit purchase', () {
    final purchases = [
      // ₹1,100 paid in full in cash
      {'id': 'p1', 'total_amount': 1100, 'due_amount': 0},
      // ₹108 credit, ₹50 paid with it, ₹58 paid later by UPI
      {'id': 'p2', 'total_amount': 108, 'due_amount': 0},
    ];
    final payments = [
      {'purchase_id': 'p2', 'amount': 58},
    ];
    final paid = paidWithBill(
      bills: purchases,
      payments: payments,
      totalKey: 'total_amount',
      linkKey: 'purchase_id',
    );
    expect(paid, {'p1': 1100.0, 'p2': 50.0});

    // running balance = bills − paid with bills − later payments = 0
    final balance = 1100 + 108 - paid.values.fold<double>(0, (a, b) => a + b) - 58;
    expect(balance, closeTo(0, 0.001));
  });

  test('unpaid credit sale and a payment without a bill', () {
    final paid = paidWithBill(
      bills: [
        {'id': 's1', 'final_amount': 60, 'due_amount': 35},
      ],
      payments: [
        {'sale_id': 's1', 'amount': 25},
        {'sale_id': null, 'amount': 10},
      ],
      totalKey: 'final_amount',
      linkKey: 'sale_id',
    );
    expect(paid, isEmpty);
  });
}
