import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_timezone.dart';

// ============================================
// ANALYTICS
// ============================================

final monthlySalesSummaryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange?>((
      ref,
      dateRange,
    ) async {
      try {
        final res = await Supabase.instance.client.rpc(
          'get_monthly_sales_summary',
        );
        if (res is List) {
          var data = res
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
          if (dateRange != null) {
            final startUtc = AppTimezone.toUtc(dateRange.start);
            final endUtc = AppTimezone.toUtc(dateRange.end);
            data = data.where((row) {
              final monthStr = row['month'] as String? ?? '';
              final monthDate = DateTime.tryParse(monthStr);
              if (monthDate == null) return true;
              return !monthDate.isBefore(startUtc) &&
                  !monthDate.isAfter(endUtc);
            }).toList();
          }
          return data;
        }
        return [];
      } catch (e) {
        return [];
      }
    });

final categorySalesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange?>((
      ref,
      dateRange,
    ) async {
      try {
        final params = <String, dynamic>{};
        if (dateRange != null) {
          final startUtc = AppTimezone.toUtc(dateRange.start);
          final endUtc = AppTimezone.toUtc(dateRange.end);
          params['p_start'] = startUtc.toIso8601String();
          params['p_end'] = endUtc.toIso8601String();
        }
        final res = await Supabase.instance.client.rpc(
          'get_category_sales',
          params: params,
        );
        if (res is List) {
          return res
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        return [];
      } catch (e) {
        return [];
      }
    });

final dailySalesTrendProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange?>((
      ref,
      dateRange,
    ) async {
      try {
        final params = <String, dynamic>{};
        if (dateRange != null) {
          final startUtc = AppTimezone.toUtc(dateRange.start);
          final endUtc = AppTimezone.toUtc(dateRange.end);
          params['p_start'] = startUtc.toIso8601String();
          params['p_end'] = endUtc.toIso8601String();
        }
        final res = await Supabase.instance.client.rpc(
          'get_daily_sales_trend',
          params: params,
        );
        if (res is List) {
          return res
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        return [];
      } catch (e) {
        return [];
      }
    });

// ============================================
// AI INSIGHTS — MONTHLY AGGREGATES
// ============================================

final monthlySalesOnlyProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.monthStartUtc();
    final end = AppTimezone.monthEndUtc();
    final res = await Supabase.instance.client.rpc(
      'get_sales_total',
      params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      },
    );
    return (res as num?)?.toDouble() ?? 0;
  } catch (e) {
    return 0;
  }
});

final monthlyExpensesProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.monthStartUtc();
    final end = AppTimezone.monthEndUtc();
    final res = await Supabase.instance.client.rpc(
      'get_expenses_total',
      params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      },
    );
    return (res as num?)?.toDouble() ?? 0;
  } catch (e) {
    return 0;
  }
});

final monthlyGstProvider = FutureProvider<double>((ref) async {
  try {
    final client = Supabase.instance.client;
    final start = AppTimezone.monthStartUtc();
    final end = AppTimezone.monthEndUtc();

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

final monthlyPurchasesOnlyProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.monthStartUtc();
    final end = AppTimezone.monthEndUtc();
    final res = await Supabase.instance.client.rpc(
      'get_monthly_profit',
      params: {
        'p_start': start.toIso8601String(),
        'p_end': end.toIso8601String(),
      },
    );
    if (res is List && res.isNotEmpty) {
      return (res.first['purchase_cost'] as num?)?.toDouble() ?? 0;
    }
    return 0;
  } catch (e) {
    return 0;
  }
});

// ============================================
// PHASE 1: SERVER-SIDE ANALYTICS PROVIDERS
// ============================================

final customerInsightsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc('get_customer_insights');
    if (res is List) {
      return res
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

final productInsightsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc('get_product_insights');
    if (res is List) {
      return res
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

final inventoryHealthProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc('get_inventory_health');
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first);
    }
    return {};
  } catch (e) {
    return {};
  }
});

final financialSummaryProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc('get_financial_summary');
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first);
    }
    return {};
  } catch (e) {
    return {};
  }
});

final salesForecastProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final res = await Supabase.instance.client.rpc('get_sales_forecast');
    if (res is List && res.isNotEmpty) {
      return Map<String, dynamic>.from(res.first);
    }
    return {};
  } catch (e) {
    return {};
  }
});
