import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';

class InventoryInsightsSection extends ConsumerWidget {
  const InventoryInsightsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory Insights',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox(),
            data: (products) {
              if (products.isEmpty) {
                return _EmptyInventory();
              }

              final outOfStock = products.where((p) => p.stock == 0).length;
              final critical = products
                  .where(
                    (p) =>
                        p.stock > 0 &&
                        p.stock <= (p.lowStockAlert * 0.5).ceil(),
                  )
                  .length;
              final low = products
                  .where(
                    (p) =>
                        p.stock > (p.lowStockAlert * 0.5).ceil() &&
                        p.isLowStock,
                  )
                  .length;
              final healthy = products.where((p) => !p.isLowStock).length;
              final totalProducts = products.length;

              return Container(
                padding: const EdgeInsets.all(16),
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
                  children: [
                    Row(
                      children: [
                        _StatChip(
                          label: 'Total',
                          count: totalProducts,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          label: 'Healthy',
                          count: healthy,
                          color: const Color(0xFF10B981),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatChip(
                          label: 'Out of Stock',
                          count: outOfStock,
                          color: const Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          label: 'Critical',
                          count: critical,
                          color: const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          label: 'Low',
                          count: low,
                          color: const Color(0xFF6366F1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Row(
                        children: [
                          if (outOfStock > 0)
                            Expanded(
                              flex: outOfStock,
                              child: Container(
                                height: 8,
                                color: const Color(0xFFEF4444),
                              ),
                            ),
                          if (critical > 0)
                            Expanded(
                              flex: critical,
                              child: Container(
                                height: 8,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          if (low > 0)
                            Expanded(
                              flex: low,
                              child: Container(
                                height: 8,
                                color: const Color(0xFF6366F1),
                              ),
                            ),
                          if (healthy > 0)
                            Expanded(
                              flex: healthy,
                              child: Container(
                                height: 8,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                        ],
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

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(32),
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
              Icons.inventory_2_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'No products added yet',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
