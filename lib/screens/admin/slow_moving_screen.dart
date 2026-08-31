import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/product.dart';
import '../../models/sale.dart';

class SlowMovingScreen extends ConsumerStatefulWidget {
  const SlowMovingScreen({super.key});

  @override
  ConsumerState<SlowMovingScreen> createState() => _SlowMovingScreenState();
}

class _SlowMovingScreenState extends ConsumerState<SlowMovingScreen> {
  int _selectedDays = 30;
  List<Map<String, dynamic>> _slowProducts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _analyzeSlowMoving();
  }

  Future<void> _analyzeSlowMoving() async {
    setState(() => _loading = true);

    try {
      // Get all products
      final products = await ref.read(productServiceProvider).getAllProducts();

      // Get all sales from last 90 days to check selling frequency
      final sales = await ref.read(saleServiceProvider).getSalesHistory(limit: 500);

      // Count how many times each product was sold in last 90 days
      final Map<String, int> salesCount = {};
      final Map<String, DateTime> lastSold = {};

      final now = DateTime.now();
      for (final sale in sales) {
        final saleDate = sale.createdAt;
        final daysSince = now.difference(saleDate).inDays;

        for (final item in sale.items) {
          final productId = item.productId;

          // Count sales in selected period
          if (daysSince <= _selectedDays) {
            salesCount[productId] = (salesCount[productId] ?? 0) + item.qty;
          }

          // Track last sold date
          if (!lastSold.containsKey(productId) || saleDate.isAfter(lastSold[productId]!)) {
            lastSold[productId] = saleDate;
          }
        }
      }

      // Find slow-moving products:
      // - Products with stock > 0
      // - Not sold (or sold very little) in the selected period
      final slowProducts = products.where((p) {
        if (p.stock <= 0) return false; // Skip out of stock

        final soldQty = salesCount[p.id] ?? 0;
        final lastSale = lastSold[p.id];

        // If never sold or sold very little relative to stock
        if (lastSale == null) return true; // Never sold
        final daysSinceLastSale = now.difference(lastSale).inDays;

        // Slow = low sales relative to stock OR not sold recently
        if (soldQty == 0 && daysSinceLastSale > _selectedDays) return true;
        if (p.stock > 20 && soldQty < 3) return true; // High stock, low sales

        return false;
      }).toList();

      // Sort by days since last sold (oldest first)
      slowProducts.sort((a, b) {
        final aLast = lastSold[a.id];
        final bLast = lastSold[b.id];
        if (aLast == null && bLast == null) return 0;
        if (aLast == null) return -1; // Never sold first
        if (bLast == null) return 1;
        return aLast.compareTo(bLast);
      });

      if (mounted) {
        setState(() {
          _slowProducts = slowProducts.map((p) => {
            'product': p,
            'soldQty': salesCount[p.id] ?? 0,
            'lastSold': lastSold[p.id],
          }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error analyzing slow moving stock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slow Moving Stock'),
        actions: [
          // Period selector
          PopupMenuButton<int>(
            icon: Chip(
              label: Text('${_selectedDays}D', style: const TextStyle(fontSize: 12)),
              backgroundColor: Colors.orange.withValues(alpha: 0.1),
            ),
            onSelected: (days) {
              setState(() => _selectedDays = days);
              _analyzeSlowMoving();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 7, child: Text('Last 7 Days')),
              const PopupMenuItem(value: 14, child: Text('Last 14 Days')),
              const PopupMenuItem(value: 30, child: Text('Last 30 Days')),
              const PopupMenuItem(value: 60, child: Text('Last 60 Days')),
              const PopupMenuItem(value: 90, child: Text('Last 90 Days')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _slowProducts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.trending_up, size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('No slow moving products!', style: TextStyle(fontSize: 16, color: Colors.green)),
                      SizedBox(height: 8),
                      Text('All products are selling well', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_slowProducts.length} products not selling well in last $_selectedDays days. Consider promotions or discounts.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _slowProducts.length,
                        itemBuilder: (context, index) {
                          final data = _slowProducts[index];
                          final product = data['product'] as Product;
                          final soldQty = data['soldQty'] as int;
                          final lastSold = data['lastSold'] as DateTime?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                ),
                              ),
                              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Stock: ${product.stock} ${product.unit} | Rs${product.sellingPrice.toStringAsFixed(0)}'),
                                  Text(
                                    lastSold != null
                                        ? 'Last sold: ${DateFormat('dd MMM yyyy').format(lastSold)} (${DateTime.now().difference(lastSold).inDays} days ago)'
                                        : 'Never sold',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: soldQty == 0 ? Colors.red.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$soldQty sold',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: soldQty == 0 ? Colors.red : Colors.orange,
                                  ),
                                ),
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
