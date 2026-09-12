import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../utils/app_timezone.dart';
import '../admin/profit_details_screen.dart';
import '../admin/all_profitable_products_screen.dart';
import 'dashboard_widgets/greeting_header.dart';

String _inr(double v) {
  final f = NumberFormat('#,##,##0', 'en_IN');
  return '₹${f.format(v.round())}';
}

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
            content: Text('Offline sales synced'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.red),
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshAll();
            if (pendingCount > 0) await _syncOfflineSales();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // ── Header with actions ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GreetingHeader(
                              onRefresh: () async {
                                await _refreshAll();
                                if (pendingCount > 0) await _syncOfflineSales();
                              },
                            ),
                          ),
                          if (pendingCount > 0)
                            GestureDetector(
                              onTap: _syncOfflineSales,
                              child: Container(
                                margin: const EdgeInsets.only(right: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                        width: 12, height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                                      )
                                    else
                                      Icon(Icons.cloud_upload_rounded, size: 14, color: Colors.orange.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$pendingCount',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(Icons.logout_rounded, size: 22, color: theme.colorScheme.error),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Sign Out'),
                                  content: const Text('Are you sure you want to sign out?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // ── Hero Cards ──
                    const _HeroCards(),
                    const SizedBox(height: 12),
                    // ── Quick Stats ──
                    const _QuickStats(),
                    const SizedBox(height: 20),
                    // ── Weekly Chart ──
                    const _WeeklyChart(),
                    const SizedBox(height: 20),
                    // ── Business Summary ──
                    const _BusinessSummary(),
                    const SizedBox(height: 20),
                    // ── Top Profitable Products ──
                    const _TopProfitableProducts(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

// ═══════════════════════════════════════════
// HERO CARDS — Today's Sales + Profit
// ═══════════════════════════════════════════
class _HeroCards extends ConsumerWidget {
  const _HeroCards();

  String _fmt(double v) {
    final f = NumberFormat('#,##,##0', 'en_IN');
    return '₹${f.format(v.round())}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);
    final monthlyProfit = ref.watch(monthlyProfitProvider);

    final sales = todaySales.value ?? 0;
    final yestSales = yesterdaySales.value ?? 0;
    final profit = monthlyProfit.value?['profit'] ?? 0;

    final salesTrend = yestSales > 0 ? ((sales - yestSales) / yestSales * 100).toDouble() : 0.0;

    return Row(
      children: [
        // Today's Sales
        Expanded(
          child: _HeroCard(
            title: "Today's Sales",
            value: _fmt(sales),
            trend: salesTrend,
            gradient: const LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF14B8A6), Color(0xFF2DD4BF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            icon: Icons.trending_up_rounded,
            decorativeIcon: Icons.show_chart_rounded,
          ),
        ),
        const SizedBox(width: 12),
        // Profit
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfitDetailsScreen()),
              );
            },
            child: _HeroCard(
              title: 'Monthly Profit',
              value: _fmt(profit),
              trend: null,
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFA5B4FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: Icons.account_balance_wallet_rounded,
              decorativeIcon: Icons.bar_chart_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String title;
  final String value;
  final double? trend;
  final Gradient gradient;
  final IconData icon;
  final IconData decorativeIcon;

  const _HeroCard({
    required this.title,
    required this.value,
    this.trend,
    required this.gradient,
    required this.icon,
    required this.decorativeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background icon
          Positioned(
            right: -8,
            bottom: -8,
            child: Icon(
              decorativeIcon,
              color: Colors.white.withValues(alpha: 0.08),
              size: 80,
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  if (trend != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: trend! >= 0
                            ? const Color(0xFF10B981).withValues(alpha: 0.9)
                            : const Color(0xFFEF4444).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            trend! >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${trend!.abs().toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// QUICK STATS — Orders, Expenses, Stock Value
// ═══════════════════════════════════════════
class _QuickStats extends ConsumerWidget {
  const _QuickStats();

  String _fmt(double v) {
    final f = NumberFormat('#,##,##0', 'en_IN');
    return '₹${f.format(v.round())}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentSales = ref.watch(recentSalesProvider);
    final expenses = ref.watch(todayExpensesProvider);
    final stockValue = ref.watch(stockValueProvider);

    final orderCount = recentSales.value?.length ?? 0;
    final expenseAmt = expenses.value ?? 0;
    final stockAmt = stockValue.value ?? 0;

    return Row(
      children: [
        _StatCard(
          label: 'Orders',
          value: '$orderCount',
          color: const Color(0xFF3B82F6),
          icon: Icons.receipt_long_rounded,
          bgGradient: [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Expenses',
          value: _fmt(expenseAmt),
          color: const Color(0xFFF59E0B),
          icon: Icons.receipt_rounded,
          bgGradient: [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)],
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Stock Value',
          value: _fmt(stockAmt),
          color: const Color(0xFF8B5CF6),
          icon: Icons.warehouse_rounded,
          bgGradient: [const Color(0xFFF5F3FF), const Color(0xFFEDE9FE)],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final List<Color> bgGradient;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    required this.bgGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// WEEKLY CHART — Mini bar chart
// ═══════════════════════════════════════════
class _WeeklyChart extends ConsumerWidget {
  const _WeeklyChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklyData = ref.watch(weeklySalesProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'This Week',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(currentTabProvider.notifier).setTab(5),
                child: Text(
                  'Details',
                  style: TextStyle(fontSize: 13, color: const Color(0xFF667eea), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: weeklyData.when(
              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (_, __) => const Center(child: Text('Error', style: TextStyle(fontSize: 12))),
              data: (days) {
                if (days.isEmpty) {
                  return Center(
                    child: Text('No data', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  );
                }
                final maxVal = days.map((d) => d['total'] as double).reduce(max);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(days.length, (i) {
                    final day = days[i];
                    final total = day['total'] as double;
                    final label = day['day'] as String;
                    final height = maxVal > 0 ? (total / maxVal * 90) : 0.0;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              total >= 1000 ? '${(total / 1000).toStringAsFixed(0)}K' : total.toStringAsFixed(0),
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: max(height, 4),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// BUSINESS SUMMARY
// ═══════════════════════════════════════════
class _BusinessSummary extends ConsumerWidget {
  const _BusinessSummary();

  String _fmt(double v) {
    final f = NumberFormat('#,##,##0', 'en_IN');
    return '₹${f.format(v.round())}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthlyProfit = ref.watch(monthlyProfitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business Summary',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        monthlyProfit.when(
          loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const SizedBox(),
          data: (data) {
            final sales = data['sales'] ?? 0;
            final purchases = data['purchases'] ?? 0;
            final expenses = data['expenses'] ?? 0;
            final profit = data['profit'] ?? 0;
            final margin = sales > 0 ? (profit / sales * 100) : 0;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                children: [
                  _SummaryRow(label: 'Monthly Sales', value: _fmt(sales), color: const Color(0xFF10B981)),
                  const Divider(height: 20),
                  _SummaryRow(label: 'Purchases', value: _fmt(purchases), color: const Color(0xFF3B82F6)),
                  const Divider(height: 20),
                  _SummaryRow(label: 'Expenses', value: _fmt(expenses), color: const Color(0xFFF59E0B)),
                  const Divider(height: 20),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfitDetailsScreen()),
                      );
                    },
                    child: _SummaryRow(
                      label: 'Net Profit',
                      value: _fmt(profit),
                      color: profit >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      bold: true,
                    ),
                  ),
                  const Divider(height: 20),
                  _SummaryRow(label: 'Margin', value: '${margin.toStringAsFixed(1)}%', color: const Color(0xFF6366F1)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _SummaryRow({required this.label, required this.value, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 18 : 16,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// TOP PROFITABLE PRODUCTS
// ═══════════════════════════════════════════
class _TopProfitableProducts extends ConsumerStatefulWidget {
  const _TopProfitableProducts();

  @override
  ConsumerState<_TopProfitableProducts> createState() => _TopProfitableProductsState();
}

class _TopProfitableProductsState extends ConsumerState<_TopProfitableProducts> {
  List<Map<String, dynamic>> _topProducts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;
      final now = AppTimezone.nowIst();
      final start = DateTime.utc(now.year, now.month, 1).subtract(AppTimezone.localOffset);
      final end = DateTime.utc(now.year, now.month, now.day + 1).subtract(AppTimezone.localOffset);

      // Fetch all sales this month
      final salesRes = await client
          .from('sales')
          .select('items')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      // Fetch products for cost lookup
      final productsRes = await client
          .from('products')
          .select('id, purchase_price');
      final costMap = <String, double>{};
      for (final p in productsRes as List) {
        costMap[p['id'] as String] = (p['purchase_price'] as num?)?.toDouble() ?? 0;
      }

      // Aggregate profit per product from actual sales
      final Map<String, Map<String, dynamic>> productData = {};
      for (final sale in salesRes as List) {
        final items = sale['items'] as List? ?? [];
        for (final item in items) {
          final name = item['name'] as String? ?? 'Unknown';
          final productId = item['product_id'] as String? ?? '';
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
          var costPrice = (item['purchase_price'] as num?)?.toDouble() ?? 0;
          if (costPrice <= 0) costPrice = costMap[productId] ?? 0;

          if (!productData.containsKey(name)) {
            productData[name] = {
              'name': name,
              'qtySold': 0,
              'revenue': 0.0,
              'cost': 0.0,
            };
          }
          productData[name]!['qtySold'] += qty;
          productData[name]!['revenue'] += itemTotal;
          productData[name]!['cost'] += costPrice * qty;
        }
      }

      // Calculate profit and sort
      final results = productData.values.map((d) {
        final revenue = d['revenue'] as double;
        final cost = d['cost'] as double;
        final profit = revenue - cost;
        final margin = revenue > 0 ? (profit / revenue * 100) : 0.0;
        return {
          'name': d['name'],
          'qtySold': d['qtySold'],
          'revenue': revenue,
          'profit': profit,
          'margin': margin,
        };
      }).toList()
        ..sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));

      if (mounted) {
        setState(() {
          _topProducts = results.take(5).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Top Profitable Products',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllProfitableProductsScreen()),
                );
              },
              child: Text(
                'View All',
                style: TextStyle(fontSize: 13, color: const Color(0xFF667eea), fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _loading
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : _topProducts.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text('No sales data this month', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                    ),
                  )
                : _buildList(),
      ],
    );
  }

  Widget _buildList() {
    final maxProfit = _topProducts.first['profit'] as double;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: List.generate(_topProducts.length, (i) {
          final item = _topProducts[i];
          final name = item['name'] as String;
          final qtySold = item['qtySold'] as int;
          final revenue = item['revenue'] as double;
          final profit = item['profit'] as double;
          final margin = item['margin'] as double;
          final ratio = maxProfit > 0 ? profit / maxProfit : 0.0;
          final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (medal.isNotEmpty)
                      Text(medal, style: const TextStyle(fontSize: 16))
                    else
                      Container(
                        width: 24,
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '$qtySold sold',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: margin >= 20
                                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                      : margin >= 10
                                          ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                                          : const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${margin.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: margin >= 20
                                        ? const Color(0xFF10B981)
                                        : margin >= 10
                                            ? const Color(0xFFF59E0B)
                                            : const Color(0xFFEF4444),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _inr(profit),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                        Text(
                          '${_inr(revenue)} rev',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation(
                      i == 0
                          ? const Color(0xFF10B981)
                          : i == 1
                              ? const Color(0xFF3B82F6)
                              : i == 2
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
