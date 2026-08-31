import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/models/customer.dart';
import 'package:ideal_store_pos/models/supplier.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/models/account.dart';
import 'package:ideal_store_pos/models/profile.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/utils/pin_auth.dart';
import 'package:ideal_store_pos/utils/app_timezone.dart';

void main() {
  // ============================================
  // PIN AUTH TESTS
  // ============================================
  group('PinAuth', () {
    test('derivePassword returns consistent 64-char hex', () {
      final p1 = PinAuth.derivePassword('test@example.com', '1234');
      final p2 = PinAuth.derivePassword('test@example.com', '1234');

      expect(p1, equals(p2));
      expect(p1.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(p1), isTrue);
    });

    test('derivePassword differs for different emails', () {
      final p1 = PinAuth.derivePassword('a@test.com', '1234');
      final p2 = PinAuth.derivePassword('b@test.com', '1234');

      expect(p1, isNot(equals(p2)));
    });

    test('derivePassword differs for different PINs', () {
      final p1 = PinAuth.derivePassword('test@example.com', '1234');
      final p2 = PinAuth.derivePassword('test@example.com', '5678');

      expect(p1, isNot(equals(p2)));
    });

    test('derivePassword is NOT the raw PIN', () {
      final derived = PinAuth.derivePassword('test@example.com', '1234');

      expect(derived, isNot(equals('1234')));
      expect(derived.contains('1234'), isFalse);
    });

    test('hashPin returns consistent hash', () {
      final h1 = PinAuth.hashPin('1234');
      final h2 = PinAuth.hashPin('1234');

      expect(h1, equals(h2));
      expect(h1.length, equals(64));
    });

    test('verifyPin returns true for matching pin and hash', () {
      final hash = PinAuth.hashPin('1234');

      expect(PinAuth.verifyPin('1234', hash), isTrue);
    });

    test('verifyPin returns false for wrong pin', () {
      final hash = PinAuth.hashPin('1234');

      expect(PinAuth.verifyPin('5678', hash), isFalse);
    });
  });

  // ============================================
  // APP TIMEZONE TESTS
  // ============================================
  group('AppTimezone', () {
    test('nowIst returns IST time', () {
      final ist = AppTimezone.nowIst();
      final utc = DateTime.now().toUtc();

      final diff = ist.difference(utc);
      expect(diff.inHours, equals(5));
    });

    test('todayStartUtc returns UTC midnight for IST today', () {
      final start = AppTimezone.todayStartUtc();

      expect(start.isUtc, isTrue);
    });

    test('todayEndUtc is one day after todayStartUtc', () {
      final start = AppTimezone.todayStartUtc();
      final end = AppTimezone.todayEndUtc();

      expect(end.difference(start).inDays, equals(1));
    });

    test('monthStartUtc returns first day of month in UTC', () {
      final start = AppTimezone.monthStartUtc();
      final now = AppTimezone.nowIst();

      // monthStartUtc returns midnight IST of day 1, converted to UTC.
      // When IST is ahead of UTC, this can land on the previous month's last day.
      expect(start.isUtc, isTrue);
      // Verify it's within 1 day of the expected UTC start
      final expectedUtcStart = DateTime.utc(now.year, now.month, 1);
      final diff = start.difference(expectedUtcStart).abs();
      expect(diff.inHours, lessThanOrEqualTo(12));
    });
  });

  // ============================================
  // CUSTOMER MODEL TESTS
  // ============================================
  group('Customer Model', () {
    test('fromJson creates valid Customer', () {
      final json = {
        'id': 'test-id',
        'name': 'Test Customer',
        'phone': '1234567890',
        'address': 'Test Address',
        'total_credit': 500.0,
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final customer = Customer.fromJson(json);

      expect(customer.id, 'test-id');
      expect(customer.name, 'Test Customer');
      expect(customer.phone, '1234567890');
      expect(customer.totalCredit, 500.0);
    });

    test('toInsertJson excludes id and total_credit', () {
      final customer = Customer(
        id: 'test-id',
        name: 'Test Customer',
        createdAt: DateTime.now(),
      );

      final json = customer.toInsertJson();

      expect(json.containsKey('id'), false);
      expect(json.containsKey('total_credit'), false);
      expect(json['name'], 'Test Customer');
    });
  });

  // ============================================
  // SUPPLIER MODEL TESTS
  // ============================================
  group('Supplier Model', () {
    test('fromJson creates valid Supplier', () {
      final json = {
        'id': 'test-id',
        'name': 'Test Supplier',
        'phone': '1234567890',
        'address': 'Test Address',
        'gst_number': 'GST123',
        'total_dues': 1000.0,
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final supplier = Supplier.fromJson(json);

      expect(supplier.id, 'test-id');
      expect(supplier.name, 'Test Supplier');
      expect(supplier.gstNumber, 'GST123');
      expect(supplier.totalDues, 1000.0);
    });
  });

  // ============================================
  // PRODUCT MODEL TESTS
  // ============================================
  group('Product Model', () {
    test('fromJson creates valid Product', () {
      final json = {
        'id': 'test-id',
        'name': 'Test Product',
        'barcode': '123456789',
        'category': 'Electronics',
        'purchase_price': 100.0,
        'selling_price': 150.0,
        'stock': 50,
        'unit': 'pcs',
        'low_stock_alert': 10,
        'shop_id': null,
      };

      final product = Product.fromJson(json);

      expect(product.id, 'test-id');
      expect(product.name, 'Test Product');
      expect(product.barcode, '123456789');
      expect(product.purchasePrice, 100.0);
      expect(product.sellingPrice, 150.0);
      expect(product.stock, 50);
    });

    test('isLowStock returns true when stock <= lowStockAlert', () {
      final product = Product(
        id: '1',
        name: 'Low',
        purchasePrice: 10,
        sellingPrice: 20,
        stock: 5,
        lowStockAlert: 10,
      );

      expect(product.isLowStock, isTrue);
    });

    test('isLowStock returns false when stock > lowStockAlert', () {
      final product = Product(
        id: '1',
        name: 'High',
        purchasePrice: 10,
        sellingPrice: 20,
        stock: 50,
        lowStockAlert: 10,
      );

      expect(product.isLowStock, isFalse);
    });
  });

  // ============================================
  // ACCOUNT MODEL TESTS
  // ============================================
  group('Account Model', () {
    test('fromJson creates valid Account', () {
      final json = {
        'id': 'acc-1',
        'name': 'Cash in Hand',
        'account_type': 'cash',
        'balance': 5000.0,
      };

      final account = Account.fromJson(json);

      expect(account.id, 'acc-1');
      expect(account.name, 'Cash in Hand');
      expect(account.accountType, 'cash');
      expect(account.balance, 5000.0);
    });

    test('fromJson handles null balance', () {
      final json = {
        'id': 'acc-1',
        'name': 'Bank',
        'account_type': 'bank',
        'balance': null,
      };

      final account = Account.fromJson(json);

      expect(account.balance, 0.0);
    });
  });

  group('AccountTransaction Model', () {
    test('fromJson creates valid transaction', () {
      final json = {
        'id': 'tx-1',
        'account_id': 'acc-1',
        'type': 'in',
        'amount': 1000.0,
        'category': 'sale',
        'description': 'Test sale',
        'created_at': '2024-01-01T12:00:00.000Z',
      };

      final tx = AccountTransaction.fromJson(json);

      expect(tx.id, 'tx-1');
      expect(tx.type, 'in');
      expect(tx.amount, 1000.0);
      expect(tx.category, 'sale');
      expect(tx.description, 'Test sale');
    });
  });

  // ============================================
  // PROFILE MODEL TESTS
  // ============================================
  group('Profile Model', () {
    test('isAdmin returns true for admin role', () {
      final profile = Profile(
        id: '1',
        name: 'Admin',
        role: 'admin',
        shopId: '',
      );

      expect(profile.isAdmin, isTrue);
      expect(profile.isStaff, isFalse);
    });

    test('isStaff returns true for staff role', () {
      final profile = Profile(
        id: '1',
        name: 'Staff',
        role: 'staff',
        shopId: '',
      );

      expect(profile.isStaff, isTrue);
      expect(profile.isAdmin, isFalse);
    });
  });

  // ============================================
  // CART ITEM TESTS
  // ============================================
  group('CartItem', () {
    test('profit calculates correctly', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 150,
        qty: 2,
        unit: 'pcs',
        purchasePrice: 100,
      );

      expect(item.profit, equals(100)); // (150-100) * 2
    });

    test('total calculates correctly', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 150,
        qty: 3,
        unit: 'pcs',
        purchasePrice: 100,
      );

      expect(item.total, equals(450)); // 150 * 3
    });

    test('toJson includes purchase_price', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 100,
        qty: 1,
        unit: 'pcs',
        purchasePrice: 50,
      );

      final json = item.toJson();

      expect(json['purchase_price'], equals(50));
      expect(json['price'], equals(100));
    });
  });
}
