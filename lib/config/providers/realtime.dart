import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/connectivity_service.dart';
import '../../services/product_service.dart';
import '../../utils/logger.dart';
import 'products.dart';
import 'sales.dart';
import 'purchases.dart';
import 'expenses.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'accounts.dart';
import 'returns.dart';

// ============================================
// REALTIME SYNC
// Subscribes to DB changes so all devices update
// automatically when another device makes a sale.
// ============================================

final realtimeChannelProvider = Provider<RealtimeChannel?>((ref) {
  final channel = Supabase.instance.client.channel('public:changes');

  // One sale changes the stock of every product on the bill, and each change
  // arrives as its own event. Reloading the whole product list per event
  // meant 20 full downloads for a 20-item bill; wait for the burst to end.
  Timer? productsDebounce;
  void refreshProducts() {
    productsDebounce?.cancel();
    productsDebounce = Timer(const Duration(seconds: 2), () {
      ProductService.invalidateCache();
      ref.invalidate(productsProvider);
      ref.invalidate(dashboardSummaryProvider);
      ref.invalidate(stockValueProvider);
    });
  }
  ref.onDispose(() => productsDebounce?.cancel());

  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'sales',
        callback: (payload) {
          ref.invalidate(salesHistoryProvider);
          ref.invalidate(recentSalesProvider);
          ref.invalidate(dashboardSummaryProvider);
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
        callback: (payload) => refreshProducts(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'purchases',
        callback: (payload) {
          ref.invalidate(purchasesProvider);
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(monthlyProfitProvider);
          refreshProducts();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'expenses',
        callback: (payload) {
          ref.invalidate(expensesProvider);
          ref.invalidate(dashboardSummaryProvider);
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
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(totalCustomerDuesProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'suppliers',
        callback: (payload) {
          ref.invalidate(suppliersProvider);
          ref.invalidate(dashboardSummaryProvider);
          ref.invalidate(totalSupplierDuesProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'product_returns',
        callback: (payload) {
          ref.invalidate(returnsProvider);
          refreshProducts();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'accounts',
        callback: (payload) {
          ref.invalidate(accountsProvider);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'account_transactions',
        callback: (payload) {
          ref.invalidate(todayTransactionsProvider);
          ref.invalidate(monthlySummaryProvider);
        },
      );

  channel.subscribe((status, [error]) {
    Logger.info('Realtime channel status: $status');
    if (error != null) {
      Logger.error('Realtime channel error', error);
    }
  });
  ref.onDispose(() => channel.unsubscribe());

  // Fallback in case Realtime drops: every 2 minutes (it was every 30 s and
  // re-downloaded the whole product list each time), and not while offline.
  final timer = Timer.periodic(const Duration(minutes: 2), (_) {
    if (!ConnectivityService().isConnected) return;
    ProductService.invalidateCache();
    ref.invalidate(productsProvider);
    ref.invalidate(dashboardSummaryProvider);
    ref.invalidate(stockValueProvider);
    ref.invalidate(salesHistoryProvider);
    ref.invalidate(recentSalesProvider);
    ref.invalidate(todaySalesProvider);
    ref.invalidate(monthlyProfitProvider);
  });
  ref.onDispose(() => timer.cancel());

  return channel;
});
