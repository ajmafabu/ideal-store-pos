import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ideal_store_pos/config/hive_adapter.dart';
import 'package:ideal_store_pos/config/providers.dart';
import 'package:ideal_store_pos/models/sale.dart';
import 'package:ideal_store_pos/services/offline_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('hive_test_');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    final service = OfflineService();
    if (!service.isReady) {
      await service.init();
    }
    await service.pendingBox.clear();
    await Hive.box<Map>(HiveAdapter.pendingOpsBox).clear();
    await Hive.box<Map>(HiveAdapter.pendingWritesBox).clear();
    await Hive.box<Map>(HiveAdapter.cachedSalesBox).clear();
    await Hive.box<Map>(HiveAdapter.cachedProductsBox).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

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

    test('fromJson handles missing optional fields with defaults', () {
      final json = {
        'product_id': 'p-2',
        'name': 'Gadget',
        'price': 50.0,
        'qty': 1,
      };

      final item = CartItem.fromJson(json);

      expect(item.unit, 'pcs');
      expect(item.purchasePrice, 0.0);
      expect(item.gstRate, 0.0);
      expect(item.hsnCode, isNull);
      expect(item.tamilName, isNull);
      expect(item.discount, 0.0);
      expect(item.unitType, 'pieces');
      expect(item.piecesPerUnit, 1);
      expect(item.tier, 'normal');
    });

    test('toJson serializes correctly', () {
      final item = CartItem(
        productId: 'p-1',
        name: 'Widget',
        price: 120.0,
        qty: 3,
        unit: 'box',
        purchasePrice: 80.0,
        gstRate: 18.0,
        hsnCode: '8471',
        tamilName: 'விட்ஜெட்',
        discount: 10.0,
        unitType: 'box',
        piecesPerUnit: 6,
        tier: 'wholesale',
      );

      final json = item.toJson();

      expect(json['product_id'], 'p-1');
      expect(json['name'], 'Widget');
      expect(json['price'], 120.0);
      expect(json['qty'], 3);
      expect(json['unit'], 'box');
      expect(json['purchase_price'], 80.0);
      expect(json['gst_rate'], 18.0);
      expect(json['hsn_code'], '8471');
      expect(json['tamil_name'], 'விட்ஜெட்');
      expect(json['discount'], 10.0);
      expect(json['unit_type'], 'box');
      expect(json['pieces_per_unit'], 6);
      expect(json['tier'], 'wholesale');
    });

    test('fromJson toJson roundtrip preserves all data', () {
      final original = CartItem(
        productId: 'p-rt',
        name: 'Roundtrip',
        price: 250.0,
        qty: 5,
        unit: 'kg',
        purchasePrice: 180.0,
        gstRate: 5.0,
        discount: 15.0,
        unitType: 'weight',
        piecesPerUnit: 1,
        tier: 'bulk',
      );

      final restored = CartItem.fromJson(original.toJson());

      expect(restored.productId, original.productId);
      expect(restored.name, original.name);
      expect(restored.price, original.price);
      expect(restored.qty, original.qty);
      expect(restored.unit, original.unit);
      expect(restored.purchasePrice, original.purchasePrice);
      expect(restored.gstRate, original.gstRate);
      expect(restored.discount, original.discount);
      expect(restored.unitType, original.unitType);
      expect(restored.piecesPerUnit, original.piecesPerUnit);
      expect(restored.tier, original.tier);
    });

    test('total calculates price * qty minus discount', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 100,
        qty: 4,
        unit: 'pcs',
        purchasePrice: 60,
        discount: 10,
      );

      expect(item.total, 360.0);
    });

    test('total with zero discount equals price * qty', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 75.5,
        qty: 2,
        unit: 'pcs',
      );

      expect(item.total, 151.0);
    });

    test('profit calculates (price - purchasePrice) * qty', () {
      final item = CartItem(
        productId: '1',
        name: 'Test',
        price: 200,
        qty: 3,
        unit: 'pcs',
        purchasePrice: 120,
      );

      expect(item.profit, 240.0);
    });

    test('profit is negative when selling below cost', () {
      final item = CartItem(
        productId: '1',
        name: 'Loss',
        price: 50,
        qty: 2,
        unit: 'pcs',
        purchasePrice: 80,
      );

      expect(item.profit, -60.0);
    });

    test('gstAmount calculates inclusive GST correctly', () {
      final item = CartItem(
        productId: '1',
        name: 'GST Item',
        price: 118,
        qty: 1,
        unit: 'pcs',
        gstRate: 18,
      );

      expect(item.gstAmount, closeTo(18.0, 0.01));
    });

    test('taxableAmount excludes GST from total', () {
      final item = CartItem(
        productId: '1',
        name: 'GST Item',
        price: 118,
        qty: 1,
        unit: 'pcs',
        gstRate: 18,
      );

      expect(item.taxableAmount, closeTo(100.0, 0.01));
    });

    test('cgst and sgst split GST amount equally', () {
      final item = CartItem(
        productId: '1',
        name: 'GST Item',
        price: 118,
        qty: 1,
        unit: 'pcs',
        gstRate: 18,
      );

      expect(item.cgst, closeTo(9.0, 0.01));
      expect(item.sgst, closeTo(9.0, 0.01));
      expect(item.cgst + item.sgst, closeTo(item.gstAmount, 0.01));
    });

    test('discountAmount calculates correctly', () {
      final item = CartItem(
        productId: '1',
        name: 'Discounted',
        price: 200,
        qty: 2,
        unit: 'pcs',
        discount: 25,
      );

      expect(item.discountAmount, 100.0);
    });

    test('totalPieces returns qty for pieces unitType', () {
      final item = CartItem(
        productId: '1',
        name: 'Pcs',
        price: 10,
        qty: 5,
        unit: 'pcs',
        unitType: 'pieces',
        piecesPerUnit: 12,
      );

      expect(item.totalPieces, 5);
    });

    test('totalPieces returns qty * piecesPerUnit for non-pieces', () {
      final item = CartItem(
        productId: '1',
        name: 'Box',
        price: 100,
        qty: 3,
        unit: 'box',
        unitType: 'box',
        piecesPerUnit: 12,
      );

      expect(item.totalPieces, 36);
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
            'name': 'Item',
            'price': 100.0,
            'qty': 2,
            'unit': 'pcs',
          },
        ],
        'total_amount': 200.0,
        'discount': 10.0,
        'total_discount': 20.0,
        'final_amount': 180.0,
        'round_off': 0.5,
        'payment_method': 'cash',
        'created_by': 'user-1',
        'created_at': '2025-01-15T10:30:00.000Z',
        'customer_id': 'cust-1',
        'is_credit': false,
        'amount_paid': 180.0,
        'due_amount': 0.0,
        'cash_amount': 100.0,
        'digital_amount': 80.0,
        'due_date': null,
        'extra_charges': 0.0,
        'igst_amount': 0.0,
        'cgst_amount': 0.0,
        'sgst_amount': 0.0,
        'tax_exempt': false,
      };

      final sale = Sale.fromJson(json);

      expect(sale.id, 'sale-1');
      expect(sale.items.length, 1);
      expect(sale.items[0].productId, 'p-1');
      expect(sale.totalAmount, 200.0);
      expect(sale.finalAmount, 180.0);
      expect(sale.discount, 10.0);
      expect(sale.totalDiscount, 20.0);
      expect(sale.roundOff, 0.5);
      expect(sale.paymentMethod, 'cash');
      expect(sale.createdBy, 'user-1');
      expect(sale.customerId, 'cust-1');
      expect(sale.isCredit, false);
      expect(sale.amountPaid, 180.0);
      expect(sale.cashAmount, 100.0);
      expect(sale.digitalAmount, 80.0);
      expect(sale.taxExempt, false);
    });

    test('fromJson handles null and missing fields gracefully', () {
      final json = {
        'id': 'sale-min',
        'items': [],
        'final_amount': 0,
        'created_at': '2025-01-15T10:30:00.000Z',
      };

      final sale = Sale.fromJson(json);

      expect(sale.id, 'sale-min');
      expect(sale.items, isEmpty);
      expect(sale.totalAmount, 0.0);
      expect(sale.discount, 0.0);
      expect(sale.paymentMethod, 'cash');
      expect(sale.isCredit, false);
      expect(sale.customerId, isNull);
      expect(sale.dueDate, isNull);
    });

    test('toJson roundtrip preserves data', () {
      final sale = Sale(
        id: 'sale-rt',
        items: [
          CartItem(
            productId: 'p-1',
            name: 'Item',
            price: 100,
            qty: 2,
            unit: 'pcs',
          ),
        ],
        totalAmount: 200,
        finalAmount: 200,
        createdBy: 'user-1',
        createdAt: DateTime.utc(2025, 6, 15, 12, 0, 0),
        paymentMethod: 'upi',
        cashAmount: 0,
        digitalAmount: 200,
      );

      final restored = Sale.fromJson(sale.toJson());

      expect(restored.id, sale.id);
      expect(restored.items.length, sale.items.length);
      expect(restored.totalAmount, sale.totalAmount);
      expect(restored.finalAmount, sale.finalAmount);
      expect(restored.paymentMethod, sale.paymentMethod);
      expect(restored.createdBy, sale.createdBy);
    });

    test('copyWith creates new Sale with overridden fields', () {
      final sale = Sale(
        id: 'sale-cw',
        items: [],
        totalAmount: 100,
        finalAmount: 100,
        createdBy: 'user-1',
        createdAt: DateTime.utc(2025, 1, 1),
        customerId: 'cust-old',
      );

      final updated = sale.copyWith(
        customerName: 'New Customer',
        dueDate: DateTime.utc(2025, 2, 1),
      );

      expect(updated.customerName, 'New Customer');
      expect(updated.dueDate, DateTime.utc(2025, 2, 1));
      expect(updated.id, sale.id);
      expect(updated.totalAmount, sale.totalAmount);
      expect(updated.customerId, sale.customerId);
    });

    test('copyWith preserves fields when not overridden', () {
      final sale = Sale(
        id: 'sale-cw2',
        items: [],
        totalAmount: 500,
        finalAmount: 480,
        createdBy: 'admin',
        createdAt: DateTime.utc(2025, 3, 10),
        isCredit: true,
        amountPaid: 200,
        dueAmount: 280,
      );

      final copy = sale.copyWith();

      expect(copy.id, sale.id);
      expect(copy.isCredit, true);
      expect(copy.amountPaid, 200);
      expect(copy.dueAmount, 280);
    });
  });

  // ============================================
  // SYNC STATUS MODEL TESTS
  // ============================================
  group('SyncStatus', () {
    test('totalPending sums all pending counts', () {
      const status = SyncStatus(
        isConnected: true,
        pendingSales: 3,
        pendingOps: 5,
        pendingWrites: 2,
      );

      expect(status.totalPending, 10);
    });

    test('totalPending returns 0 when all counts are 0', () {
      const status = SyncStatus(
        isConnected: true,
        pendingSales: 0,
        pendingOps: 0,
        pendingWrites: 0,
      );

      expect(status.totalPending, 0);
    });

    test('hasPending returns true when any count > 0', () {
      const withSales = SyncStatus(
        isConnected: true,
        pendingSales: 1,
        pendingOps: 0,
        pendingWrites: 0,
      );
      expect(withSales.hasPending, isTrue);

      const withOps = SyncStatus(
        isConnected: true,
        pendingSales: 0,
        pendingOps: 5,
        pendingWrites: 0,
      );
      expect(withOps.hasPending, isTrue);

      const withWrites = SyncStatus(
        isConnected: false,
        pendingSales: 0,
        pendingOps: 0,
        pendingWrites: 1,
      );
      expect(withWrites.hasPending, isTrue);
    });

    test('hasPending returns false when all counts are 0', () {
      const status = SyncStatus(
        isConnected: true,
        pendingSales: 0,
        pendingOps: 0,
        pendingWrites: 0,
      );

      expect(status.hasPending, isFalse);
    });
  });

  // ============================================
  // OFFLINE SERVICE TESTS
  // ============================================
  group('OfflineService', () {
    test('isReady returns true after init', () {
      final service = OfflineService();
      expect(service.isReady, isTrue);
    });

    test('pendingCount starts at 0 when boxes are empty', () {
      final service = OfflineService();
      expect(service.pendingCount, 0);
    });

    test('pendingOpsCount starts at 0 when boxes are empty', () {
      final service = OfflineService();
      expect(service.pendingOpsCount, 0);
    });

    test('pendingWritesCount starts at 0 when boxes are empty', () {
      final service = OfflineService();
      expect(service.pendingWritesCount, 0);
    });

    test('saveSaleOffline increments pendingCount', () async {
      final service = OfflineService();

      expect(service.pendingCount, 0);

      await service.saveSaleOffline({
        'id': 'offline-sale-1',
        'total_amount': 500,
        'final_amount': 480,
        'items': [],
      });

      expect(service.pendingCount, 1);

      await service.saveSaleOffline({
        'id': 'offline-sale-2',
        'total_amount': 300,
        'final_amount': 300,
        'items': [],
      });

      expect(service.pendingCount, 2);
    });

    test('saveSaleOffline adds sale to both pending and cached sales', () async {
      final service = OfflineService();

      await service.saveSaleOffline({
        'id': 'dual-box-sale',
        'total_amount': 100,
        'final_amount': 100,
      });

      expect(service.pendingCount, 1);

      final cachedSales = service.getCachedSalesHistory();
      expect(cachedSales.length, 1);
      expect(cachedSales.first['id'], 'dual-box-sale');
    });

    test('removePendingSale decrements pendingCount', () async {
      final service = OfflineService();

      await service.saveSaleOffline({
        'id': 'to-remove-1',
        'total_amount': 100,
        'final_amount': 100,
      });
      await service.saveSaleOffline({
        'id': 'to-remove-2',
        'total_amount': 200,
        'final_amount': 200,
      });
      expect(service.pendingCount, 2);

      await service.removePendingSale('to-remove-1');
      expect(service.pendingCount, 1);

      final pending = service.getPendingSales();
      expect(pending.length, 1);
      expect(pending.first['id'], 'to-remove-2');
    });

    test('getPendingSales returns all pending sales', () async {
      final service = OfflineService();

      await service.saveSaleOffline({
        'id': 'ps-1',
        'total_amount': 100,
        'final_amount': 100,
      });
      await service.saveSaleOffline({
        'id': 'ps-2',
        'total_amount': 200,
        'final_amount': 200,
      });

      final pending = service.getPendingSales();
      expect(pending.length, 2);

      final ids = pending.map((s) => s['id']).toSet();
      expect(ids, containsAll(['ps-1', 'ps-2']));
    });

    test('getPendingOperations returns sorted list by timestamp', () async {
      final service = OfflineService();

      await Hive.box<Map>(HiveAdapter.pendingOpsBox).put('op-2', {
        'id': 'op-2',
        'type': 'edit',
        'sale_id': 's-1',
        'timestamp': '2025-06-15T12:00:00.000Z',
      });
      await Hive.box<Map>(HiveAdapter.pendingOpsBox).put('op-1', {
        'id': 'op-1',
        'type': 'delete',
        'sale_id': 's-2',
        'timestamp': '2025-06-15T10:00:00.000Z',
      });
      await Hive.box<Map>(HiveAdapter.pendingOpsBox).put('op-3', {
        'id': 'op-3',
        'type': 'edit',
        'sale_id': 's-3',
        'timestamp': '2025-06-15T14:00:00.000Z',
      });

      expect(service.pendingOpsCount, 3);

      final ops = service.getPendingOperations();
      expect(ops.length, 3);
      expect(ops[0]['id'], 'op-1');
      expect(ops[1]['id'], 'op-2');
      expect(ops[2]['id'], 'op-3');
    });

    test('addPendingOperation increments pendingOpsCount', () async {
      final service = OfflineService();

      expect(service.pendingOpsCount, 0);

      await service.addPendingOperation({
        'type': 'edit',
        'sale_id': 'sale-abc',
        'data': {'total_amount': 999},
      });

      expect(service.pendingOpsCount, 1);
    });

    test('removePendingOperation decrements pendingOpsCount', () async {
      final service = OfflineService();

      await service.addPendingOperation({
        'type': 'delete',
        'sale_id': 'sale-del',
      });
      expect(service.pendingOpsCount, 1);

      final ops = service.getPendingOperations();
      await service.removePendingOperation(ops.first['id'] as String);
      expect(service.pendingOpsCount, 0);
    });

    test('pendingWritesCount tracks write queue separately', () async {
      final service = OfflineService();

      expect(service.pendingWritesCount, 0);

      await service.queuePendingWrite({
        'table': 'products',
        'operation': 'stock_deduct',
        'data': {'product_id': 'p-1', 'qty': 5},
      });
      expect(service.pendingWritesCount, 1);

      // Small delay to avoid microsecond ID collision
      await Future.delayed(const Duration(milliseconds: 5));

      await service.queuePendingWrite({
        'table': 'purchases',
        'operation': 'insert',
        'data': {'id': 'pur-1', 'total': 500},
      });
      expect(service.pendingWritesCount, 2);
    });

    test('getPendingWrites returns sorted by timestamp ascending', () async {
      final service = OfflineService();

      await service.queuePendingWrite({
        'table': 'products',
        'operation': 'stock_deduct',
        'data': {'product_id': 'p-1', 'qty': 1},
      });
      await Future.delayed(const Duration(milliseconds: 15));
      await service.queuePendingWrite({
        'table': 'products',
        'operation': 'stock_deduct',
        'data': {'product_id': 'p-2', 'qty': 2},
      });

      final writes = service.getPendingWrites();
      expect(writes.length, 2);

      final ts0 = writes[0]['timestamp'] as String;
      final ts1 = writes[1]['timestamp'] as String;
      expect(ts0.compareTo(ts1), lessThanOrEqualTo(0));
    });

    test('removePendingWrite decrements pendingWritesCount', () async {
      final service = OfflineService();

      await service.queuePendingWrite({
        'table': 'products',
        'operation': 'insert',
        'data': {'id': 'pw-1'},
      });
      expect(service.pendingWritesCount, 1);

      final writes = service.getPendingWrites();
      await service.removePendingWrite(writes.first['id'] as String);
      expect(service.pendingWritesCount, 0);
    });

    test('clearPendingWrites empties the queue', () async {
      final service = OfflineService();

      await service.queuePendingWrite({
        'table': 't',
        'operation': 'insert',
        'data': {'id': 'cw-1'},
      });
      await Future.delayed(const Duration(milliseconds: 15));
      await service.queuePendingWrite({
        'table': 't',
        'operation': 'update',
        'data': {'id': 'cw-2'},
      });
      expect(service.pendingWritesCount, 2);

      await service.clearPendingWrites();
      expect(service.pendingWritesCount, 0);
    });

    test('cacheProducts stores and retrieves products', () async {
      final service = OfflineService();

      await service.cacheProducts([
        {'id': 'p-1', 'name': 'Alpha', 'price': 10},
        {'id': 'p-2', 'name': 'Beta', 'price': 20},
      ]);

      final cached = service.getCachedProducts();
      expect(cached.length, 2);

      final product = service.getCachedProduct('p-1');
      expect(product, isNotNull);
      expect(product!['name'], 'Alpha');
    });

    test('getCachedProduct returns null for nonexistent id', () {
      final service = OfflineService();
      expect(service.getCachedProduct('nonexistent'), isNull);
    });

    test('cacheSalesHistory stores sales in cache box', () async {
      final service = OfflineService();

      await service.cacheSalesHistory([
        {'id': 's-1', 'total_amount': 100, 'created_at': '2025-06-15T10:00:00.000Z'},
        {'id': 's-2', 'total_amount': 200, 'created_at': '2025-06-15T12:00:00.000Z'},
      ]);

      final cached = service.getCachedSalesHistory();
      expect(cached.length, 2);
    });

    test('getCachedSalesHistory returns sorted by created_at descending', () async {
      final service = OfflineService();

      await service.cacheSalesHistory([
        {'id': 's-old', 'total_amount': 100, 'created_at': '2025-01-01T00:00:00.000Z'},
        {'id': 's-new', 'total_amount': 200, 'created_at': '2025-12-31T23:59:59.000Z'},
        {'id': 's-mid', 'total_amount': 150, 'created_at': '2025-06-15T12:00:00.000Z'},
      ]);

      final cached = service.getCachedSalesHistory();
      expect(cached.length, 3);
      expect(cached[0]['id'], 's-new');
      expect(cached[1]['id'], 's-mid');
      expect(cached[2]['id'], 's-old');
    });

    test('applyEditToLocalCache updates cached sale', () async {
      final service = OfflineService();

      await service.cacheSalesHistory([
        {'id': 'edit-target', 'total_amount': 100, 'final_amount': 100},
      ]);

      service.applyEditToLocalCache('edit-target', {
        'id': 'edit-target',
        'total_amount': 150,
        'final_amount': 150,
      });

      final sales = service.getCachedSalesHistory();
      expect(sales.firstWhere((s) => s['id'] == 'edit-target')['total_amount'], 150);
    });

    test('applyDeleteToLocalCache removes cached sale', () async {
      final service = OfflineService();

      await service.cacheSalesHistory([
        {'id': 'del-target', 'total_amount': 100},
        {'id': 'del-keep', 'total_amount': 200},
      ]);

      service.applyDeleteToLocalCache('del-target');

      final sales = service.getCachedSalesHistory();
      expect(sales.length, 1);
      expect(sales.first['id'], 'del-keep');
    });
  });

  // ============================================
  // SALE SERVICE OFFLINE FALLBACK TESTS
  // ============================================
  group('SaleService offline cache', () {
    test('cached sales survive as offline fallback', () async {
      final offlineService = OfflineService();

      await offlineService.cacheSalesHistory([
        {
          'id': 'cached-sale-1',
          'items': [
            {'product_id': 'p-1', 'name': 'Item', 'price': 100, 'qty': 2, 'unit': 'pcs'},
          ],
          'total_amount': 200,
          'final_amount': 200,
          'created_by': 'user-1',
          'created_at': '2025-06-15T10:00:00.000Z',
        },
        {
          'id': 'cached-sale-2',
          'items': [],
          'total_amount': 50,
          'final_amount': 50,
          'created_by': 'user-1',
          'created_at': '2025-06-15T12:00:00.000Z',
        },
      ]);

      final cached = offlineService.getCachedSalesHistory();
      expect(cached.length, 2);

      final sales = cached.map((e) => Sale.fromJson(e)).toList();
      expect(sales[0].id, 'cached-sale-2');
      expect(sales[1].id, 'cached-sale-1');
      expect(sales[0].totalAmount, 50);
      expect(sales[1].totalAmount, 200);
    });

    test('offline sale appears in cache immediately', () async {
      final offlineService = OfflineService();

      await offlineService.saveSaleOffline({
        'id': 'offline-fallback-sale',
        'total_amount': 750,
        'final_amount': 750,
        'items': [],
        'created_at': '2025-06-15T14:00:00.000Z',
      });

      final cached = offlineService.getCachedSalesHistory();
      expect(cached.length, 1);
      expect(cached.first['id'], 'offline-fallback-sale');

      final pending = offlineService.getPendingSales();
      expect(pending.length, 1);
    });
  });
}
