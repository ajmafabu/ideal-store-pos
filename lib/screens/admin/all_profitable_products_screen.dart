import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_timezone.dart';

String _inr(double v) {
  final f = NumberFormat('#,##,##0', 'en_IN');
  return '₹${f.format(v.round())}';
}

class AllProfitableProductsScreen extends StatefulWidget {
  const AllProfitableProductsScreen({super.key});

  @override
  State<AllProfitableProductsScreen> createState() => _AllProfitableProductsScreenState();
}

class _AllProfitableProductsScreenState extends State<AllProfitableProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String _sortBy = 'profit'; // profit, revenue, qty, margin

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;
      final now = AppTimezone.nowIst();
      final start = DateTime.utc(now.year, now.month, 1).subtract(AppTimezone.localOffset);
      final end = DateTime.utc(now.year, now.month, now.day + 1).subtract(AppTimezone.localOffset);

      final salesRes = await client
          .from('sales')
          .select('items')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      final productsRes = await client
          .from('products')
          .select('id, purchase_price');
      final costMap = <String, double>{};
      for (final p in productsRes as List) {
        costMap[p['id'] as String] = (p['purchase_price'] as num?)?.toDouble() ?? 0;
      }

      final Map<String, Map<String, dynamic>> productData = {};
      for (final sale in salesRes as List) {
        final items = sale['items'] as List? ?? [];
        for (final item in items) {
          final name = item['name'] as String? ?? 'Unknown';
          final productId = item['product_id'] as String? ?? '';
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
          var costPrice = (item['purchase_price'] as num?)?.toDouble() ?? 0;
          if (costPrice <= 0) costPrice = costMap[productId] ?? 0;

          if (!productData.containsKey(name)) {
            productData[name] = {
              'name': name,
              'qtySold': 0,
              'revenue': 0.0,
              'cost': 0.0,
            };
          }
          productData[name]!['qtySold'] += qty;
          productData[name]!['revenue'] += itemTotal;
          productData[name]!['cost'] += costPrice * qty;
        }
      }

      final results = productData.values.map((d) {
        final revenue = d['revenue'] as double;
        final cost = d['cost'] as double;
        final profit = revenue - cost;
        final margin = revenue > 0 ? (profit / revenue * 100) : 0.0;
        return {
          'name': d['name'],
          'qtySold': d['qtySold'],
          'revenue': revenue,
          'profit': profit,
          'margin': margin,
        };
      }).toList();

      _sortList(results);

      if (mounted) {
        setState(() {
          _products = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortList(List<Map<String, dynamic>> list) {
    switch (_sortBy) {
      case 'revenue':
        list.sort((a, b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
        break;
      case 'qty':
        list.sort((a, b) => (b['qtySold'] as int).compareTo(a['qtySold'] as int));
        break;
      case 'margin':
        list.sort((a, b) => (b['margin'] as double).compareTo(a['margin'] as double));
        break;
      default:
        list.sort((a, b) => (b['profit'] as double).compareTo(a['profit'] as double));
    }
  }

  void _resort() {
    _sortList(_products);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F5F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('All Profitable Products', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) {
              _sortBy = v;
              _resort();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profit', child: Text('Sort by Profit')),
              const PopupMenuItem(value: 'revenue', child: Text('Sort by Revenue')),
              const PopupMenuItem(value: 'qty', child: Text('Sort by Qty Sold')),
              const PopupMenuItem(value: 'margin', child: Text('Sort by Margin')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Text('No sales data this month', style: TextStyle(color: Colors.grey.shade400)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  itemBuilder: (context, i) {
                    final item = _products[i];
                    final name = item['name'] as String;
                    final qtySold = item['qtySold'] as int;
                    final revenue = item['revenue'] as double;
                    final profit = item['profit'] as double;
                    final margin = item['margin'] as double;
                    final maxProfit = _products.first['profit'] as double;
                    final ratio = maxProfit > 0 ? profit / maxProfit : 0.0;
                    final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              if (medal.isNotEmpty)
                                Text(medal, style: const TextStyle(fontSize: 18))
                              else
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                                  ),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _Tag('$qtySold sold', const Color(0xFF3B82F6)),
                                        const SizedBox(width: 6),
                                        _Tag('${_inr(revenue)} rev', const Color(0xFF6366F1)),
                                        const SizedBox(width: 6),
                                        _Tag(
                                          '${margin.toStringAsFixed(0)}%',
                                          margin >= 20
                                              ? const Color(0xFF10B981)
                                              : margin >= 10
                                                  ? const Color(0xFFF59E0B)
                                                  : const Color(0xFFEF4444),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _inr(profit),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 4,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation(
                                i == 0
                                    ? const Color(0xFF10B981)
                                    : i == 1
                                        ? const Color(0xFF3B82F6)
                                        : i == 2
                                            ? const Color(0xFF8B5CF6)
                                            : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
