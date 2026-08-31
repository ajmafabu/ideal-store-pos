import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/providers.dart';
import '../../../models/product.dart';
import '../../admin/all_top_products_screen.dart';

class TopProductsSection extends ConsumerWidget {
  const TopProductsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Top Profitable Products',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllTopProductsScreen(),
                  ),
                ),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          productsAsync.when(
            loading: () => const SizedBox(height: 80),
            error: (_, __) => const SizedBox(),
            data: (products) {
              // Sort by profit margin (selling - purchase) * stock
              final profitable = products
                  .where((p) => p.sellingPrice > 0 && p.stock > 0)
                  .toList();
              profitable.sort((a, b) {
                final profitA = (a.sellingPrice - a.purchasePrice) * a.stock;
                final profitB = (b.sellingPrice - b.purchasePrice) * b.stock;
                return profitB.compareTo(profitA);
              });
              final top3 = profitable.take(3).toList();

              if (top3.isEmpty) {
                return _EmptyState(
                  icon: Icons.trending_up_rounded,
                  message: 'No profitable products yet',
                );
              }

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
                  children: top3.asMap().entries.map((entry) {
                    final i = entry.key;
                    final product = entry.value;
                    final profit =
                        (product.sellingPrice - product.purchasePrice) *
                        product.stock;
                    final margin = product.sellingPrice > 0
                        ? ((product.sellingPrice - product.purchasePrice) /
                              product.sellingPrice *
                              100)
                        : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _RankBadge(rank: i + 1),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Rs${product.sellingPrice.toStringAsFixed(0)} | Stock: ${product.stock} | Margin: ${margin.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Rs${profit.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: profit >= 0
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String text;

    switch (rank) {
      case 1:
        bgColor = const Color(0xFFFFF7E6);
        textColor = const Color(0xFFFFB800);
        text = '#1';
        break;
      case 2:
        bgColor = const Color(0xFFF0F0F0);
        textColor = const Color(0xFF9E9E9E);
        text = '#2';
        break;
      case 3:
        bgColor = const Color(0xFFFFF3E6);
        textColor = const Color(0xFFCD7F32);
        text = '#3';
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey;
        text = '#$rank';
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

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
              icon,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
