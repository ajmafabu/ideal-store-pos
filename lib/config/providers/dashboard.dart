import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/product.dart';
import '../../utils/logger.dart';
import 'products.dart';

// ============================================
// DASHBOARD PROVIDERS
// ============================================

// Consolidated dashboard provider — single RPC call replaces 6+ individual calls
final dashboardSummaryProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc('get_dashboard_summary');
    if (res is Map<String, dynamic>) return res;
    if (res is String) {
      return Map<String, dynamic>.from(
        (res as dynamic) as Map,
      );
    }
    return {};
  } catch (e) {
    return {};
  }
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
  final sales = (summary['monthly_sales'] as num?)?.toDouble() ?? 0;
  final purchases = (summary['monthly_cogs'] as num?)?.toDouble() ?? 0;
  final expenses = (summary['monthly_expenses'] as num?)?.toDouble() ?? 0;
  return {
    'sales': sales,
    'purchases': purchases,
    'expenses': expenses,
    'profit': (summary['monthly_profit'] as num?)?.toDouble() ??
        (sales - purchases - expenses),
  };
});

final stockValueProvider = FutureProvider<double>((ref) async {
  final summary = await ref.watch(dashboardSummaryProvider.future);
  return (summary['stock_value'] as num?)?.toDouble() ?? 0;
});

final lowStockListProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products.where((p) => p.isLowStock).toList();
});

final missingCostPriceProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products.where((p) => p.purchasePrice <= 0).toList();
});

final expiringProductsProvider = FutureProvider<List<Product>>((ref) async {
  final products = await ref.watch(productsProvider.future);
  return products
      .where((p) => p.expiryDate != null && (p.isExpiringSoon || p.isExpired))
      .toList()
    ..sort((a, b) => a.expiryDate!.compareTo(b.expiryDate!));
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
    final sales = await ref.read(recentSalesProvider.future);
    return sales.length;
  } catch (e) {
    return 0;
  }
});

final todayAvgOrderValueProvider = FutureProvider<double>((ref) async {
  try {
    final sales = await ref.watch(recentSalesProvider.future);
    if (sales.isEmpty) return 0;
    double total = 0;
    for (final s in sales) {
      total += (s['final_amount'] as num?)?.toDouble() ?? 0;
    }
    return sales.isNotEmpty ? total / sales.length : 0;
  } catch (e) {
    return 0;
  }
});
