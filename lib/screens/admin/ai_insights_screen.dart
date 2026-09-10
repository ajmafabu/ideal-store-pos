import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/providers.dart';
import '../../models/product.dart';
import '../../utils/app_timezone.dart';

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AI Insights',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todaySalesProvider);
          ref.invalidate(yesterdaySalesProvider);
          ref.invalidate(todayExpensesProvider);
          ref.invalidate(monthlyProfitProvider);
          ref.invalidate(stockValueProvider);
          ref.invalidate(lowStockListProvider);
          ref.invalidate(expiringProductsProvider);
          ref.invalidate(topProductsProvider);
          ref.invalidate(productsProvider);
          ref.invalidate(totalCustomerDuesProvider);
          ref.invalidate(totalSupplierDuesProvider);
          ref.invalidate(weeklySalesProvider);
          ref.invalidate(salesHistoryProvider);
          ref.invalidate(customersProvider);
          ref.invalidate(suppliersProvider);
          ref.invalidate(returnsProvider);
          ref.invalidate(damagedProvider);
          ref.invalidate(accountsProvider);
          ref.invalidate(monthlyExpensesProvider);
          ref.invalidate(monthlyGstProvider);
          ref.invalidate(monthlyPurchasesOnlyProvider);
          ref.invalidate(customerInsightsProvider);
          ref.invalidate(productInsightsProvider);
          ref.invalidate(inventoryHealthProvider);
          ref.invalidate(financialSummaryProvider);
          ref.invalidate(salesForecastProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BusinessHealthScore(),
              const SizedBox(height: 16),
              const _SmartAlerts(),
              const SizedBox(height: 16),
              const _SalesIntelligence(),
              const SizedBox(height: 16),
              const _InventoryIntelligence(),
              const SizedBox(height: 16),
              const _FinancialInsights(),
              const SizedBox(height: 16),
              const _CustomerIntelligence(),
              const SizedBox(height: 16),
              const _ProfitabilityDeepDive(),
              const SizedBox(height: 16),
              const _ReturnsDamagedAnalytics(),
              const SizedBox(height: 16),
              const _SupplierPerformance(),
              const SizedBox(height: 16),
              const _CashFlowIntelligence(),
              const SizedBox(height: 16),
              const _TimeSeriesForecast(),
              const SizedBox(height: 16),
              const _GstTaxIntelligence(),
              const SizedBox(height: 16),
              const _ExpenseIntelligence(),
              const SizedBox(height: 16),
              const _ActionRecommendations(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// BUSINESS HEALTH SCORE — Circular gauge
// ═══════════════════════════════════════════
class _BusinessHealthScore extends ConsumerWidget {
  const _BusinessHealthScore();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);
    final monthlyProfit = ref.watch(monthlyProfitProvider);
    final lowStock = ref.watch(lowStockListProvider);
    final products = ref.watch(productsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667eea).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Business Health Score',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          _buildScore(
            context,
            todaySales,
            yesterdaySales,
            monthlyProfit,
            lowStock,
            products,
          ),
          const SizedBox(height: 16),
          _buildMiniStats(todaySales, yesterdaySales, monthlyProfit),
        ],
      ),
    );
  }

  Widget _buildScore(
    BuildContext context,
    AsyncValue<double> todaySales,
    AsyncValue<double> yesterdaySales,
    AsyncValue<Map<String, double>> monthlyProfit,
    AsyncValue<List<Product>> lowStock,
    AsyncValue<List<Product>> products,
  ) {
    double score = 50;
    final sales = todaySales.value ?? 0;
    final yestSales = yesterdaySales.value ?? 0;
    final profit = monthlyProfit.value?['profit'] ?? 0;
    final lowCount = lowStock.value?.length ?? 0;
    final totalProducts = products.value?.length ?? 1;

    if (yestSales > 0) {
      final trend = (sales - yestSales) / yestSales;
      score += (trend * 15).clamp(-15, 15);
    } else if (sales > 0) {
      score += 10;
    }

    if (sales > 0) {
      final margin = profit / max(sales, 1);
      score += (margin * 40).clamp(-20, 20);
    }

    final lowRatio = lowCount / max(totalProducts, 1);
    score -= (lowRatio * 30).clamp(0, 15);

    score = score.clamp(0, 100);

    String label;
    String sublabel;
    Color color;
    if (score >= 80) {
      label = 'Excellent';
      sublabel = 'Your business is performing great!';
      color = const Color(0xFF10B981);
    } else if (score >= 60) {
      label = 'Good';
      sublabel = 'Healthy with room to improve';
      color = const Color(0xFF3B82F6);
    } else if (score >= 40) {
      label = 'Fair';
      sublabel = 'Some areas need attention';
      color = const Color(0xFFF59E0B);
    } else {
      label = 'Needs Work';
      sublabel = 'Action needed to improve';
      color = const Color(0xFFEF4444);
    }

    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${score.round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          sublabel,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildMiniStats(
    AsyncValue<double> todaySales,
    AsyncValue<double> yesterdaySales,
    AsyncValue<Map<String, double>> monthlyProfit,
  ) {
    final sales = todaySales.value ?? 0;
    final yestSales = yesterdaySales.value ?? 0;
    final profit = monthlyProfit.value?['profit'] ?? 0;
    final trend = yestSales > 0 ? ((sales - yestSales) / yestSales * 100) : 0.0;

    return Row(
      children: [
        _MiniStat('Today', '₹${sales.toStringAsFixed(0)}', Colors.white),
        Container(
          width: 1,
          height: 30,
          color: Colors.white.withValues(alpha: 0.2),
        ),
        _MiniStat(
          'Trend',
          '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(0)}%',
          trend >= 0 ? Colors.green.shade300 : Colors.red.shade300,
        ),
        Container(
          width: 1,
          height: 30,
          color: Colors.white.withValues(alpha: 0.2),
        ),
        _MiniStat(
          'Profit',
          '₹${profit.toStringAsFixed(0)}',
          profit >= 0 ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// SMART ALERTS — Priority-based alerts
// ═══════════════════════════════════════════
class _SmartAlerts extends ConsumerWidget {
  const _SmartAlerts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStock = ref.watch(lowStockListProvider);
    final expiring = ref.watch(expiringProductsProvider);
    final products = ref.watch(productsProvider);
    final customerDues = ref.watch(totalCustomerDuesProvider);

    final alerts = <_Alert>[];
    final now = AppTimezone.nowIst();

    final expired =
        expiring.value
            ?.where((p) => p.expiryDate?.isBefore(now) ?? false)
            .toList() ??
        [];
    if (expired.isNotEmpty) {
      alerts.add(
        _Alert(
          'Products Expired',
          '${expired.length} products have expired and should be removed from shelf',
          Icons.event_busy_rounded,
          const Color(0xFFEF4444),
          1,
        ),
      );
    }

    final expiringSoon =
        expiring.value?.where((p) {
          final diff = p.expiryDate?.difference(now).inDays ?? 999;
          return diff >= 0 && diff <= 30;
        }).toList() ??
        [];
    if (expiringSoon.isNotEmpty) {
      alerts.add(
        _Alert(
          'Expiring Within 30 Days',
          '${expiringSoon.length} products expiring soon — consider discounts',
          Icons.schedule_rounded,
          const Color(0xFFF97316),
          1,
        ),
      );
    }

    final critical =
        lowStock.value
            ?.where(
              (p) =>
                  p.stock > 0 &&
                  p.stock <= (p.lowStockAlert ~/ 2).clamp(1, 999),
            )
            .toList() ??
        [];
    if (critical.isNotEmpty) {
      alerts.add(
        _Alert(
          'Critically Low Stock',
          '${critical.length} products may run out today',
          Icons.warning_amber_rounded,
          const Color(0xFFEF4444),
          1,
        ),
      );
    }

    final missingCost =
        products.value?.where((p) => p.purchasePrice <= 0).toList() ?? [];
    if (missingCost.isNotEmpty) {
      alerts.add(
        _Alert(
          'Missing Cost Price',
          '${missingCost.length} products have no cost price — profits may be inaccurate',
          Icons.info_outline_rounded,
          const Color(0xFF8B5CF6),
          1,
        ),
      );
    }

    final dues = customerDues.value ?? 0;
    if (dues > 10000) {
      alerts.add(
        _Alert(
          'High Receivables',
          '₹${dues.toStringAsFixed(0)} pending from customers — follow up recommended',
          Icons.payments_rounded,
          const Color(0xFFF59E0B),
          2,
        ),
      );
    }

    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              size: 20,
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Text(
              'Smart Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${alerts.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...alerts.map((a) => _AlertCard(alert: a)),
      ],
    );
  }
}

class _Alert {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final int priority;
  const _Alert(this.title, this.message, this.icon, this.color, this.priority);
}

class _AlertCard extends StatelessWidget {
  final _Alert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alert.color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: alert.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(alert.icon, color: alert.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.message,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// SALES INTELLIGENCE — Trend analysis
// ═══════════════════════════════════════════
class _SalesIntelligence extends ConsumerWidget {
  const _SalesIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklySales = ref.watch(weeklySalesProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);
    final topProducts = ref.watch(topProductsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insights_rounded,
              size: 20,
              color: Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            Text(
              'Sales Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        weeklySales.when(
          loading: () => const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (days) {
            final totals = days.map((d) => d['total'] as double).toList();
            if (totals.isEmpty || totals.every((t) => t == 0)) {
              return const SizedBox.shrink();
            }

            final avg = totals.isNotEmpty
                ? totals.reduce((a, b) => a + b) / totals.length
                : 0.0;
            final maxDay = totals.reduce(max);
            final today = todaySales.value ?? 0;
            final yesterday = yesterdaySales.value ?? 0;

            final bestDayIdx = totals.indexOf(maxDay);
            final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            final bestDay = bestDayIdx < dayNames.length
                ? dayNames[bestDayIdx]
                : 'N/A';

            final weekendTotal = totals.length >= 7
                ? totals[5] + totals[6]
                : 0.0;
            final weekdayTotal = totals.take(5).fold(0.0, (a, b) => a + b);
            final weekendRatio = weekdayTotal > 0
                ? weekendTotal / weekdayTotal
                : 0;

            return Column(
              children: [
                _InsightCard(
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Weekly Average',
                  value: '₹${avg.toStringAsFixed(0)}/day',
                  subtitle: today > avg
                      ? 'Today is above average'
                      : 'Today is below average',
                ),
                const SizedBox(height: 8),
                _InsightCard(
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Best Day This Week',
                  value: bestDay,
                  subtitle: '₹${maxDay.toStringAsFixed(0)} in sales',
                ),
                const SizedBox(height: 8),
                if (weekendRatio > 1.2)
                  _InsightCard(
                    icon: Icons.weekend_rounded,
                    color: const Color(0xFF8B5CF6),
                    title: 'Weekend Pattern',
                    value:
                        '+${((weekendRatio - 1) * 100).round()}% on weekends',
                    subtitle: 'Consider stocking more for weekend rush',
                  ),
                if (yesterday > 0)
                  _InsightCard(
                    icon: Icons.compare_arrows_rounded,
                    color: today > yesterday
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    title: 'Day-over-Day',
                    value:
                        '${today > yesterday ? '+' : ''}${((today - yesterday) / yesterday * 100).toStringAsFixed(0)}%',
                    subtitle: today > yesterday
                        ? 'Sales improved from yesterday'
                        : 'Sales dropped from yesterday',
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// INVENTORY INTELLIGENCE
// ═══════════════════════════════════════════
class _InventoryIntelligence extends ConsumerWidget {
  const _InventoryIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(inventoryHealthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.inventory_2_rounded,
              size: 20,
              color: Color(0xFF6366F1),
            ),
            const SizedBox(width: 8),
            Text(
              'Inventory Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        health.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (data) {
            if (data.isEmpty) return const SizedBox.shrink();

            final total = (data['total_products'] as num?)?.toInt() ?? 0;
            final healthy = (data['healthy_count'] as num?)?.toInt() ?? 0;
            final lowStock = (data['low_stock_count'] as num?)?.toInt() ?? 0;
            final outOfStock =
                (data['out_of_stock_count'] as num?)?.toInt() ?? 0;
            final slowMoving =
                (data['slow_moving_count'] as num?)?.toInt() ?? 0;
            final deadStock = (data['dead_stock_count'] as num?)?.toInt() ?? 0;
            final stockValue =
                (data['total_stock_value'] as num?)?.toDouble() ?? 0;

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Inventory Health ($total products)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Row(
                          children: [
                            if (healthy > 0)
                              Expanded(
                                flex: healthy,
                                child: Container(
                                  height: 24,
                                  color: const Color(0xFF10B981),
                                ),
                              ),
                            if (lowStock > 0)
                              Expanded(
                                flex: lowStock,
                                child: Container(
                                  height: 24,
                                  color: const Color(0xFFF59E0B),
                                ),
                              ),
                            if (outOfStock > 0)
                              Expanded(
                                flex: outOfStock,
                                child: Container(
                                  height: 24,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _LegendDot(
                            const Color(0xFF10B981),
                            'Healthy ($healthy)',
                          ),
                          const SizedBox(width: 12),
                          _LegendDot(
                            const Color(0xFFF59E0B),
                            'Low ($lowStock)',
                          ),
                          const SizedBox(width: 12),
                          _LegendDot(
                            const Color(0xFFEF4444),
                            'Out ($outOfStock)',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (slowMoving > 0)
                  _InsightCard(
                    icon: Icons.pause_circle_outline_rounded,
                    color: const Color(0xFF8B5CF6),
                    title: 'Slow Moving Stock',
                    value: '$slowMoving products',
                    subtitle: 'No sales in 90+ days',
                  ),
                if (deadStock > 0)
                  _InsightCard(
                    icon: Icons.delete_sweep_rounded,
                    color: const Color(0xFF6B7280),
                    title: 'Dead Stock',
                    value: '$deadStock products',
                    subtitle: 'No sales in 180+ days — consider clearance',
                  ),
                if (outOfStock > 0)
                  _InsightCard(
                    icon: Icons.remove_shopping_cart_rounded,
                    color: const Color(0xFFEF4444),
                    title: 'Out of Stock',
                    value: '$outOfStock products',
                    subtitle: 'Reorder these items to avoid lost sales',
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// FINANCIAL INSIGHTS
// ═══════════════════════════════════════════
class _FinancialInsights extends ConsumerWidget {
  const _FinancialInsights();

  String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financial = ref.watch(financialSummaryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_rounded,
              size: 20,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            Text(
              'Financial Insights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        financial.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (data) {
            if (data.isEmpty) return const SizedBox.shrink();

            final margin = (data['gross_margin_pct'] as num?)?.toDouble() ?? 0;
            final expenseRatio =
                (data['expense_ratio_pct'] as num?)?.toDouble() ?? 0;
            final receivables =
                (data['total_receivables'] as num?)?.toDouble() ?? 0;
            final payables = (data['total_payables'] as num?)?.toDouble() ?? 0;
            final cashRunway =
                (data['cash_runway_days'] as num?)?.toDouble() ?? 999;

            return Column(
              children: [
                _InsightCard(
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'Gross Margin',
                  value: '${margin.toStringAsFixed(1)}%',
                  subtitle: margin > 20
                      ? 'Healthy profit margin'
                      : margin > 10
                      ? 'Average margin'
                      : 'Low margin — review pricing',
                ),
                const SizedBox(height: 8),
                _InsightCard(
                  icon: Icons.speed_rounded,
                  color: const Color(0xFF6366F1),
                  title: 'Expense Ratio',
                  value: '${expenseRatio.toStringAsFixed(1)}%',
                  subtitle: expenseRatio < 15
                      ? 'Expenses well controlled'
                      : 'High expenses — review overhead',
                ),
                if (receivables > 0) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.people_alt_rounded,
                    color: const Color(0xFF3B82F6),
                    title: 'Customer Dues',
                    value: _fmt(receivables),
                    subtitle: 'Follow up with customers to collect payments',
                  ),
                ],
                if (payables > 0) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.local_shipping_rounded,
                    color: const Color(0xFFEF4444),
                    title: 'Supplier Dues',
                    value: _fmt(payables),
                    subtitle: 'Schedule payments to maintain good relations',
                  ),
                ],
                if (cashRunway < 30 && cashRunway < 999) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.timer_off_rounded,
                    color: const Color(0xFFEF4444),
                    title: 'Cash Runway',
                    value: '${cashRunway.toStringAsFixed(0)} days',
                    subtitle:
                        'Cash may run out within a month at current burn rate',
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// CUSTOMER INTELLIGENCE
// ═══════════════════════════════════════════
class _CustomerIntelligence extends ConsumerWidget {
  const _CustomerIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(customerInsightsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.people_rounded,
              size: 20,
              color: Color(0xFFEC4899),
            ),
            const SizedBox(width: 8),
            Text(
              'Customer Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        insights.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (data) {
            if (data.isEmpty) return const SizedBox.shrink();

            final top5 = data.take(5).toList();
            final atRisk = data
                .where(
                  (c) =>
                      c['churn_risk'] == 'high' || c['churn_risk'] == 'medium',
                )
                .toList();
            final totalCustomers = data.length;
            final totalDues = data.fold(
              0.0,
              (sum, c) =>
                  sum + ((c['total_purchases'] as num?)?.toDouble() ?? 0),
            );

            return Column(
              children: [
                if (top5.isNotEmpty)
                  _InsightCard(
                    icon: Icons.star_rounded,
                    color: const Color(0xFFEC4899),
                    title: 'Top 5 Customers',
                    value:
                        '₹${(top5.first['total_purchases'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    subtitle:
                        '${top5.first['customer_name'] ?? ''} leads with ${top5.first['total_orders'] ?? 0} orders',
                  ),
                const SizedBox(height: 8),
                if (atRisk.isNotEmpty)
                  _InsightCard(
                    icon: Icons.person_off_rounded,
                    color: const Color(0xFFF97316),
                    title: 'At-Risk Customers',
                    value: '${atRisk.length} customers',
                    subtitle:
                        'Haven\'t purchased in 30+ days — send promotions',
                  ),
                const SizedBox(height: 8),
                _InsightCard(
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'Customer Segments',
                  value: '$totalCustomers total',
                  subtitle:
                      'Platinum: ${data.where((c) => c['segment'] == 'platinum').length} | Gold: ${data.where((c) => c['segment'] == 'gold').length} | Silver: ${data.where((c) => c['segment'] == 'silver').length}',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// PROFITABILITY DEEP DIVE
// ═══════════════════════════════════════════
class _ProfitabilityDeepDive extends ConsumerWidget {
  const _ProfitabilityDeepDive();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final salesHistory = ref.watch(salesHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.analytics_rounded,
              size: 20,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            Text(
              'Profitability Deep Dive',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        products.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (allProducts) {
            return salesHistory.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (sales) {
                if (allProducts.isEmpty || sales.isEmpty)
                  return const SizedBox.shrink();

                // Category margin analysis
                final categoryRevenue = <String, double>{};
                final categoryProfit = <String, double>{};
                final categoryCount = <String, int>{};
                for (final sale in sales) {
                  for (final item in sale.items) {
                    final cat =
                        allProducts
                            .where((p) => p.id == item.productId)
                            .map((p) => p.category ?? 'Other')
                            .firstOrNull ??
                        'Other';
                    final revenue = item.price * item.qty;
                    final profit = (item.price - item.purchasePrice) * item.qty;
                    categoryRevenue[cat] =
                        (categoryRevenue[cat] ?? 0) + revenue;
                    categoryProfit[cat] = (categoryProfit[cat] ?? 0) + profit;
                    categoryCount[cat] = (categoryCount[cat] ?? 0) + 1;
                  }
                }

                final sortedCats = categoryProfit.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final topCategory = sortedCats.isNotEmpty
                    ? sortedCats.first
                    : null;

                // Loss-making products
                final lossMaking = allProducts
                    .where(
                      (p) =>
                          p.sellingPrice > 0 &&
                          p.purchasePrice > 0 &&
                          p.purchasePrice >= p.sellingPrice,
                    )
                    .length;

                // Margin distribution
                final marginBuckets = {
                  '0-5%': 0,
                  '5-10%': 0,
                  '10-20%': 0,
                  '20%+': 0,
                };
                for (final p in allProducts) {
                  if (p.sellingPrice <= 0 || p.purchasePrice <= 0) continue;
                  final margin =
                      (p.sellingPrice - p.purchasePrice) / p.sellingPrice * 100;
                  if (margin < 5)
                    marginBuckets['0-5%'] = marginBuckets['0-5%']! + 1;
                  else if (margin < 10)
                    marginBuckets['5-10%'] = marginBuckets['5-10%']! + 1;
                  else if (margin < 20)
                    marginBuckets['10-20%'] = marginBuckets['10-20%']! + 1;
                  else
                    marginBuckets['20%+'] = marginBuckets['20%+']! + 1;
                }

                return Column(
                  children: [
                    if (topCategory != null)
                      _InsightCard(
                        icon: Icons.category_rounded,
                        color: const Color(0xFF10B981),
                        title: 'Most Profitable Category',
                        value: topCategory.key,
                        subtitle:
                            '₹${topCategory.value.toStringAsFixed(0)} profit from ${categoryCount[topCategory.key] ?? 0} sales',
                      ),
                    const SizedBox(height: 8),
                    if (lossMaking > 0)
                      _InsightCard(
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFEF4444),
                        title: 'Loss-Making Products',
                        value: '$lossMaking products',
                        subtitle:
                            'Selling below cost — review pricing immediately',
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Margin Distribution',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...marginBuckets.entries.map((e) {
                            final total = marginBuckets.values.fold(
                              0,
                              (a, b) => a + b,
                            );
                            final pct = total > 0 ? e.value / total : 0.0;
                            final color = e.key == '0-5%'
                                ? const Color(0xFFEF4444)
                                : e.key == '5-10%'
                                ? const Color(0xFFF59E0B)
                                : e.key == '10-20%'
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF10B981);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      e.key,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct,
                                        backgroundColor: Colors.grey.shade100,
                                        valueColor: AlwaysStoppedAnimation(
                                          color,
                                        ),
                                        minHeight: 8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${e.value}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// RETURNS & DAMAGED ANALYTICS
// ═══════════════════════════════════════════
class _ReturnsDamagedAnalytics extends ConsumerWidget {
  const _ReturnsDamagedAnalytics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returns = ref.watch(returnsProvider);
    final damaged = ref.watch(damagedProvider);
    final salesHistory = ref.watch(salesHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.assignment_return_rounded,
              size: 20,
              color: Color(0xFFF97316),
            ),
            const SizedBox(width: 8),
            Text(
              'Returns & Damaged',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        returns.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (returnList) {
            return damaged.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (damagedList) {
                if (returnList.isEmpty && damagedList.isEmpty)
                  return const SizedBox.shrink();

                // Return stats
                double totalReturnRefund = 0;
                int totalReturnQty = 0;
                final returnProducts = <String, int>{};
                for (final r in returnList) {
                  totalReturnRefund +=
                      (r['refund_amount'] as num?)?.toDouble() ?? 0;
                  totalReturnQty += (r['quantity'] as num?)?.toInt() ?? 0;
                  final name = r['product_name'] as String? ?? 'Unknown';
                  returnProducts[name] =
                      (returnProducts[name] ?? 0) +
                      ((r['quantity'] as num?)?.toInt() ?? 0);
                }

                // Damaged stats
                double totalDamagedValue = 0;
                int totalDamagedQty = 0;
                final damagedProducts = <String, int>{};
                for (final d in damagedList) {
                  final qty = (d['quantity'] as num?)?.toInt() ?? 0;
                  final price = (d['unit_price'] as num?)?.toDouble() ?? 0;
                  totalDamagedValue += qty * price;
                  totalDamagedQty += qty;
                  final name = d['product_name'] as String? ?? 'Unknown';
                  damagedProducts[name] = (damagedProducts[name] ?? 0) + qty;
                }

                // Return rate
                final totalSold =
                    salesHistory.value?.fold(
                      0,
                      (sum, s) =>
                          sum + s.items.fold(0, (isum, i) => isum + i.qty),
                    ) ??
                    0;
                final returnRate = totalSold > 0
                    ? (totalReturnQty / totalSold * 100)
                    : 0.0;

                final topReturns = returnProducts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final topDamaged = damagedProducts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                return Column(
                  children: [
                    _InsightCard(
                      icon: Icons.replay_rounded,
                      color: returnRate > 5
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF3B82F6),
                      title: 'Return Rate',
                      value: '${returnRate.toStringAsFixed(1)}%',
                      subtitle: returnRate > 5
                          ? 'High — investigate quality issues'
                          : 'Within normal range',
                    ),
                    const SizedBox(height: 8),
                    if (topReturns.isNotEmpty)
                      _InsightCard(
                        icon: Icons.undo_rounded,
                        color: const Color(0xFFF97316),
                        title: 'Top Returned Product',
                        value: topReturns.first.key,
                        subtitle:
                            '${topReturns.first.value} units returned — ₹${totalReturnRefund.toStringAsFixed(0)} refunded',
                      ),
                    const SizedBox(height: 8),
                    if (totalDamagedQty > 0)
                      _InsightCard(
                        icon: Icons.broken_image_rounded,
                        color: const Color(0xFFEF4444),
                        title: 'Damaged Goods',
                        value: '$totalDamagedQty units',
                        subtitle:
                            '₹${totalDamagedValue.toStringAsFixed(0)} value lost to damage',
                      ),
                    if (topDamaged.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InsightCard(
                        icon: Icons.priority_high_rounded,
                        color: const Color(0xFF8B5CF6),
                        title: 'Most Damaged Product',
                        value: topDamaged.first.key,
                        subtitle:
                            '${topDamaged.first.value} units damaged — review handling',
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// SUPPLIER PERFORMANCE
// ═══════════════════════════════════════════
class _SupplierPerformance extends ConsumerWidget {
  const _SupplierPerformance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    final purchases = ref.watch(purchasesProvider);
    final purchaseOrders = ref.watch(purchaseOrdersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.local_shipping_rounded,
              size: 20,
              color: const Color(0xFF6366F1),
            ),
            const SizedBox(width: 8),
            Text(
              'Supplier Performance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        suppliers.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (allSuppliers) {
            if (allSuppliers.isEmpty) return const SizedBox.shrink();

            return purchases.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (allPurchases) {
                // Top suppliers by spend
                final supplierSpend = <String, double>{};
                for (final p in allPurchases) {
                  final name = p.supplierName ?? 'Unknown';
                  supplierSpend[name] =
                      (supplierSpend[name] ?? 0) + p.totalAmount;
                }
                final sorted = supplierSpend.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final topSupplier = sorted.isNotEmpty ? sorted.first : null;

                // Pending POs
                final pendingPOs =
                    purchaseOrders.value
                        ?.where(
                          (po) =>
                              po.status != 'completed' &&
                              po.status != 'cancelled',
                        )
                        .toList() ??
                    [];
                final pendingPOValue = pendingPOs.fold(
                  0.0,
                  (sum, po) => sum + po.totalAmount,
                );

                // Supplier concentration risk
                final totalSpend = supplierSpend.values.fold(
                  0.0,
                  (a, b) => a + b,
                );
                final topSupplierConcentration =
                    topSupplier != null && totalSpend > 0
                    ? (topSupplier.value / totalSpend * 100)
                    : 0.0;

                return Column(
                  children: [
                    if (topSupplier != null)
                      _InsightCard(
                        icon: Icons.store_rounded,
                        color: const Color(0xFF6366F1),
                        title: 'Top Supplier by Spend',
                        value: topSupplier.key,
                        subtitle:
                            '₹${topSupplier.value.toStringAsFixed(0)} total purchases',
                      ),
                    if (topSupplierConcentration > 50) ...[
                      const SizedBox(height: 8),
                      _InsightCard(
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFF59E0B),
                        title: 'Supplier Concentration Risk',
                        value:
                            '${topSupplierConcentration.toStringAsFixed(0)}%',
                        subtitle:
                            'Over half your purchases from one supplier — diversify',
                      ),
                    ],
                    if (pendingPOs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InsightCard(
                        icon: Icons.reorder_rounded,
                        color: const Color(0xFF3B82F6),
                        title: 'Pending Purchase Orders',
                        value: '${pendingPOs.length} orders',
                        subtitle:
                            '₹${pendingPOValue.toStringAsFixed(0)} total value pending',
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// CASH FLOW INTELLIGENCE
// ═══════════════════════════════════════════
class _CashFlowIntelligence extends ConsumerWidget {
  const _CashFlowIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financial = ref.watch(financialSummaryProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final todayExpenses = ref.watch(todayExpensesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 20,
              color: Color(0xFF14B8A6),
            ),
            const SizedBox(width: 8),
            Text(
              'Cash Flow Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        financial.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (data) {
            final cashPos = (data['cash_position'] as num?)?.toDouble() ?? 0;
            final bankPos = (data['bank_position'] as num?)?.toDouble() ?? 0;
            final totalCash = cashPos + bankPos;
            final cashRunway =
                (data['cash_runway_days'] as num?)?.toDouble() ?? 999;

            final sales = todaySales.value ?? 0;
            final expenses = todayExpenses.value ?? 0;
            final netFlow = sales - expenses;

            return Column(
              children: [
                _InsightCard(
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFF14B8A6),
                  title: 'Cash Position',
                  value: '₹${totalCash.toStringAsFixed(0)}',
                  subtitle:
                      'Cash: ₹${cashPos.toStringAsFixed(0)} | Bank: ₹${bankPos.toStringAsFixed(0)}',
                ),
                const SizedBox(height: 8),
                _InsightCard(
                  icon: Icons.swap_horiz_rounded,
                  color: netFlow >= 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                  title: "Today's Net Cash Flow",
                  value:
                      '${netFlow >= 0 ? '+' : ''}₹${netFlow.toStringAsFixed(0)}',
                  subtitle:
                      'In: ₹${sales.toStringAsFixed(0)} | Out: ₹${expenses.toStringAsFixed(0)}',
                ),
                if (cashRunway < 30 && cashRunway < 999) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.timer_off_rounded,
                    color: const Color(0xFFEF4444),
                    title: 'Cash Health Warning',
                    value: '${cashRunway.toStringAsFixed(0)} days runway',
                    subtitle:
                        'Cash may run out within a month at current burn rate',
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// TIME-SERIES FORECAST
// ═══════════════════════════════════════════
class _TimeSeriesForecast extends ConsumerWidget {
  const _TimeSeriesForecast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(salesForecastProvider);
    final inventoryHealth = ref.watch(inventoryHealthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_graph_rounded,
              size: 20,
              color: Color(0xFF8B5CF6),
            ),
            const SizedBox(width: 8),
            Text(
              'Time-Series Forecast',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        forecast.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (data) {
            if (data.isEmpty) return const SizedBox.shrink();

            final projected =
                (data['projected_monthly_sales'] as num?)?.toDouble() ?? 0;
            final dailyAvg = (data['daily_average'] as num?)?.toDouble() ?? 0;
            final trend = (data['trend_direction'] as String?) ?? 'stable';
            final confidence =
                (data['forecast_confidence'] as String?) ?? 'low';
            final daysElapsed = (data['days_elapsed'] as num?)?.toInt() ?? 0;
            final momPct =
                (data['month_over_month_pct'] as num?)?.toDouble() ?? 0;

            return Column(
              children: [
                _InsightCard(
                  icon: Icons.show_chart_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'Projected Monthly Revenue',
                  value: '₹${projected.toStringAsFixed(0)}',
                  subtitle:
                      '₹${dailyAvg.toStringAsFixed(0)}/day avg | $daysElapsed days data | $confidence confidence',
                ),
                const SizedBox(height: 8),
                _InsightCard(
                  icon: Icons.trending_up_rounded,
                  color: trend == 'growing'
                      ? const Color(0xFF10B981)
                      : trend == 'declining'
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF3B82F6),
                  title: 'Sales Trend',
                  value: '${trend[0].toUpperCase()}${trend.substring(1)}',
                  subtitle: momPct > 0
                      ? '+${momPct.toStringAsFixed(1)}% vs last month'
                      : '${momPct.toStringAsFixed(1)}% vs last month',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        inventoryHealth.when(
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
          data: (data) {
            if (data.isEmpty) return const SizedBox.shrink();
            final reorderItems = (data['top_reorder_items'] as List?) ?? [];
            if (reorderItems.isEmpty) return const SizedBox.shrink();

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.timer_rounded,
                        color: Color(0xFFEF4444),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Needs Reorder',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...reorderItems
                      .take(5)
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item['name'] ?? ''}',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${item['stock'] ?? 0} left (need ${item['alert'] ?? 0})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFEF4444),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// GST & TAX INTELLIGENCE
// ═══════════════════════════════════════════
class _GstTaxIntelligence extends ConsumerWidget {
  const _GstTaxIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthlyGst = ref.watch(monthlyGstProvider);
    final products = ref.watch(productsProvider);
    final salesHistory = ref.watch(salesHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.receipt_rounded,
              size: 20,
              color: const Color(0xFF0EA5E9),
            ),
            const SizedBox(width: 8),
            Text(
              'GST & Tax Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        monthlyGst.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (gst) {
            return products.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (allProducts) {
                return salesHistory.when(
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                  data: (sales) {
                    // Tax exempt sales
                    int totalSalesCount = sales.length;
                    int taxExemptCount = sales.where((s) => s.taxExempt).length;
                    final exemptRatio = totalSalesCount > 0
                        ? (taxExemptCount / totalSalesCount * 100)
                        : 0.0;

                    // HSN distribution
                    final hsnMap = <String, double>{};
                    for (final sale in sales) {
                      for (final item in sale.items) {
                        final hsn = item.hsnCode ?? 'N/A';
                        hsnMap[hsn] =
                            (hsnMap[hsn] ?? 0) + (item.price * item.qty);
                      }
                    }
                    final sortedHSN = hsnMap.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value));
                    final topHSN = sortedHSN.take(3).toList();

                    // Products with GST
                    final withGst = allProducts
                        .where((p) => p.gstRate > 0)
                        .length;
                    final withoutGst = allProducts
                        .where((p) => p.gstRate <= 0)
                        .length;

                    return Column(
                      children: [
                        _InsightCard(
                          icon: Icons.savings_rounded,
                          color: const Color(0xFF0EA5E9),
                          title: 'Monthly GST Liability',
                          value: '₹${gst.toStringAsFixed(0)}',
                          subtitle: 'GST collected this month to be remitted',
                        ),
                        const SizedBox(height: 8),
                        _InsightCard(
                          icon: Icons.gavel_rounded,
                          color: exemptRatio > 10
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981),
                          title: 'Tax-Exempt Sales',
                          value: '${exemptRatio.toStringAsFixed(1)}%',
                          subtitle:
                              '$taxExemptCount of $totalSalesCount sales are tax-exempt',
                        ),
                        if (topHSN.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Top HSN Codes by Revenue',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...topHSN.map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF0EA5E9,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            e.key,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0EA5E9),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '₹${e.value.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// EXPENSE INTELLIGENCE
// ═══════════════════════════════════════════
class _ExpenseIntelligence extends ConsumerWidget {
  const _ExpenseIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    final monthlyExpenses = ref.watch(monthlyExpensesProvider);
    final monthlyProfit = ref.watch(monthlyProfitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.money_off_rounded,
              size: 20,
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(width: 8),
            Text(
              'Expense Intelligence',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        monthlyExpenses.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => const SizedBox(),
          data: (mExpenses) {
            return monthlyProfit.when(
              loading: () => const SizedBox(),
              error: (_, __) => const SizedBox(),
              data: (profitData) {
                final sales = profitData['sales'] ?? 0;
                final expenseRatio = sales > 0
                    ? (mExpenses / sales * 100)
                    : 0.0;

                return Column(
                  children: [
                    _InsightCard(
                      icon: Icons.pie_chart_rounded,
                      color: expenseRatio > 15
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      title: 'Expense-to-Sales Ratio',
                      value: '${expenseRatio.toStringAsFixed(1)}%',
                      subtitle: expenseRatio > 15
                          ? 'High — expenses consuming too much revenue'
                          : 'Healthy expense level',
                    ),
                    const SizedBox(height: 8),
                    expenses.when(
                      loading: () => const SizedBox(),
                      error: (_, __) => const SizedBox(),
                      data: (expList) {
                        if (expList.isEmpty) return const SizedBox.shrink();

                        // Category breakdown
                        final categories = <String, double>{};
                        for (final e in expList) {
                          categories[e.category] =
                              (categories[e.category] ?? 0) + e.amount;
                        }
                        final sorted = categories.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        final top3 = sorted.take(3).toList();
                        final totalExp = sorted.fold(
                          0.0,
                          (sum, e) => sum + e.value,
                        );

                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Top Expense Categories',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...top3.map((e) {
                                    final pct = totalExp > 0
                                        ? (e.value / totalExp * 100)
                                        : 0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              e.key,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '₹${e.value.toStringAsFixed(0)}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${pct.toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// ACTION RECOMMENDATIONS
// ═══════════════════════════════════════════
class _ActionRecommendations extends ConsumerWidget {
  const _ActionRecommendations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStock = ref.watch(lowStockListProvider);
    final expiring = ref.watch(expiringProductsProvider);
    final products = ref.watch(productsProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final topProducts = ref.watch(topProductsProvider);

    final actions = <_Action>[];
    final now = AppTimezone.nowIst();

    final topSelling = topProducts.value;
    if (topSelling != null && topSelling.isNotEmpty) {
      final top = topSelling.first;
      final name = top['name'] ?? 'Top product';
      final count = top['total'] ?? 0;
      actions.add(
        _Action(
          'Reorder Best Seller',
          '"$name" is your top seller ($count sold). Ensure it never runs out.',
          Icons.shopping_cart_checkout_rounded,
          const Color(0xFF10B981),
        ),
      );
    }

    final expiringSoon =
        expiring.value?.where((p) {
          final diff = p.expiryDate?.difference(now).inDays ?? 999;
          return diff >= 0 && diff <= 14;
        }).toList() ??
        [];
    if (expiringSoon.isNotEmpty) {
      actions.add(
        _Action(
          'Run Expiry Discount',
          '${expiringSoon.length} products expire within 14 days. Offer 20-30% off to recover cost.',
          Icons.local_offer_rounded,
          const Color(0xFFF97316),
        ),
      );
    }

    final productsList = products.value ?? [];
    final lowMargin = productsList
        .where(
          (p) =>
              p.sellingPrice > 0 &&
              p.purchasePrice > 0 &&
              ((p.sellingPrice - p.purchasePrice) / p.sellingPrice) < 0.1,
        )
        .length;
    if (lowMargin > 0) {
      actions.add(
        _Action(
          'Review Pricing',
          '$lowMargin products have less than 10% margin. Consider price adjustments.',
          Icons.price_change_rounded,
          const Color(0xFF8B5CF6),
        ),
      );
    }

    final criticalStock =
        lowStock.value?.where((p) => p.stock > 0 && p.stock <= 5).toList() ??
        [];
    if (criticalStock.isNotEmpty) {
      actions.add(
        _Action(
          'Emergency Restock',
          '${criticalStock.length} products have 5 or fewer units left.',
          Icons.build_rounded,
          const Color(0xFFEF4444),
        ),
      );
    }

    final sales = todaySales.value ?? 0;
    if (sales == 0 && now.hour > 10) {
      actions.add(
        _Action(
          'Boost Today\'s Sales',
          'No sales recorded yet. Consider running a flash deal or promotion.',
          Icons.campaign_rounded,
          const Color(0xFF3B82F6),
        ),
      );
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: Color(0xFF667eea),
            ),
            const SizedBox(width: 8),
            Text(
              'Recommended Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...actions.map(
          (a) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: a.color.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: a.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(a.icon, color: a.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        a.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Action {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  const _Action(this.title, this.message, this.icon, this.color);
}

// ═══════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════
class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;

  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
