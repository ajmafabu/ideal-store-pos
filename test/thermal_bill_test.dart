import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/utils/thermal_invoice.dart';

Sale _sale({
  String? customer,
  bool credit = false,
  String method = 'cash',
  double paid = 0,
  double discount = 0,
  double cash = 0,
  double upi = 0,
}) =>
    Sale(
      id: 'abcdef12-0000-0000-0000-000000000000',
      invoiceNo: 1234,
      items: [
        CartItem(productId: 'a', name: 'MILK BIKIS 10rs', price: 9.17, qty: 2, unit: 'pcs'),
        CartItem(productId: 'b', name: 'good night koshu bathi refill 45 nights', price: 140, qty: 1, unit: 'pcs'),
      ],
      totalAmount: 158.34,
      discount: discount,
      totalDiscount: 0,
      finalAmount: 158.34 - discount,
      paymentMethod: method,
      createdBy: 'u',
      createdAt: DateTime.utc(2026, 10, 18, 5, 30),
      customerName: customer,
      isCredit: credit,
      amountPaid: paid,
      dueAmount: credit ? 158.34 - discount - paid : 0,
      cashAmount: cash,
      digitalAmount: upi,
    );

void main() {
  group('Windows thermal bill (18 Oct 2026)', () {
    test('the customer saved on the bill is printed even when not passed (till bug)', () {
      final r = ThermalInvoice.generate(sale: _sale(customer: 'Ravi Stores'), shopName: 'IDEAL STORE');
      expect(r.headerLines, contains('Customer: Ravi Stores'));
      // walk-in: no customer line
      expect(
        ThermalInvoice.generate(sale: _sale(), shopName: 'IDEAL STORE').headerLines.any((l) => l.startsWith('Customer')),
        isFalse,
      );
    });

    test('no shop address on the thermal bill (owner), QUOTATION kept', () {
      final r = ThermalInvoice.generate(sale: _sale(), shopName: 'IDEAL STORE', shopAddress: 'Main Road');
      expect(r.headerLines, isNot(contains('Main Road')));
      expect(r.headerLines, contains('QUOTATION'));
    });

    test('amount in words, the Indian way', () {
      expect(ThermalInvoice.amountInWords(510), 'Rupees Five Hundred Ten Only');
      expect(ThermalInvoice.amountInWords(516.36), 'Rupees Five Hundred Sixteen and Thirty Six Paise Only');
      expect(ThermalInvoice.amountInWords(125000), 'Rupees One Lakh Twenty Five Thousand Only');
      expect(ThermalInvoice.amountInWords(10234567), 'Rupees One Crore Two Lakh Thirty Four Thousand Five Hundred Sixty Seven Only');
      expect(ThermalInvoice.amountInWords(0.5), 'Fifty Paise Only');
      expect(ThermalInvoice.amountInWords(0), 'Rupees Zero Only');
    });

    test('a credit bill shows what was paid and what is still due', () {
      final r = ThermalInvoice.generate(sale: _sale(credit: true, paid: 100, method: 'credit'), shopName: 'S');
      expect(r.totalLines, containsAllInOrder(['NET TOTAL: 158.34', 'Paid: 100.00', 'Balance Due: 58.34']));
    });

    test('cash, UPI and split say how it was paid', () {
      expect(ThermalInvoice.generate(sale: _sale(), shopName: 'S').totalLines.last, 'Paid by: Cash');
      expect(ThermalInvoice.generate(sale: _sale(method: 'upi'), shopName: 'S').totalLines.last, 'Paid by: UPI');
      expect(
        ThermalInvoice.generate(sale: _sale(method: 'split', cash: 100, upi: 58.34), shopName: 'S').totalLines.last,
        'Paid: Cash 100.00 + UPI 58.34',
      );
    });

    test('a discount comes with the sub-total, and items with the quantity', () {
      final r = ThermalInvoice.generate(sale: _sale(discount: 8.34), shopName: 'S');
      expect(r.totalLines, containsAllInOrder(['Total Items: 2   Qty: 3', 'Sub Total: 158.34', 'Discount: -8.34', 'NET TOTAL: 150.00']));
      expect(r.footerLines, ['Thank you! Visit again']);
    });

    test('text (WhatsApp) version: 48 columns, headings over the numbers, names wrap between words', () {
      final text = ThermalInvoice.generate(sale: _sale(), shopName: 'S').toText();
      final lines = text.split('\n');
      for (final l in lines) {
        expect(l.length, lessThanOrEqualTo(48), reason: l);
      }
      final head = lines.firstWhere((l) => l.contains('Item'));
      final row = lines.firstWhere((l) => l.contains('MILK BIKIS'));
      expect(head.indexOf('Amount') + 'Amount'.length, row.length); // amounts end under "Amount"
      expect(lines, contains(' 2 good night koshu        1   140.00     140.00'));
      expect(lines, contains('   bathi refill 45'));
      expect(lines, contains('   nights'));
    });
  });
}
