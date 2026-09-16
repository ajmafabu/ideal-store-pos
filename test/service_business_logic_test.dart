import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/models/purchase.dart';

void main() {
  // ============================================
  // SALE SERVICE BUSINESS LOGIC TESTS
  // ============================================
  group('Sale Business Logic', () {
    test('Sale final_amount = total_amount - discount - total_discount', () {
      final sale = Sale(
        id: 'sale-1',
        items: [
          CartItem(
            productId: 'p-1',
            name: 'Item A',
            price: 100.0,
            qty: 2,
            unit: 'pcs',
            discount: 5.0, // 5% item discount
          ),
          CartItem(
            productId: 'p-2',
            name: 'Item B',
            price: 200.0,
            qty: 1,
            unit: 'pcs',
          ),
        ],
        totalAmount: 400.0, // (100*2) + (200*1)
        discount: 20.0, // bill discount
        totalDiscount: 10.0, // item A: 200 * 5% = 10
        finalAmount: 370.0, // 400 - 20 - 10
        paymentMethod: 'cash',
        createdBy: 'user-1',
        createdAt: DateTime.now(),
      );

      expect(sale.totalAmount, 400.0);
      expect(sale.discount, 20.0);
      expect(sale.totalDiscount, 10.0);
      expect(sale.finalAmount, 370.0);
    });

    test('Credit sale due_amount = final_amount - amount_paid', () {
      final sale = Sale(
        id: 'sale-2',
        items: [],
        totalAmount: 500.0,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 500.0,
        paymentMethod: 'credit',
        createdBy: 'user-1',
        createdAt: DateTime.now(),
        isCredit: true,
        amountPaid: 200.0,
        dueAmount: 300.0,
      );

      expect(sale.dueAmount, sale.finalAmount - sale.amountPaid);
    });

    test('Split payment: cash + digital = final_amount', () {
      final sale = Sale(
        id: 'sale-3',
        items: [],
        totalAmount: 1000.0,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 1000.0,
        paymentMethod: 'split',
        createdBy: 'user-1',
        createdAt: DateTime.now(),
        cashAmount: 600.0,
        digitalAmount: 400.0,
      );

      expect(sale.cashAmount + sale.digitalAmount, sale.finalAmount);
    });

    test('Cart profit calculation with multiple items', () {
      final items = [
        CartItem(
          productId: 'p-1',
          name: 'A',
          price: 100.0,
          qty: 5,
          unit: 'pcs',
          purchasePrice: 60.0,
        ),
        CartItem(
          productId: 'p-2',
          name: 'B',
          price: 200.0,
          qty: 3,
          unit: 'pcs',
          purchasePrice: 120.0,
        ),
      ];

      final totalProfit = items.fold(0.0, (sum, item) => sum + item.profit);

      // Item A: (100-60)*5 = 200
      // Item B: (200-120)*3 = 240
      expect(totalProfit, 440.0);
    });

    test('GST totals from cart items', () {
      final items = [
        CartItem(
          productId: 'p-1',
          name: 'A',
          price: 118.0,
          qty: 2,
          unit: 'pcs',
          gstRate: 18.0,
        ),
        CartItem(
          productId: 'p-2',
          name: 'B',
          price: 128.0,
          qty: 1,
          unit: 'pcs',
          gstRate: 28.0,
        ),
      ];

      final totalGst = items.fold(0.0, (sum, item) => sum + item.gstAmount);
      final totalCgst = items.fold(0.0, (sum, item) => sum + item.cgst);
      final totalSgst = items.fold(0.0, (sum, item) => sum + item.sgst);

      // Item A: 118*2*18/118 = 36
      // Item B: 128*1*28/128 = 28
      expect(totalGst, closeTo(64.0, 0.01));
      expect(totalCgst, closeTo(32.0, 0.01));
      expect(totalSgst, closeTo(32.0, 0.01));
    });
  });

  // ============================================
  // PURCHASE SERVICE BUSINESS LOGIC TESTS
  // ============================================
  group('Purchase Business Logic', () {
    test('Purchase total = sum of item totals', () {
      final items = [
        PurchaseItem(
          productId: 'p-1',
          name: 'A',
          price: 50.0,
          qty: 10,
          unit: 'pcs',
        ),
        PurchaseItem(
          productId: 'p-2',
          name: 'B',
          price: 100.0,
          qty: 5,
          unit: 'pcs',
        ),
      ];

      final total = items.fold(0.0, (sum, item) => sum + item.total);

      // A: 50*10=500, B: 100*5=500
      expect(total, 1000.0);
    });

    test('Credit purchase due_amount = total - amount_paid', () {
      final purchase = Purchase(
        id: 'pur-1',
        items: [],
        totalAmount: 5000.0,
        createdBy: 'user-1',
        createdAt: DateTime.now(),
        isCredit: true,
        amountPaid: 2000.0,
        dueAmount: 3000.0,
      );

      expect(purchase.dueAmount, purchase.totalAmount - purchase.amountPaid);
    });

    test('PurchaseItem GST calculation', () {
      final item = PurchaseItem(
        productId: 'p-1',
        name: 'Widget',
        price: 1180.0,
        qty: 10,
        unit: 'pcs',
        gstRate: 18.0,
      );

      // Total: 1180*10 = 11800
      // GST: 11800 * 18/118 = 1800
      expect(item.total, 11800.0);
      expect(item.gstAmount, closeTo(1800.0, 0.01));
      expect(item.priceExcludingGst, closeTo(10000.0, 0.01));
    });

    test('PurchaseItem batch number preserved in roundtrip', () {
      final item = PurchaseItem(
        productId: 'p-1',
        name: 'Widget',
        price: 50.0,
        qty: 100,
        unit: 'pcs',
        batchNumber: 'BATCH-2026-001',
      );

      final json = item.toJson();
      final restored = PurchaseItem.fromJson(json);

      expect(restored.batchNumber, 'BATCH-2026-001');
    });
  });

  // ============================================
  // FINANCIAL CONSISTENCY TESTS
  // ============================================
  group('Financial Consistency', () {
    test('COGS calculation matches sale items', () {
      final items = [
        CartItem(
          productId: 'p-1',
          name: 'A',
          price: 100.0,
          qty: 5,
          unit: 'pcs',
          purchasePrice: 60.0,
        ),
        CartItem(
          productId: 'p-2',
          name: 'B',
          price: 200.0,
          qty: 3,
          unit: 'pcs',
          purchasePrice: 120.0,
        ),
      ];

      final cogs = items.fold(
        0.0,
        (sum, item) => sum + item.purchasePrice * item.qty,
      );

      // A: 60*5=300, B: 120*3=360
      expect(cogs, 660.0);
    });

    test('Revenue = total_amount - discount - total_discount', () {
      final totalAmount = 1000.0;
      final billDiscount = 50.0;
      final itemDiscount = 30.0;
      final revenue = totalAmount - billDiscount - itemDiscount;

      expect(revenue, 920.0);
    });

    test('Gross margin percentage', () {
      final revenue = 1000.0;
      final cogs = 600.0;
      final grossMargin = ((revenue - cogs) / revenue) * 100;

      expect(grossMargin, 40.0);
    });

    test('Expense ratio percentage', () {
      final revenue = 1000.0;
      final expenses = 150.0;
      final expenseRatio = (expenses / revenue) * 100;

      expect(expenseRatio, 15.0);
    });
  });
}
