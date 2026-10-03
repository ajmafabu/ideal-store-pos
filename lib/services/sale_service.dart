import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'offline_service.dart';
import 'product_service.dart';

/// Thrown when a sale could not reach the server and was kept on this
/// device instead. The caller tells the user it will sync later.
class SaleSavedOffline implements Exception {
  final Sale sale;
  SaleSavedOffline(this.sale);
  @override
  String toString() => 'Sale saved offline';
}

/// Result of an edit: either applied on the server or queued for later.
enum EditOutcome { saved, queuedOffline }

class SaleService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  SaleService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _offlineService = offlineService ?? OfflineService();

  /// Saves a sale. The database deducts stock (true FIFO), computes GST,
  /// posts the money to cash/bank and assigns the invoice number in the same
  /// transaction (#10), and returns the stored row so the printed invoice
  /// matches the database (#19).
  ///
  /// [sale.id] must be a client UUID (see [newDocumentId]). If the server
  /// can't be reached the sale is queued offline under the SAME id and
  /// [SaleSavedOffline] is thrown; when the queue syncs, a sale that did
  /// reach the server is recognised by its id and not inserted twice (#5).
  /// Server rejections (e.g. inactive account) are rethrown, never queued.
  Future<Sale> createSale(Sale sale) async {
    final payload = sale.toInsertJson();
    try {
      final response = await _client
          .from('sales')
          .insert(payload)
          .select()
          .single()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Connection timeout'),
          );
      final created = Sale.fromJson(response);
      ProductService.invalidateCache();
      AuditService().log(
        action: 'create',
        entityType: 'sale',
        entityId: created.id,
        newData: {'final_amount': created.finalAmount, 'invoice_no': created.invoiceNo},
        description: 'Sale #${created.invoiceLabel} for Rs.${created.finalAmount}',
      );
      return sale.customerName != null ? created.copyWith(customerName: sale.customerName) : created;
    } catch (e) {
      if (isDuplicateKey(e)) {
        // an earlier attempt already committed this exact sale
        final existing = await _client.from('sales').select().eq('id', sale.id).single();
        return Sale.fromJson(existing);
      }
      if (!isNetworkError(e)) rethrow;
      Logger.warning('Sale insert could not reach the server, saving offline: $e');
      await _offlineService.saveSaleOffline(sale.toJson());
      throw SaleSavedOffline(sale);
    }
  }

  Future<void> syncOfflineSales() async {
    await _offlineService.syncPendingSales();
  }

  /// Get sales history - from cache when offline, from Supabase when online
  Future<List<Sale>> getSalesHistory({int limit = 50, int days = 90}) async {
    final online = await _offlineService.isOnline();
    if (online) {
      try {
        final since = AppTimezone.nowUtc().subtract(Duration(days: days));
        final response = await _client
            .from('sales')
            .select('*, customers(name)')
            .gte('created_at', since.toIso8601String())
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(const Duration(seconds: 10));

        final sales = <Sale>[];
        final cacheData = <Map<String, dynamic>>[];
        for (final e in response as List) {
          final map = Map<String, dynamic>.from(e as Map);
          final customerData = map.remove('customers') as Map<String, dynamic>?;
          cacheData.add(map);
          try {
            final sale = Sale.fromJson(map);
            final customerName = customerData?['name'] as String?;
            sales.add(customerName != null ? sale.copyWith(customerName: customerName) : sale);
          } catch (ex) {
            Logger.warning('Skipping unreadable sale ${map['id']}: $ex');
          }
        }
        // pending (not yet synced) sales stay visible
        for (final p in _offlineService.getPendingSales()) {
          try {
            sales.insert(0, Sale.fromJson(p));
          } catch (_) {}
        }
        try {
          await _offlineService.cacheSalesHistory(cacheData);
        } catch (e) {
          Logger.warning('Failed to cache sales history for offline: $e');
        }
        return sales;
      } catch (e) {
        Logger.warning('Supabase query failed, falling back to cache: $e');
      }
    }
    return _loadOfflineSales(limit: limit);
  }

  List<Sale> _loadOfflineSales({int limit = 50}) {
    final cached = _offlineService.getCachedSalesHistory();
    final pending = _offlineService.getPendingSales();
    final allOffline = <String, Map<String, dynamic>>{};
    for (final s in cached) {
      final id = s['id']?.toString() ?? '';
      if (id.isNotEmpty) allOffline[id] = s;
    }
    for (final s in pending) {
      final id = s['id']?.toString() ?? '';
      if (id.isNotEmpty) allOffline[id] = s;
    }
    final merged = allOffline.values.toList()
      ..sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));
    final sales = <Sale>[];
    for (final e in merged.take(limit)) {
      try {
        sales.add(Sale.fromJson(e));
      } catch (ex) {
        Logger.warning('Failed to parse cached sale: $ex');
      }
    }
    return sales;
  }

  /// Sales of one Indian-time calendar day.
  Future<List<Sale>> getSalesByDate(DateTime date) async {
    final ist = AppTimezone.toIst(date);
    final start = AppTimezone.toUtc(DateTime(ist.year, ist.month, ist.day));
    final end = start.add(const Duration(days: 1));
    try {
      final response = await _client
          .from('sales')
          .select('*, customers(name)')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at', ascending: false);

      return (response as List).map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        final customerData = map.remove('customers') as Map<String, dynamic>?;
        final sale = Sale.fromJson(map);
        final customerName = customerData?['name'] as String?;
        return customerName != null ? sale.copyWith(customerName: customerName) : sale;
      }).toList();
    } catch (e) {
      Logger.warning('getSalesByDate failed, loading from cache');
      return _loadOfflineSales(limit: 100000)
          .where((s) => !s.createdAt.isBefore(start) && s.createdAt.isBefore(end))
          .toList();
    }
  }

  Future<double> getTodaySalesTotal() async {
    try {
      final sales = await getSalesByDate(AppTimezone.nowUtc());
      return sales.fold<double>(0, (sum, sale) => sum + sale.finalAmount);
    } catch (e) {
      return 0;
    }
  }

  /// Deletes a sale in ONE database transaction: stock goes back to the
  /// exact batches, returns and payments are removed with it and every
  /// cash-book effect is reversed (#9). A sale that only exists on this
  /// device is simply dropped from the queue.
  Future<void> deleteSale(String saleId) async {
    final pendingSale = _offlineService.pendingBox.get(saleId);
    if (pendingSale != null) {
      await _offlineService.removePendingSale(saleId);
      _offlineService.applyDeleteToLocalCache(saleId);
      return;
    }

    try {
      final result = await _client
          .rpc('delete_sale_atomic', params: {'p_sale_id': saleId})
          .single()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Connection timeout'),
          );
      ProductService.invalidateCache();
      AuditService().log(
        action: 'delete',
        entityType: 'sale',
        entityId: saleId,
        oldData: {'final_amount': result['final_amount']},
        description: 'Deleted sale Rs.${result['final_amount']}',
      );
      _offlineService.applyDeleteToLocalCache(saleId);
    } catch (e) {
      if (e is PostgrestException && e.code == 'P0002') {
        // already deleted (e.g. from another device)
        _offlineService.applyDeleteToLocalCache(saleId);
        return;
      }
      if (isNetworkError(e)) {
        await _offlineService.addPendingOperation({'type': 'delete', 'sale_id': saleId});
        _offlineService.applyDeleteToLocalCache(saleId);
        return;
      }
      rethrow;
    }
  }

  /// Returns every remaining unit of a sale as proper return records
  /// (refunds, stock and credit handled by the database) — the desktop
  /// "Return Full Sale" action used to delete the sale instead (#14).
  Future<int> returnFullSale(String saleId, {String reason = 'Full sale returned'}) async {
    final res = await _client.rpc('return_full_sale', params: {'p_sale_id': saleId, 'p_reason': reason});
    ProductService.invalidateCache();
    return (res as num?)?.toInt() ?? 0;
  }

  Future<double> getTotalSales() async {
    try {
      final res = await _client.rpc('get_sales_total', params: {
        'p_start': DateTime.utc(2000).toIso8601String(),
        'p_end': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
      });
      return (res as num?)?.toDouble() ?? 0;
    } catch (e) {
      final cached = _offlineService.getCachedSalesHistory();
      return cached.fold<double>(0, (sum, s) => sum + ((s['final_amount'] as num?)?.toDouble() ?? 0));
    }
  }

  Map<String, dynamic> _editParams({
    required String saleId,
    required List<CartItem> items,
    required double totalAmount,
    required double discount,
    required double finalAmount,
    String? customerId,
    required bool isCredit,
    required double amountPaid,
    required double dueAmount,
    required String paymentMethod,
    required double cashAmount,
    required double digitalAmount,
    required String reason,
    double? extraCharges,
    double? roundOff,
  }) => {
    'p_sale_id': saleId,
    'p_items': items.map((item) => item.toJson()).toList(),
    'p_total_amount': totalAmount,
    'p_discount': discount,
    'p_final_amount': finalAmount,
    'p_customer_id': (customerId != null && customerId.isNotEmpty) ? customerId : null,
    'p_is_credit': isCredit,
    'p_amount_paid': amountPaid,
    'p_due_amount': dueAmount,
    'p_payment_method': paymentMethod,
    'p_cash_amount': cashAmount,
    'p_digital_amount': digitalAmount,
    'p_reason': reason,
    'p_extra_charges': extraCharges,
    'p_round_off': roundOff,
  };

  /// Edits a sale atomically on the server (stock, FIFO batches, GST, cash
  /// book, both customers' balances). Server rejections such as "Admin
  /// permission required" or "This sale has returns" are thrown to the
  /// caller so the user sees them — they used to be swallowed and shown as
  /// "Sale updated" (#7). Only a genuine network failure queues the edit,
  /// and the queue replays it through the same RPC, never as a plain UPDATE.
  Future<EditOutcome> editSaleAtomic({
    required String saleId,
    required List<CartItem> items,
    required double totalAmount,
    required double discount,
    required double finalAmount,
    String? customerId,
    required bool isCredit,
    required double amountPaid,
    required double dueAmount,
    required String paymentMethod,
    required double cashAmount,
    required double digitalAmount,
    required String reason,
    double? extraCharges,
    double? roundOff,
  }) async {
    if (!isUuid(saleId)) {
      throw Exception('This sale has not been synced yet. Delete it and bill again, or wait for sync.');
    }
    final params = _editParams(
      saleId: saleId,
      items: items,
      totalAmount: totalAmount,
      discount: discount,
      finalAmount: finalAmount,
      customerId: customerId,
      isCredit: isCredit,
      amountPaid: amountPaid,
      dueAmount: dueAmount,
      paymentMethod: paymentMethod,
      cashAmount: cashAmount,
      digitalAmount: digitalAmount,
      reason: reason,
      extraCharges: extraCharges,
      roundOff: roundOff,
    );

    try {
      final res = await _client
          .rpc('edit_sale_atomic', params: params)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Connection timeout'),
          );
      ProductService.invalidateCache();
      AuditService().log(
        action: 'update',
        entityType: 'sale',
        entityId: saleId,
        newData: {'final_amount': finalAmount},
        description: 'Edited sale. Reason: $reason',
      );
      if (res is List && res.isNotEmpty) {
        _offlineService.applyEditToLocalCache(saleId, Map<String, dynamic>.from(res.first as Map));
      }
      return EditOutcome.saved;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      Logger.warning('Edit could not reach the server, queuing: $e');
      await _offlineService.addPendingOperation({
        'type': 'edit',
        'sale_id': saleId,
        'params': params,
        'reason': reason,
      });
      return EditOutcome.queuedOffline;
    }
  }

  Future<List<Map<String, dynamic>>> getTopSoldProducts({
    int limit = 6,
    int days = 7,
  }) async {
    try {
      final stats = await getProductSalesStats();
      final key = days <= 7 ? 'qty7d' : (days <= 15 ? 'qty15d' : (days <= 30 ? 'qty30d' : 'qty90d'));
      final names = <String, String>{};
      final cached = _offlineService.getCachedProducts();
      for (final p in cached) {
        names[p['id'].toString()] = p['name']?.toString() ?? '';
      }
      final rows = stats.entries
          .where((e) => ((e.value[key] as num?) ?? 0) > 0)
          .map((e) => {
                'product_id': e.key,
                'name': names[e.key] ?? '',
                'totalQty': (e.value[key] as num).toInt(),
              })
          .toList()
        ..sort((a, b) => (b['totalQty'] as int).compareTo(a['totalQty'] as int));
      return rows.take(limit).toList();
    } catch (e) {
      Logger.warning('getTopSoldProducts failed: $e');
      return [];
    }
  }

  /// Per-product sales velocity, aggregated by the database over 90 days.
  Future<Map<String, Map<String, dynamic>>> getProductSalesStats() async {
    final res = await _client.rpc('get_product_sales_stats');
    final stats = <String, Map<String, dynamic>>{};
    if (res is Map) {
      for (final entry in res.entries) {
        final data = entry.value;
        if (data is Map) {
          stats[entry.key.toString()] = {
            'qtyToday': (data['qtyToday'] as num?)?.toInt() ?? 0,
            'qty7d': (data['qty7d'] as num?)?.toInt() ?? 0,
            'qty15d': (data['qty15d'] as num?)?.toInt() ?? 0,
            'qty30d': (data['qty30d'] as num?)?.toInt() ?? 0,
            'qty60d': (data['qty60d'] as num?)?.toInt() ?? 0,
            'qty90d': (data['qty90d'] as num?)?.toInt() ?? 0,
            'totalValue30d': (data['totalValue30d'] as num?)?.toDouble() ?? 0,
            'lastSoldAt': data['lastSoldAt'] != null ? DateTime.tryParse(data['lastSoldAt'].toString()) : null,
            'daysSinceLastSale': (data['daysSinceLastSale'] as num?)?.toInt() ?? 999,
          };
        }
      }
    }
    return stats;
  }
}
