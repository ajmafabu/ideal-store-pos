import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/product.dart';
import '../../utils/error_messages.dart';
import '../../utils/qty_format.dart';

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

      // Per-product quantities over 7–90 days, aggregated by the database
      // over EVERY sale (it used to scan only the last 500 bills, so busy
      // shops saw best sellers listed as "never sold") (#24).
      final stats = await ref.read(saleServiceProvider).getProductSalesStats();
      final key = _selectedDays <= 7
          ? 'qty7d'
          : _selectedDays <= 15
              ? 'qty15d'
              : _selectedDays <= 30
                  ? 'qty30d'
                  : _selectedDays <= 60
                      ? 'qty60d'
                      : 'qty90d';
      final Map<String, double> salesCount = {}; // 0.5 kg sold is a sale (QA #60)
      final Map<String, DateTime> lastSold = {};
      stats.forEach((id, st) {
        salesCount[id] = (st[key] as num?)?.toDouble() ?? 0;
        final last = st['lastSoldAt'];
        if (last is DateTime) lastSold[id] = last;
      });
      final now = DateTime.now();

      // Slow moving: in stock, and not sold in the period or selling very
      // little against the stock held
      final slowProducts = products.where((p) {
        if (p.stock <= 0) return false;
        final soldQty = salesCount[p.id] ?? 0;
        final lastSale = lastSold[p.id];
        if (lastSale == null) return true; // no sale in 90 days
        if (soldQty <= 0 && now.difference(lastSale).inDays > _selectedDays) return true;
        if (p.stock > 20 && soldQty < 3) return true;
        return false;
      }).toList();

      slowProducts.sort((a, b) {
        final aLast = lastSold[a.id];
        final bLast = lastSold[b.id];
        if (aLast == null && bLast == null) return 0;
        if (aLast == null) return -1;
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
            content: Text('Error analyzing slow moving stock: ${ErrorMessages.parse(e)}'),
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
                      Text('No slow moving products!', style: TextStyle(fontSize: 16, color: Color(0xFF2E7D32))),
                      SizedBox(height: 8),
                      Text('All products are selling well', style: TextStyle(color: Color(0xFF757575))),
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
                          final soldQty = data['soldQty'] as num;
                          final lastSold = data['lastSold'] as DateTime?;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                                ),
                              ),
                              title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Stock: ${formatQty(product.stock)} ${product.unit} | Rs${product.sellingPrice.toStringAsFixed(0)}'),
                                  Text(
                                    lastSold != null
                                        ? 'Last sold: ${DateFormat('dd MMM yyyy').format(lastSold)} (${DateTime.now().difference(lastSold).inDays} days ago)'
                                        : 'No sale in 90+ days',
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
                                  '${formatQty(soldQty)} sold',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: soldQty == 0 ? Color(0xFFC62828) : Color(0xFFC2410C),
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
