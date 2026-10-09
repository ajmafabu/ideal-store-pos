import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase.dart';
import '../models/sale.dart' show isUuid, newDocumentId;
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'product_service.dart';
import 'account_service.dart';
import 'offline_service.dart';

class PurchaseService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  PurchaseService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _offlineService = offlineService ?? OfflineService();

  /// Saves a purchase with ONE insert. The database adds stock, creates
  /// costed batches (bill discount spread into the landed cost), updates the
  /// cost price, the supplier's dues and the cash/bank outflow in the same
  /// transaction (#11). Server rejections are thrown; only a network
  /// failure queues the purchase (same id, so the replay is idempotent).
  Future<Purchase> createPurchase(Purchase purchase) async {
    final withId = isUuid(purchase.id) ? purchase : _withId(purchase, newDocumentId());
    final insertData = withId.toInsertJson();
    try {
      final response = await _client
          .from('purchases')
          .insert(insertData)
          .select()
          .single()
          .timeout(const Duration(seconds: 20), onTimeout: () => throw Exception('Connection timeout'));
      ProductService.invalidateCache();
      return Purchase.fromJson(response);
    } catch (e) {
      if (isDuplicateKey(e)) {
        final existing = await _client.from('purchases').select().eq('id', withId.id).single();
        return Purchase.fromJson(existing);
      }
      if (!isNetworkError(e)) rethrow;
      Logger.warning('Purchase could not reach the server, queuing: $e');
      await _offlineService.queuePendingWrite({
        'table': 'purchases',
        'operation': 'insert',
        'data': insertData,
      });
      await _offlineService.addCachedPurchase(Map<String, dynamic>.from(insertData));
      return withId;
    }
  }

  Purchase _withId(Purchase p, String id) => Purchase(
    id: id,
    supplierName: p.supplierName,
    items: p.items,
    totalAmount: p.totalAmount,
    roundOff: p.roundOff,
    createdBy: p.createdBy,
    createdAt: p.createdAt,
    supplierId: p.supplierId,
    isCredit: p.isCredit,
    amountPaid: p.amountPaid,
    dueAmount: p.dueAmount,
    paymentMethod: p.paymentMethod,
    dueDate: p.dueDate,
  );

  /// Purchases older than [before], newest first — for "Load older
  /// purchases" (history held only the latest 500, QA #21).
  Future<List<Purchase>> getOlderPurchases({required DateTime before, int limit = 200}) async {
    final response = await _client
        .from('purchases')
        .select()
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit)
        .timeout(const Duration(seconds: 15));
    final list = <Purchase>[];
    for (final e in response as List) {
      try {
        list.add(Purchase.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (ex) {
        Logger.warning('Skipping unreadable purchase: $ex');
      }
    }
    return list;
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

          final merged = await _mergeOfflinePurchases(
            result,
            rawList,
            supabaseIds,
          );
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
      ..sort(
        (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
      );
    final purchases = <Purchase>[];
    for (final e in merged.take(limit)) {
      try {
        purchases.add(Purchase.fromJson(e));
      } catch (ex) {
        Logger.warning('Failed to parse cached purchase: $ex');
      }
    }
    Logger.info(
      'Loaded ${purchases.length} purchases from offline cache+pending',
    );
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

      Logger.info(
        'Merged ${pendingPurchases.length} pending/offline purchases',
      );
      return mergedList;
    } catch (e) {
      Logger.warning('Failed to merge offline purchases: $e');
      return supabasePurchases;
    }
  }

  /// Deletes a purchase in one database transaction: its stock and batches
  /// are removed, supplier dues recomputed, and its cash/bank payment (and
  /// any supplier payments against it) reversed to the right account. The
  /// database refuses when some of the stock has already been sold (#11).
  Future<void> deletePurchase(String purchaseId) async {
    if (!isUuid(purchaseId)) {
      // never reached the server: just drop it from the queue/cache
      for (final w in _offlineService.getPendingWrites()) {
        final data = w['data'];
        if (w['table'] == 'purchases' && data is Map && data['id'] == purchaseId) {
          await _offlineService.removePendingWrite(w['id'].toString());
        }
      }
      await _offlineService.removeCachedPurchase(purchaseId);
      return;
    }
    final pending = _offlineService.getPendingWrites().where((w) {
      final data = w['data'];
      return w['table'] == 'purchases' && w['operation'] == 'insert' && data is Map && data['id'] == purchaseId;
    }).toList();
    if (pending.isNotEmpty) {
      for (final w in pending) {
        await _offlineService.removePendingWrite(w['id'].toString());
      }
      await _offlineService.removeCachedPurchase(purchaseId);
      return;
    }
    await _client.rpc('delete_purchase_atomic', params: {'p_purchase_id': purchaseId});
    ProductService.invalidateCache();
    await _offlineService.removeCachedPurchase(purchaseId);
  }

  Future<double> getTotalPurchases() async {
    double total = 0;
    var offset = 0;
    try {
      while (true) {
        final page = await _client
            .from('purchases')
            .select('total_amount')
            .order('id')
            .range(offset, offset + 999);
        for (final e in page as List) {
          total += (e['total_amount'] as num?)?.toDouble() ?? 0;
        }
        if ((page as List).length < 1000) break;
        offset += 1000;
      }
    } catch (e) {
      Logger.warning('getTotalPurchases: $e');
    }
    return total;
  }

  /// Edits a purchase atomically on the server: old stock/batches out, new
  /// ones in at the new landed cost, cash/bank delta to ONE resolved
  /// account, supplier dues for old and new supplier (#11, #13). Errors are
  /// thrown to the caller — never queued as a raw UPDATE (#7).
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
    double? roundOff,
  }) async {
    if (!isUuid(purchaseId)) {
      throw Exception('This purchase has not been synced yet. Wait for sync, then edit it.');
    }
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
        'p_round_off': roundOff,
      },
    );
    ProductService.invalidateCache();
  }
}
