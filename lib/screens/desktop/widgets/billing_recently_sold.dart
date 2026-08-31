import 'package:flutter/material.dart';

import '../../../models/product.dart';

class BillingRecentlySold extends StatelessWidget {
  final List<Map<String, dynamic>> recentlySold;
  final List<Product> allProducts;
  final String selectedTier;
  final void Function(Product product) onProductTap;

  const BillingRecentlySold({
    super.key,
    required this.recentlySold,
    required this.allProducts,
    required this.selectedTier,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recently Sold', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recentlySold.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = recentlySold[i];
                final product = allProducts.where((x) => x.id == p['productId']).firstOrNull;
                return GestureDetector(
                  onTap: () {
                    if (product == null) return;
                    onProductTap(product);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('Sold: ${p['qty']}', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
