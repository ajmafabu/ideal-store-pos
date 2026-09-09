import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
      final id = const Uuid().v4();

      final response = await _client
          .rpc(
            'create_return_atomic',
            params: {
              'p_id': id,
              'p_product_id': productReturn.productId,
              'p_sale_id': productReturn.originalSaleId,
              'p_product_name': productReturn.productName,
              'p_quantity': productReturn.quantity,
              'p_unit_price': productReturn.unitPrice,
              'p_refund_amount': productReturn.returnAmount,
              'p_reason': productReturn.reason,
              'p_created_by': user?.id,
            },
          )
          .select()
          .single();

      final created = ProductReturn.fromJson(response);

      // Update sale amounts and credit after return
      if (created.originalSaleId != null && created.returnAmount > 0) {
        try {
          final saleData = await _client
              .from('sales')
              .select('is_credit, final_amount, due_amount')
              .eq('id', created.originalSaleId!)
              .maybeSingle();

          if (saleData != null) {
            final currentFinal =
                (saleData['final_amount'] as num?)?.toDouble() ?? 0;
            final newFinal = (currentFinal - created.returnAmount).clamp(
              0,
              double.infinity,
            );
            final updateData = <String, dynamic>{'final_amount': newFinal};

            if (saleData['is_credit'] == true) {
              final currentDue =
                  (saleData['due_amount'] as num?)?.toDouble() ?? 0;
              final newDue = (currentDue - created.returnAmount).clamp(
                0,
                double.infinity,
              );
              updateData['due_amount'] = newDue;
            }

            await _client
                .from('sales')
                .update(updateData)
                .eq('id', created.originalSaleId!);
          }
        } catch (e) {
          Logger.warning('Failed to update sale amounts after return: $e');
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
      // Re-throw validation/business errors — do NOT queue for offline
      final msg = e.toString();
      if (msg.contains('Cannot return') ||
          msg.contains('not found') ||
          msg.contains('Invalid') ||
          msg.contains('must be positive') ||
          msg.contains('Exceeded maximum')) {
        rethrow;
      }
      // Network/offline error — queue for offline sync
      final id = const Uuid().v4();
      await _offlineService.queuePendingWrite({
        'table': 'product_returns',
        'operation': 'insert',
        'data': {
          'id': id,
          'product_id': productReturn.productId,
          'original_sale_id': productReturn.originalSaleId,
          'product_name': productReturn.productName,
          'quantity': productReturn.quantity,
          'unit_price': productReturn.unitPrice,
          'refund_amount': productReturn.returnAmount,
          'reason': productReturn.reason,
          'created_by': _client.auth.currentUser?.id,
        },
      });
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
