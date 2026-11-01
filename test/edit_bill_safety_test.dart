import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/config/desktop_billing_provider.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/screens/desktop/desktop_billing_screen.dart' show looksLikeReplacingBill;

/// Bill #3603 (1 Nov 2026): a ₹13,874 bill being edited was emptied with
/// Clear Cart, a new bill tab was opened, and the next customer's ₹390 sale
/// was saved over #3603. An edit now belongs to its own tab only.
void main() {
  Sale bill3603() => Sale(
        id: '00000000-0000-4000-8000-000000003603',
        items: [
          for (var i = 0; i < 30; i++) CartItem(productId: 'p$i', name: 'Item $i', price: 100, qty: 1, unit: 'pcs'),
        ],
        totalAmount: 13874,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 13874,
        paymentMethod: 'cash',
        createdBy: 'u',
        createdAt: DateTime.utc(2026, 10, 31, 16),
        invoiceNo: 3603,
      );
  DesktopCartItem item(String name) => DesktopCartItem(productId: name, name: name, price: 130, qty: 1, unit: 'pcs');

  late ProviderContainer c;
  late DesktopBillingNotifier till;
  setUp(() {
    c = ProviderContainer();
    till = c.read(desktopBillingProvider.notifier);
  });
  tearDown(() => c.dispose());

  test('what happened to #3603: Clear Cart, New bill, next customer → a NEW bill', () {
    till.setEditingSale(bill3603());
    till.addItem(item('a'));
    expect(till.editingSale?.invoiceNo, 3603);

    till.clearCart(till.activeSessionIndex); // Clear Cart
    expect(till.editingSale, isNull, reason: 'Clear Cart ends the edit');

    till.autoHoldCurrentSession(); // Ctrl+N: nothing to hold
    till.createQuickSale();
    till.addItem(item('b'));
    expect(till.editingSale, isNull, reason: 'the new tab is a new bill');
  });

  test('another bill tab is never the edit, even while the edit is open', () {
    till.setEditingSale(bill3603());
    till.createQuickSale(); // second tab for the next customer
    expect(till.editingSale, isNull);
    till.switchSession(0);
    expect(till.editingSale?.invoiceNo, 3603, reason: 'the edit stays in its own tab');
    // the tab bar marks only that tab as "EDIT #3603"
    final tabs = c.read(desktopBillingProvider);
    expect(till.editingSaleIn(tabs[0].id)?.invoiceNo, 3603);
    expect(till.editingSaleIn(tabs[1].id), isNull);
  });

  test('closing the tab of an edit ends the edit', () {
    till.createQuickSale();
    till.setEditingSale(bill3603());
    till.closeSession(till.activeSessionIndex);
    for (var i = 0; i < c.read(desktopBillingProvider).length; i++) {
      till.switchSession(i);
      expect(till.editingSale, isNull);
    }
  });

  test('a held edit comes back as the same edit; the other tab stays a new bill', () {
    till.setEditingSale(bill3603());
    till.addItem(item('a'));
    expect(till.autoHoldCurrentSession(), isTrue);
    expect(till.editingSale, isNull);
    expect(till.heldBills.single.editingSale?.invoiceNo, 3603);
    till.restoreHeldBill(0);
    expect(till.editingSale?.invoiceNo, 3603);
  });

  test('saving an edit that drops most of a bill asks first', () {
    expect(looksLikeReplacingBill(oldTotal: 13874, oldLines: 30, newTotal: 390, newLines: 3), isTrue);
    expect(looksLikeReplacingBill(oldTotal: 11755, oldLines: 26, newTotal: 13874, newLines: 30), isFalse);
    expect(looksLikeReplacingBill(oldTotal: 1136.2, oldLines: 14, newTotal: 1136, newLines: 14), isFalse);
    expect(looksLikeReplacingBill(oldTotal: 100, oldLines: 2, newTotal: 10, newLines: 1), isFalse);
  });
}
