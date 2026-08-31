import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';
import '../../../utils/app_timezone.dart';

class KpiCards extends ConsumerWidget {
  const KpiCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todaySales = ref.watch(todaySalesProvider);
    final yesterdaySales = ref.watch(yesterdaySalesProvider);
    final todayExpenses = ref.watch(todayExpensesProvider);
    final stockValue = ref.watch(stockValueProvider);
    final recentSales = ref.watch(recentSalesProvider);
    final customerDues = ref.watch(totalCustomerDuesProvider);
    final supplierDues = ref.watch(totalSupplierDuesProvider);
    final avgOrderValue = ref.watch(todayAvgOrderValueProvider);
    final todayGst = ref.watch(todayGstTotalProvider);
    final sparkData = ref.watch(weeklySalesSparkProvider);

    final todayOrdersCount = recentSales.when(
      loading: () => 0,
      error: (_, __) => 0,
      data: (sales) => sales.length,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Row 1: Sales + Orders
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: "Today's Sales",
                  value: todaySales.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => 'Rs${_formatAmount(v)}',
                  ),
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF10B981),
                  bgColor: const Color(0xFFECFDF5),
                  subtitle: _buildTrendText(todaySales, yesterdaySales),
                  subtitleColor: _getTrendColor(todaySales, yesterdaySales),
                  sparkData: sparkData.value,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: "Today's Orders",
                  value: '$todayOrdersCount',
                  icon: Icons.receipt_long_rounded,
                  color: const Color(0xFF6366F1),
                  bgColor: const Color(0xFFEEF2FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Expenses + GST
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: "Today's Expenses",
                  value: todayExpenses.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => 'Rs${_formatAmount(v)}',
                  ),
                  icon: Icons.account_balance_wallet_rounded,
                  color: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFFFBEB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: "Today's GST",
                  value: todayGst.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => 'Rs${_formatAmount(v)}',
                  ),
                  icon: Icons.receipt_rounded,
                  color: const Color(0xFF0EA5E9),
                  bgColor: const Color(0xFFE0F2FE),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 3: Avg Order + Stock Value
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Avg Order Value',
                  value: avgOrderValue.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => 'Rs${_formatAmount(v)}',
                  ),
                  icon: Icons.analytics_rounded,
                  color: const Color(0xFFEC4899),
                  bgColor: const Color(0xFFFDF2F8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'Stock Value',
                  value: stockValue.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => 'Rs${_formatAmount(v)}',
                  ),
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xFF8B5CF6),
                  bgColor: const Color(0xFFF5F3FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 4: Customer Dues + Supplier Dues
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  title: 'Customer Dues',
                  value: customerDues.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => v > 0 ? 'Rs${_formatAmount(v)}' : 'Clear',
                  ),
                  icon: Icons.people_rounded,
                  color: const Color(0xFFEF4444),
                  bgColor: const Color(0xFFFEF2F2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  title: 'Supplier Dues',
                  value: supplierDues.when(
                    loading: () => '...',
                    error: (_, __) => 'Rs0',
                    data: (v) => v > 0 ? 'Rs${_formatAmount(v)}' : 'Clear',
                  ),
                  icon: Icons.local_shipping_rounded,
                  color: const Color(0xFFF97316),
                  bgColor: const Color(0xFFFFF7ED),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String? _buildTrendText(
    AsyncValue<double> today,
    AsyncValue<double> yesterday,
  ) {
    final t = today.value ?? 0;
    final y = yesterday.value ?? 0;
    if (y == 0 && t == 0) return null;
    if (y == 0) return 'New sales today';
    final diff = ((t - y) / y * 100);
    if (diff > 0) return '+${diff.toStringAsFixed(0)}% vs yesterday';
    if (diff < 0) return '${diff.toStringAsFixed(0)}% vs yesterday';
    return 'Same as yesterday';
  }

  static Color? _getTrendColor(
    AsyncValue<double> today,
    AsyncValue<double> yesterday,
  ) {
    final t = today.value ?? 0;
    final y = yesterday.value ?? 0;
    if (y == 0) return null;
    if (t > y) return const Color(0xFF10B981);
    if (t < y) return const Color(0xFFEF4444);
    return null;
  }

  static String _formatAmount(double value) {
    if (value == 0) return '0';
    final intValue = value.toInt().abs();
    final isNeg = value < 0;
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

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String? subtitle;
  final Color? subtitleColor;
  final List<double>? sparkData;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.subtitle,
    this.subtitleColor,
    this.sparkData,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              if (sparkData != null && sparkData!.isNotEmpty)
                SizedBox(
                  width: 50,
                  height: 24,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      data: sparkData!,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final maxVal = data.reduce((a, b) => a > b ? a : b);
    final minVal = data.reduce((a, b) => a < b ? a : b);
    final range = maxVal - minVal == 0 ? 1.0 : maxVal - minVal;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.data != data || old.color != color;
}
