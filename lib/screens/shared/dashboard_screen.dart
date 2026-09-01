import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/providers.dart';
import '../../services/offline_service.dart';
import '../../services/sale_service.dart';
import 'dashboard_widgets/greeting_header.dart';
import 'dashboard_widgets/kpi_cards.dart';
import 'dashboard_widgets/quick_actions.dart';
import 'dashboard_widgets/monthly_summary.dart';
import 'dashboard_widgets/top_products_section.dart';
import 'dashboard_widgets/low_stock_section.dart';
import 'dashboard_widgets/data_quality_section.dart';
import 'dashboard_widgets/expiring_products_section.dart';
import 'dashboard_widgets/recent_sales_section.dart';
import 'dashboard_widgets/business_insights_section.dart';
import 'dashboard_widgets/inventory_insights_section.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _syncing = false;

  Future<void> _refreshAll() async {
    ref.invalidate(todaySalesProvider);
    ref.invalidate(yesterdaySalesProvider);
    ref.invalidate(todayExpensesProvider);
    ref.invalidate(monthlyProfitProvider);
    ref.invalidate(stockValueProvider);
    ref.invalidate(lowStockListProvider);
    ref.invalidate(expiringProductsProvider);
    ref.invalidate(recentSalesProvider);
    ref.invalidate(weeklySalesProvider);
    ref.invalidate(topProductsProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(productsProvider);
    ref.invalidate(totalCustomerDuesProvider);
    ref.invalidate(totalSupplierDuesProvider);
    ref.invalidate(todayAvgOrderValueProvider);
    ref.invalidate(todayGstTotalProvider);
    ref.invalidate(weeklySalesSparkProvider);
    ref.invalidate(todayCategorySalesProvider);
    ref.invalidate(salesHistoryProvider);
  }

  Future<void> _syncOfflineSales() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final service = ref.read(saleServiceProvider);
      await service.syncOfflineSales();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline sales synced successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offlineService = ref.watch(offlineServiceProvider);
    final pendingCount = offlineService.pendingCount;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await _refreshAll();
          if (pendingCount > 0) {
            await _syncOfflineSales();
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              elevation: 0,
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Dashboard',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              actions: [
                if (pendingCount > 0)
                  GestureDetector(
                    onTap: _syncOfflineSales,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_syncing)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.orange,
                              ),
                            )
                          else
                            Icon(
                              Icons.cloud_upload_rounded,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            '$pendingCount pending',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  onPressed: () async {
                    await _refreshAll();
                    if (pendingCount > 0) await _syncOfflineSales();
                  },
                  tooltip: 'Refresh all',
                ),
                IconButton(
                  icon: Icon(
                    Icons.logout_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Sign Out'),
                        content: const Text(
                          'Are you sure you want to sign out?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Sign Out',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      ref.invalidate(profileProvider);
                      await ref.read(authServiceProvider).signOut();
                      if (context.mounted) context.go('/login');
                    }
                  },
                  tooltip: 'Sign out',
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  GreetingHeader(
                    onRefresh: () async {
                      await _refreshAll();
                      if (pendingCount > 0) await _syncOfflineSales();
                    },
                  ),
                  const SizedBox(height: 8),
                  const KpiCards(),
                  const SizedBox(height: 24),
                  const QuickActions(),
                  const SizedBox(height: 24),
                  const MonthlySummary(),
                  const SizedBox(height: 24),
                  const TopProductsSection(),
                  const SizedBox(height: 24),
                  const LowStockSection(),
                  const SizedBox(height: 24),
                  const DataQualitySection(),
                  const SizedBox(height: 24),
                  const RecentSalesSection(),
                  const SizedBox(height: 24),
                  const InventoryInsightsSection(),
                  const SizedBox(height: 24),
                  const BusinessInsightsSection(),
                  const SizedBox(height: 24),
                  const ExpiringProductsSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
