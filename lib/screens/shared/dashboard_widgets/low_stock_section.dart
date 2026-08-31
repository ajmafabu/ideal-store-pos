import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';
import '../../../models/product.dart';
import '../../admin/all_low_stock_screen.dart';
import '../../admin/slow_moving_screen.dart';

class LowStockSection extends ConsumerWidget {
  const LowStockSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lowStock = ref.watch(lowStockListProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Stock Alerts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllLowStockScreen()),
                ),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          lowStock.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (products) {
              if (products.isEmpty) {
                return _StockEmpty();
              }

              final outOfStock = products.where((p) => p.stock == 0).toList();
              final critical = products
                  .where(
                    (p) =>
                        p.stock > 0 &&
                        p.stock <= (p.lowStockAlert * 0.5).ceil(),
                  )
                  .toList();
              final low = products
                  .where(
                    (p) =>
                        p.stock > (p.lowStockAlert * 0.5).ceil() &&
                        p.isLowStock,
                  )
                  .toList();

              return Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
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
                    if (outOfStock.isNotEmpty) ...[
                      _StockCategory(
                        label: 'Out of Stock',
                        count: outOfStock.length,
                        color: const Color(0xFFEF4444),
                        icon: Icons.block_rounded,
                      ),
                      ...outOfStock
                          .take(3)
                          .map(
                            (p) => _StockTile(
                              product: p,
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                    ],
                    if (critical.isNotEmpty) ...[
                      _StockCategory(
                        label: 'Critical',
                        count: critical.length,
                        color: const Color(0xFFF59E0B),
                        icon: Icons.warning_amber_rounded,
                      ),
                      ...critical
                          .take(3)
                          .map(
                            (p) => _StockTile(
                              product: p,
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                    ],
                    if (low.isNotEmpty) ...[
                      _StockCategory(
                        label: 'Low Stock',
                        count: low.length,
                        color: const Color(0xFF6366F1),
                        icon: Icons.info_outline_rounded,
                      ),
                      ...low
                          .take(3)
                          .map(
                            (p) => _StockTile(
                              product: p,
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                    ],
                    // Slow Moving Stock Button
                    InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SlowMovingScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.05),
                          border: Border(
                            top: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 18,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Slow Moving Stock',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Colors.orange.shade700,
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
      ),
    );
  }
}

class _StockEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 40,
              color: const Color(0xFF10B981).withValues(alpha: 0.6),
            ),
            const SizedBox(height: 8),
            const Text(
              'All stock levels are healthy',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockCategory extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _StockCategory({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  final dynamic product;
  final Color color;

  const _StockTile({required this.product, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        product.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        product.barcode ?? 'No barcode',
        style: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${product.stock} ${product.unit}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}
