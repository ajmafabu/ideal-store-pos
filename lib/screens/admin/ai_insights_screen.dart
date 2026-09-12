import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/providers.dart';
import '../../models/product_return.dart';
import '../../models/damaged_product.dart';
import '../../utils/app_timezone.dart';
import 'all_low_stock_screen.dart';
import 'customer_screen.dart';
import 'returns_screen.dart';
import 'damaged_screen.dart';
import 'supplier_screen.dart';
import 'expense_screen.dart';
import 'purchase_order_screen.dart';
import 'gst_filing_screen.dart';
import 'all_top_products_screen.dart';

class AiInsightsScreen extends ConsumerStatefulWidget {
  const AiInsightsScreen({super.key});

  @override
  ConsumerState<AiInsightsScreen> createState() => _AiInsightsScreenState();
}

class _AiInsightsScreenState extends ConsumerState<AiInsightsScreen> {
  int _selectedRange = 30;
  DateTimeRange? _customRange;

  DateTimeRange get _dateRange {
    final now = DateTime.now();
    if (_customRange != null) return _customRange!;
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _selectedRange));
    return DateTimeRange(start: start, end: now);
  }

  void _showCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selectedRange = -1;
      });
    }
  }

  void _selectRange(int days) {
    setState(() {
      _selectedRange = days;
      _customRange = null;
    });
  }

  void _exportPdf() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PDF export coming soon')));
  }

  void _exportCsv() async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('CSV export coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
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
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('AI Insights',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'pdf') _exportPdf();
              else if (v == 'csv') _exportCsv();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'pdf',
                child: Row(children: [
                  Icon(Icons.picture_as_pdf, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Export PDF'),
                ]),
              ),
              const PopupMenuItem(
                value: 'csv',
                child: Row(children: [
                  Icon(Icons.table_chart, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Export CSV'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(salesHistoryProvider);
          ref.invalidate(categorySalesProvider);
          ref.invalidate(dailySalesTrendProvider);
          ref.invalidate(topProductsProvider);
          ref.invalidate(todaySalesProvider);
          ref.invalidate(yesterdaySalesProvider);
          ref.invalidate(monthlyProfitProvider);
          ref.invalidate(lowStockListProvider);
          ref.invalidate(productsProvider);
          ref.invalidate(customersProvider);
          ref.invalidate(returnsProvider);
          ref.invalidate(damagedProvider);
          ref.invalidate(suppliersProvider);
          ref.invalidate(purchasesProvider);
          ref.invalidate(purchaseOrdersProvider);
          ref.invalidate(expensesProvider);
          ref.invalidate(financialSummaryProvider);
          ref.invalidate(salesForecastProvider);
          ref.invalidate(inventoryHealthProvider);
          ref.invalidate(productInsightsProvider);
          ref.invalidate(customerInsightsProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DateRangeFilter(
                selectedRange: _selectedRange,
                onSelect: _selectRange,
                onCustom: _showCustomDateRange,
              ),
              const SizedBox(height: 16),
              _SalesChart(dateRange: _dateRange),
              const SizedBox(height: 16),
              _CategoryPieChart(dateRange: _dateRange),
              const SizedBox(height: 16),
              _TopProductsChart(dateRange: _dateRange),
              const SizedBox(height: 16),
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
// SHARED WIDGETS
// ═══════════════════════════════════════════
Widget _sectionHeader(String title, IconData icon, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800)),
      ]),
      const SizedBox(height: 12),
    ],
  );
}

Widget _sectionLoading(String title, IconData icon, Color color) {
  return const SizedBox.shrink();
}

Widget _empty() => const SizedBox.shrink();

// ═══════════════════════════════════════════
// BUSINESS HEALTH SCORE
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

    double score = 50;
    final sales = todaySales.value ?? 0;
    final yestSales = yesterdaySales.value ?? 0;
    final profit = monthlyProfit.value?['profit'] ?? 0;
    final lowCount = lowStock.value?.length ?? 0;
    final totalProducts = products.value?.length ?? 1;

    if (yestSales > 0) {
      score += ((sales - yestSales) / yestSales * 15).clamp(-15.0, 15.0);
    } else if (sales > 0) {
      score += 10;
    }
    if (sales > 0) {
      score += (profit / max(sales, 1) * 40).clamp(-20.0, 20.0);
    }
    score -= (lowCount / max(totalProducts, 1) * 30).clamp(0.0, 15.0);
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

    final trend = yestSales > 0 ? ((sales - yestSales) / yestSales * 100) : 0.0;

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
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          const Text('Business Health Score',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
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
                    Text('${score.round()}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            height: 1)),
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(sublabel,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            children: [
              _MiniStat('Today', '₹${sales.toStringAsFixed(0)}', Colors.white),
              Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.2)),
              _MiniStat(
                  'Trend',
                  '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(0)}%',
                  trend >= 0 ? Colors.green.shade300 : Colors.red.shade300),
              Container(
                  width: 1,
                  height: 30,
                  color: Colors.white.withValues(alpha: 0.2)),
              _MiniStat(
                  'Profit',
                  '₹${profit.toStringAsFixed(0)}',
                  profit >= 0 ? Colors.green.shade300 : Colors.red.shade300),
            ],
          ),
        ],
      ),
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
      child: Column(children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════
// SMART ALERTS
// ═══════════════════════════════════════════
class _Alert {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _Alert(this.title, this.message, this.icon, this.color, [this.onTap]);
}

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

    final expired = expiring.value?.where((p) => p.expiryDate?.isBefore(now) ?? false).toList() ?? [];
    if (expired.isNotEmpty) {
      alerts.add(_Alert('Products Expired', '${expired.length} products have expired and should be removed from shelf', Icons.event_busy_rounded, const Color(0xFFEF4444), () => Navigator.pushNamed(context, '/admin', arguments: 1)));
    }
    final expiringSoon = expiring.value?.where((p) {
      final diff = p.expiryDate?.difference(now).inDays ?? 999;
      return diff >= 0 && diff <= 30;
    }).toList() ?? [];
    if (expiringSoon.isNotEmpty) {
      alerts.add(_Alert('Expiring Within 30 Days', '${expiringSoon.length} products expiring soon — consider discounts', Icons.schedule_rounded, const Color(0xFFF97316), () => Navigator.pushNamed(context, '/admin', arguments: 1)));
    }
    final critical = lowStock.value?.where((p) => p.stock > 0 && p.stock <= (p.lowStockAlert ~/ 2).clamp(1, 999)).toList() ?? [];
    if (critical.isNotEmpty) {
      alerts.add(_Alert('Critically Low Stock', '${critical.length} products may run out today', Icons.warning_amber_rounded, const Color(0xFFEF4444), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllLowStockScreen()))));
    }
    final missingCost = products.value?.where((p) => p.purchasePrice <= 0).toList() ?? [];
    if (missingCost.isNotEmpty) {
      alerts.add(_Alert('Missing Cost Price', '${missingCost.length} products have no cost price — profits may be inaccurate', Icons.info_outline_rounded, const Color(0xFF8B5CF6), () => Navigator.pushNamed(context, '/admin', arguments: 1)));
    }
    final dues = customerDues.value ?? 0;
    if (dues > 10000) {
      alerts.add(_Alert('High Receivables', '₹${dues.toStringAsFixed(0)} pending from customers — follow up recommended', Icons.payments_rounded, const Color(0xFFF59E0B), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerScreen()))));
    }

    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.notifications_active_rounded, size: 20, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Text('Smart Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text('${alerts.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
          ),
        ]),
        const SizedBox(height: 12),
        ...alerts.map((a) => GestureDetector(
              onTap: a.onTap,
              child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: a.color.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: a.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(a.icon, color: a.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(a.message,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
              ]),
            ),
        )),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// SALES INTELLIGENCE
// ═══════════════════════════════════════════
class _SalesIntelligence extends ConsumerWidget {
  const _SalesIntelligence();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeklySales = ref.watch(weeklySalesProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);

    return weeklySales.when(
      loading: () => _sectionLoading('Sales Intelligence', Icons.insights_rounded, const Color(0xFF3B82F6)),
      error: (_, __) => _empty(),
      data: (days) {
        final totals = days.map((d) => d['total'] as double).toList();
        if (totals.isEmpty || totals.every((t) => t == 0)) return _empty();

        final avg = totals.reduce((a, b) => a + b) / totals.length;
        final maxDay = totals.reduce(max);
        final today = todaySales.value ?? 0;
        final yesterday = yesterdaySales.value ?? 0;
        final bestDayIdx = totals.indexOf(maxDay);
        final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final bestDay = bestDayIdx < dayNames.length ? dayNames[bestDayIdx] : 'N/A';
        final weekendTotal = totals.length >= 7 ? totals[5] + totals[6] : 0.0;
        final weekdayTotal = totals.take(5).fold(0.0, (a, b) => a + b);
        final weekendRatio = weekdayTotal > 0 ? weekendTotal / weekdayTotal : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Sales Intelligence', Icons.insights_rounded, const Color(0xFF3B82F6)),
            _InsightCard(icon: Icons.trending_up_rounded, color: const Color(0xFF10B981), title: 'Weekly Average', value: '₹${avg.toStringAsFixed(0)}/day', subtitle: today > avg ? 'Today is above average' : 'Today is below average'),
            const SizedBox(height: 8),
            _InsightCard(icon: Icons.emoji_events_rounded, color: const Color(0xFFF59E0B), title: 'Best Day This Week', value: bestDay, subtitle: '₹${maxDay.toStringAsFixed(0)} in sales'),
            if (weekendRatio > 1.2) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.weekend_rounded, color: const Color(0xFF8B5CF6), title: 'Weekend Pattern', value: '+${((weekendRatio - 1) * 100).round()}% on weekends', subtitle: 'Consider stocking more for weekend rush'),
            ],
            if (yesterday > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.compare_arrows_rounded, color: today > yesterday ? const Color(0xFF10B981) : const Color(0xFFEF4444), title: 'Day-over-Day', value: '${today > yesterday ? '+' : ''}${((today - yesterday) / yesterday * 100).toStringAsFixed(0)}%', subtitle: today > yesterday ? 'Sales improved from yesterday' : 'Sales dropped from yesterday'),
            ],
          ],
        );
      },
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

    return health.when(
      loading: () => _sectionLoading('Inventory Intelligence', Icons.inventory_2_rounded, const Color(0xFF6366F1)),
      error: (_, __) => _empty(),
      data: (data) {
        if (data.isEmpty) return _empty();
        final total = (data['total_products'] as num?)?.toInt() ?? 0;
        final healthy = (data['healthy_count'] as num?)?.toInt() ?? 0;
        final lowStock = (data['low_stock_count'] as num?)?.toInt() ?? 0;
        final outOfStock = (data['out_of_stock_count'] as num?)?.toInt() ?? 0;
        final slowMoving = (data['slow_moving_count'] as num?)?.toInt() ?? 0;
        final deadStock = (data['dead_stock_count'] as num?)?.toInt() ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Inventory Intelligence', Icons.inventory_2_rounded, const Color(0xFF6366F1)),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Inventory Health ($total products)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(children: [
                      if (healthy > 0) Expanded(flex: healthy, child: Container(height: 24, color: const Color(0xFF10B981))),
                      if (lowStock > 0) Expanded(flex: lowStock, child: Container(height: 24, color: const Color(0xFFF59E0B))),
                      if (outOfStock > 0) Expanded(flex: outOfStock, child: Container(height: 24, color: const Color(0xFFEF4444))),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    _LegendDot(const Color(0xFF10B981), 'Healthy ($healthy)'),
                    const SizedBox(width: 12),
                    _LegendDot(const Color(0xFFF59E0B), 'Low ($lowStock)'),
                    const SizedBox(width: 12),
                    _LegendDot(const Color(0xFFEF4444), 'Out ($outOfStock)'),
                  ]),
                ],
              ),
            ),
            if (slowMoving > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.pause_circle_outline_rounded, color: const Color(0xFF8B5CF6), title: 'Slow Moving Stock', value: '$slowMoving products', subtitle: 'No sales in 90+ days'),
            ],
            if (deadStock > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.delete_sweep_rounded, color: const Color(0xFF6B7280), title: 'Dead Stock', value: '$deadStock products', subtitle: 'No sales in 180+ days — consider clearance'),
            ],
            if (outOfStock > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.remove_shopping_cart_rounded, color: const Color(0xFFEF4444), title: 'Out of Stock', value: '$outOfStock products', subtitle: 'Reorder these items to avoid lost sales'),
            ],
          ],
        );
      },
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]);
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

    return financial.when(
      loading: () => _sectionLoading('Financial Insights', Icons.account_balance_rounded, const Color(0xFF10B981)),
      error: (_, __) => _empty(),
      data: (data) {
        if (data.isEmpty) return _empty();
        final margin = (data['gross_margin_pct'] as num?)?.toDouble() ?? 0;
        final expenseRatio = (data['expense_ratio_pct'] as num?)?.toDouble() ?? 0;
        final receivables = (data['total_receivables'] as num?)?.toDouble() ?? 0;
        final payables = (data['total_payables'] as num?)?.toDouble() ?? 0;
        final cashRunway = (data['cash_runway_days'] as num?)?.toDouble() ?? 999;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Financial Insights', Icons.account_balance_rounded, const Color(0xFF10B981)),
            _InsightCard(icon: Icons.receipt_long_rounded, color: const Color(0xFF3B82F6), title: 'Gross Margin', value: '${margin.toStringAsFixed(1)}%', subtitle: margin > 20 ? 'Healthy profit margin' : margin > 10 ? 'Average margin' : 'Low margin — review pricing'),
            const SizedBox(height: 8),
            _InsightCard(icon: Icons.speed_rounded, color: const Color(0xFF6366F1), title: 'Expense Ratio', value: '${expenseRatio.toStringAsFixed(1)}%', subtitle: expenseRatio < 15 ? 'Expenses well controlled' : 'High expenses — review overhead'),
            if (receivables > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.people_alt_rounded, color: const Color(0xFF3B82F6), title: 'Customer Dues', value: _fmt(receivables), subtitle: 'Follow up with customers to collect payments', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerScreen()))),
            ],
            if (payables > 0) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.local_shipping_rounded, color: const Color(0xFFEF4444), title: 'Supplier Dues', value: _fmt(payables), subtitle: 'Schedule payments to maintain good relations', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierScreen()))),
            ],
            if (cashRunway < 30 && cashRunway < 999) ...[
              const SizedBox(height: 8),
              _InsightCard(icon: Icons.timer_off_rounded, color: const Color(0xFFEF4444), title: 'Cash Runway', value: '${cashRunway.toStringAsFixed(0)} days', subtitle: 'Cash may run out within a month at current burn rate'),
            ],
          ],
        );
      },
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

    return insights.when(
      loading: () => _sectionLoading('Customer Intelligence', Icons.people_rounded, const Color(0xFFEC4899)),
      error: (_, __) => _empty(),
      data: (data) {
        if (data.isEmpty) return _empty();
        final top5 = data.take(5).toList();
        final atRisk = data.where((c) => c['churn_risk'] == 'high' || c['churn_risk'] == 'medium').toList();
        final totalCustomers = data.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Customer Intelligence', Icons.people_rounded, const Color(0xFFEC4899)),
            if (top5.isNotEmpty)
              _InsightCard(
                icon: Icons.star_rounded,
                color: const Color(0xFFEC4899),
                title: 'Top Customers',
                value: top5.length > 1 ? '${top5.length} customers' : '₹${(top5.first['total_purchases'] as num?)?.toStringAsFixed(0) ?? '0'}',
                subtitle: top5.length > 1 ? '${top5.first['customer_name'] ?? ''} leads with ₹${(top5.first['total_purchases'] as num?)?.toStringAsFixed(0) ?? '0'}' : '${top5.first['customer_name'] ?? ''} — ${top5.first['total_orders'] ?? 0} orders',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerScreen())),
              ),
            if (top5.isNotEmpty) const SizedBox(height: 8),
            if (atRisk.isNotEmpty)
              _InsightCard(
                icon: Icons.person_off_rounded,
                color: const Color(0xFFF97316),
                title: 'At-Risk Customers',
                value: '${atRisk.length} customers',
                subtitle: 'Haven\'t purchased in 30+ days — send promotions',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerScreen())),
              ),
            if (atRisk.isNotEmpty) const SizedBox(height: 8),
            _InsightCard(
              icon: Icons.person_add_rounded,
              color: const Color(0xFF3B82F6),
              title: 'Customer Segments',
              value: '$totalCustomers total',
              subtitle: 'Platinum: ${data.where((c) => c['segment'] == 'platinum').length} | Gold: ${data.where((c) => c['segment'] == 'gold').length} | Silver: ${data.where((c) => c['segment'] == 'silver').length}',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerScreen())),
            ),
          ],
        );
      },
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

    return products.when(
      loading: () => _sectionLoading('Profitability Deep Dive', Icons.analytics_rounded, const Color(0xFF10B981)),
      error: (_, __) => _empty(),
      data: (allProducts) {
        return salesHistory.when(
          loading: () => _empty(),
          error: (_, __) => _empty(),
          data: (sales) {
            if (allProducts.isEmpty || sales.isEmpty) return _empty();

            final categoryRevenue = <String, double>{};
            final categoryProfit = <String, double>{};
            final categoryCount = <String, int>{};
            for (final sale in sales) {
              for (final item in sale.items) {
                final cat = allProducts.where((p) => p.id == item.productId).map((p) => p.category ?? 'Other').firstOrNull ?? 'Other';
                final revenue = item.price * item.qty;
                final profit = (item.price - item.purchasePrice) * item.qty;
                categoryRevenue[cat] = (categoryRevenue[cat] ?? 0) + revenue;
                categoryProfit[cat] = (categoryProfit[cat] ?? 0) + profit;
                categoryCount[cat] = (categoryCount[cat] ?? 0) + 1;
              }
            }

            final sortedCats = categoryProfit.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            final topCategory = sortedCats.isNotEmpty ? sortedCats.first : null;
            final lossMaking = allProducts.where((p) => p.sellingPrice > 0 && p.purchasePrice > 0 && p.purchasePrice >= p.sellingPrice).length;

            final marginBuckets = {'0-5%': 0, '5-10%': 0, '10-20%': 0, '20%+': 0};
            for (final p in allProducts) {
              if (p.sellingPrice <= 0 || p.purchasePrice <= 0) continue;
              final margin = (p.sellingPrice - p.purchasePrice) / p.sellingPrice * 100;
              if (margin < 5) marginBuckets['0-5%'] = marginBuckets['0-5%']! + 1;
              else if (margin < 10) marginBuckets['5-10%'] = marginBuckets['5-10%']! + 1;
              else if (margin < 20) marginBuckets['10-20%'] = marginBuckets['10-20%']! + 1;
              else marginBuckets['20%+'] = marginBuckets['20%+']! + 1;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Profitability Deep Dive', Icons.analytics_rounded, const Color(0xFF10B981)),
                if (topCategory != null)
                  _InsightCard(icon: Icons.category_rounded, color: const Color(0xFF10B981), title: 'Most Profitable Category', value: topCategory.key, subtitle: '₹${topCategory.value.toStringAsFixed(0)} profit from ${categoryCount[topCategory.key] ?? 0} sales'),
                if (topCategory != null) const SizedBox(height: 8),
                if (lossMaking > 0)
                  _InsightCard(icon: Icons.warning_amber_rounded, color: const Color(0xFFEF4444), title: 'Loss-Making Products', value: '$lossMaking products', subtitle: 'Selling below cost — review pricing immediately'),
                if (lossMaking > 0) const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Margin Distribution', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ...marginBuckets.entries.map((e) {
                        final total = marginBuckets.values.fold(0, (a, b) => a + b);
                        final pct = total > 0 ? e.value / total : 0.0;
                        final color = e.key == '0-5%' ? const Color(0xFFEF4444) : e.key == '5-10%' ? const Color(0xFFF59E0B) : e.key == '10-20%' ? const Color(0xFF3B82F6) : const Color(0xFF10B981);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            SizedBox(width: 50, child: Text(e.key, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                            const SizedBox(width: 8),
                            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation(color), minHeight: 8))),
                            const SizedBox(width: 8),
                            Text('${e.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
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

    return returns.when(
      loading: () => _sectionLoading('Returns & Damaged', Icons.assignment_return_rounded, const Color(0xFFF97316)),
      error: (e, st) => _empty(),
      data: (returnList) {
        return damaged.when(
          loading: () => _empty(),
          error: (e, st) => _empty(),
          data: (damagedList) {
            if (returnList.isEmpty && damagedList.isEmpty) return _empty();

            double totalReturnRefund = 0;
            int totalReturnQty = 0;
            final returnProducts = <String, int>{};
            for (final r in returnList) {
              final ret = r as ProductReturn;
              totalReturnRefund += ret.refundAmount;
              totalReturnQty += ret.quantity;
              returnProducts[ret.productName] = (returnProducts[ret.productName] ?? 0) + ret.quantity;
            }

            double totalDamagedValue = 0;
            int totalDamagedQty = 0;
            final damagedProducts = <String, int>{};
            for (final d in damagedList) {
              final dmg = d as DamagedProduct;
              totalDamagedValue += dmg.quantity * dmg.unitPrice;
              totalDamagedQty += dmg.quantity;
              damagedProducts[dmg.productName] = (damagedProducts[dmg.productName] ?? 0) + dmg.quantity;
            }

            final totalSold = salesHistory.value?.fold(0, (sum, s) => sum + s.items.fold(0, (isum, i) => isum + i.qty)) ?? 0;
            final returnRate = totalSold > 0 ? (totalReturnQty / totalSold * 100) : 0.0;

            final topReturns = returnProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            final topDamaged = damagedProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Returns & Damaged', Icons.assignment_return_rounded, const Color(0xFFF97316)),
                _InsightCard(
                  icon: Icons.replay_rounded,
                  color: returnRate > 5 ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
                  title: 'Return Rate',
                  value: '${returnRate.toStringAsFixed(1)}%',
                  subtitle: returnRate > 5 ? 'High — investigate quality issues' : 'Within normal range',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen())),
                ),
                if (topReturns.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.undo_rounded,
                    color: const Color(0xFFF97316),
                    title: 'Top Returned Product',
                    value: topReturns.first.key,
                    subtitle: '${topReturns.first.value} units returned — ₹${totalReturnRefund.toStringAsFixed(0)} refunded',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReturnsScreen())),
                  ),
                ],
                if (totalDamagedQty > 0) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.broken_image_rounded,
                    color: const Color(0xFFEF4444),
                    title: 'Damaged Goods',
                    value: '$totalDamagedQty units',
                    subtitle: '₹${totalDamagedValue.toStringAsFixed(0)} value lost to damage',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DamagedScreen())),
                  ),
                ],
                if (topDamaged.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InsightCard(
                    icon: Icons.priority_high_rounded,
                    color: const Color(0xFF8B5CF6),
                    title: 'Most Damaged Product',
                    value: topDamaged.first.key,
                    subtitle: '${topDamaged.first.value} units damaged — review handling',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DamagedScreen())),
                  ),
                ],
              ],
            );
          },
        );
      },
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

    return suppliers.when(
      loading: () => _sectionLoading('Supplier Performance', Icons.local_shipping_rounded, const Color(0xFF6366F1)),
      error: (_, __) => _empty(),
      data: (allSuppliers) {
        if (allSuppliers.isEmpty) return _empty();
        return purchases.when(
          loading: () => _empty(),
          error: (_, __) => _empty(),
          data: (allPurchases) {
            final supplierSpend = <String, double>{};
            for (final p in allPurchases) {
              final name = p.supplierName ?? 'Unknown';
              supplierSpend[name] = (supplierSpend[name] ?? 0) + p.totalAmount;
            }
            final sorted = supplierSpend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
            final topSupplier = sorted.isNotEmpty ? sorted.first : null;
            final pendingPOs = purchaseOrders.value?.where((po) => po.status != 'completed' && po.status != 'cancelled').toList() ?? [];
            final pendingPOValue = pendingPOs.fold(0.0, (sum, po) => sum + po.totalAmount);
            final totalSpend = supplierSpend.values.fold(0.0, (a, b) => a + b);
            final topSupplierConcentration = topSupplier != null && totalSpend > 0 ? (topSupplier.value / totalSpend * 100) : 0.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Supplier Performance', Icons.local_shipping_rounded, const Color(0xFF6366F1)),
                if (topSupplier != null)
                  _InsightCard(icon: Icons.store_rounded, color: const Color(0xFF6366F1), title: 'Top Supplier by Spend', value: topSupplier.key, subtitle: '₹${topSupplier.value.toStringAsFixed(0)} total purchases', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierScreen()))),
                if (topSupplierConcentration > 50) ...[
                  const SizedBox(height: 8),
                  _InsightCard(icon: Icons.warning_amber_rounded, color: const Color(0xFFF59E0B), title: 'Supplier Concentration Risk', value: '${topSupplierConcentration.toStringAsFixed(0)}%', subtitle: 'Over half your purchases from one supplier — diversify'),
                ],
                if (pendingPOs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _InsightCard(icon: Icons.reorder_rounded, color: const Color(0xFF3B82F6), title: 'Pending Purchase Orders', value: '${pendingPOs.length} orders', subtitle: '₹${pendingPOValue.toStringAsFixed(0)} total value pending', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderScreen()))),
                ],
              ],
            );
          },
        );
      },
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

    return financial.when(
      loading: () => _sectionLoading('Cash Flow Intelligence', Icons.account_balance_wallet_rounded, const Color(0xFF14B8A6)),
      error: (_, __) => _empty(),
      data: (data) {
        if (data.isEmpty) return _empty();
        final cashPos = (data['cash_position'] as num?)?.toDouble() ?? 0;
        final bankPos = (data['bank_position'] as num?)?.toDouble() ?? 0;
        final totalCash = cashPos + bankPos;
        final sales = todaySales.value ?? 0;
        final expenses = todayExpenses.value ?? 0;
        final netFlow = sales - expenses;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Cash Flow Intelligence', Icons.account_balance_wallet_rounded, const Color(0xFF14B8A6)),
            _InsightCard(icon: Icons.account_balance_wallet_rounded, color: const Color(0xFF14B8A6), title: 'Cash Position', value: '₹${totalCash.toStringAsFixed(0)}', subtitle: 'Cash: ₹${cashPos.toStringAsFixed(0)} | Bank: ₹${bankPos.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
            _InsightCard(icon: Icons.swap_horiz_rounded, color: netFlow >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444), title: "Today's Net Cash Flow", value: '${netFlow >= 0 ? '+' : ''}₹${netFlow.toStringAsFixed(0)}', subtitle: 'In: ₹${sales.toStringAsFixed(0)} | Out: ₹${expenses.toStringAsFixed(0)}'),
          ],
        );
      },
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

    return forecast.when(
      loading: () => _sectionLoading('Time-Series Forecast', Icons.auto_graph_rounded, const Color(0xFF8B5CF6)),
      error: (_, __) => _empty(),
      data: (data) {
        if (data.isEmpty) return _empty();
        final projected = (data['projected_monthly_sales'] as num?)?.toDouble() ?? 0;
        final dailyAvg = (data['daily_average'] as num?)?.toDouble() ?? 0;
        final trend = (data['trend_direction'] as String?) ?? 'stable';
        final confidence = (data['forecast_confidence'] as String?) ?? 'low';
        final daysElapsed = (data['days_elapsed'] as num?)?.toInt() ?? 0;
        final momPct = (data['month_over_month_pct'] as num?)?.toDouble() ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('Time-Series Forecast', Icons.auto_graph_rounded, const Color(0xFF8B5CF6)),
            _InsightCard(icon: Icons.show_chart_rounded, color: const Color(0xFF8B5CF6), title: 'Projected Monthly Revenue', value: '₹${projected.toStringAsFixed(0)}', subtitle: '₹${dailyAvg.toStringAsFixed(0)}/day avg | $daysElapsed days data | $confidence confidence'),
            const SizedBox(height: 8),
            _InsightCard(icon: Icons.trending_up_rounded, color: trend == 'growing' ? const Color(0xFF10B981) : trend == 'declining' ? const Color(0xFFEF4444) : const Color(0xFF3B82F6), title: 'Sales Trend', value: '${trend[0].toUpperCase()}${trend.substring(1)}', subtitle: momPct > 0 ? '+${momPct.toStringAsFixed(1)}% vs last month' : '${momPct.toStringAsFixed(1)}% vs last month'),
            const SizedBox(height: 8),
            inventoryHealth.when(
              loading: () => _empty(),
              error: (_, __) => _empty(),
              data: (data) {
                if (data.isEmpty) return _empty();
                final reorderItems = (data['top_reorder_items'] as List?) ?? [];
                if (reorderItems.isEmpty) return _empty();
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.timer_rounded, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 6),
                        const Text('Needs Reorder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      ...reorderItems.take(5).map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              Expanded(child: Text('${item['name'] ?? ''}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                              Text('${item['stock'] ?? 0} left (need ${item['alert'] ?? 0})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                            ]),
                          )),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
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
    final salesHistory = ref.watch(salesHistoryProvider);

    return monthlyGst.when(
      loading: () => _sectionLoading('GST & Tax Intelligence', Icons.receipt_rounded, const Color(0xFF0EA5E9)),
      error: (_, __) => _empty(),
      data: (gst) {
            return salesHistory.when(
              loading: () => _empty(),
              error: (_, __) => _empty(),
              data: (sales) {
                if (sales.isEmpty && gst == 0) return _empty();
                int totalSalesCount = sales.length;
                int taxExemptCount = sales.where((s) => s.taxExempt).length;
                final exemptRatio = totalSalesCount > 0 ? (taxExemptCount / totalSalesCount * 100) : 0.0;
                final hsnMap = <String, double>{};
                for (final sale in sales) {
                  for (final item in sale.items) {
                    final hsn = item.hsnCode ?? 'N/A';
                    hsnMap[hsn] = (hsnMap[hsn] ?? 0) + (item.price * item.qty);
                  }
                }
                final sortedHSN = hsnMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                final topHSN = sortedHSN.take(3).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('GST & Tax Intelligence', Icons.receipt_rounded, const Color(0xFF0EA5E9)),
                    _InsightCard(icon: Icons.savings_rounded, color: const Color(0xFF0EA5E9), title: 'Monthly GST Liability', value: '₹${gst.toStringAsFixed(0)}', subtitle: 'GST collected this month to be remitted', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GstFilingScreen()))),
                    const SizedBox(height: 8),
                    _InsightCard(icon: Icons.gavel_rounded, color: exemptRatio > 10 ? const Color(0xFFF59E0B) : const Color(0xFF10B981), title: 'Tax-Exempt Sales', value: '${exemptRatio.toStringAsFixed(1)}%', subtitle: '$taxExemptCount of $totalSalesCount sales are tax-exempt'),
                    if (topHSN.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Top HSN Codes by Revenue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            ...topHSN.map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0EA5E9))),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('₹${e.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                                  ]),
                                )),
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

    return monthlyExpenses.when(
      loading: () => _sectionLoading('Expense Intelligence', Icons.money_off_rounded, const Color(0xFFEF4444)),
      error: (_, __) => _empty(),
      data: (mExpenses) {
        return monthlyProfit.when(
          loading: () => _empty(),
          error: (_, __) => _empty(),
          data: (profitData) {
            final sales = profitData['sales'] ?? 0;
            if (sales == 0 && mExpenses == 0) return _empty();
            final expenseRatio = sales > 0 ? (mExpenses / sales * 100) : 0.0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader('Expense Intelligence', Icons.money_off_rounded, const Color(0xFFEF4444)),
                _InsightCard(icon: Icons.pie_chart_rounded, color: expenseRatio > 15 ? const Color(0xFFEF4444) : const Color(0xFF10B981), title: 'Expense-to-Sales Ratio', value: '${expenseRatio.toStringAsFixed(1)}%', subtitle: expenseRatio > 15 ? 'High — expenses consuming too much revenue' : 'Healthy expense level', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseScreen()))),
                const SizedBox(height: 8),
                expenses.when(
                  loading: () => _empty(),
                  error: (_, __) => _empty(),
                  data: (expList) {
                    if (expList.isEmpty) return _empty();
                    final categories = <String, double>{};
                    for (final e in expList) {
                      categories[e.category] = (categories[e.category] ?? 0) + e.amount;
                    }
                    final sorted = categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                    final top3 = sorted.take(3).toList();
                    final totalExp = sorted.fold(0.0, (sum, e) => sum + e.value);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Top Expense Categories', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          ...top3.map((e) {
                            final pct = totalExp > 0 ? (e.value / totalExp * 100) : 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12))),
                                Text('₹${e.value.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                const SizedBox(width: 8),
                                Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ]),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════
// ACTION RECOMMENDATIONS
// ═══════════════════════════════════════════
class _Action {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  const _Action(this.title, this.message, this.icon, this.color);
}

class _ActionRecommendations extends ConsumerWidget {
  const _ActionRecommendations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStock = ref.watch(lowStockListProvider);
    final expiring = ref.watch(expiringProductsProvider);
    final products = ref.watch(productsProvider);
    final todaySales = ref.watch(todaySalesProvider);
    final topProducts = ref.watch(topProductsProvider);
    final customers = ref.watch(customerInsightsProvider);
    final returns = ref.watch(returnsProvider);
    final expenses = ref.watch(monthlyExpensesProvider);
    final monthlyProfit = ref.watch(monthlyProfitProvider);
    final actions = <_Action>[];
    final now = AppTimezone.nowIst();

    final topSelling = topProducts.value;
    if (topSelling != null && topSelling.isNotEmpty) {
      final top = topSelling.first;
      actions.add(_Action('Reorder Best Seller', '"${top['name'] ?? 'Top product'}" is your top seller. Ensure it never runs out.', Icons.shopping_cart_checkout_rounded, const Color(0xFF10B981)));
    }
    final expiringSoon = expiring.value?.where((p) {
      final diff = p.expiryDate?.difference(now).inDays ?? 999;
      return diff >= 0 && diff <= 14;
    }).toList() ?? [];
    if (expiringSoon.isNotEmpty) {
      actions.add(_Action('Run Expiry Discount', '${expiringSoon.length} products expire within 14 days. Offer 20-30% off to recover cost.', Icons.local_offer_rounded, const Color(0xFFF97316)));
    }
    final productsList = products.value ?? [];
    final lowMargin = productsList.where((p) => p.sellingPrice > 0 && p.purchasePrice > 0 && ((p.sellingPrice - p.purchasePrice) / p.sellingPrice) < 0.1).length;
    if (lowMargin > 0) {
      actions.add(_Action('Review Pricing', '$lowMargin products have less than 10% margin. Consider price adjustments.', Icons.price_change_rounded, const Color(0xFF8B5CF6)));
    }
    final criticalStock = lowStock.value ?? [];
    final criticalCount = criticalStock.where((p) => p.stock > 0 && p.stock <= (p.lowStockAlert ~/ 2).clamp(1, 999)).length;
    if (criticalCount > 0) {
      actions.add(_Action('Emergency Restock', '$criticalCount products at critically low stock levels.', Icons.build_rounded, const Color(0xFFEF4444)));
    }
    final sales = todaySales.value ?? 0;
    if (sales == 0 && now.hour > 10) {
      actions.add(_Action('Boost Today\'s Sales', 'No sales recorded yet. Consider running a flash deal or promotion.', Icons.campaign_rounded, const Color(0xFF3B82F6)));
    }

    final customerData = customers.value ?? [];
    final atRisk = customerData.where((c) => c['churn_risk'] == 'high' || c['churn_risk'] == 'medium').toList();
    if (atRisk.isNotEmpty) {
      actions.add(_Action('Re-engage At-Risk Customers', '${atRisk.length} customers haven\'t purchased in 30+ days. Send them a personalized offer.', Icons.person_add_rounded, const Color(0xFFEC4899)));
    }

    final returnData = returns.value ?? [];
    if (returnData.length >= 3) {
      actions.add(_Action('Investigate Return Patterns', '${returnData.length} returns recorded. Check for recurring quality issues.', Icons.assignment_return_rounded, const Color(0xFFF97316)));
    }

    final profitData = monthlyProfit.value;
    final profit = (profitData?['profit'] as num?)?.toDouble() ?? 0;
    final profitSales = (profitData?['sales'] as num?)?.toDouble() ?? 0;
    if (profitSales > 0 && profit / profitSales < 0.1) {
      actions.add(_Action('Improve Profit Margins', 'Monthly profit margin is ${(profit / profitSales * 100).toStringAsFixed(1)}%. Review costs and pricing.', Icons.trending_down_rounded, const Color(0xFFEF4444)));
    }

    final outOfStock = productsList.where((p) => p.stock <= 0).length;
    if (outOfStock > 0) {
      actions.add(_Action('Restore Out-of-Stock Items', '$outOfStock products are completely out of stock. Restock or delist them.', Icons.inventory_2_rounded, const Color(0xFFF59E0B)));
    }

    final mExpenses = expenses.value ?? 0;
    if (mExpenses > 0 && profitSales > 0 && mExpenses / profitSales > 0.15) {
      actions.add(_Action('Cut Unnecessary Expenses', 'Expenses are ${(mExpenses / profitSales * 100).toStringAsFixed(1)}% of sales. Review subscriptions and overhead.', Icons.money_off_rounded, const Color(0xFFEF4444)));
    }

    final highStock = productsList.where((p) => p.stock > p.lowStockAlert * 3).length;
    if (highStock > 0) {
      actions.add(_Action('Clear Overstocked Items', '$highStock products have more than 3x their alert level. Consider clearance sales.', Icons.warehouse_rounded, const Color(0xFF6366F1)));
    }

    if (now.hour >= 14 && now.hour < 17) {
      actions.add(_Action('Afternoon Push', 'Peak hours ahead. Ensure staff is ready and displays are refreshed.', Icons.schedule_rounded, const Color(0xFF0EA5E9)));
    }

    final hasMissingHsn = productsList.where((p) => p.hsnCode == null || p.hsnCode!.isEmpty).length;
    if (hasMissingHsn > 0) {
      actions.add(_Action('Update HSN Codes', '$hasMissingHsn products missing HSN codes. Required for GST filing.', Icons.receipt_rounded, const Color(0xFF0EA5E9)));
    }

    final expiring30 = expiring.value?.where((p) {
      final diff = p.expiryDate?.difference(now).inDays ?? 999;
      return diff >= 15 && diff <= 30;
    }).toList() ?? [];
    if (expiring30.isNotEmpty) {
      actions.add(_Action('Plan Expiry Management', '${expiring30.length} products expire in 15-30 days. Plan markdowns or bundle deals.', Icons.event_repeat_rounded, const Color(0xFFF59E0B)));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF667eea)),
          const SizedBox(width: 8),
          Text('Recommended Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF667eea).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text('${actions.length}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF667eea))),
          ),
        ]),
        const SizedBox(height: 12),
        ...actions.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: a.color.withValues(alpha: 0.15)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: a.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(a.icon, color: a.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(a.message, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ]),
                ),
              ]),
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// SHARED INSIGHT CARD
// ═══════════════════════════════════════════
class _InsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;

  const _InsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ]),
        ),
        Expanded(
          child: Text(subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.end),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 20),
        ],
      ]),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

// ═══════════════════════════════════════════
// DATE RANGE FILTER
// ═══════════════════════════════════════════
class _DateRangeFilter extends StatelessWidget {
  final int selectedRange;
  final Function(int) onSelect;
  final Function() onCustom;

  const _DateRangeFilter({
    required this.selectedRange,
    required this.onSelect,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          _buildChip('Today', 1),
          _buildChip('7 Days', 7),
          _buildChip('30 Days', 30),
          _buildChip('90 Days', 90),
          _buildChip('Custom', -1),
        ],
      ),
    );
  }

  Widget _buildChip(String label, int days) {
    final isSelected = selectedRange == days;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (days == -1) {
            onCustom();
          } else {
            onSelect(days);
          }
        },
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF667eea) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// SALES TREND LINE CHART
// ═══════════════════════════════════════════
class _SalesChart extends ConsumerWidget {
  final DateTimeRange dateRange;
  const _SalesChart({required this.dateRange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(dailySalesTrendProvider(dateRange));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.show_chart_rounded, size: 20, color: Color(0xFF667eea)),
            const SizedBox(width: 8),
            const Text('Sales Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          trend.when(
            loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => const SizedBox(height: 150, child: Center(child: Text('Failed to load'))),
            data: (data) {
              if (data.isEmpty) return const SizedBox(height: 150, child: Center(child: Text('No data')));
              final spots = <FlSpot>[];
              for (int i = 0; i < data.length && i < 30; i++) {
                spots.add(FlSpot(i.toDouble(), (data[i]['total_sales'] as num?)?.toDouble() ?? 0));
              }
              final maxY = spots.isEmpty ? 0.0 : spots.map((s) => s.y).reduce(max);
              return SizedBox(
                height: 150,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY > 0 ? maxY / 4 : 1, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.shade100, strokeWidth: 1)),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text('₹${_abbrev(v)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)))),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20, interval: data.length > 7 ? (data.length / 7).ceilToDouble() : 1, getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx >= 0 && idx < data.length) {
                          final day = data[idx]['day']?.toString().substring(5) ?? '';
                          return Text(day, style: TextStyle(fontSize: 9, color: Colors.grey.shade500));
                        }
                        return const Text('');
                      })),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: const Color(0xFF667eea),
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: spots.length < 15),
                        belowBarData: BarAreaData(show: true, color: const Color(0xFF667eea).withValues(alpha: 0.1)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _abbrev(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ═══════════════════════════════════════════
// CATEGORY PIE CHART
// ═══════════════════════════════════════════
class _CategoryPieChart extends ConsumerWidget {
  final DateTimeRange dateRange;
  const _CategoryPieChart({required this.dateRange});

  static const _colors = [
    Color(0xFF667eea),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categorySales = ref.watch(categorySalesProvider(dateRange));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.pie_chart_rounded, size: 20, color: Color(0xFFEC4899)),
            const SizedBox(width: 8),
            const Text('Category Sales', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          categorySales.when(
            loading: () => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => const SizedBox(height: 150, child: Center(child: Text('Failed to load'))),
            data: (data) {
              if (data.isEmpty) return const SizedBox(height: 150, child: Center(child: Text('No data')));
              final total = data.fold<double>(0, (s, d) => s + ((d['total_revenue'] as num?)?.toDouble() ?? 0));
              if (total <= 0) return const SizedBox(height: 150, child: Center(child: Text('No sales data')));
              final sections = <PieChartSectionData>[];
              final legends = <Widget>[];
              for (int i = 0; i < data.length && i < 8; i++) {
                final cat = data[i];
                final revenue = (cat['total_revenue'] as num?)?.toDouble() ?? 0;
                final pct = (revenue / total * 100);
                final color = _colors[i % _colors.length];
                sections.add(PieChartSectionData(value: revenue, color: color, title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '', titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white), radius: 50));
                legends.add(Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(cat['category'] ?? 'Other', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    Text('₹${revenue.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  ]),
                ));
              }
              return Row(children: [
                SizedBox(width: 120, height: 120, child: PieChart(PieChartData(sections: sections, centerSpaceRadius: 20, sectionsSpace: 2))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: legends)),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// TOP PRODUCTS BAR CHART
// ═══════════════════════════════════════════
class _TopProductsChart extends ConsumerWidget {
  final DateTimeRange dateRange;
  const _TopProductsChart({required this.dateRange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topProducts = ref.watch(topProductsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 20, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            const Text('Top Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllTopProductsScreen())),
              child: Text('View All', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 16),
          topProducts.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => const SizedBox(height: 120, child: Center(child: Text('Failed to load'))),
            data: (data) {
              if (data.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No data')));
              final maxVal = data.map((d) => d['total'] as double).reduce(max);
              final barColors = [const Color(0xFF667eea), const Color(0xFFEC4899), const Color(0xFFF59E0B), const Color(0xFF10B981), const Color(0xFFEF4444)];
              return Column(
                children: data.take(5).toList().asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final name = item['name'] as String? ?? '';
                  final total = (item['total'] as num?)?.toDouble() ?? 0;
                  final pct = maxVal > 0 ? total / maxVal : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      SizedBox(width: 20, child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500))),
                      Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Expanded(flex: 5, child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, backgroundColor: Colors.grey.shade100, valueColor: AlwaysStoppedAnimation(barColors[i % barColors.length]), minHeight: 10))),
                      const SizedBox(width: 8),
                      SizedBox(width: 60, child: Text('₹${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                    ]),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
