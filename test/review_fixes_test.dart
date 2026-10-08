import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ideal_store_pos/config/desktop_billing_provider.dart';
import 'package:ideal_store_pos/config/hive_adapter.dart';
import 'package:ideal_store_pos/models/product.dart';
import 'package:ideal_store_pos/models/product_return.dart';
import 'package:ideal_store_pos/models/purchase.dart';
import 'package:ideal_store_pos/models/purchase_order.dart';
import 'package:ideal_store_pos/models/profile.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/services/backup_service.dart';
import 'package:ideal_store_pos/services/gst_export_service.dart';
import 'package:ideal_store_pos/services/profile_cache.dart';
import 'package:ideal_store_pos/utils/paged_query.dart';
import 'package:ideal_store_pos/utils/qty_format.dart';
import 'package:ideal_store_pos/utils/search_term.dart';
import 'package:ideal_store_pos/utils/thermal_invoice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixes from the October 2026 review (numbers match the review list).
void main() {
  group('1. the app opens offline after a restart', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('profile_cache_test');
      Hive.init(dir.path);
      await Hive.openBox<Map>(HiveAdapter.cachedProfileBox,
          encryptionCipher: HiveAesCipher(List<int>.generate(32, (i) => i)));
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    final profile = Profile(id: 'u1', name: 'Ravi', role: 'staff', shopId: 's', pin: 'hash');

    test('the last profile is kept for the same user', () async {
      await ProfileCache.save(profile);
      final back = ProfileCache.read('u1');
      expect(back?.role, 'staff');
      expect(back?.pin, 'hash'); // the till can still be unlocked offline
    });

    test('another user never gets it, and sign-out clears it', () async {
      await ProfileCache.save(profile);
      expect(ProfileCache.read('someone-else'), isNull);
      await ProfileCache.clear();
      expect(ProfileCache.read('u1'), isNull);
    });
  });

  group('2. reports read every bill, not only the first 1000', () {
    test('all pages are read, in a stable order', () async {
      final requests = <Uri>[];
      final client = MockClient((req) async {
        requests.add(req.url);
        final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
        final limit = int.parse(req.url.queryParameters['limit']!);
        final rows = [
          for (var i = offset; i < offset + limit && i < 2500; i++) {'id': 'id$i'},
        ];
        return http.Response(jsonEncode(rows), 200, headers: {'content-type': 'application/json'}, request: req);
      });
      final db = PostgrestClient('http://db.test', httpClient: client);

      final rows = await fetchAllRows(() => db.from('sales').select('id').gte('created_at', '2026-10-01'));

      expect(rows, hasLength(2500));
      expect(rows.map((r) => r['id']).toSet(), hasLength(2500)); // nothing repeated
      expect(requests, hasLength(3));
      expect(requests.first.queryParameters['order'], startsWith('id.asc'));
      expect(requests.first.queryParameters['created_at'], 'gte.2026-10-01');
    });
  });

  group('3. a held edit stays an edit after a restart', () {
    test('the sale being edited is saved with the held bill', () {
      final original = Sale(
        id: '6f1c2a10-0000-4000-8000-000000000001',
        items: [CartItem(productId: 'p', name: 'Rice', price: 60, qty: 2, unit: 'kg')],
        totalAmount: 120,
        discount: 0,
        totalDiscount: 0,
        finalAmount: 120,
        paymentMethod: 'cash',
        createdBy: 'u',
        createdAt: DateTime.utc(2026, 10, 1),
        invoiceNo: 77,
      );
      final held = HeldBill(
        session: SaleSession(id: 'sale_1', items: [DesktopCartItem(productId: 'p', name: 'Rice', price: 60, qty: 1.5, unit: 'kg')]),
        time: DateTime.utc(2026, 10, 2),
        editingSale: original,
      );

      // what is written to disk and read back on the next start
      final back = HeldBill.fromJson(jsonDecode(jsonEncode(held.toJson())) as Map<String, dynamic>);

      expect(back.editingSale?.id, original.id);
      expect(back.editingSale?.invoiceNo, 77);
      expect(back.session.items.single.qty, 1.5);
    });

    test('an ordinary held bill has no sale attached', () {
      final held = HeldBill(session: SaleSession(id: 'sale_2', items: []), time: DateTime.utc(2026));
      expect(HeldBill.fromJson(held.toJson()).editingSale, isNull);
    });
  });

  group('4. backups read each table in key order', () {
    test('every table has a sort key', () {
      for (final t in BackupService.tables) {
        expect(BackupService.orderColumns(t), isNotEmpty, reason: t);
      }
      expect(BackupService.orderColumns('sales'), ['id']);
      expect(BackupService.orderColumns('app_config'), ['key']);
      expect(BackupService.orderColumns('legacy_postings'), ['ref_type', 'ref_id', 'account_id']);
    });
  });

  group('5. an offline bill is marked provisional', () {
    Sale sale({int? invoiceNo}) => Sale(
          id: 'abcdef12-0000-4000-8000-000000000000',
          items: [CartItem(productId: 'p', name: 'Soap', price: 30, qty: 1, unit: 'pcs')],
          totalAmount: 30,
          discount: 0,
          totalDiscount: 0,
          finalAmount: 30,
          paymentMethod: 'cash',
          createdBy: 'u',
          createdAt: DateTime.utc(2026, 10, 8, 6),
          invoiceNo: invoiceNo,
        );

    test('no bill number yet', () {
      final r = ThermalInvoice.generate(sale: sale(), shopName: 'Ideal Store');
      expect(r.headerLines.join('\n'), contains('Bill No: ABCDEF12 (offline - provisional)'));
    });

    test('a synced bill shows its real number only', () {
      final r = ThermalInvoice.generate(sale: sale(invoiceNo: 1201), shopName: 'Ideal Store');
      expect(r.headerLines, contains('Bill No: 1201'));
    });
  });

  group('10. GST report = the tax the database stored', () {
    test('IGST, bill discount and tax-exempt bills are respected', () {
      final rows = GstExportService().hsnRows([
        {
          // inter-state: 18% soap, ₹10 bill discount, database stored IGST
          'final_amount': 108.0, 'tax_exempt': false,
          'cgst_amount': 0, 'sgst_amount': 0, 'igst_amount': 16.47,
          'items': [
            {'name': 'Soap', 'hsn_code': '3401', 'gst_rate': 18, 'qty': 4, 'total': 118.0, 'unit': 'pcs'},
          ],
        },
        {
          'final_amount': 50.0, 'tax_exempt': true,
          'cgst_amount': 0, 'sgst_amount': 0, 'igst_amount': 0,
          'items': [
            {'name': 'Soap', 'hsn_code': '3401', 'gst_rate': 18, 'qty': 2, 'total': 50.0, 'unit': 'pcs'},
          ],
        },
      ]);
      final soap = rows.single;
      expect(soap['igst'] as double, closeTo(16.47, 0.01));
      expect(soap['cgst'] as double, closeTo(0, 0.001));
      expect(soap['value'] as double, closeTo(158, 0.01)); // after the bill discount
      expect(soap['taxable'] as double, closeTo(158 - 16.47, 0.01));
      expect(soap['qty'], 6);
    });
  });

  group('11. decimal quantities and stock', () {
    test('a sale line keeps 1.5 kg', () {
      final line = CartItem.fromJson({'product_id': 'p', 'name': 'Dal', 'price': 120, 'qty': 1.5, 'unit': 'kg'});
      expect(line.qty, 1.5);
      expect(line.total, 180);
      final till = DesktopCartItem.fromHeldJson(
          DesktopCartItem(productId: 'p', name: 'Dal', price: 120, qty: 0.25, unit: 'kg').toHeldJson());
      expect(till.qty, 0.25);
      expect(till.total, 30);
    });

    test('stock is no longer rounded down', () {
      final p = Product.fromJson({'id': 'p', 'name': 'Dal', 'stock': 0.5});
      expect(p.stock, 0.5); // it read as 0: "out of stock"
      expect(p.isLowStock, isTrue);
    });

    test('purchases, purchase orders and returns keep decimals', () {
      final bought = PurchaseItem.fromJson({'product_id': 'p', 'name': 'Dal', 'price': 120, 'qty': 25.5, 'unit': 'kg'});
      expect(bought.qty, 25.5); // it was rounded to 26
      expect(bought.total, 3060);
      expect(PurchaseItem.fromJson(bought.toJson()).qty, 25.5);
      expect(PurchaseOrderItem.fromJson({'product_id': 'p', 'name': 'Dal', 'qty': 2.5, 'price': 120}).qty, 2.5);
      final back = ProductReturn.fromJson({'id': 'r', 'product_name': 'Dal', 'quantity': 0.5, 'created_at': '2026-10-08T10:00:00Z'});
      expect(back.quantity, 0.5); // it was rounded to 1 (or 0)
    });

    test('quantities print without needless decimals', () {
      expect(formatQty(2), '2');
      expect(formatQty(2.0), '2');
      expect(formatQty(1.5), '1.5');
      expect(formatQty(0.25), '0.25');
      expect(formatQty(0.125), '0.125');
    });
  });

  group('18. search text with commas or brackets', () {
    test('characters with a meaning in the filter are removed', () {
      expect(searchTerm('Kumar, R'), 'Kumar  R');
      expect(searchTerm('(Shop) "A"'), 'Shop   A');
      expect(searchTerm('  9876543210 '), '9876543210');
    });
  });
}
