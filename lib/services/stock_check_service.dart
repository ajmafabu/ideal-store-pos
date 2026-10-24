import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../utils/stock_health.dart';
import 'product_service.dart';

/// Stock check: counting the shelf, and the data for the stock health
/// report (18 Oct 2026). Admin only (counts and batches are admin data).
class StockCheckService {
  StockCheckService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  /// What the app says right now (the list may be minutes old).
  Future<double> currentStock(String productId) async {
    final row = await _client.from('products').select('stock').eq('id', productId).single();
    return (row['stock'] as num?)?.toDouble() ?? 0;
  }

  /// Saves one count: the counted quantity becomes the stock (batches follow,
  /// in the database), and the count is kept with the app's figure when
  /// counting began ([appQty]) and the reason. Sales made while counting are
  /// kept. Returns {stock, moved, difference}.
  Future<Map<String, dynamic>> saveCount(Product product, double counted, String reason, {double? appQty}) =>
      ProductService.saveCountWith(_client, product.id, counted, appQty: appQty, reason: reason);

  /// Counts of the last [days] days (newest first).
  Future<List<StockCount>> recentCounts({int days = 120}) async {
    final since = DateTime.now().toUtc().subtract(Duration(days: days)).toIso8601String();
    final rows = await _client
        .from('stock_reconciliation')
        .select('product_id, system_qty, physical_qty, notes, created_at')
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(5000);
    return [
      for (final r in rows as List)
        if (r['product_id'] != null)
          StockCount(
            productId: r['product_id'].toString(),
            systemQty: (r['system_qty'] as num?)?.toDouble() ?? 0,
            countedQty: (r['physical_qty'] as num?)?.toDouble() ?? 0,
            at: DateTime.parse(r['created_at'].toString()).toLocal(),
            reason: r['notes']?.toString(),
          ),
    ];
  }

  /// Units still in batches per product (what FIFO cost is based on).
  Future<Map<String, double>> batchTotals() async {
    final totals = <String, double>{};
    var from = 0;
    const page = 1000;
    while (true) {
      final rows = await _client
          .from('inventory_batches')
          .select('product_id, remaining')
          .gt('remaining', 0)
          .order('id')
          .range(from, from + page - 1);
      final list = rows as List;
      for (final r in list) {
        final id = r['product_id']?.toString();
        if (id == null) continue;
        totals[id] = (totals[id] ?? 0) + ((r['remaining'] as num?)?.toDouble() ?? 0);
      }
      if (list.length < page) break;
      from += page;
    }
    return totals;
  }
}
