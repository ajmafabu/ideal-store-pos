import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';
import '../../../utils/app_timezone.dart';

class ExpiringProductsSection extends ConsumerWidget {
  const ExpiringProductsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expiring = ref.watch(expiringProductsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Expiry Alerts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          expiring.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const SizedBox(),
            data: (products) {
              if (products.isEmpty) {
                return _ExpiryEmpty();
              }

              final expired = products.where((p) => p.isExpired).toList();
              final expiringSoon = products
                  .where((p) => p.isExpiringSoon && !p.isExpired)
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
                    if (expired.isNotEmpty) ...[
                      _ExpiryCategory(
                        label: 'Expired',
                        count: expired.length,
                        color: const Color(0xFFEF4444),
                        icon: Icons.event_busy_rounded,
                      ),
                      ...expired
                          .take(3)
                          .map(
                            (p) => _ExpiryTile(
                              product: p,
                              color: const Color(0xFFEF4444),
                              isExpired: true,
                            ),
                          ),
                    ],
                    if (expiringSoon.isNotEmpty) ...[
                      _ExpiryCategory(
                        label: 'Expiring Soon (30 days)',
                        count: expiringSoon.length,
                        color: const Color(0xFFF59E0B),
                        icon: Icons.warning_amber_rounded,
                      ),
                      ...expiringSoon
                          .take(3)
                          .map(
                            (p) => _ExpiryTile(
                              product: p,
                              color: const Color(0xFFF59E0B),
                              isExpired: false,
                            ),
                          ),
                    ],
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

class _ExpiryEmpty extends StatelessWidget {
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
              'No products expiring soon',
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

class _ExpiryCategory extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _ExpiryCategory({
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

class _ExpiryTile extends StatelessWidget {
  final dynamic product;
  final Color color;
  final bool isExpired;

  const _ExpiryTile({
    required this.product,
    required this.color,
    required this.isExpired,
  });

  @override
  Widget build(BuildContext context) {
    final days = product.daysUntilExpiry;
    final expiryText = isExpired
        ? 'Expired ${AppTimezone.formatDate(product.expiryDate)}'
        : days != null
        ? 'Expires in $days days'
        : '';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        product.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(expiryText, style: TextStyle(fontSize: 11, color: color)),
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
