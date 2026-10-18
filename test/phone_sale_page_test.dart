import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/config/providers/cart.dart';
import 'package:ideal_store_pos/models/customer.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/widgets/cart/cart_item_tile.dart';
import 'package:ideal_store_pos/widgets/cart/checkout_sheet.dart';
import 'package:ideal_store_pos/widgets/cart/line_edit_sheet.dart';

CartItem _item({String id = 'soap', double price = 9.33, double qty = 1, String? rate, String unit = 'pcs'}) =>
    CartItem(productId: id, name: 'lux 10 rs', price: price, qty: qty, unit: unit, rateLabel: rate, stockFactor: 1);

/// Opens [sheet] from a button and returns what it pops.
Future<T?> _open<T>(WidgetTester tester, Future<T?> Function(BuildContext) sheet) async {
  T? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await sheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('money on screen', () {
    test('exact paise, never rounded', () {
      expect(rupees(9.33), '₹9.33');
      expect(rupees(60), '₹60');
      expect(rupees2(80), '₹80.00');
      expect(rupees2(46.65), '₹46.65');
    });
  });

  group('the phone cart', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('the same product at the same price adds up on one line', () {
      final n = c.read(cartProvider.notifier)
        ..addItem(_item())
        ..addItem(_item(qty: 2));
      expect(c.read(cartProvider), hasLength(1));
      expect(c.read(cartProvider).single.qty, 3);
      n.clear();
    });

    test('another rate or price is its own line (was billed at the first price)', () {
      c.read(cartProvider.notifier)
        ..addItem(_item())
        ..addItem(_item(price: 100, rate: 'Box'))
        ..addItem(_item(price: 8.5));
      final lines = c.read(cartProvider);
      expect(lines, hasLength(3));
      expect(lines.map((l) => l.price), [9.33, 100, 8.5]);
    });

    test('Undo puts a removed line back where it was', () {
      final n = c.read(cartProvider.notifier)
        ..addItem(_item(id: 'a'))
        ..addItem(_item(id: 'b'))
        ..addItem(_item(id: 'c'));
      final removed = c.read(cartProvider)[1];
      n.removeItem(1);
      n.insertItem(1, removed);
      expect(c.read(cartProvider).map((l) => l.productId), ['a', 'b', 'c']);
    });

    test('setQty to 0 removes; replaceItem changes rate and price', () {
      final n = c.read(cartProvider.notifier)..addItem(_item(rate: 'Box', price: 100));
      n.replaceItem(0, c.read(cartProvider).first.copyWith(price: 9.33, clearRateLabel: true));
      expect(c.read(cartProvider).first.rateLabel, isNull);
      expect(c.read(cartProvider).first.price, 9.33);
      n.setQty(0, 0);
      expect(c.read(cartProvider), isEmpty);
    });
  });

  group('checkout sheet', () {
    Future<Checkout?> pay(WidgetTester tester, Future<void> Function() steps, {PayMode mode = PayMode.cash}) async {
      Checkout? result;
      await _open<void>(tester, (context) async {
        result = await CheckoutSheet.show(
          context,
          total: 80,
          itemCount: 2,
          mode: mode,
          customer: null,
          pickCustomer: () async => Customer(id: 'c1', name: 'Ravi', createdAt: DateTime(2026)),
        );
      });
      await steps();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('cash: the change to give back', (tester) async {
      final r = await pay(tester, () async {
        await tester.tap(find.text('₹100'));
        await tester.pump();
        expect(find.text('Give back ₹20.00'), findsOneWidget);
        await tester.tap(find.text('Complete ₹80.00'));
      });
      expect(r?.mode, PayMode.cash);
    });

    testWidgets('split must add up to the total', (tester) async {
      final r = await pay(tester, () async {
        await tester.enterText(find.widgetWithText(TextField, 'Cash'), '50');
        await tester.pump();
        await tester.tap(find.text('Complete ₹80.00'));
        await tester.pump();
      }, mode: PayMode.split);
      // 50 cash fills 30 UPI by itself
      expect(r?.mode, PayMode.split);
      expect(r?.splitCash, 50);
      expect(r?.splitUpi, 30);
    });

    testWidgets('credit needs a customer', (tester) async {
      Checkout? r = await pay(tester, () async {
        await tester.tap(find.text('Save credit bill'));
        await tester.pump();
        expect(find.text('Choose the customer for a credit bill'), findsOneWidget);
        await tester.tap(find.text('Choose customer'));
        await tester.pumpAndSettle();
        expect(find.text('Ravi'), findsOneWidget);
        await tester.tap(find.text('Save credit bill'));
      }, mode: PayMode.credit);
      expect(r?.mode, PayMode.credit);
      expect(r?.customer?.name, 'Ravi');
      expect(r?.creditPaid, 0);
    });
  });

  group('line edit sheet', () {
    testWidgets('pieces are whole numbers', (tester) async {
      LineEdit? r;
      await _open<void>(tester, (context) async => r = await LineEditSheet.show(context, _item(qty: 2)));
      await tester.enterText(find.widgetWithText(TextField, 'Quantity (pcs)'), '3');
      await tester.enterText(find.widgetWithText(TextField, 'Discount'), '10');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(r?.qty, 3);
      expect(r?.discount, 10);
      expect(r?.price, 9.33);
    });

    testWidgets('Remove asks to take the line off', (tester) async {
      LineEdit? r;
      await _open<void>(tester, (context) async => r = await LineEditSheet.show(context, _item()));
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(r?.remove, isTrue);
    });
  });
}
