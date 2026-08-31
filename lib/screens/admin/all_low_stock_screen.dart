import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/providers.dart';

class AllLowStockScreen extends ConsumerWidget {
  const AllLowStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStock = ref.watch(lowStockListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('All Low Stock Products')),
      body: lowStock.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: Colors.green,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'All stock levels are healthy!',
                    style: TextStyle(fontSize: 16, color: Colors.green),
                  ),
                ],
              ),
            );
          }

          // Sort: out of stock first, then critical, then low
          products.sort((a, b) {
            if (a.stock == 0 && b.stock != 0) return -1;
            if (a.stock != 0 && b.stock == 0) return 1;
            return a.stock.compareTo(b.stock);
          });

          final outOfStock = products.where((p) => p.stock == 0).toList();
          final critical = products
              .where(
                (p) => p.stock > 0 && p.stock <= (p.lowStockAlert * 0.5).ceil(),
              )
              .toList();
          final low = products
              .where((p) => p.stock > (p.lowStockAlert * 0.5).ceil())
              .toList();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (outOfStock.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Out of Stock',
                  count: outOfStock.length,
                  color: Colors.red,
                ),
                ...outOfStock.map(
                  (p) => _StockTile(product: p, color: Colors.red),
                ),
              ],
              if (critical.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Critical',
                  count: critical.length,
                  color: Colors.orange,
                ),
                ...critical.map(
                  (p) => _StockTile(product: p, color: Colors.orange),
                ),
              ],
              if (low.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Low Stock',
                  count: low.length,
                  color: Colors.indigo,
                ),
                ...low.map((p) => _StockTile(product: p, color: Colors.indigo)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$label ($count)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 13,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.inventory_2, color: color, size: 20),
        ),
        title: Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'Stock: ${product.stock} ${product.unit} | Price: Rs${product.sellingPrice.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${product.stock}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
