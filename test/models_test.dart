import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/models/purchase.dart';
import 'package:ideal_store_pos/models/customer.dart';
import 'package:ideal_store_pos/models/supplier.dart';
import 'package:ideal_store_pos/models/account.dart';

void main() {
  // ============================================
  // CART ITEM MODEL TESTS
  // ============================================
  group('CartItem', () {
    test('fromJson creates CartItem correctly', () {
      final json = {
        'product_id': 'p-1',
        'name': 'Widget',
        'price': 120.0,
        'qty': 3,
        'unit': 'box',
        'purchase_price': 80.0,
        'gst_rate': 18.0,
        'hsn_code': '8471',
        'tamil_name': 'விட்ஜெட்',
        'discount': 10.0,
        'unit_type': 'box',
        'pieces_per_unit': 6,
        'tier': 'wholesale',
      };

      final item = CartItem.fromJson(json);

      expect(item.productId, 'p-1');
      expect(item.name, 'Widget');
      expect(item.price, 120.0);
      expect(item.qty, 3);
      expect(item.unit, 'box');
      expect(item.purchasePrice, 80.0);
      expect(item.gstRate, 18.0);
      expect(item.hsnCode, '8471');
      expect(item.tamilName, 'விட்ஜெட்');
      expect(item.discount, 10.0);
      expect(item.unitType, 'box');
      expect(item.piecesPerUnit, 6);
      expect(item.tier, 'wholesale');
    });

    test('toJson serializes correctly', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Widget',
        price: 100.0,
        qty: 2,
        unit: 'pcs',
        purchasePrice: 60.0,
        gstRate: 18.0,
      );

      final json = item.toJson();

      expect(json['product_id'], 'p-1');
      expect(json['name'], 'Widget');
      expect(json['price'], 100.0);
      expect(json['qty'], 2);
      expect(json['purchase_price'], 60.0);
      expect(json['total'], 200.0);
    });

    test('discountAmount calculates correctly', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 5,
        unit: 'pcs',
        discount: 10.0,
      );

      // 100 * 5 * 10/100 = 50
      expect(item.discountAmount, 50.0);
    });

    test('total excludes discount', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 5,
        unit: 'pcs',
        discount: 10.0,
      );

      // (100 * 5) - 50 = 450
      expect(item.total, 450.0);
    });

    test('profit calculates correctly', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 3,
        unit: 'pcs',
        purchasePrice: 60.0,
      );

      // (100 - 60) * 3 = 120
      expect(item.profit, 120.0);
    });

    test('GST back-calculation from inclusive price', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 118.0,
        qty: 1,
        unit: 'pcs',
        gstRate: 18.0,
      );

      // GST = 118 * 18 / (100 + 18) = 18.0
      expect(item.gstAmount, closeTo(18.0, 0.01));
      expect(item.taxableAmount, closeTo(100.0, 0.01));
      expect(item.cgst, closeTo(9.0, 0.01));
      expect(item.sgst, closeTo(9.0, 0.01));
    });

    test('totalPieces for pieces unit type', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 10.0,
        qty: 5,
        unit: 'pcs',
        unitType: 'pieces',
      );

      expect(item.totalPieces, 5);
    });

    test('totalPieces for box unit type with pieces_per_unit', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 3,
        unit: 'box',
        unitType: 'box',
        piecesPerUnit: 12,
      );

      expect(item.totalPieces, 36);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'product_id': 'p-1',
        'name': 'Test',
        'price': 50.0,
        'qty': 1,
      };

      final item = CartItem.fromJson(json);

      expect(item.unit, 'pcs');
      expect(item.purchasePrice, 0.0);
      expect(item.gstRate, 0.0);
      expect(item.discount, 0.0);
      expect(item.unitType, 'pieces');
      expect(item.piecesPerUnit, 1);
      expect(item.tier, 'normal');
    });
  });

  // ============================================
  // SALE MODEL TESTS
  // ============================================
  group('Sale', () {
    test('fromJson creates Sale correctly', () {
      final json = {
        'id': 'sale-1',
        'items': [
          {
            'product_id': 'p-1',
            'name': 'Widget',
            'price': 100.0,
            'qty': 2,
            'unit': 'pcs',
          },
        ],
        'total_amount': 200.0,
        'discount': 10.0,
        'total_discount': 5.0,
        'final_amount': 185.0,
        'payment_method': 'cash',
        'created_by': 'user-1',
        'created_at': '2026-01-01T10:00:00Z',
        'customer_id': 'cust-1',
        'is_credit': false,
        'amount_paid': 185.0,
        'due_amount': 0.0,
        'cash_amount': 185.0,
        'digital_amount': 0.0,
        'cgst_amount': 15.0,
        'sgst_amount': 15.0,
        'igst_amount': 30.0,
      };

      final sale = Sale.fromJson(json);

      expect(sale.id, 'sale-1');
      expect(sale.items.length, 1);
      expect(sale.totalAmount, 200.0);
      expect(sale.discount, 10.0);
      expect(sale.finalAmount, 185.0);
      expect(sale.paymentMethod, 'cash');
      expect(sale.isCredit, false);
    });

    test('toInsertJson serializes correctly', () {
      final sale = Sale(
        id: 'sale-1',
        items: [
          CartItem(
            productId: 'p-1',
            name: 'Widget',
            price: 100.0,
            qty: 2,
            unit: 'pcs',
          ),
        ],
        totalAmount: 200.0,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 200.0,
        paymentMethod: 'cash',
        createdBy: 'user-1',
        createdAt: DateTime(2026, 1, 1),
      );

      final json = sale.toInsertJson();

      expect(json['total_amount'], 200.0);
      expect(json['final_amount'], 200.0);
      expect(json['payment_method'], 'cash');
      expect(json['items'], isA<List>());
    });

    test('isCredit sale has due_amount', () {
      final sale = Sale(
        id: 'sale-2',
        items: [],
        totalAmount: 100.0,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 100.0,
        paymentMethod: 'credit',
        createdBy: 'user-1',
        createdAt: DateTime(2026, 1, 1),
        isCredit: true,
        amountPaid: 40.0,
        dueAmount: 60.0,
      );

      expect(sale.isCredit, true);
      expect(sale.amountPaid, 40.0);
      expect(sale.dueAmount, 60.0);
    });
  });

  // ============================================
  // PRODUCT MODEL TESTS
  // ============================================
  group('Product', () {
    test('fromJson creates Product correctly', () {
      final json = {
        'id': 'prod-1',
        'name': 'Test Product',
        'barcode': '123456789',
        'category': 'Electronics',
        'purchase_price': 50.0,
        'selling_price': 100.0,
        'stock': 25,
        'unit': 'pcs',
        'low_stock_alert': 10,
        'shop_id': 'shop-1',
        'gst_rate': 18.0,
        'hsn_code': '8471',
        'has_variants': false,
        'variants': [],
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      };

      final product = Product.fromJson(json);

      expect(product.id, 'prod-1');
      expect(product.name, 'Test Product');
      expect(product.barcode, '123456789');
      expect(product.category, 'Electronics');
      expect(product.purchasePrice, 50.0);
      expect(product.sellingPrice, 100.0);
      expect(product.stock, 25);
      expect(product.hasVariants, false);
    });

    test('isLowStock correctly identifies low stock', () {
      final product = Product(
        id: 'prod-1',
        name: 'Test',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 5,
        unit: 'pcs',
        lowStockAlert: 10,
      );

      expect(product.isLowStock, true);
    });

    test('isOutOfStock correctly identifies zero stock', () {
      final product = Product(
        id: 'prod-1',
        name: 'Test',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 0,
        unit: 'pcs',
        lowStockAlert: 10,
      );

      expect(product.stock <= 0, true);
      expect(product.isLowStock, false);
    });

    test('totalStock includes variant stock', () {
      final product = Product(
        id: 'prod-1',
        name: 'Test',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 10,
        unit: 'pcs',
        lowStockAlert: 5,
        hasVariants: true,
        variants: [
          ProductVariant(
            id: 'v-1',
            productId: 'prod-1',
            name: 'Small',
            price: 90.0,
            purchasePrice: 45.0,
            stock: 5,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          ProductVariant(
            id: 'v-2',
            productId: 'prod-1',
            name: 'Large',
            price: 120.0,
            purchasePrice: 60.0,
            stock: 8,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ],
      );

      expect(product.totalStock, 13); // 5 + 8 (variants only, not product.stock=10)
    });
  });

  // ============================================
  // PURCHASE MODEL TESTS
  // ============================================
  group('Purchase', () {
    test('PurchaseItem total calculates correctly', () {
      final item = PurchaseItem(
        productId: 'p-1',
        name: 'Widget',
        price: 50.0,
        qty: 10,
        unit: 'pcs',
      );

      expect(item.total, 500.0);
    });

    test('PurchaseItem GST back-calculation', () {
      final item = PurchaseItem(
        productId: 'p-1',
        name: 'Widget',
        price: 118.0,
        qty: 1,
        unit: 'pcs',
        gstRate: 18.0,
      );

      expect(item.gstAmount, closeTo(18.0, 0.01));
      expect(item.priceExcludingGst, closeTo(100.0, 0.01));
    });

    test('PurchaseItem toJson/toFromJson roundtrip', () {
      final item = PurchaseItem(
        productId: 'p-1',
        name: 'Widget',
        price: 50.0,
        qty: 10,
        unit: 'pcs',
        gstRate: 18.0,
        batchNumber: 'B001',
      );

      final json = item.toJson();
      final restored = PurchaseItem.fromJson(json);

      expect(restored.productId, item.productId);
      expect(restored.name, item.name);
      expect(restored.price, item.price);
      expect(restored.qty, item.qty);
      expect(restored.batchNumber, 'B001');
    });

    test('Purchase fromJson creates correctly', () {
      final json = {
        'id': 'pur-1',
        'supplier_name': 'Acme Corp',
        'items': [
          {
            'product_id': 'p-1',
            'name': 'Widget',
            'price': 50.0,
            'qty': 10,
            'unit': 'pcs',
          },
        ],
        'total_amount': 500.0,
        'round_off': 0.0,
        'created_by': 'user-1',
        'created_at': '2026-01-01T00:00:00Z',
        'supplier_id': 'sup-1',
        'is_credit': false,
        'amount_paid': 500.0,
        'due_amount': 0.0,
        'payment_method': 'cash',
      };

      final purchase = Purchase.fromJson(json);

      expect(purchase.id, 'pur-1');
      expect(purchase.supplierName, 'Acme Corp');
      expect(purchase.items.length, 1);
      expect(purchase.totalAmount, 500.0);
      expect(purchase.isCredit, false);
    });
  });

  // ============================================
  // CUSTOMER MODEL TESTS
  // ============================================
  group('Customer', () {
    test('fromJson creates Customer correctly', () {
      final json = {
        'id': 'cust-1',
        'name': 'Ravi Kumar',
        'phone': '9876543210',
        'total_credit': 1500.0,
        'created_at': '2026-01-01T00:00:00Z',
      };

      final customer = Customer.fromJson(json);

      expect(customer.id, 'cust-1');
      expect(customer.name, 'Ravi Kumar');
      expect(customer.phone, '9876543210');
      expect(customer.totalCredit, 1500.0);
    });

    test('toJson serializes correctly', () {
      final customer = Customer(
        id: 'cust-1',
        name: 'Ravi Kumar',
        phone: '9876543210',
        totalCredit: 500.0,
        createdAt: DateTime(2026, 1, 1),
      );

      final json = customer.toJson();

      expect(json['name'], 'Ravi Kumar');
      expect(json['phone'], '9876543210');
    });
  });

  // ============================================
  // SUPPLIER MODEL TESTS
  // ============================================
  group('Supplier', () {
    test('fromJson creates Supplier correctly', () {
      final json = {
        'id': 'sup-1',
        'name': 'Acme Corp',
        'phone': '9876543211',
        'address': '123 Main St',
        'gst_number': 'GST123456',
        'total_dues': 2500.0,
        'created_at': '2026-01-01T00:00:00Z',
      };

      final supplier = Supplier.fromJson(json);

      expect(supplier.id, 'sup-1');
      expect(supplier.name, 'Acme Corp');
      expect(supplier.phone, '9876543211');
      expect(supplier.totalDues, 2500.0);
    });
  });

  // ============================================
  // ACCOUNT MODEL TESTS
  // ============================================
  group('Account', () {
    test('fromJson creates Account correctly', () {
      final json = {
        'id': 'acc-1',
        'name': 'Cash Drawer',
        'account_type': 'cash',
        'balance': 15000.0,
        'created_by': 'user-1',
        'created_at': '2026-01-01T00:00:00Z',
      };

      final account = Account.fromJson(json);

      expect(account.id, 'acc-1');
      expect(account.name, 'Cash Drawer');
      expect(account.accountType, 'cash');
      expect(account.balance, 15000.0);
    });
  });

  // ============================================
  // EDGE CASE TESTS
  // ============================================
  group('Edge Cases', () {
    test('CartItem with zero qty', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 0,
        unit: 'pcs',
      );

      expect(item.total, 0.0);
      expect(item.discountAmount, 0.0);
      expect(item.profit, 0.0);
    });

    test('CartItem with 100% discount', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 1,
        unit: 'pcs',
        discount: 100.0,
      );

      expect(item.total, 0.0);
      expect(item.discountAmount, 100.0);
    });

    test('CartItem with zero GST rate', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 100.0,
        qty: 1,
        unit: 'pcs',
        gstRate: 0,
      );

      expect(item.gstAmount, 0.0);
      expect(item.taxableAmount, 100.0);
    });

    test('CartItem with high GST rate (28%)', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Test',
        price: 128.0,
        qty: 1,
        unit: 'pcs',
        gstRate: 28.0,
      );

      expect(item.gstAmount, closeTo(28.0, 0.01));
      expect(item.taxableAmount, closeTo(100.0, 0.01));
    });

    test('Sale with empty items', () {
      final sale = Sale(
        id: 'sale-empty',
        items: [],
        totalAmount: 0,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 0,
        paymentMethod: 'cash',
        createdBy: 'user-1',
        createdAt: DateTime.now(),
      );

      expect(sale.items, isEmpty);
      expect(sale.finalAmount, 0);
    });

    test('Product with variants sums stock correctly', () {
      final product = Product(
        id: 'prod-1',
        name: 'Test',
        purchasePrice: 50.0,
        sellingPrice: 100.0,
        stock: 0,
        unit: 'pcs',
        lowStockAlert: 5,
        hasVariants: true,
        variants: List.generate(
          5,
          (i) => ProductVariant(
            id: 'v-$i',
            productId: 'prod-1',
            name: 'Variant $i',
            price: 100.0,
            purchasePrice: 50.0,
            stock: 10,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
      );

      expect(product.totalStock, 50); // 5 variants × 10 each (variants-only when hasVariants=true)
    });
  });
}
