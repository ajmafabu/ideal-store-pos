import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';

class BusinessInsightsSection extends ConsumerWidget {
  const BusinessInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);
    final lowStock = ref.watch(lowStockListProvider);
    final monthlyProfit = ref.watch(monthlyProfitProvider);
    final topProducts = ref.watch(topProductsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Business Insights',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _InsightRow(
                  icon: Icons.trending_up_rounded,
                  label: _getSalesTrend(todaySales, yesterdaySales),
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 8),
                _InsightRow(
                  icon: Icons.warning_amber_rounded,
                  label: _getLowStockInsight(lowStock),
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 8),
                _InsightRow(
                  icon: Icons.category_rounded,
                  label: _getBestCategory(topProducts),
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 8),
                _InsightRow(
                  icon: Icons.payments_rounded,
                  label: _getProfitInsight(monthlyProfit),
                  color: const Color(0xFF8B5CF6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSalesTrend(
    AsyncValue<double> today,
    AsyncValue<double> yesterday,
  ) {
    final t = today.value ?? 0;
    final y = yesterday.value ?? 0;
    if (y == 0 && t == 0) return 'No sales data yet';
    if (y == 0) return 'Starting strong today with Rs${t.toStringAsFixed(0)}';
    final diff = ((t - y) / y * 100).abs();
    if (t > y) return 'Sales up ${diff.toStringAsFixed(0)}% vs yesterday';
    if (t < y) return 'Sales down ${diff.toStringAsFixed(0)}% vs yesterday';
    return 'Same as yesterday - Rs${t.toStringAsFixed(0)}';
  }

  String _getLowStockInsight(AsyncValue<List<dynamic>> lowStock) {
    final count = lowStock.value?.length ?? 0;
    if (count == 0) return 'All stock levels healthy';
    return '$count products need restocking';
  }

  String _getBestCategory(AsyncValue<List<Map<String, dynamic>>> topProducts) {
    final products = topProducts.value ?? [];
    if (products.isEmpty) return 'No sales data for category insights';
    return 'Best seller: ${products.first['name']}';
  }

  String _getProfitInsight(AsyncValue<Map<String, double>> profit) {
    final data = profit.value;
    if (data == null) return 'Loading profit data...';
    final p = data['profit'] ?? 0;
    if (p > 0) return 'Profitable month: Rs${p.toStringAsFixed(0)} earned';
    if (p < 0) return 'Loss this month: Rs${(-p).toStringAsFixed(0)}';
    return 'Breaking even this month';
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InsightRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}
