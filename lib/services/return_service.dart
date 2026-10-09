import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/product_return.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'account_service.dart';
import 'offline_service.dart';
import 'product_service.dart';

class ReturnService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  ReturnService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _offlineService = offlineService ?? OfflineService();

  /// Records a return in one database transaction (#14):
  ///  * the refund value is what the customer actually paid for those units
  ///    (line and bill discounts, extras and round-off spread over the bill),
  ///  * on a credit sale the customer's due is reduced first and only the
  ///    rest is paid out,
  ///  * the refund leaves the account the customer paid into (or
  ///    [refundMethod] when given),
  ///  * stock goes back into the exact batches the sale consumed.
  /// Only a network failure queues the return for later; any rule the
  /// database rejects (e.g. returning more than was sold) is thrown.
  Future<ProductReturn> createReturn(ProductReturn productReturn, {String? refundMethod}) async {
    final id = const Uuid().v4();
    final params = {
      'p_id': id,
      'p_product_id': productReturn.productId,
      'p_sale_id': productReturn.originalSaleId,
      'p_product_name': productReturn.productName,
      'p_quantity': productReturn.quantity,
      'p_reason': productReturn.reason,
      'p_created_by': _client.auth.currentUser?.id,
      'p_refund_method': refundMethod,
    };
    try {
      final response = await _client.rpc('create_return_atomic', params: params).select().single();
      ProductService.invalidateCache();
      return ProductReturn.fromJson(response);
    } catch (e) {
      Logger.error('createReturn', e);
      if (!isNetworkError(e)) rethrow;
      await _offlineService.addPendingOperation({
        'type': 'return',
        'data': {
          'id': id,
          'product_id': productReturn.productId,
          'original_sale_id': productReturn.originalSaleId,
          'product_name': productReturn.productName,
          'quantity': productReturn.quantity,
          'reason': productReturn.reason,
          'refund_method': refundMethod,
        },
      });
      return ProductReturn(
        id: id,
        productId: productReturn.productId,
        originalSaleId: productReturn.originalSaleId,
        productName: productReturn.productName,
        quantity: productReturn.quantity,
        unitPrice: productReturn.unitPrice,
        returnAmount: productReturn.returnAmount,
        refundAmount: productReturn.returnAmount,
        reason: productReturn.reason,
        createdAt: DateTime.now().toUtc(),
      );
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
          .select('return_amount')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      double total = 0;
      for (final e in response as List) {
        total += (e['return_amount'] as num?)?.toDouble() ?? 0;
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
          .or('original_sale_id.eq.$saleId,sale_id.eq.$saleId')
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
            'id, invoice_no, final_amount, payment_method, created_at, items, is_credit, due_amount, cash_amount, digital_amount, customer_id, customers(name)',
          );

      if (query != null && query.isNotEmpty) {
        final n = int.tryParse(query.replaceAll('#', '').trim());
        if (n != null) {
          builder = builder.eq('invoice_no', n);
        } else if (RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(query.trim())) {
          builder = builder.eq('id', query.trim());
        }
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

  /// Bills to pick a return from: the last 30 days, up to 500. Was 7 days
  /// and 50 bills — about one day at this shop (QA #27). Older bills are
  /// found by number with [findSaleByInvoice].
  Future<List<Map<String, dynamic>>> getRecentWeekSales() async {
    try {
      final weekAgo = AppTimezone.nowIst().subtract(const Duration(days: 30));
      final weekAgoUtc = weekAgo.toUtc();

      final response = await _client
          .from('sales')
          .select(
            'id, invoice_no, final_amount, payment_method, created_at, items, is_credit, due_amount, cash_amount, digital_amount, customer_id, customers(name)',
          )
          .gte('created_at', weekAgoUtc.toIso8601String())
          .order('created_at', ascending: false)
          .limit(500);

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      Logger.error('getRecentWeekSales', e);
      return [];
    }
  }

  /// Any bill by its number, however old.
  Future<Map<String, dynamic>?> findSaleByInvoice(int invoiceNo) async {
    final response = await _client
        .from('sales')
        .select(
          'id, invoice_no, final_amount, payment_method, created_at, items, is_credit, due_amount, cash_amount, digital_amount, customer_id, customers(name)',
        )
        .eq('invoice_no', invoiceNo)
        .maybeSingle();
    return response;
  }

  /// Creates several returns; reports which ones the database refused
  /// instead of silently dropping them (#14).
  Future<({List<ProductReturn> created, List<String> failed})> createBulkReturn({
    required String? originalSaleId,
    required List<ProductReturn> returns,
    String? refundMethod,
  }) async {
    final created = <ProductReturn>[];
    final failed = <String>[];
    for (final r in returns) {
      try {
        created.add(await createReturn(r, refundMethod: refundMethod));
      } catch (e) {
        failed.add('${r.productName}: ${serverMessage(e)}');
      }
    }
    return (created: created, failed: failed);
  }
}
