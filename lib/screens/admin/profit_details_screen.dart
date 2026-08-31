import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/providers.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../utils/app_timezone.dart';

class ProfitDetailsScreen extends ConsumerStatefulWidget {
  final String initialPeriod;
  const ProfitDetailsScreen({super.key, this.initialPeriod = 'all'});

  @override
  ConsumerState<ProfitDetailsScreen> createState() =>
      _ProfitDetailsScreenState();
}

class _ProfitDetailsScreenState extends ConsumerState<ProfitDetailsScreen> {
  List<Map<String, dynamic>> _productProfits = [];
  double _totalRevenue = 0; // Sum of final_amount (matches Business Summary)
  double _totalCOGS = 0;
  double _totalExpenses = 0;
  bool _loading = true;
  String _selectedPeriod = 'all';

  @override
  void initState() {
    super.initState();
    _selectedPeriod = widget.initialPeriod;
    _analyzeProfit();
  }

  Future<void> _analyzeProfit() async {
    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;
      final now = AppTimezone.nowIst();
      DateTime start;
      DateTime end = now;
      _totalRevenue = 0;

      switch (_selectedPeriod) {
        case 'daily':
          start = DateTime(now.year, now.month, now.day);
          break;
        case 'weekly':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          start = DateTime(weekStart.year, weekStart.month, weekStart.day);
          break;
        case 'monthly':
          start = DateTime(now.year, now.month, 1);
          break;
        default:
          start = DateTime(2020, 1, 1);
      }

      final endExclusive = end.add(const Duration(days: 1));
      final startUtc = start.toUtc().toIso8601String();
      final endUtc = endExclusive.toUtc().toIso8601String();

      // Fetch sales with date filter
      final salesRes = await client
          .from('sales')
          .select('final_amount, items')
          .gte('created_at', startUtc)
          .lt('created_at', endUtc);

      // Fetch products for COGS fallback (when purchase_price is 0 in sale items)
      final productsRes = await client
          .from('products')
          .select('id, purchase_price');
      final productCostMap = <String, double>{};
      for (final p in productsRes as List) {
        productCostMap[p['id'] as String] =
            (p['purchase_price'] as num?)?.toDouble() ?? 0;
      }

      // Fetch expenses with date filter
      final expensesRes = await client
          .from('expenses')
          .select('amount')
          .gte('created_at', startUtc)
          .lt('created_at', endUtc);
      _totalExpenses = 0;
      for (final e in expensesRes as List) {
        _totalExpenses += (e['amount'] as num?)?.toDouble() ?? 0;
      }

      // Calculate profit per product from sale items
      final Map<String, Map<String, dynamic>> productData = {};

      for (final sale in salesRes as List) {
        // Sum final_amount for revenue (matches Business Summary)
        _totalRevenue += (sale['final_amount'] as num?)?.toDouble() ?? 0;
        final items = sale['items'] as List? ?? [];
        for (final item in items) {
          final name = item['name'] as String? ?? 'Unknown';
          final tamilName = item['tamil_name'] as String?;
          final productId = item['product_id'] as String? ?? '';
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
          var costPrice = (item['purchase_price'] as num?)?.toDouble() ?? 0;
          // Fallback: use products table if purchase_price is 0
          if (costPrice <= 0) {
            costPrice = productCostMap[productId] ?? 0;
          }

          if (!productData.containsKey(name)) {
            productData[name] = {
              'name': name,
              'tamilName': tamilName,
              'qtySold': 0,
              'totalSold': 0.0,
              'totalCost': 0.0,
            };
          }
          productData[name]!['qtySold'] += qty;
          productData[name]!['totalSold'] += itemTotal;
          productData[name]!['totalCost'] += costPrice * qty;
        }
      }

      // Calculate profit for each product
      _productProfits = productData.values.map((data) {
        final sold = data['totalSold'] as double;
        final cost = data['totalCost'] as double;
        return {
          'name': data['name'],
          'tamilName': data['tamilName'],
          'qtySold': data['qtySold'],
          'totalSold': sold,
          'totalCost': cost,
          'profit': sold - cost,
          'margin': sold > 0 ? ((sold - cost) / sold * 100) : 0.0,
        };
      }).toList();

      // Sort by profit (lowest first to show losses)
      _productProfits.sort(
        (a, b) => (a['profit'] as double).compareTo(b['profit'] as double),
      );

      _totalCOGS = _productProfits.fold(
        0.0,
        (sum, p) => sum + (p['totalCost'] as double),
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _periodChip(String label, String period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        if (_selectedPeriod != period) {
          setState(() => _selectedPeriod = period);
          _analyzeProfit();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF667eea) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF667eea) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grossProfit = _totalRevenue - _totalCOGS;
    final netProfit = grossProfit - _totalExpenses;
    final margin = _totalRevenue > 0 ? (netProfit / _totalRevenue * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Profit Analysis')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      _periodChip('Daily', 'daily'),
                      const SizedBox(width: 6),
                      _periodChip('Weekly', 'weekly'),
                      const SizedBox(width: 6),
                      _periodChip('Monthly', 'monthly'),
                      const SizedBox(width: 6),
                      _periodChip('All', 'all'),
                    ],
                  ),
                ),
                // Summary card
                Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: netProfit >= 0
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: netProfit >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Sales Revenue:'),
                          Text(
                            'Rs${_totalRevenue.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cost of Goods (COGS):'),
                          Text(
                            '-Rs${_totalCOGS.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Gross Profit:'),
                          Text(
                            'Rs${grossProfit.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: grossProfit >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Expenses:'),
                          Text(
                            '-Rs${_totalExpenses.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Net Profit:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Rs${netProfit.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: netProfit >= 0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              Text(
                                'Margin: ${margin.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: netProfit >= 0
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Loss making products warning
                if (_productProfits.any((p) => (p['profit'] as double) < 0))
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_productProfits.where((p) => (p['profit'] as double) < 0).length} products sold below cost',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 8),

                // Product list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _productProfits.length,
                    itemBuilder: (context, index) {
                      final p = _productProfits[index];
                      final name = p['name'] as String;
                      final tamilName = p['tamilName'] as String?;
                      final qtySold = p['qtySold'] as int;
                      final totalSold = p['totalSold'] as double;
                      final totalCost = p['totalCost'] as double;
                      final prodProfit = p['profit'] as double;
                      final margin = p['margin'] as double;

                      final isLoss = prodProfit < 0;
                      final color = isLoss ? Colors.red : Colors.green;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          onTap: () =>
                              _editPurchasePrice(name, totalCost / qtySold),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.1),
                            child: isLoss
                                ? const Icon(
                                    Icons.trending_down,
                                    color: Colors.red,
                                    size: 18,
                                  )
                                : const Icon(
                                    Icons.trending_up,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              if (tamilName != null && tamilName.isNotEmpty)
                                Text(
                                  tamilName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            'Qty: $qtySold | Rev: Rs${totalSold.toStringAsFixed(0)} | Cost: Rs${totalCost.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // View bills button
                              GestureDetector(
                                onTap: () => _viewProductBills(name),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${prodProfit >= 0 ? '+' : ''}Rs${prodProfit.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${margin.toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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

  void _editPurchasePrice(String productName, double currentCostPrice) {
    // Find the product to get current selling price and stock
    ref.read(productServiceProvider).getAllProducts().then((products) {
      final product = products.where((p) => p.name == productName).firstOrNull;
      if (product == null) return;

      final purchaseController = TextEditingController(
        text: product.purchasePrice.toStringAsFixed(2),
      );
      final sellingController = TextEditingController(
        text: product.sellingPrice.toStringAsFixed(2),
      );
      final stockController = TextEditingController(
        text: product.stock.toString(),
      );

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Edit Product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product name
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (product.tamilName != null &&
                          product.tamilName!.isNotEmpty)
                        Text(
                          product.tamilName!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Current profit info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Analysis',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sold: ${product.stock} units in stock',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Selling: Rs${product.sellingPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Purchase: Rs${product.purchasePrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Margin: ${product.sellingPrice > 0 ? ((product.sellingPrice - product.purchasePrice) / product.sellingPrice * 100).toStringAsFixed(1) : '0'}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: product.sellingPrice > product.purchasePrice
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Editable fields
                TextField(
                  controller: purchaseController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Purchase Price (Rs)',
                    border: OutlineInputBorder(),
                    prefixText: 'Rs ',
                    helperText: 'Cost price you paid to supplier',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sellingController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Selling Price (Rs)',
                    border: OutlineInputBorder(),
                    prefixText: 'Rs ',
                    helperText: 'Price you sell to customer',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current Stock',
                    border: OutlineInputBorder(),
                    helperText: 'Units currently in inventory',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Updates apply to future transactions. Past sales retain original values.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newPurchasePrice =
                    double.tryParse(purchaseController.text) ?? 0;
                final newSellingPrice =
                    double.tryParse(sellingController.text) ?? 0;
                final newStock =
                    int.tryParse(stockController.text) ?? product.stock;

                if (newPurchasePrice <= 0 || newSellingPrice <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Prices must be greater than 0'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  final updated = Product(
                    id: product.id,
                    name: product.name,
                    barcode: product.barcode,
                    category: product.category,
                    purchasePrice: newPurchasePrice,
                    sellingPrice: newSellingPrice,
                    stock: newStock,
                    unit: product.unit,
                    lowStockAlert: product.lowStockAlert,
                    gstRate: product.gstRate,
                    hsnCode: product.hsnCode,
                    tamilName: product.tamilName,
                    hasVariants: product.hasVariants,
                    variants: product.variants,
                  );
                  await ref.read(productServiceProvider).updateProduct(updated);
                  ProductService.invalidateCache();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Updated $productName'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _analyzeProfit(); // Refresh
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    });
  }

  void _viewProductBills(String productName) async {
    final sales = await ref
        .read(saleServiceProvider)
        .getSalesHistory(limit: 500);
    final matchingSales = <Map<String, dynamic>>[];

    for (final sale in sales) {
      for (final item in sale.items) {
        if (item.name == productName) {
          matchingSales.add({
            'saleId': sale.id,
            'shortId': sale.id.length > 8
                ? sale.id.substring(0, 8).toUpperCase()
                : sale.id.toUpperCase(),
            'date': sale.createdAt,
            'qty': item.qty,
            'price': item.price,
            'total': item.total,
            'purchasePrice': item.purchasePrice,
            'profit': item.total - (item.purchasePrice * item.qty),
            'sale': sale,
          });
        }
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sale Bills - $productName'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: matchingSales.isEmpty
              ? const Center(child: Text('No sales found for this product'))
              : ListView.builder(
                  itemCount: matchingSales.length,
                  itemBuilder: (_, index) {
                    final s = matchingSales[index];
                    final date = s['date'] as DateTime;
                    final isProfit = (s['profit'] as double) >= 0;
                    return Card(
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _editSaleFromHistory(s['sale']);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Bill #${s['shortId']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '${isProfit ? '+' : ''}Rs${(s['profit'] as double).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isProfit
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateFormat('dd MMM yyyy').format(date)} | Qty: ${s['qty']} | Rs${(s['price'] as double).toStringAsFixed(0)} × ${s['qty']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Revenue: Rs${(s['total'] as double).toStringAsFixed(0)} | Cost: Rs${((s['purchasePrice'] as double) * (s['qty'] as int)).toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'TAP TO EDIT',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _editSaleFromHistory(dynamic saleData) async {
    // Ensure proper typing
    final sale = saleData as Sale;
    final saleItems = sale.items.toList();
    final purchaseControllers = <TextEditingController>[];
    final sellingControllers = <TextEditingController>[];
    for (final item in saleItems) {
      purchaseControllers.add(
        TextEditingController(text: item.purchasePrice.toStringAsFixed(2)),
      );
      sellingControllers.add(
        TextEditingController(text: item.price.toStringAsFixed(2)),
      );
    }

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Sale', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(ctx).size.height * 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date: ${DateFormat('dd MMM yyyy').format(sale.createdAt)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Product',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'Qty',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Sell Price',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Cost Price',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: saleItems.length,
                  itemBuilder: (_, index) {
                    final item = saleItems[index];
                    final margin = item.price > 0
                        ? ((item.price - item.purchasePrice) / item.price * 100)
                        : 0.0;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Margin: ${margin.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: margin >= 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                '${item.qty}',
                                style: const TextStyle(fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: sellingControllers[index],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  isDense: true,
                                  prefixText: 'Rs',
                                  hintText: 'Sell',
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: purchaseControllers[index],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  isDense: true,
                                  prefixText: 'Rs',
                                  hintText: 'Cost',
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final c in purchaseControllers) {
      c.dispose();
    }
    for (final c in sellingControllers) {
      c.dispose();
    }

    if (result == true && mounted) {
      try {
        final updatedItems = saleItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final newCost =
              double.tryParse(purchaseControllers[idx].text) ??
              item.purchasePrice;
          final newSell =
              double.tryParse(sellingControllers[idx].text) ?? item.price;
          return CartItem(
            productId: item.productId,
            name: item.name,
            tamilName: item.tamilName,
            price: newSell,
            qty: item.qty,
            unit: item.unit,
            purchasePrice: newCost,
            gstRate: item.gstRate,
            hsnCode: item.hsnCode,
            discount: item.discount,
          );
        }).toList();

        await ref
            .read(saleServiceProvider)
            .editSaleAtomic(
              saleId: sale.id,
              items: updatedItems,
              totalAmount: sale.totalAmount,
              discount: sale.discount,
              finalAmount: sale.finalAmount,
              customerId: sale.customerId,
              isCredit: sale.isCredit,
              amountPaid: sale.amountPaid,
              dueAmount: sale.dueAmount,
              paymentMethod: sale.paymentMethod,
              cashAmount: sale.cashAmount,
              digitalAmount: sale.digitalAmount,
              reason: 'Corrected prices from Profit Analysis',
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale updated'),
              backgroundColor: Colors.green,
            ),
          );
          _analyzeProfit();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}
