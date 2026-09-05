import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase.dart';
import '../utils/logger.dart';
import 'product_service.dart';
import 'account_service.dart';
import 'offline_service.dart';

class PurchaseService {
  final SupabaseClient _client;
  final ProductService _productService;
  final AccountService _accountService;
  final OfflineService _offlineService;

  PurchaseService({
    SupabaseClient? client,
    ProductService? productService,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _productService = productService ?? ProductService(),
       _accountService = accountService ?? AccountService(),
       _offlineService = offlineService ?? OfflineService();

  Future<Purchase> createPurchase(Purchase purchase) async {
    try {
      final insertData = purchase.toInsertJson();
      print('[PURCHASE] Creating purchase: total=${insertData['total_amount']}, items=${insertData['items'].length}');
      print('[PURCHASE] Insert data keys: ${insertData.keys.toList()}');
      print('[PURCHASE] supplier_id=${insertData['supplier_id']}, created_by=${insertData['created_by']}');
      print('[PURCHASE] Full insert data: $insertData');

      final response = await _client
          .from('purchases')
          .insert(insertData)
          .select()
          .single();

      final purchaseId = response['id'] as String;
      print('[PURCHASE] SUCCESS — created with id: $purchaseId');

      // Add stock and inventory batches in parallel (non-fatal — purchase is already saved)
      final itemFutures = <Future>[];
      for (final item in purchase.items) {
        itemFutures.add(
          _productService.addStock(item.productId, item.qty).catchError((e) {
            Logger.error('Stock add failed for ${item.productId}', e);
          }),
        );

        // Update product purchase_price to latest purchase price
        itemFutures.add(
          _client
              .from('products')
              .update({'purchase_price': item.price})
              .eq('id', item.productId)
              .then(
                (_) {},
                onError: (e) {
                  Logger.warning('Failed to update purchase_price: $e');
                },
              ),
        );

        itemFutures.add(
          _client
              .rpc(
                'add_inventory_batch',
                params: {
                  'p_product_id': item.productId,
                  'p_purchase_id': purchaseId,
                  'p_quantity': item.qty,
                  'p_purchase_price': item.price,
                  'p_batch_number': item.batchNumber,
                  'p_expiry_date': item.expiryDate
                      ?.toIso8601String()
                      .split('T')
                      .first,
                },
              )
              .catchError((e) {
                Logger.warning('Failed to add inventory batch: $e');
              }),
        );
      }
      await Future.wait(itemFutures);

      // Wire to accounts: only if NOT credit
      if (!purchase.isCredit) {
        try {
          final accounts = await _accountService.getAccounts();
          String accountType;
          if (purchase.paymentMethod == 'upi' ||
              purchase.paymentMethod == 'bank') {
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
            type: 'out',
            amount: purchase.totalAmount,
            category: 'purchase',
            description:
                'Purchase #${purchaseId.length >= 8 ? purchaseId.substring(0, 8) : purchaseId}',
          );
          Logger.info(
            'Account entry: Purchase Rs${purchase.totalAmount} → $accountType',
          );
        } catch (e) {
          Logger.error('Account entry failed for purchase', e);
        }
      }

      return Purchase.fromJson(response);
    } catch (e) {
      print('[PURCHASE] ❌ INSERT FAILED: $e');
      print('[PURCHASE] Error type: ${e.runtimeType}');
      Logger.warning('Supabase insert failed, saving offline: $e');
      // Queue for offline sync
      final insertData = purchase.toInsertJson();
      // Add id and created_at so Purchase.fromJson() can parse pending data after restart
      final offlineId = DateTime.now().microsecondsSinceEpoch.toString();
      insertData['id'] = offlineId;
      insertData['created_at'] = DateTime.now().toUtc().toIso8601String();
      await _offlineService.queuePendingWrite({
        'table': 'purchases',
        'operation': 'insert',
        'data': insertData,
      });
      // Also cache locally so History tab shows it immediately
      await _offlineService.addCachedPurchase(insertData);
      // Queue stock increments for each item
      for (final item in purchase.items) {
        await _offlineService.queuePendingWrite({
          'table': 'products',
          'operation': 'stock_add',
          'data': {'product_id': item.productId, 'qty': item.qty},
        });
      }
      return purchase;
    }
  }

  Future<List<Purchase>> getPurchases({int limit = 100}) async {
    try {
      final response = await _client
          .from('purchases')
          .select()
          .order('created_at', ascending: false)
          .limit(limit)
          .timeout(const Duration(seconds: 10));

      final list = <Purchase>[];
      final rawList = <Map<String, dynamic>>[];
      final supabaseIds = <String>{};
      for (final e in response as List) {
        final map = e as Map<String, dynamic>;
        rawList.add(map);
        supabaseIds.add(map['id'] as String);
        try {
          list.add(Purchase.fromJson(map));
        } catch (parseError) {
          Logger.warning('Failed to parse purchase: $parseError');
        }
      }

      // Supabase returned data — normal path
      if (list.isNotEmpty) {
        final missingIds = list
            .where(
              (p) =>
                  (p.supplierName == null || p.supplierName!.isEmpty) &&
                  p.supplierId != null,
            )
            .map((p) => p.supplierId!)
            .toSet()
            .toList();

        if (missingIds.isNotEmpty) {
          final suppliersRes = await _client
              .from('suppliers')
              .select('id, name')
              .inFilter('id', missingIds);
          final nameMap = {
            for (final s in suppliersRes as List)
              s['id'] as String: s['name'] as String,
          };
          final result = list.map((p) {
            if (p.supplierId != null && nameMap.containsKey(p.supplierId)) {
              return Purchase(
                id: p.id,
                supplierName: nameMap[p.supplierId],
                items: p.items,
                totalAmount: p.totalAmount,
                createdBy: p.createdBy,
                createdAt: p.createdAt,
                supplierId: p.supplierId,
                isCredit: p.isCredit,
                amountPaid: p.amountPaid,
                dueAmount: p.dueAmount,
                paymentMethod: p.paymentMethod,
              );
            }
            return p;
          }).toList();

          final merged = await _mergeOfflinePurchases(result, rawList, supabaseIds);
          return merged;
        }

        final merged = await _mergeOfflinePurchases(list, rawList, supabaseIds);
        return merged;
      }

      // Supabase returned EMPTY — fall back to cache (like sales does)
      Logger.warning('Supabase returned 0 purchases, falling back to cache');
      return _loadOfflinePurchases(limit: limit);
    } catch (e) {
      Logger.warning('Supabase fetch failed, using cache: $e');
      return _loadOfflinePurchases(limit: limit);
    }
  }

  /// Load purchases from local cache + pending writes (mirrors sale_service._loadOfflineSales)
  List<Purchase> _loadOfflinePurchases({int limit = 100}) {
    final cached = _offlineService.getCachedPurchases();
    final pendingRaw = _offlineService.getPendingPurchases();
    final allOffline = <String, Map<String, dynamic>>{};
    for (final p in cached) {
      final id = p['id']?.toString() ?? '';
      if (id.isNotEmpty) allOffline[id] = p;
    }
    for (final p in pendingRaw) {
      final id = p['id']?.toString() ?? '';
      if (id.isNotEmpty) allOffline[id] = p;
    }
    final merged = allOffline.values.toList()
      ..sort((a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''));
    final purchases = <Purchase>[];
    for (final e in merged.take(limit)) {
      try {
        purchases.add(Purchase.fromJson(e));
      } catch (ex) {
        Logger.warning('Failed to parse cached purchase: $ex');
      }
    }
    Logger.info('Loaded ${purchases.length} purchases from offline cache+pending');
    return purchases;
  }

  /// Merge pending offline purchases (not yet in Supabase) into the result list
  Future<List<Purchase>> _mergeOfflinePurchases(
    List<Purchase> supabasePurchases,
    List<Map<String, dynamic>> supabaseRaw,
    Set<String> supabaseIds,
  ) async {
    try {
      // 1. Get purchases from pending writes (still queued for sync)
      final pendingRaw = _offlineService.getPendingPurchases();
      final offlineIds = <String>{};
      final pendingPurchases = <Purchase>[];
      for (final rawData in pendingRaw) {
        final pid = rawData['id'] as String?;
        if (pid != null && supabaseIds.contains(pid)) continue;
        offlineIds.add(pid ?? '');
        try {
          pendingPurchases.add(Purchase.fromJson(rawData));
        } catch (e) {
          Logger.warning('Failed to parse pending purchase: $e');
        }
      }

      // 2. Also check cache for orphaned purchases (pending write removed after max retries)
      final cachedPurchases = _offlineService.getCachedPurchases();
      for (final cached in cachedPurchases) {
        final cid = cached['id'] as String?;
        if (cid == null) continue;
        // Skip if already in Supabase or already found in pending writes
        if (supabaseIds.contains(cid) || offlineIds.contains(cid)) continue;
        try {
          pendingPurchases.add(Purchase.fromJson(cached));
          Logger.info('Found orphaned cached purchase: $cid');
        } catch (e) {
          Logger.warning('Failed to parse cached purchase: $e');
        }
      }

      if (pendingPurchases.isEmpty) {
        // Only overwrite cache if Supabase actually returned data
        if (supabaseRaw.isNotEmpty) {
          try {
            await _offlineService.cachePurchases(supabaseRaw);
          } catch (_) {}
        }
        return supabasePurchases;
      }

      // Merge: pending/offline purchases + Supabase purchases
      final mergedList = [...pendingPurchases, ...supabasePurchases];

      // Update cache with merged data so orphaned purchases persist
      try {
        final mergedRaw = [
          ...pendingPurchases.map((p) => p.toInsertJson()..['id'] = p.id),
          ...supabaseRaw,
        ];
        await _offlineService.cachePurchases(mergedRaw);
      } catch (_) {}

      Logger.info('Merged ${pendingPurchases.length} pending/offline purchases');
      return mergedList;
    } catch (e) {
      Logger.warning('Failed to merge offline purchases: $e');
      return supabasePurchases;
    }
  }

  Future<void> deletePurchase(String purchaseId) async {
    try {
      final purchaseData = await _client
          .from('purchases')
          .select('items, is_credit, supplier_id, total_amount, payment_method')
          .eq('id', purchaseId)
          .single();

      final items = purchaseData['items'] as List? ?? [];
      final isCredit = purchaseData['is_credit'] as bool? ?? false;
      final supplierId = purchaseData['supplier_id'] as String?;
      final totalAmount =
          (purchaseData['total_amount'] as num?)?.toDouble() ?? 0;
      final paymentMethod = purchaseData['payment_method'] as String? ?? 'cash';

      try {
        await _client
            .from('inventory_batches')
            .delete()
            .eq('purchase_id', purchaseId);
      } catch (e) {
        Logger.warning('Failed to delete inventory batches: $e');
      }

      // Decrement stock per item (with individual error handling)
      for (final item in items) {
        final productId = item['product_id'] as String?;
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        if (productId != null && qty > 0) {
          try {
            await _client.rpc(
              'decrement_stock',
              params: {'p_product_id': productId, 'p_qty': qty},
            );
          } catch (e) {
            Logger.warning('Failed to decrement stock for $productId: $e');
          }
        }
      }

      // Reverse account entry (Money In — undo the Money Out)
      if (!isCredit && totalAmount > 0) {
        try {
          final accounts = await _accountService.getAccounts();
          if (accounts.isNotEmpty) {
            final accountType =
                (paymentMethod == 'upi' ||
                    paymentMethod == 'digital' ||
                    paymentMethod == 'bank')
                ? 'bank'
                : 'cash';
            final account = accounts.firstWhere(
              (a) => a.accountType == accountType,
              orElse: () => accounts.first,
            );
            await _accountService.addTransaction(
              accountId: account.id,
              type: 'in',
              amount: totalAmount,
              category: 'purchase_reversal',
              description: 'Reversed purchase',
            );
          }
        } catch (e) {
          Logger.error('Failed to reverse account entry for purchase', e);
        }
      }

      if (isCredit && supplierId != null) {
        try {
          await _client
              .from('supplier_payments')
              .delete()
              .eq('purchase_id', purchaseId);
        } catch (e) {
          Logger.warning('Failed to delete supplier payment for purchase: $e');
        }
      }

      await _client.from('purchases').delete().eq('id', purchaseId);
      ProductService.invalidateCache();
    } catch (e) {
      Logger.warning('Delete purchase failed (offline?), queuing: $e');
      await _offlineService.queuePendingWrite({
        'table': 'purchases',
        'operation': 'delete',
        'data': {'id': purchaseId},
      });
      rethrow;
    }
  }

  Future<double> getTotalPurchases() async {
    try {
      final response = await _client.from('purchases').select('total_amount');
      double total = 0;
      for (final e in response as List) {
        total += (e['total_amount'] as num).toDouble();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<void> editPurchaseAtomic({
    required String purchaseId,
    required List<PurchaseItem> items,
    required double totalAmount,
    String? supplierId,
    String? supplierName,
    required bool isCredit,
    required double amountPaid,
    required double dueAmount,
    required String paymentMethod,
    required String reason,
  }) async {
    try {
      // Fetch original purchase to identify new items
      List<String> oldProductIds = [];
      try {
        final oldPurchase = await _client
            .from('purchases')
            .select('items')
            .eq('id', purchaseId)
            .single();
        final oldItems = (oldPurchase['items'] as List?) ?? [];
        oldProductIds = oldItems
            .map((e) => e['product_id'] as String)
            .where((id) => id.isNotEmpty)
            .toList();
      } catch (e) {
        Logger.warning('Could not fetch original purchase items: $e');
      }

      final newProductIds = items.map((e) => e.productId).toSet();
      final addedItems = items
          .where((item) => !oldProductIds.contains(item.productId))
          .toList();

      await _client.rpc(
        'edit_purchase_atomic',
        params: {
          'p_purchase_id': purchaseId,
          'p_items': items.map((item) => item.toJson()).toList(),
          'p_total_amount': totalAmount,
          'p_supplier_id': supplierId,
          'p_supplier_name': supplierName,
          'p_is_credit': isCredit,
          'p_amount_paid': amountPaid,
          'p_due_amount': dueAmount,
          'p_payment_method': paymentMethod,
          'p_reason': reason,
        },
      );

      // Handle stock + batches for newly added products (RPC may not cover these)
      if (addedItems.isNotEmpty) {
        final stockFutures = <Future>[];
        for (final item in addedItems) {
          stockFutures.add(_productService.addStock(item.productId, item.qty));
          stockFutures.add(
            _client
                .rpc(
                  'add_inventory_batch',
                  params: {
                    'p_product_id': item.productId,
                    'p_purchase_id': purchaseId,
                    'p_quantity': item.qty,
                    'p_purchase_price': item.price,
                    'p_batch_number': item.batchNumber,
                    'p_expiry_date': item.expiryDate
                        ?.toIso8601String()
                        .split('T')
                        .first,
                  },
                )
                .catchError((e) {
                  Logger.warning('Failed to add inventory batch: $e');
                }),
          );
          stockFutures.add(
            _client
                .from('products')
                .update({'purchase_price': item.price})
                .eq('id', item.productId)
                .catchError((e) {
                  Logger.warning('Failed to update purchase_price: $e');
                }),
          );
        }
        await Future.wait(stockFutures);
      }
    } catch (e) {
      Logger.warning('Edit purchase failed (offline?), queuing: $e');
      await _offlineService.queuePendingWrite({
        'table': 'purchases',
        'operation': 'update',
        'data': {
          'id': purchaseId,
          'items': items.map((item) => item.toJson()).toList(),
          'total_amount': totalAmount,
          'supplier_id': supplierId,
          'is_credit': isCredit,
          'amount_paid': amountPaid,
          'due_amount': dueAmount,
          'payment_method': paymentMethod,
        },
      });
    }
  }
}
