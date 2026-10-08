import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ideal_store_pos/config/desktop_billing_provider.dart';
import 'package:ideal_store_pos/config/supabase_config.dart';
import 'package:ideal_store_pos/models/purchase.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/services/gst_export_service.dart';
import 'package:ideal_store_pos/services/update_service.dart';
import 'package:ideal_store_pos/utils/payment_methods.dart';
import 'package:ideal_store_pos/utils/validators.dart';

/// Tests for the October 2026 audit fixes (app side). The database side is
/// covered by sql/tests (run in CI against Postgres).
void main() {
  group('Payment methods (#12)', () {
    test('every spelling maps to one vocabulary', () {
      expect(PaymentMethods.normalize('Digital'), 'upi');
      expect(PaymentMethods.normalize('GPay'), 'upi');
      expect(PaymentMethods.normalize('card'), 'bank');
      expect(PaymentMethods.normalize('NEFT'), 'bank');
      expect(PaymentMethods.normalize(null), 'cash');
      expect(PaymentMethods.normalize('udhaar'), 'credit');
      expect(PaymentMethods.normalize('mixed'), 'split');
    });

    test('UPI and bank land in the bank account, the rest in cash', () {
      expect(PaymentMethods.accountType('upi'), 'bank');
      expect(PaymentMethods.accountType('bank'), 'bank');
      expect(PaymentMethods.accountType('digital'), 'bank');
      expect(PaymentMethods.accountType('cash'), 'cash');
      expect(PaymentMethods.accountType('credit'), 'cash');
    });
  });

  group('Validators (#27)', () {
    test('amount', () {
      expect(Validators.amount('45.50'), isNull);
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount('-1'), isNotNull);
      expect(Validators.amount('0'), isNotNull);
      expect(Validators.amount('0', allowZero: true), isNull);
      expect(Validators.amount('', required: false), isNull);
    });

    test('GSTIN and state code', () {
      expect(Validators.gstin('33ABCDE1234F1Z5'), isNull);
      expect(Validators.gstin('33abcde1234f1z5'), isNull);
      expect(Validators.gstin('33ABCDE1234F1Z'), isNotNull);
      expect(Validators.gstin(''), isNull);
      expect(Validators.stateFromGstin('32ABCDE1234F1Z5'), '32');
      expect(Validators.stateFromGstin('bad'), isNull);
    });

    test('phone, quantity, HSN', () {
      expect(Validators.phone('9876543210'), isNull);
      expect(Validators.phone('+91 9876543210'), isNull);
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.quantity('0', min: 0), isNull);
      expect(Validators.quantity('-2', min: 0), isNotNull);
      expect(Validators.quantity('1.5'), isNotNull);
      expect(Validators.hsn('1006'), isNull);
      expect(Validators.hsn('100630'), isNull);
      expect(Validators.hsn('10'), isNotNull);
    });
  });

  group('Stock units (#22)', () {
    test('a box of 12 of a piece-counted product uses 12 stock units', () {
      final f = CartItem.stockFactorFor(
        lineUnitType: 'box',
        linePiecesPerUnit: 12,
        productUnitType: 'pieces',
        productPiecesPerUnit: 1,
      );
      expect(f, 12);
    });

    test('selling in the product\'s own unit uses 1 stock unit', () {
      expect(
        CartItem.stockFactorFor(
          lineUnitType: 'box',
          linePiecesPerUnit: 12,
          productUnitType: 'box',
          productPiecesPerUnit: 12,
        ),
        1,
      );
    });

    test('the factor travels with the line to the database', () {
      final item = CartItem(
        productId: 'p',
        name: 'Soap',
        price: 300,
        qty: 2,
        unit: 'box',
        unitType: 'box',
        piecesPerUnit: 12,
        stockFactor: 12,
      );
      expect(item.toJson()['stock_factor'], 12);
      expect(item.totalPieces, 24);
      expect(CartItem.fromJson(item.toJson()).stockFactor, 12);
    });
  });

  group('Profit after discount', () {
    test('line profit uses the discounted total', () {
      final item = CartItem(
        productId: 'p',
        name: 'A',
        price: 100,
        qty: 2,
        unit: 'pcs',
        purchasePrice: 60,
        discount: 10,
      );
      // total 180, cost 120
      expect(item.profit, 60);
    });

    test('database FIFO cost wins when known', () {
      final item = CartItem.fromJson({
        'product_id': 'p',
        'name': 'A',
        'price': 100,
        'qty': 2,
        'purchase_price': 60,
        'cost_total': 110,
      });
      expect(item.profit, 90);
    });
  });

  group('Sale payload (#5, #15, #19)', () {
    Sale make(String id, double finalAmount) => Sale(
          id: id,
          items: [CartItem(productId: 'p', name: 'A', price: 50, qty: 1, unit: 'pcs')],
          totalAmount: 50,
          discount: 0,
          totalDiscount: 0,
          finalAmount: finalAmount,
          paymentMethod: 'cash',
          createdBy: 'u',
          createdAt: DateTime.utc(2026, 10, 3, 18, 30),
        );

    test('client UUID is sent so a retried save is recognised', () {
      final id = newDocumentId();
      expect(isUuid(id), isTrue);
      expect(make(id, 50).toInsertJson()['id'], id);
      expect(make('local-123', 50).toInsertJson().containsKey('id'), isFalse);
    });

    test('GST split is left to the database and totals are never negative', () {
      final json = make(newDocumentId(), -5).toInsertJson();
      expect(json.containsKey('cgst_amount'), isFalse);
      expect(json['final_amount'], 0);
    });

    test('invoice label prefers the database number', () {
      final s = Sale.fromJson({...make('abcdef12-0000-4000-8000-000000000000', 50).toJson(), 'invoice_no': 1042});
      expect(s.invoiceLabel, '1042');
      expect(make('abcdef12-0000-4000-8000-000000000000', 50).invoiceLabel, 'ABCDEF12');
    });
  });

  group('Desktop held bills keep every field (#22)', () {
    test('round trip', () {
      final item = DesktopCartItem(
        productId: 'p',
        name: 'Rice',
        price: 600,
        qty: 2,
        unit: 'bag',
        unitType: 'bag',
        piecesPerUnit: 10,
        tier: 'wholesale',
        rateLabel: 'Old rate',
        stockFactor: 10,
      );
      final back = DesktopCartItem.fromHeldJson(item.toHeldJson());
      expect(back.stockFactor, 10);
      expect(back.tier, 'wholesale');
      expect(back.rateLabel, 'Old rate');
      expect(back.toCartItem().stockFactor, 10);
    });

    test('edit keeps unit and factor', () {
      final item = DesktopCartItem(productId: 'p', name: 'x', price: 10, qty: 1, unit: 'box', unitType: 'box', piecesPerUnit: 6, stockFactor: 6);
      final edited = item.copyWith(qty: 3, price: 12);
      expect(edited.stockFactor, 6);
      expect(edited.unitType, 'box');
      expect(edited.total, 36);
    });
  });

  group('Purchase line copy keeps batch and expiry (#8)', () {
    test('copyWith', () {
      final item = PurchaseItem(
        productId: 'p',
        name: 'Oil',
        price: 100,
        qty: 5,
        unit: 'pcs',
        batchNumber: 'B1',
        expiryDate: DateTime(2027, 1, 1),
      );
      final c = item.copyWith(qty: 6);
      expect(c.batchNumber, 'B1');
      expect(c.expiryDate, DateTime(2027, 1, 1));
      expect(item.copyWith(batchNumber: null).batchNumber, isNull);
    });
  });

  group('Updates (#32)', () {
    test('only a higher version is offered', () {
      expect(UpdateService.isNewer('1.1.0', '1.0.122'), isTrue);
      expect(UpdateService.isNewer('1.0.122', '1.0.122'), isFalse);
      expect(UpdateService.isNewer('1.0.9', '1.0.10'), isFalse);
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('bundled trusted certificate list loads (fresh-laptop TLS fix)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final data = await rootBundle.load(UpdateService.certsAsset);
      final pem = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final count = RegExp('BEGIN CERTIFICATE').allMatches(String.fromCharCodes(pem)).length;
      expect(count, greaterThan(100));
      // throws if any certificate in the list is unreadable
      expect(UpdateService.securityContextFor(pem), isNotNull);
    });
  });

  group('GSTR-1 (#23)', () {
    test('place of supply uses the portal format', () {
      expect(GstExportService.placeOfSupply('33'), '33-Tamil Nadu');
      expect(GstExportService.placeOfSupply('7'), '07-Delhi');
    });
  });

  group('Supabase config', () {
    test('URL and anon key are the right kind of value', () {
      expect(SupabaseConfig.supabaseUrl, startsWith('https://'));
      // the anon key is a JWT, never the URL
      expect(SupabaseConfig.supabaseAnonKey, startsWith('eyJ'));
      expect(SupabaseConfig.supabaseAnonKey.split('.').length, 3);
    });
  });
}
