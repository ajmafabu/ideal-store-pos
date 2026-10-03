import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/product.dart';
import 'products.dart';

// ============================================
// DASHBOARD PROVIDERS
// ============================================

// Consolidated dashboard provider — single RPC call replaces 6+ individual calls
final dashboardSummaryProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  // Errors are NOT turned into zeros any more: a failed load shows as an
  // error instead of a misleading ₹0 (#18).
  final res = await Supabase.instance.client.rpc('get_dashboard_summary');
  if (res is Map) return Map<String, dynamic>.from(res);
  return {};
});

/// Profit, cost and stock value are admin-only; the database returns them
/// as null for staff (#28).
final dashboardIsAdminProvider = FutureProvider<bool>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return summary['is_admin'] == true;
});

// Individual providers now read from the consolidated summary
final todaySalesProvider = FutureProvider<double>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return (summary['today_sales'] as num?)?.toDouble() ?? 0;
});

final yesterdaySalesProvider = FutureProvider<double>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return (summary['yesterday_sales'] as num?)?.toDouble() ?? 0;
});

final todayExpensesProvider = FutureProvider<double>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return (summary['today_expenses'] as num?)?.toDouble() ?? 0;
});

final monthlyProfitProvider = FutureProvider<Map<String, double>>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  // monthly_sales is revenue net of GST and returns; cogs is the FIFO cost
  // of what was sold (not purchase bills) (#15, #18)
  final sales = (summary['monthly_sales'] as num?)?.toDouble() ?? 0;
  final cogs = (summary['monthly_cogs'] as num?)?.toDouble() ?? 0;
  final expenses = (summary['monthly_expenses'] as num?)?.toDouble() ?? 0;
  return {
    'sales': sales,
    'cogs': cogs,
    'purchases': cogs, // old key, same meaning (cost of goods sold)
    'returns': (summary['monthly_returns'] as num?)?.toDouble() ?? 0,
    'expenses': expenses,
    'profit': (summary['monthly_profit'] as num?)?.toDouble() ?? (sales - cogs - expenses),
  };
});

final stockValueProvider = FutureProvider<double>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return (summary['stock_value'] as num?)?.toDouble() ?? 0;
});

/// Low AND out-of-stock products (the old filter skipped stock 0, so the
/// "Out of Stock" list was always empty) (#24).
final lowStockListProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products
      .where((p) => !p.hasVariants && p.stock <= p.lowStockAlert)
      .toList()
    ..sort((a, b) => a.stock.compareTo(b.stock));
});

final missingCostPriceProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products.where((p) => p.purchasePrice <= 0).toList();
});

/// Expiry alerts from purchase batches (where expiry dates are entered) as
/// well as the product's own expiry field (#24). One entry per product, at
/// its earliest expiring batch that still has stock.
final expiringProductsProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  final byId = {for (final p in products) p.id: p};
  final earliest = <String, DateTime>{};
  try {
    final rows = await Supabase.instance.client.rpc('get_expiring_batches', params: {'p_days': 30});
    for (final r in (rows as List? ?? const [])) {
      final m = Map<String, dynamic>.from(r as Map);
      final id = m['product_id']?.toString();
      final d = DateTime.tryParse(m['expiry_date']?.toString() ?? '');
      if (id == null || d == null || !byId.containsKey(id)) continue;
      if (!earliest.containsKey(id) || d.isBefore(earliest[id]!)) earliest[id] = d;
    }
  } catch (_) {
    // fall back to the product field below
  }
  for (final p in products) {
    if (p.expiryDate != null && (p.isExpiringSoon || p.isExpired) && !earliest.containsKey(p.id)) {
      earliest[p.id] = p.expiryDate!;
    }
  }
  final list = earliest.entries.map((e) => byId[e.key]!.copyWith(expiryDate: e.value)).toList()
    ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
  return list;
});

final recentSalesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  final recent = summary['recent_sales'];
  if (recent is List) {
    return recent.cast<Map<String, dynamic>>();
  }
  return [];
});

final weeklySalesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  final weekly = summary['weekly_sales'];
  if (weekly is List) {
    return weekly.cast<Map<String, dynamic>>();
  }
  return [];
});

final topProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  final top = summary['top_products'];
  if (top is List) {
    return top
        .map<Map<String, dynamic>>(
          (e) => {
            'name': e['name'] ?? '',
            'total': (e['total'] as num?)?.toDouble() ?? 0,
          },
        )
        .toList();
  }
  return [];
});

// ============================================
// ENHANCED DASHBOARD
// ============================================

final todayOrderCountProvider = FutureProvider<int>((ref) async {
  try {
    final summary = await ref.watch(dashboardSummaryProvider.future);
    return (summary['today_order_count'] as num?)?.toInt() ?? 0;
  } catch (e) {
    return 0;
  }
});

final yesterdayOrderCountProvider = FutureProvider<int>((ref) async {
  try {
    final summary = await ref.watch(dashboardSummaryProvider.future);
    return (summary['yesterday_order_count'] as num?)?.toInt() ?? 0;
  } catch (e) {
    return 0;
  }
});

final todayAvgOrderValueProvider = FutureProvider<double>((ref) async {
  try {
    final summary = await ref.watch(dashboardSummaryProvider.future);
    final todaySales = (summary['today_sales'] as num?)?.toDouble() ?? 0;
    final orderCount = (summary['today_order_count'] as num?)?.toInt() ?? 0;
    return orderCount > 0 ? todaySales / orderCount : 0;
  } catch (e) {
    return 0;
  }
});
