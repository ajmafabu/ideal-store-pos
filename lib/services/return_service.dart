import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_return.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'offline_service.dart';

class ReturnService {
  final SupabaseClient _client;
  final AccountService? _accountService;
  final OfflineService _offlineService;

  ReturnService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _accountService = accountService,
       _offlineService = offlineService ?? OfflineService();

  Future<ProductReturn> createReturn(ProductReturn productReturn) async {
    try {
      final user = _client.auth.currentUser;

      final response = await _client
          .from('product_returns')
          .insert(productReturn.toInsertJson()..['created_by'] = user?.id)
          .select()
          .single();

      final created = ProductReturn.fromJson(response);

      // Increase stock back
      if (created.productId != null) {
        try {
          await _client.rpc(
            'increment_stock',
            params: {
              'p_product_id': created.productId,
              'p_qty': created.quantity,
            },
          );
        } catch (e) {
          Logger.warning('Failed to increment stock for return: $e');
        }
      }

      // Update original sale's due_amount if it was a credit sale
      if (created.originalSaleId != null && created.returnAmount > 0) {
        try {
          final saleData = await _client
              .from('sales')
              .select('is_credit, due_amount')
              .eq('id', created.originalSaleId!)
              .maybeSingle();

          if (saleData != null && saleData['is_credit'] == true) {
            final currentDue =
                (saleData['due_amount'] as num?)?.toDouble() ?? 0;
            final newDue = (currentDue - created.returnAmount).clamp(
              0,
              double.infinity,
            );
            await _client
                .from('sales')
                .update({'due_amount': newDue})
                .eq('id', created.originalSaleId!);
          }
        } catch (e) {
          Logger.warning('Failed to update original sale due_amount: $e');
        }
      }

      // Money out from accounts (refund)
      if (created.refundAmount > 0 && _accountService != null) {
        final accountService = _accountService;
        try {
          final accounts = await accountService.getAccounts();
          final account = accounts.firstWhere(
            (a) => a.accountType == 'cash',
            orElse: () => accounts.first,
          );
          await accountService.addTransaction(
            accountId: account.id,
            type: 'out',
            amount: created.refundAmount,
            category: 'return_refund',
            description:
                'Return: ${created.productName} (qty: ${created.quantity})',
          );
        } catch (e) {
          Logger.warning('Failed to add account entry for return: $e');
        }
      }

      return created;
    } catch (e) {
      Logger.error('createReturn', e);
      // Queue for offline
      await _offlineService.queuePendingWrite({
        'table': 'product_returns',
        'operation': 'insert',
        'data': productReturn.toInsertJson(),
      });
      // Queue stock increment for returned product
      if (productReturn.productId != null &&
          productReturn.productId!.isNotEmpty &&
          productReturn.quantity > 0) {
        await _offlineService.queuePendingWrite({
          'table': 'products',
          'operation': 'stock_add',
          'data': {
            'product_id': productReturn.productId,
            'qty': productReturn.quantity,
          },
        });
      }
      return productReturn;
    }
  }

  Future<List<ProductReturn>> getReturns({int limit = 100}) async {
    try {
      final response = await _client
          .from('product_returns')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (response as List)
          .map((e) => ProductReturn.fromJson(e))
          .toList();

      // Cache for offline
      try {
        await _offlineService.cacheReturns(
          (response as List).cast<Map<String, dynamic>>(),
        );
      } catch (e) {
        Logger.warning('Failed to cache product returns for offline: $e');
      }

      return list;
    } catch (e) {
      Logger.error('getReturns', e);
      // Offline fallback
      try {
        final cached = _offlineService.getCachedReturns();
        if (cached.isNotEmpty) {
          return cached.map((e) => ProductReturn.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to load product returns from offline cache: $e');
      }
      return [];
    }
  }

  Future<double> getTodayReturnsTotal() async {
    try {
      final start = AppTimezone.todayStartUtc();
      final end = AppTimezone.todayEndUtc();

      final response = await _client
          .from('product_returns')
          .select('refund_amount')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      double total = 0;
      for (final e in response as List) {
        total += (e['refund_amount'] as num?)?.toDouble() ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<List<ProductReturn>> getReturnsBySaleId(String saleId) async {
    try {
      final response = await _client
          .from('product_returns')
          .select()
          .eq('original_sale_id', saleId)
          .order('created_at', ascending: false);

      return (response as List).map((e) => ProductReturn.fromJson(e)).toList();
    } catch (e) {
      Logger.error('getReturnsBySaleId', e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getSalesForReturnSearch({
    String? query,
    int limit = 20,
  }) async {
    try {
      var builder = _client
          .from('sales')
          .select(
            'id, final_amount, payment_method, created_at, items, is_credit, due_amount, customer_id, customers(name)',
          );

      if (query != null && query.isNotEmpty) {
        builder = builder.ilike('id', '%$query%');
      }

      final response = await builder
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      Logger.error('getSalesForReturnSearch', e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRecentWeekSales() async {
    try {
      final weekAgo = AppTimezone.nowIst().subtract(const Duration(days: 7));
      final weekAgoUtc = weekAgo.toUtc();

      final response = await _client
          .from('sales')
          .select(
            'id, final_amount, payment_method, created_at, items, is_credit, due_amount, customer_id, customers(name)',
          )
          .gte('created_at', weekAgoUtc.toIso8601String())
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      Logger.error('getRecentWeekSales', e);
      return [];
    }
  }

  Future<List<ProductReturn>> createBulkReturn({
    required String? originalSaleId,
    required List<ProductReturn> returns,
  }) async {
    final created = <ProductReturn>[];
    for (final r in returns) {
      try {
        final result = await createReturn(r);
        created.add(result);
      } catch (e) {
        Logger.warning('Failed to create return for ${r.productName}: $e');
      }
    }
    return created;
  }
}
