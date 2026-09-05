import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/profile.dart';
import '../models/sale.dart';
import '../models/purchase.dart';
import '../models/expense.dart';
import '../models/purchase_order.dart';
import '../models/customer.dart';
import '../models/supplier.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/purchase_service.dart';
import '../services/expense_service.dart';
import '../services/customer_service.dart';
import '../services/supplier_service.dart';
import '../services/account_service.dart';
import '../models/account.dart';
import '../utils/logger.dart';
import '../services/return_service.dart';
import '../services/damaged_service.dart';
import '../services/purchase_order_service.dart';
import '../services/offline_service.dart';
import '../services/connectivity_service.dart';
import '../utils/app_timezone.dart';

// ============================================
// SERVICE PROVIDERS (DI chain)
// ============================================

final authServiceProvider = Provider<AuthService>((ref) => AuthService());
final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(),
);
final offlineServiceProvider = Provider<OfflineService>(
  (ref) => OfflineService(),
);
final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);
final forceSyncProvider = FutureProvider<bool>((ref) async {
  final offlineService = ref.watch(offlineServiceProvider);
  return await offlineService.forceSync();
});

// Periodically refreshes pending sync count (every 10 seconds)
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final offlineService = ref.watch(offlineServiceProvider);
  final connectivityService = ref.watch(connectivityServiceProvider);

  while (true) {
    final pendingSales = offlineService.pendingCount;
    final pendingOps = offlineService.pendingOpsCount;
    final pendingWrites = offlineService.pendingWritesCount;
    final isConnected = connectivityService.isConnected;

    yield SyncStatus(
      isConnected: isConnected,
      pendingSales: pendingSales,
      pendingOps: pendingOps,
      pendingWrites: pendingWrites,
      lastSyncError: offlineService.lastSyncError,
    );

    await Future.delayed(const Duration(seconds: 10));
  }
});

class SyncStatus {
  final bool isConnected;
  final int pendingSales;
  final int pendingOps;
  final int pendingWrites;
  final String? lastSyncError;

  const SyncStatus({
    required this.isConnected,
    required this.pendingSales,
    required this.pendingOps,
    required this.pendingWrites,
    this.lastSyncError,
  });

  int get totalPending => pendingSales + pendingOps + pendingWrites;
  bool get hasPending => totalPending > 0;
}

final productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(offlineService: ref.watch(offlineServiceProvider)),
);

final saleServiceProvider = Provider<SaleService>(
  (ref) => SaleService(
    accountService: ref.watch(accountServiceProvider),
    offlineService: ref.watch(offlineServiceProvider),
  ),
);
final purchaseServiceProvider = Provider<PurchaseService>(
  (ref) => PurchaseService(accountService: ref.watch(accountServiceProvider)),
);
final expenseServiceProvider = Provider<ExpenseService>(
  (ref) => ExpenseService(accountService: ref.watch(accountServiceProvider)),
);
final customerServiceProvider = Provider<CustomerService>(
  (ref) => CustomerService(accountService: ref.watch(accountServiceProvider)),
);
final supplierServiceProvider = Provider<SupplierService>(
  (ref) => SupplierService(accountService: ref.watch(accountServiceProvider)),
);
final returnServiceProvider = Provider<ReturnService>(
  (ref) => ReturnService(accountService: ref.watch(accountServiceProvider)),
);
final damagedServiceProvider = Provider<DamagedService>(
  (ref) => DamagedService(),
);
final purchaseOrderServiceProvider = Provider<PurchaseOrderService>(
  (ref) => PurchaseOrderService(),
);

// ============================================
// PROFILE & AUTH
// ============================================

final profileProvider = FutureProvider<Profile?>((ref) async {
  final auth = ref.watch(authServiceProvider);
  final user = auth.currentUser;
  if (user == null) return null;
  try {
    return await auth.getCurrentProfile();
  } catch (e) {
    return null;
  }
});

// Helper for showing error states in UI
class DataLoadError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const DataLoadError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================
// PRODUCTS
// ============================================

final productsProvider = FutureProvider<List<Product>>((ref) async {
  final service = ref.watch(productServiceProvider);
  return service.getAllProducts();
});

// ============================================
// SALES
// ============================================

final salesHistoryProvider = FutureProvider<List<Sale>>((ref) async {
  final service = ref.watch(saleServiceProvider);
  return service.getSalesHistory(limit: 500);
});

// ============================================
// PURCHASES
// ============================================

final purchasesProvider = FutureProvider<List<Purchase>>((ref) async {
  final service = ref.watch(purchaseServiceProvider);
  return service.getPurchases(limit: 500);
});

// ============================================
// EXPENSES
// ============================================

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final service = ref.watch(expenseServiceProvider);
  return service.getExpenses(limit: 100);
});

// ============================================
// CUSTOMERS & SUPPLIERS
// ============================================

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final service = ref.watch(customerServiceProvider);
  return service.getCustomers();
});

final suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final service = ref.watch(supplierServiceProvider);
  return service.getSuppliers();
});

// ============================================
// STAFF
// ============================================

final staffListProvider = FutureProvider<List<Profile>>((ref) async {
  try {
    final response = await Supabase.instance.client
        .from('profiles')
        .select()
        .order('name');
    return (response as List).map((e) => Profile.fromJson(e)).toList();
  } catch (e) {
    return [];
  }
});

// ============================================
// DASHBOARD PROVIDERS
// ============================================

final todaySalesProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();
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

final yesterdaySalesProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.yesterdayStartUtc();
    final end = AppTimezone.yesterdayEndUtc();
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

final todayExpensesProvider = FutureProvider<double>((ref) async {
  try {
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();
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

final monthlyProfitProvider = FutureProvider<Map<String, double>>((ref) async {
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
      final row = res.first;
      final sales = (row['sales_total'] as num?)?.toDouble() ?? 0;
      final purchases = (row['purchase_cost'] as num?)?.toDouble() ?? 0;
      final expenses = (row['expenses_total'] as num?)?.toDouble() ?? 0;
      return {
        'sales': sales,
        'purchases': purchases,
        'expenses': expenses,
        'profit': sales - purchases - expenses,
      };
    }
    return {'sales': 0, 'purchases': 0, 'expenses': 0, 'profit': 0};
  } catch (e) {
    return {'sales': 0, 'purchases': 0, 'expenses': 0, 'profit': 0};
  }
});

final stockValueProvider = FutureProvider<double>((ref) async {
  try {
    final res = await Supabase.instance.client.rpc('get_stock_value');
    return (res as num?)?.toDouble() ?? 0;
  } catch (e) {
    return 0;
  }
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
  try {
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();

    final response = await Supabase.instance.client
        .from('sales')
        .select('id, final_amount, payment_method, created_at, items')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String())
        .order('created_at', ascending: false);
    return (response as List).cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});

final weeklySalesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
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
      final key = DateFormat('EEE').format(day);
      daily[key] = 0;
    }

    for (final sale in response as List) {
      final date = DateTime.parse(sale['created_at']).toLocal();
      final key = DateFormat('EEE').format(date);
      daily[key] = (daily[key] ?? 0) + (sale['final_amount'] as num).toDouble();
    }

    return daily.entries.map((e) => {'day': e.key, 'total': e.value}).toList();
  } catch (e) {
    return [];
  }
});

final topProductsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final res = await Supabase.instance.client.rpc(
      'get_top_products',
      params: {'p_days': 30, 'p_limit': 5},
    );
    if (res is List) {
      return res
          .map<Map<String, dynamic>>(
            (e) => {
              'name': e['name'] ?? '',
              'total': (e['total'] as num?)?.toDouble() ?? 0,
            },
          )
          .toList();
    }
    return [];
  } catch (e) {
    return [];
  }
});

// ============================================
// ACCOUNTS
// ============================================

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final service = ref.watch(accountServiceProvider);
  await service.ensureAccountsExist();
  return service.getAccounts();
});

final todayTransactionsProvider = FutureProvider<List<AccountTransaction>>((
  ref,
) async {
  final service = ref.watch(accountServiceProvider);
  return service.getTodayTransactions();
});

final monthlySummaryProvider = FutureProvider<Map<String, double>>((ref) async {
  final service = ref.watch(accountServiceProvider);
  return service.getMonthlySummary();
});

final dateRangeTransactionsProvider =
    FutureProvider.family<
      List<AccountTransaction>,
      ({DateTime start, DateTime end})
    >((ref, dates) async {
      final service = ref.watch(accountServiceProvider);
      return service.getTransactions(
        startDate: dates.start,
        endDate: dates.end,
      );
    });

// ============================================
// RETURNS & DAMAGED
// ============================================

final returnsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(returnServiceProvider).getReturns(limit: 100);
});

final damagedProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(damagedServiceProvider).getDamaged(limit: 100);
});

// ============================================
// PURCHASE ORDERS
// ============================================

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  return ref.watch(purchaseOrderServiceProvider).getPurchaseOrders(limit: 100);
});

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
        final res = await Supabase.instance.client.rpc('get_category_sales');
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
        final res = await Supabase.instance.client.rpc('get_daily_sales_trend');
        if (res is List) {
          var data = res
              .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
              .toList();
          if (dateRange != null) {
            final startUtc = AppTimezone.toUtc(dateRange.start);
            final endUtc = AppTimezone.toUtc(dateRange.end);
            data = data.where((row) {
              final dayStr = row['day'] as String? ?? '';
              final dayDate = DateTime.tryParse(dayStr);
              if (dayDate == null) return true;
              return !dayDate.isBefore(startUtc) && !dayDate.isAfter(endUtc);
            }).toList();
          }
          return data;
        }
        return [];
      } catch (e) {
        return [];
      }
    });

// ============================================
// NAVIGATION
// ============================================

class CurrentTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) => state = index;
}

final currentTabProvider = NotifierProvider<CurrentTabNotifier, int>(
  CurrentTabNotifier.new,
);

// ============================================
// REALTIME SYNC
// Subscribes to DB changes so all devices update
// automatically when another device makes a sale.
// ============================================

final realtimeChannelProvider = Provider<RealtimeChannel?>((ref) {
  final channel = Supabase.instance.client.channel('public:changes');

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        callback: (payload) {
          ref.invalidate(salesHistoryProvider);
          ref.invalidate(recentSalesProvider);
          ref.invalidate(todaySalesProvider);
          ref.invalidate(yesterdaySalesProvider);
          ref.invalidate(todayTransactionsProvider);
          ref.invalidate(monthlyProfitProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'products',
        callback: (payload) {
          ProductService.invalidateCache();
          ref.invalidate(productsProvider);
          ref.invalidate(stockValueProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'purchases',
        callback: (payload) {
          ref.invalidate(purchasesProvider);
          ref.invalidate(productsProvider);
          ref.invalidate(monthlyProfitProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'expenses',
        callback: (payload) {
          ref.invalidate(expensesProvider);
          ref.invalidate(todayExpensesProvider);
          ref.invalidate(todayTransactionsProvider);
          ref.invalidate(monthlyProfitProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'customers',
        callback: (payload) {
          ref.invalidate(customersProvider);
          ref.invalidate(totalCustomerDuesProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'suppliers',
        callback: (payload) {
          ref.invalidate(suppliersProvider);
          ref.invalidate(totalSupplierDuesProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'product_returns',
        callback: (payload) {
          ref.invalidate(returnsProvider);
          ref.invalidate(productsProvider);
        },
      );

  channel.subscribe((status, [error]) {
    Logger.info('Realtime channel status: $status');
    if (error != null) {
      Logger.error('Realtime channel error', error);
    }
  });
  ref.onDispose(() => channel.unsubscribe());

  // Fallback: refresh products every 60s even if Realtime drops
  final timer = Timer.periodic(const Duration(seconds: 60), (_) {
    ProductService.invalidateCache();
    ref.invalidate(productsProvider);
    ref.invalidate(stockValueProvider);
  });
  ref.onDispose(() => timer.cancel());

  return channel;
});

// ============================================
// GLOBAL CART STATE
// Persists across tab switches until sale is completed
// ============================================

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addItem(CartItem item) {
    final existing = state.indexWhere((c) => c.productId == item.productId);
    if (existing >= 0) {
      state[existing].qty += item.qty;
      state = List.from(state);
    } else {
      state = [...state, item];
    }
  }

  void removeItem(int index) {
    state = List.from(state)..removeAt(index);
  }

  void updateQty(int index, int delta) {
    final item = state[index];
    final newQty = item.qty + delta;
    if (newQty <= 0) {
      state = List.from(state)..removeAt(index);
    } else {
      item.qty = newQty;
      state = List.from(state);
    }
  }

  void updateDiscount(int index, double discount) {
    state[index].discount = discount;
    state = List.from(state);
  }

  void updateItemPrice(int index, double newPrice) {
    final item = state[index];
    state[index] = CartItem(
      productId: item.productId,
      name: item.name,
      price: newPrice,
      qty: item.qty,
      unit: item.unit,
      purchasePrice: item.purchasePrice,
      gstRate: item.gstRate,
      hsnCode: item.hsnCode,
      tamilName: item.tamilName,
      discount: item.discount,
      unitType: item.unitType,
      piecesPerUnit: item.piecesPerUnit,
      tier: item.tier,
      rateLabel: item.rateLabel,
    );
    state = List.from(state);
  }

  void clear() {
    state = [];
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

// ============================================
// STOCK SELLING VALUE (what stock would sell for)
// ============================================

final stockSellingValueProvider = FutureProvider<double>((ref) async {
  try {
    final products = await ref.watch(productsProvider.future);
    double sellingValue = 0;
    for (final p in products) {
      if (!p.hasVariants) {
        sellingValue += p.stock * p.sellingPrice;
      } else {
        for (final v in p.variants) {
          if (v.isActive) {
            sellingValue += v.stock * v.price;
          }
        }
      }
    }
    return sellingValue;
  } catch (e) {
    return 0;
  }
});

// ============================================
// ENHANCED DASHBOARD PROVIDERS
// ============================================

final totalCustomerDuesProvider = FutureProvider<double>((ref) async {
  try {
    final customers = await ref.read(customersProvider.future);
    double total = 0;
    for (final c in customers) {
      total += c.totalCredit;
    }
    return total;
  } catch (e) {
    return 0;
  }
});

final totalSupplierDuesProvider = FutureProvider<double>((ref) async {
  try {
    final suppliers = await ref.read(suppliersProvider.future);
    double total = 0;
    for (final s in suppliers) {
      total += s.totalDues;
    }
    return total;
  } catch (e) {
    return 0;
  }
});

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
      start.year, start.month, start.day,
    ).subtract(AppTimezone.localOffset);
    final endUtc = DateTime.utc(
      now.year, now.month, now.day + 1,
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
