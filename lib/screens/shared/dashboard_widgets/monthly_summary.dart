import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../config/providers.dart';
import '../../../utils/app_timezone.dart';
import '../../../utils/logger.dart';
import '../../admin/profit_details_screen.dart';

class MonthlySummary extends ConsumerStatefulWidget {
  const MonthlySummary({super.key});

  @override
  ConsumerState<MonthlySummary> createState() => _MonthlySummaryState();
}

class _MonthlySummaryState extends ConsumerState<MonthlySummary> {
  String _selectedPeriod = 'monthly';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Business Summary',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfitDetailsScreen(initialPeriod: _selectedPeriod),
                  ),
                ),
                child: const Text('Details'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _periodChip('Daily', 'daily'),
              const SizedBox(width: 6),
              _periodChip('Weekly', 'weekly'),
              const SizedBox(width: 6),
              _periodChip('Monthly', 'monthly'),
              const SizedBox(width: 6),
              _periodChip('All', 'all'),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummary(theme),
        ],
      ),
    );
  }

  Widget _periodChip(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF667eea) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return FutureBuilder<Map<String, double>>(
      future: _fetchSummary(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!;
        final sales = data['sales'] ?? 0;
        final purchases = data['purchases'] ?? 0;
        final expenses = data['expenses'] ?? 0;
        final profit = sales - purchases - expenses;
        final profitMargin = sales > 0 ? (profit / sales * 100) : 0;

        return Container(
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
              _SummaryRow(
                icon: Icons.trending_up_rounded,
                label: 'Sales',
                value: 'Rs${_fmt(sales)}',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                icon: Icons.shopping_cart_rounded,
                label: 'Cost of Goods',
                value: '-Rs${_fmt(purchases)}',
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Expenses',
                value: '-Rs${_fmt(expenses)}',
                color: const Color(0xFFF59E0B),
              ),
              Divider(
                height: 24,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              _SummaryRow(
                icon: Icons.payments_rounded,
                label: 'Net Profit',
                value: 'Rs${_fmt(profit)}',
                color: profit >= 0
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                isBold: true,
              ),
              const SizedBox(height: 4),
              // Profit margin indicator
              Row(
                children: [
                  const SizedBox(width: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: profitMargin >= 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.1)
                          : const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          profitMargin >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 12,
                          color: profitMargin >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Margin: ${profitMargin.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: profitMargin >= 0
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Mini category pie
                  if (sales > 0)
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: _MiniCategoryPie(sales: sales, purchases: purchases),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _fetchSummary() async {
    try {
      final client = Supabase.instance.client;
      DateTime start;
      DateTime end;

      final now = AppTimezone.nowIst();
      switch (_selectedPeriod) {
        case 'daily':
          start = DateTime(now.year, now.month, now.day);
          end = now;
          break;
        case 'weekly':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          start = DateTime(weekStart.year, weekStart.month, weekStart.day);
          end = now;
          break;
        case 'all':
          start = DateTime(2020, 1, 1);
          end = now;
          break;
        default:
          start = DateTime(now.year, now.month, 1);
          end = now;
      }

      final endExclusive = end.add(const Duration(days: 1));
      final startUtc = start.toUtc().toIso8601String();
      final endUtc = endExclusive.toUtc().toIso8601String();

      double sales = 0;
      double cogs = 0;
      try {
        final salesRes = await client
            .from('sales')
            .select('final_amount, items')
            .gte('created_at', startUtc)
            .lt('created_at', endUtc);

        // Fetch products for COGS fallback
        final productsRes = await client
            .from('products')
            .select('id, purchase_price');
        final productCostMap = <String, double>{};
        for (final p in productsRes as List) {
          productCostMap[p['id'] as String] =
              (p['purchase_price'] as num?)?.toDouble() ?? 0;
        }

        for (final s in salesRes as List) {
          sales += (s['final_amount'] as num?)?.toDouble() ?? 0;
          final items = s['items'] as List? ?? [];
          for (final item in items) {
            var pp = (item['purchase_price'] as num?)?.toDouble() ?? 0;
            // Fallback: use products table if purchase_price is 0
            if (pp <= 0) {
              final productId = item['product_id'] as String? ?? '';
              pp = productCostMap[productId] ?? 0;
            }
            final qty = (item['qty'] as num?)?.toInt() ?? 0;
            cogs += pp * qty;
          }
        }
      } catch (e) {
        Logger.warning('Failed to calculate sales and COGS for monthly summary: $e');
      }

      double expenses = 0;
      try {
        final expensesRes = await client
            .from('expenses')
            .select('amount')
            .gte('created_at', startUtc)
            .lt('created_at', endUtc);
        for (final e in expensesRes as List) {
          expenses += (e['amount'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        // Keep expenses at 0 but log the error
        print('[MonthlySummary] Failed to fetch expenses: $e');
      }

      return {'sales': sales, 'purchases': cogs, 'expenses': expenses};
    } catch (e) {
      return {'sales': 0, 'purchases': 0, 'expenses': 0};
    }
  }

  static String _fmt(double v) {
    if (v == 0) return '0';
    final intValue = v.toInt().abs();
    final isNeg = v < 0;
    final str = intValue.toString();
    if (str.length <= 3) return '${isNeg ? '-' : ''}$str';

    String result = str.substring(str.length - 3);
    int i = str.length - 3;
    while (i > 0) {
      final start = i - 2 < 0 ? 0 : i - 2;
      result = '${str.substring(start, i)},$result';
      i -= 2;
    }
    return '${isNeg ? '-' : ''}$result';
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MiniCategoryPie extends StatelessWidget {
  final double sales;
  final double purchases;

  const _MiniCategoryPie({required this.sales, required this.purchases});

  @override
  Widget build(BuildContext context) {
    final grossProfit = sales - purchases;
    final grossPct = sales > 0 ? ((grossProfit / sales).toDouble()) : 0.0;
    final cogsPct = sales > 0 ? ((purchases / sales).toDouble()) : 0.0;

    if (sales == 0) return const SizedBox.shrink();

    return PieChart(
      PieChartData(
        sectionsSpace: 0,
        centerSpaceRadius: 8,
        sections: [
          PieChartSectionData(
            value: grossPct,
            color: const Color(0xFF10B981),
            radius: 6,
            showTitle: false,
          ),
          PieChartSectionData(
            value: cogsPct,
            color: const Color(0xFF6366F1),
            radius: 6,
            showTitle: false,
          ),
        ],
      ),
    );
  }
}
