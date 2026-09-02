import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'offline_service.dart';

class SaleService {
  final SupabaseClient _client;
  final AccountService _accountService;
  final OfflineService _offlineService;

  SaleService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _accountService = accountService ?? AccountService(),
       _offlineService = offlineService ?? OfflineService();

  Future<Sale> createSale(Sale sale) async {
    try {
      final response = await _client
          .from('sales')
          .insert(sale.toInsertJson())
          .select()
          .single()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Connection timeout'),
          );

      final createdSale = Sale.fromJson(response);

      AuditService().log(
        action: 'create',
        entityType: 'sale',
        entityId: createdSale.id,
        newData: sale.toInsertJson(),
        description: 'Sale for Rs.${sale.finalAmount}',
      );

      // Wire to accounts: split always wires cash/UPI; non-split only if not credit
      if (sale.paymentMethod == 'split' || !sale.isCredit) {
        try {
          final accounts = await _accountService.getAccounts();
          final shortId = createdSale.id.length >= 8
              ? createdSale.id.substring(0, 8)
              : createdSale.id;

          if (sale.paymentMethod == 'split' &&
              sale.cashAmount > 0 &&
              sale.digitalAmount > 0) {
            if (sale.cashAmount > 0) {
              final cashAccount = accounts.firstWhere(
                (a) => a.accountType == 'cash',
                orElse: () => accounts.first,
              );
              await _accountService.addTransaction(
                accountId: cashAccount.id,
                type: 'in',
                amount: sale.cashAmount,
                category: 'sale',
                description: 'Sale #$shortId (Cash)',
              );
            }
            if (sale.digitalAmount > 0) {
              final bankAccount = accounts.firstWhere(
                (a) => a.accountType == 'bank',
                orElse: () => accounts.last,
              );
              await _accountService.addTransaction(
                accountId: bankAccount.id,
                type: 'in',
                amount: sale.digitalAmount,
                category: 'sale',
                description: 'Sale #$shortId (UPI)',
              );
            }
          } else {
            String accountType;
            if (sale.paymentMethod == 'upi' ||
                sale.paymentMethod == 'digital') {
              accountType = 'bank';
            } else {
              accountType = 'cash';
            }
            final account = accounts.firstWhere(
              (a) => a.accountType == accountType,
              orElse: () => accounts.first,
            );
            await _accountService.addTransaction(
              accountId: account.id,
              type: 'in',
              amount: sale.finalAmount,
              category: 'sale',
              description: 'Sale #$shortId',
            );
          }
        } catch (e) {
          Logger.error('Account entry failed for sale', e);
        }
      }

      return createdSale;
    } catch (e) {
      Logger.warning('Supabase insert failed, saving offline: $e');
      // Re-throw so the caller knows the insert failed
      // The caller can decide whether to show an error or save offline
      rethrow;
    }
  }

  Future<void> syncOfflineSales() async {
    await _offlineService.syncPendingSales();
  }

  /// Get sales history - from cache when offline, from Supabase when online
  Future<List<Sale>> getSalesHistory({int limit = 50}) async {
    print('[SALES] getSalesHistory called');
    final online = await _offlineService.isOnline();
    print('[SALES] isOnline=$online');
    if (online) {
      try {
        final since = AppTimezone.nowUtc().subtract(const Duration(days: 90));
        final response = await _client
            .from('sales')
            .select('*, customers(name)')
            .gte('created_at', since.toIso8601String())
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(const Duration(seconds: 5));

        final sales = (response as List).map((e) {
          final map = Map<String, dynamic>.from(e as Map);
          final customerData = map.remove('customers') as Map<String, dynamic>?;
          final sale = Sale.fromJson(map);
          final customerName = customerData?['name'] as String?;
          return customerName != null
              ? sale.copyWith(customerName: customerName)
              : sale;
        }).toList();

        // Cache for offline use (strip joined customer data)
        try {
          final cacheData = (response as List).map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            map.remove('customers');
            return map;
          }).toList();
          await _offlineService.cacheSalesHistory(cacheData);
        } catch (e) {
          Logger.warning('Failed to cache sales history for offline: $e');
        }

        print('[SALES] Online: returning ${sales.length} sales from Supabase');
        return sales;
      } catch (e) {
        print('[SALES] Supabase query failed: $e');
        Logger.warning('Supabase query failed, falling back to cache: $e');
      }
    }

    // Offline or Supabase failed — load from cache + pending
    final offline = _loadOfflineSales(limit: limit);
    print('[SALES] Offline: returning ${offline.length} sales from cache+pending');
    return offline;
  }

  List<Sale> _loadOfflineSales({int limit = 50}) {
    Logger.info('Loading sales from local cache');
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
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
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

  Future<List<Sale>> getSalesByDate(DateTime date) async {
    try {
      final utcDate = date.toUtc();
      final start = DateTime(utcDate.year, utcDate.month, utcDate.day).toUtc();
      final end = start.add(const Duration(days: 1));

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
        return customerName != null
            ? sale.copyWith(customerName: customerName)
            : sale;
      }).toList();
    } catch (e) {
      Logger.warning('getSalesByDate failed, loading from cache');
      final cached = _offlineService.getCachedSalesHistory();
      final sales = cached.map((e) => Sale.fromJson(e)).toList();
      return sales.where((s) {
        final d = s.createdAt;
        return d.year == date.year &&
            d.month == date.month &&
            d.day == date.day;
      }).toList();
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

  /// Delete sale - queues if offline
  Future<void> deleteSale(String saleId) async {
    // First check if this is an offline-created sale (never synced to Supabase)
    final pendingSale = _offlineService.pendingBox.get(saleId);
    if (pendingSale != null) {
      // Offline-created sale: remove from pending box and local cache directly
      await _offlineService.removePendingSale(saleId);
      _offlineService.applyDeleteToLocalCache(saleId);
      Logger.info('Deleted offline sale $saleId from pending queue');
      return;
    }

    try {
      final saleData = await _client
          .from('sales')
          .select(
            'items, final_amount, payment_method, is_credit, cash_amount, digital_amount, customer_id, due_amount',
          )
          .eq('id', saleId)
          .single();
      final items = saleData['items'] as List? ?? [];
      final finalAmount = (saleData['final_amount'] as num?)?.toDouble() ?? 0;
      final paymentMethod = saleData['payment_method'] as String? ?? 'cash';
      final isCredit = saleData['is_credit'] as bool? ?? false;
      final cashAmount = (saleData['cash_amount'] as num?)?.toDouble() ?? 0;
      final digitalAmount =
          (saleData['digital_amount'] as num?)?.toDouble() ?? 0;
      final customerId = saleData['customer_id'] as String?;
      final dueAmount = (saleData['due_amount'] as num?)?.toDouble() ?? 0;

      // Restore stock per item (batched for performance)
      final stockFutures = <Future>[];
      for (final item in items) {
        final productId = item['product_id'] as String?;
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        if (productId != null && qty > 0) {
          stockFutures.add(
            _client.rpc(
              'increment_stock',
              params: {'p_product_id': productId, 'p_qty': qty},
            ).catchError((e) => Logger.error('Failed to restore stock for $productId', e)),
          );
        }
      }
      if (stockFutures.isNotEmpty) {
        await Future.wait(stockFutures);
      }

      // Reverse account entry (non-credit only)
      if (!isCredit && finalAmount > 0) {
        try {
          final accounts = await _accountService.getAccounts();
          if (cashAmount > 0 && digitalAmount > 0) {
            if (cashAmount > 0) {
              final cashAccount = accounts.firstWhere(
                (a) => a.accountType == 'cash',
                orElse: () => accounts.first,
              );
              await _accountService.addTransaction(
                accountId: cashAccount.id,
                type: 'out',
                amount: cashAmount,
                category: 'sale_reversal',
                description: 'Reversed sale #$saleId (Cash)',
              );
            }
            if (digitalAmount > 0) {
              final bankAccount = accounts.firstWhere(
                (a) => a.accountType == 'bank',
                orElse: () => accounts.last,
              );
              await _accountService.addTransaction(
                accountId: bankAccount.id,
                type: 'out',
                amount: digitalAmount,
                category: 'sale_reversal',
                description: 'Reversed sale #$saleId (UPI)',
              );
            }
          } else {
            String accountType =
                (paymentMethod == 'upi' || paymentMethod == 'digital')
                ? 'bank'
                : 'cash';
            final account = accounts.firstWhere(
              (a) => a.accountType == accountType,
              orElse: () => accounts.first,
            );
            await _accountService.addTransaction(
              accountId: account.id,
              type: 'out',
              amount: finalAmount,
              category: 'sale_reversal',
              description: 'Reversed sale #$saleId',
            );
          }
        } catch (e) {
          Logger.error('Failed to reverse account entry for sale', e);
        }
      }

      // Reverse customer credit if this was a credit sale
      if (isCredit && customerId != null && dueAmount > 0) {
        try {
          // Recalculate customer total_credit from remaining sales
          final remainingSales = await _client
              .from('sales')
              .select('due_amount')
              .eq('customer_id', customerId)
              .gt('due_amount', 0);
          double totalCredit = 0;
          for (final sale in remainingSales) {
            totalCredit += (sale['due_amount'] as num?)?.toDouble() ?? 0;
          }
          await _client
              .from('customers')
              .update({'total_credit': totalCredit})
              .eq('id', customerId);
          Logger.info('Reversed credit for customer $customerId: -$dueAmount (new total: $totalCredit)');
        } catch (e) {
          Logger.error('Failed to reverse customer credit for sale', e);
        }
      }

      await _client.from('sales').delete().eq('id', saleId);

      AuditService().log(
        action: 'delete',
        entityType: 'sale',
        entityId: saleId,
        oldData: saleData,
        description: 'Deleted sale Rs.$finalAmount',
      );

      // Update local cache
      _offlineService.applyDeleteToLocalCache(saleId);
    } catch (e) {
      Logger.warning('Delete failed (offline?), queuing: $e');
      // Queue for later sync
      await _offlineService.addPendingOperation({
        'type': 'delete',
        'sale_id': saleId,
      });
      // Remove from local cache immediately
      _offlineService.applyDeleteToLocalCache(saleId);
    }
  }

  Future<double> getTotalSales() async {
    try {
      final response = await _client.from('sales').select('final_amount');
      double total = 0;
      for (final e in response as List) {
        total += (e['final_amount'] as num).toDouble();
      }
      return total;
    } catch (e) {
      // Calculate from cache
      final cached = _offlineService.getCachedSalesHistory();
      return cached.fold<double>(
        0,
        (sum, s) => sum + ((s['final_amount'] as num?)?.toDouble() ?? 0),
      );
    }
  }

  /// Edit sale - queues if offline
  Future<void> editSaleAtomic({
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
  }) async {
    final updateData = {
      'items': items.map((item) => item.toJson()).toList(),
      'total_amount': totalAmount,
      'discount': discount,
      'final_amount': finalAmount,
      'customer_id': customerId,
      'is_credit': isCredit,
      'amount_paid': amountPaid,
      'due_amount': dueAmount,
      'payment_method': paymentMethod,
      'cash_amount': cashAmount,
      'digital_amount': digitalAmount,
    };

    try {
      await _client
          .rpc(
            'edit_sale_atomic',
            params: {
              'p_sale_id': saleId,
              'p_items': items.map((item) => item.toJson()).toList(),
              'p_total_amount': totalAmount,
              'p_discount': discount,
              'p_final_amount': finalAmount,
              'p_customer_id': customerId,
              'p_is_credit': isCredit,
              'p_amount_paid': amountPaid,
              'p_due_amount': dueAmount,
              'p_payment_method': paymentMethod,
              'p_cash_amount': cashAmount,
              'p_digital_amount': digitalAmount,
              'p_reason': reason,
            },
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Connection timeout'),
          );

      AuditService().log(
        action: 'update',
        entityType: 'sale',
        entityId: saleId,
        newData: updateData,
        description: 'Edited sale. Reason: $reason',
      );

      // Update local cache
      _offlineService.applyEditToLocalCache(saleId, updateData);
    } catch (e) {
      Logger.warning('Edit failed (offline?), queuing: $e');
      // Queue for later sync
      await _offlineService.addPendingOperation({
        'type': 'edit',
        'sale_id': saleId,
        'data': updateData,
        'reason': reason,
      });
      // Update local cache immediately so user sees the change
      _offlineService.applyEditToLocalCache(saleId, updateData);
    }
  }

  Future<List<Map<String, dynamic>>> getTopSoldProducts({
    int limit = 6,
    int days = 7,
  }) async {
    try {
      final since = AppTimezone.nowUtc().subtract(Duration(days: days));
      final response = await _client
          .from('sales')
          .select('items')
          .gte('created_at', since.toIso8601String());

      final sales = response as List;
      final Map<String, Map<String, dynamic>> productQty = {};

      for (final sale in sales) {
        final items = (sale['items'] as List?) ?? [];
        for (final item in items) {
          final pid = item['product_id'] as String?;
          if (pid == null) continue;
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          if (productQty.containsKey(pid)) {
            productQty[pid]!['totalQty'] =
                (productQty[pid]!['totalQty'] as int) + qty;
          } else {
            productQty[pid] = {
              'product_id': pid,
              'name': item['name'] ?? '',
              'totalQty': qty,
            };
          }
        }
      }

      final sorted = productQty.values.toList()
        ..sort((a, b) => (b['totalQty'] as int).compareTo(a['totalQty'] as int));

      return sorted.take(limit).toList();
    } catch (e) {
      Logger.warning('getTopSoldProducts failed: $e');
      return [];
    }
  }

  /// Returns per-product sales summary: {productId: {qty7d, qty30d, qty60d, qty90d, qtyToday, totalValue30d, lastSoldAt}}
  Future<Map<String, Map<String, dynamic>>> getProductSalesStats() async {
    try {
      final now = AppTimezone.nowUtc();
      final since90 = now.subtract(const Duration(days: 90));
      final since60 = now.subtract(const Duration(days: 60));
      final since30 = now.subtract(const Duration(days: 30));
      final since7 = now.subtract(const Duration(days: 7));
      final sinceToday = DateTime(now.year, now.month, now.day);

      final response = await _client
          .from('sales')
          .select('items, created_at')
          .gte('created_at', since90.toIso8601String());

      final sales = response as List;
      final Map<String, Map<String, dynamic>> stats = {};

      for (final sale in sales) {
        final saleDate = DateTime.parse(sale['created_at'] as String);
        final items = (sale['items'] as List?) ?? [];
        final isToday = saleDate.isAfter(sinceToday);
        final is7d = saleDate.isAfter(since7);
        final is30d = saleDate.isAfter(since30);
        final is60d = saleDate.isAfter(since60);

        for (final item in items) {
          final pid = item['product_id'] as String?;
          if (pid == null) continue;
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0;

          stats.putIfAbsent(pid, () => {
            'qtyToday': 0, 'qty7d': 0, 'qty30d': 0, 'qty60d': 0, 'qty90d': 0,
            'totalValue30d': 0.0, 'lastSoldAt': saleDate,
          });

          stats[pid]!['qty90d'] = (stats[pid]!['qty90d'] as int) + qty;
          if (is60d) stats[pid]!['qty60d'] = (stats[pid]!['qty60d'] as int) + qty;
          if (is30d) {
            stats[pid]!['qty30d'] = (stats[pid]!['qty30d'] as int) + qty;
            stats[pid]!['totalValue30d'] = (stats[pid]!['totalValue30d'] as double) + qty * price;
          }
          if (is7d) stats[pid]!['qty7d'] = (stats[pid]!['qty7d'] as int) + qty;
          if (isToday) stats[pid]!['qtyToday'] = (stats[pid]!['qtyToday'] as int) + qty;

          final last = stats[pid]!['lastSoldAt'] as DateTime;
          if (saleDate.isAfter(last)) stats[pid]!['lastSoldAt'] = saleDate;
        }
      }

      return stats;
    } catch (e) {
      Logger.warning('getProductSalesStats failed: $e');
      return {};
    }
  }
}
