import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_timezone.dart';
import 'products.dart';
import 'dashboard.dart';

// ============================================
// ENHANCED DASHBOARD — TODAY CATEGORY/GST/SPARK
// ============================================

final todayCategorySalesProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  try {
    final client = Supabase.instance.client;
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();

    final salesRes = await client
        .from('sales')
        .select('items')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String());

    final products = await ref.watch(productsProvider.future);
    final productCat = <String, String>{};
    for (final p in products) {
      productCat[p.id] = p.category ?? 'Other';
    }

    final catSales = <String, double>{};
    for (final sale in salesRes as List) {
      final items = sale['items'] as List? ?? [];
      for (final item in items) {
        final pid = item['product_id'] as String? ?? '';
        final cat = productCat[pid] ?? 'Other';
        final amount = (item['total'] as num?)?.toDouble() ?? 0;
        catSales[cat] = (catSales[cat] ?? 0) + amount;
      }
    }
    return catSales;
  } catch (e) {
    return {};
  }
});

final todayGstTotalProvider = FutureProvider<double>((ref) async {
  try {
    final client = Supabase.instance.client;
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();

    final salesRes = await client
        .from('sales')
        .select('items')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String());

    double totalGst = 0;
    for (final sale in salesRes as List) {
      final items = sale['items'] as List? ?? [];
      for (final item in items) {
        final rate = (item['gst_rate'] as num?)?.toDouble() ?? 0;
        final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
        if (rate > 0) {
          totalGst += itemTotal * rate / (100 + rate);
        }
      }
    }
    return totalGst;
  } catch (e) {
    return 0;
  }
});

final weeklySalesSparkProvider = FutureProvider<List<double>>((ref) async {
  try {
    final now = AppTimezone.nowIst();
    final start = now.subtract(const Duration(days: 6));
    final dayStartUtc = DateTime.utc(
      start.year,
      start.month,
      start.day,
    ).subtract(AppTimezone.localOffset);
    final endUtc = DateTime.utc(
      now.year,
      now.month,
      now.day + 1,
    ).subtract(AppTimezone.localOffset);

    final response = await Supabase.instance.client
        .from('sales')
        .select('final_amount, created_at')
        .gte('created_at', dayStartUtc.toIso8601String())
        .lt('created_at', endUtc.toIso8601String());

    Map<String, double> daily = {};
    for (int i = 0; i < 7; i++) {
      final day = now.subtract(Duration(days: 6 - i));
      final key = '${day.year}-${day.month}-${day.day}';
      daily[key] = 0;
    }

    for (final sale in response as List) {
      final date = DateTime.parse(sale['created_at']).toLocal();
      final key = '${date.year}-${date.month}-${date.day}';
      daily[key] = (daily[key] ?? 0) + (sale['final_amount'] as num).toDouble();
    }

    return daily.values.toList();
  } catch (e) {
    return List.filled(7, 0);
  }
});
