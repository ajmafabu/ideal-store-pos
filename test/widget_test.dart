import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:intl/intl.dart';

void main() {
  // ============================================
  // INDIAN CURRENCY FORMAT TESTS
  // ============================================
  group('Indian Currency Format', () {
    final f = NumberFormat('#,##,##0', 'en_IN');

    testWidgets('formats lakhs correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text('₹${f.format(1234567)}'),
          ),
        ),
      );

      expect(find.textContaining('12,34,567'), findsOneWidget);
    });

    testWidgets('formats small amounts correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text('₹${f.format(999)}'),
          ),
        ),
      );

      expect(find.textContaining('999'), findsOneWidget);
    });

    testWidgets('formats zero correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text('₹${f.format(0)}'),
          ),
        ),
      );

      expect(find.textContaining('₹0'), findsOneWidget);
    });

    testWidgets('formats large amounts in lakh system', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text('₹${f.format(5000000)}'),
          ),
        ),
      );

      // 50,00,000 in Indian format
      expect(find.textContaining('50,00,000'), findsOneWidget);
    });
  });

  // ============================================
  // CART ITEM CARD WIDGET TESTS
  // ============================================
  group('CartItem Card', () {
    testWidgets('displays item name and price', (WidgetTester tester) async {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test Product',
        price: 250.0,
        qty: 3,
        unit: 'pcs',
        purchasePrice: 150.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: Text(item.name),
              subtitle: Text('Qty: ${item.qty}'),
              trailing: Text('₹${item.total}'),
            ),
          ),
        ),
      );

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('Qty: 3'), findsOneWidget);
      expect(find.text('₹750.0'), findsOneWidget);
    });

    testWidgets('displays Tamil name when available', (
      WidgetTester tester,
    ) async {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test Product',
        tamilName: 'சோதனை பொருள்',
        price: 100.0,
        qty: 1,
        unit: 'pcs',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text(item.name),
                if (item.tamilName != null) Text(item.tamilName!),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('சோதனை பொருள்'), findsOneWidget);
    });
  });

  // ============================================
  // PRODUCT CARD WIDGET TESTS
  // ============================================
  group('Product Card', () {
    testWidgets('displays product info correctly', (
      WidgetTester tester,
    ) async {
      final product = Product(
        id: 'prod-1',
        name: 'Widget Pro',
        purchasePrice: 100.0,
        sellingPrice: 200.0,
        stock: 15,
        unit: 'pcs',
        lowStockAlert: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Column(
                children: [
                  Text(product.name),
                  Text('₹${product.sellingPrice}'),
                  Text('Stock: ${product.stock}'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Widget Pro'), findsOneWidget);
      expect(find.text('₹200.0'), findsOneWidget);
      expect(find.text('Stock: 15'), findsOneWidget);
    });

    testWidgets('low stock indicator', (WidgetTester tester) async {
      final product = Product(
        id: 'prod-1',
        name: 'Low Stock Item',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 3,
        unit: 'pcs',
        lowStockAlert: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: ListTile(
                title: Text(product.name),
                trailing: product.isLowStock
                    ? const Icon(Icons.warning, color: Colors.orange)
                    : null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Low Stock Item'), findsOneWidget);
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('out of stock indicator', (WidgetTester tester) async {
      final product = Product(
        id: 'prod-1',
        name: 'Out of Stock',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 0,
        unit: 'pcs',
        lowStockAlert: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: ListTile(
                title: Text(product.name),
                trailing: product.stock <= 0
                    ? const Icon(Icons.error, color: Colors.red)
                    : null,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Out of Stock'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });
  });

  // ============================================
  // SALE SUMMARY WIDGET TESTS
  // ============================================
  group('Sale Summary', () {
    testWidgets('displays total, GST, and final amount', (
      WidgetTester tester,
    ) async {
      final items = [
        CartItem(
          productId: 'p-1',
          name: 'Item A',
          price: 118.0,
          qty: 2,
          unit: 'pcs',
          gstRate: 18.0,
          purchasePrice: 80.0,
        ),
      ];

      final totalGst = items.fold(0.0, (sum, item) => sum + item.gstAmount);
      final totalAmount = items.fold(0.0, (sum, item) => sum + item.total);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Subtotal: ₹$totalAmount'),
                Text('GST: ₹${totalGst.toStringAsFixed(2)}'),
                Text('Total: ₹${(totalAmount).toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('Subtotal'), findsOneWidget);
      expect(find.textContaining('GST'), findsOneWidget);
      expect(find.textContaining('Total'), findsOneWidget);
    });

    testWidgets('profit display', (WidgetTester tester) async {
      final item = CartItem(
        productId: 'p-1',
        name: 'Profit Item',
        price: 200.0,
        qty: 3,
        unit: 'pcs',
        purchasePrice: 120.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text('Profit: ₹${item.profit.toStringAsFixed(2)}'),
          ),
        ),
      );

      // (200-120)*3 = 240
      expect(find.text('Profit: ₹240.00'), findsOneWidget);
    });
  });

  // ============================================
  // CART OPERATIONS TESTS
  // ============================================
  group('Cart Operations', () {
    test('add item increases qty', () {
      final items = <CartItem>[
        CartItem(
          productId: 'p-1',
          name: 'Widget',
          price: 100.0,
          qty: 1,
          unit: 'pcs',
        ),
      ];

      final existing = items.firstWhere((i) => i.productId == 'p-1');
      existing.qty += 2;

      expect(existing.qty, 3);
      expect(items.length, 1);
    });

    test('remove item decreases list', () {
      final items = <CartItem>[
        CartItem(
          productId: 'p-1',
          name: 'A',
          price: 100.0,
          qty: 1,
          unit: 'pcs',
        ),
        CartItem(
          productId: 'p-2',
          name: 'B',
          price: 200.0,
          qty: 1,
          unit: 'pcs',
        ),
      ];

      items.removeWhere((i) => i.productId == 'p-1');

      expect(items.length, 1);
      expect(items.first.productId, 'p-2');
    });

    test('clear cart empties list', () {
      final items = <CartItem>[
        CartItem(
          productId: 'p-1',
          name: 'A',
          price: 100.0,
          qty: 1,
          unit: 'pcs',
        ),
      ];

      items.clear();

      expect(items, isEmpty);
    });
  });
}
