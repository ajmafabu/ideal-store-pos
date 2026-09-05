import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/product.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../services/barcode_service.dart';
import '../../utils/app_timezone.dart';
import '../../widgets/barcode_scanner.dart';
import '../../utils/error_messages.dart';
import '../../widgets/empty_state.dart';
import 'product_form_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  final String? initialFilter;
  const InventoryScreen({super.key, this.initialFilter});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _searchQuery = '';
  String? _selectedCategory;
  String _sortBy = 'name';
  List<String> _categories = [];
  String _batchSearch = '';
  double? _stockMin;
  double? _stockMax;
  double? _priceMin;
  double? _priceMax;
  bool _isGridView = false;
  bool _showFilters = false;
  Set<String> _activeFilters = {};
  Map<String, Map<String, dynamic>> _productSalesStats = {};
  List<Product> _filteredProducts = [];
  Set<String> _duplicateNames = {};
  Set<String> _duplicateBarcodes = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _activeFilters.add(widget.initialFilter!);
    }
    _loadCategories();
    _loadSalesStats();
  }

  Future<void> _loadSalesStats() async {
    final stats = await ref.read(saleServiceProvider).getProductSalesStats();
    if (mounted) setState(() => _productSalesStats = stats);
  }

  Future<void> _loadCategories() async {
    final categories = await ref.read(productServiceProvider).getCategories();
    setState(() => _categories = categories);
  }

  void _openAddProduct({String? barcode}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(barcode: barcode)),
    ).then((_) {
      ref.invalidate(productsProvider);
      _loadCategories();
    });
  }

  void _openEditProduct(Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    ).then((_) {
      ref.invalidate(productsProvider);
      _loadCategories();
    });
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result != null && mounted) {
      final product = await ref
          .read(productServiceProvider)
          .getProductByBarcode(result);
      if (product != null && mounted) {
        _showStockDialog(product);
      } else if (mounted) {
        _showProductNotFound(result);
      }
    }
  }

  void _showProductNotFound(String barcode) async {
    // Show loading while looking up in Indian barcode database
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final barcodeProduct = await BarcodeService.lookup(barcode);

    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    if (barcodeProduct != null) {
      // Found in Indian barcode database — show details and create
      _showApiProductDialog(barcode, barcodeProduct);
    } else {
      // Not found anywhere — manual create with hint
      _showManualCreateDialog(barcode);
    }
  }

  void _showApiProductDialog(String barcode, BarcodeProduct apiProduct) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, size: 48, color: Colors.green),
        title: const Text('Product Found in Database!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (apiProduct.brand.isNotEmpty)
              Text(
                '${apiProduct.brand} ${apiProduct.name}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            if (apiProduct.brand.isEmpty)
              Text(
                apiProduct.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            if (apiProduct.category.isNotEmpty)
              Text('Category: ${apiProduct.category}'),
            if (apiProduct.mrp != null)
              Text(
                'MRP: Rs${apiProduct.mrp}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            Text(
              'Barcode: $barcode',
              style: TextStyle(color: Colors.grey[600], fontSize: 11),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap below to add this product to your inventory.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(
                    barcode: barcode,
                    prefilledName: apiProduct.brand.isNotEmpty
                        ? '${apiProduct.brand} ${apiProduct.name}'.trim()
                        : apiProduct.name,
                    prefilledCategory: apiProduct.category,
                    prefilledSellingPrice: apiProduct.mrp,
                  ),
                ),
              );
              if (result == true) {
                ref.invalidate(productsProvider);
                _loadCategories();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add to Inventory'),
          ),
        ],
      ),
    );
  }

  void _showManualCreateDialog(String barcode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.search_off, size: 48, color: Colors.orange),
        title: const Text('Product Not Found'),
        content: Text(
          'Barcode "$barcode" not found in database.\n\nCreate this product manually?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _openAddProduct(barcode: barcode);
            },
            icon: const Icon(Icons.add),
            label: const Text('Create New Product'),
          ),
        ],
      ),
    );
  }

  void _showStockDialog(Product product) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Stock: ${product.stock} ${product.unit}'),
            Text('Price: ₹${product.sellingPrice}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final qty = int.tryParse(controller.text) ?? 0;
              if (qty > 0) {
                await ref
                    .read(productServiceProvider)
                    .addStock(product.id, qty);
                ref.invalidate(productsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text(
              'Stock In',
              style: TextStyle(color: Colors.green),
            ),
          ),
          TextButton(
            onPressed: () async {
              final qty = int.tryParse(controller.text) ?? 0;
              if (qty > 0 && qty <= product.stock) {
                await ref
                    .read(productServiceProvider)
                    .deductStock(product.id, qty);
                ref.invalidate(productsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text(
              'Stock Out',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickStockSheet() {
    List<Product> allProducts = [];
    List<Product> filteredProducts = [];
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          // Load products if empty
          if (allProducts.isEmpty) {
            ref.read(productServiceProvider).getAllProducts().then((products) {
              setSheetState(() {
                allProducts = products;
                filteredProducts = products;
              });
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.inventory, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Quick Stock',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Search product to add/remove stock',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search product name...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        autofocus: true,
                        onChanged: (v) {
                          setSheetState(() {
                            searchQuery = v.toLowerCase();
                            filteredProducts = allProducts
                                .where(
                                  (p) => p.name.toLowerCase().contains(
                                    searchQuery,
                                  ),
                                )
                                .toList();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Product list
                Expanded(
                  child: filteredProducts.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: product.stock == 0
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : product.isLowStock
                                    ? Colors.orange.withValues(alpha: 0.1)
                                    : Colors.green.withValues(alpha: 0.1),
                                child: Text(
                                  '${product.stock}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: product.stock == 0
                                        ? Colors.red
                                        : product.isLowStock
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ),
                              ),
                              title: Text(
                                product.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                'Rs${product.sellingPrice.toStringAsFixed(0)} | ${product.unit}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(ctx);
                                _showStockDialog(product);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showStockReconciliation() {
    List<Product> allProducts = [];
    List<Product> filteredProducts = [];
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          if (allProducts.isEmpty) {
            ref.read(productServiceProvider).getAllProducts().then((products) {
              setSheetState(() {
                allProducts = products;
                filteredProducts = products;
              });
            });
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.fact_check, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Stock Reconciliation',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Compare system qty vs physical count',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search product...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        autofocus: true,
                        onChanged: (v) {
                          setSheetState(() {
                            searchQuery = v.toLowerCase();
                            filteredProducts = allProducts
                                .where(
                                  (p) => p.name.toLowerCase().contains(
                                    searchQuery,
                                  ),
                                )
                                .toList();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filteredProducts.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            return _ReconciliationRow(
                              product: product,
                              ref: ref,
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _rebuildFilteredProducts(List<Product> products) {
    final seenNames = <String>{};
    _duplicateNames = {};
    for (final p in products) {
      final lower = p.name.toLowerCase();
      if (seenNames.contains(lower)) {
        _duplicateNames.add(lower);
      }
      seenNames.add(lower);
    }

    final seenBarcodes = <String>{};
    _duplicateBarcodes = {};
    for (final p in products) {
      if (p.barcode != null && p.barcode!.isNotEmpty) {
        if (seenBarcodes.contains(p.barcode!)) {
          _duplicateBarcodes.add(p.barcode!);
        }
        seenBarcodes.add(p.barcode!);
      }
    }

    final searchQ = _searchQuery.replaceAll(RegExp(r'\broses?\b'), 'rose');
    var filtered = products.where((p) {
      final pName = p.name.toLowerCase().replaceAll(RegExp(r'\broses?\b'), 'rose');
      final matchesSearch = pName.contains(searchQ) ||
          (p.barcode?.toLowerCase().contains(_searchQuery) ?? false) ||
          (p.tamilName?.toLowerCase().contains(_searchQuery) ?? false) ||
          (_batchSearch.isNotEmpty &&
              (p.batchNumber?.toLowerCase().contains(_batchSearch) ?? false));
      final matchesCategory = _selectedCategory == null || p.category == _selectedCategory;
      bool matchesStockRange = true;
      if (_stockMin != null && p.stock < _stockMin!) matchesStockRange = false;
      if (_stockMax != null && p.stock > _stockMax!) matchesStockRange = false;
      bool matchesPriceRange = true;
      if (_priceMin != null && p.sellingPrice < _priceMin!) matchesPriceRange = false;
      if (_priceMax != null && p.sellingPrice > _priceMax!) matchesPriceRange = false;
      bool matchesFilters = true;
      if (_activeFilters.isNotEmpty) {
        for (final filter in _activeFilters) {
          final stockVal = p.totalStock;
          final value = stockVal * p.sellingPrice;
          final costWorth = stockVal * p.purchasePrice;
          bool match = true;
          switch (filter) {
            case 'out_of_stock': match = stockVal == 0; break;
            case 'low_stock': match = stockVal > 0 && p.lowStockAlert > 0 && stockVal <= p.lowStockAlert; break;
            case 'excess': match = p.lowStockAlert > 0 && stockVal > p.lowStockAlert * 3; break;
            case 'negative': match = stockVal < 0; break;
            case 'fast_moving': final s = _productSalesStats[p.id]; match = s != null && (s['qty7d'] as int) >= 10; break;
            case 'slow_moving': final s = _productSalesStats[p.id]; match = s != null && (s['qty7d'] as int) > 0 && (s['qty7d'] as int) < 3; break;
            case 'no_sales': match = !_productSalesStats.containsKey(p.id); break;
            case 'sold_today': final s = _productSalesStats[p.id]; match = s != null && (s['qtyToday'] as int) > 0; break;
            case 'sold_7d': final s = _productSalesStats[p.id]; match = s != null && (s['qty7d'] as int) > 0; break;
            case 'sold_30d': final s = _productSalesStats[p.id]; match = s != null && (s['qty30d'] as int) > 0; break;
            case 'no_move_7d': final s = _productSalesStats[p.id]; match = s == null || (s['qty7d'] as int) == 0; break;
            case 'no_move_30d': final s = _productSalesStats[p.id]; match = s == null || (s['qty30d'] as int) == 0; break;
            case 'no_move_60d': final s = _productSalesStats[p.id]; match = s == null || (s['qty60d'] as int) == 0; break;
            case 'no_move_90d': final s = _productSalesStats[p.id]; match = s == null || (s['qty90d'] as int) == 0; break;
            case 'high_stock_value': match = value > 100000; break;
            case 'med_stock_value': match = value >= 10000 && value <= 100000; break;
            case 'low_stock_value': match = value > 0 && value < 10000; break;
            case 'missing_purchase': match = p.purchasePrice == 0; break;
            case 'missing_barcode': match = p.barcode == null || p.barcode!.isEmpty; break;
            case 'dup_product': match = _duplicateNames.contains(p.name.toLowerCase()); break;
            case 'dup_barcode': match = p.barcode != null && p.barcode!.isNotEmpty && _duplicateBarcodes.contains(p.barcode); break;
            case 'wrong_purchase': match = p.purchasePrice == 0 || p.purchasePrice < 0; break;
            case 'wrong_selling': match = p.sellingPrice == 0 || p.sellingPrice < 0; break;
            case 'no_tamil': match = p.tamilName == null || p.tamilName!.isEmpty; break;
            case 'no_category': match = p.category == null || p.category!.isEmpty; break;
            case 'expiring': match = p.isExpiringSoon && !p.isExpired; break;
            case 'expired': match = p.isExpired; break;
            case 'below_cost': match = p.sellingPrice > 0 && p.sellingPrice <= p.purchasePrice; break;
            case 'zero_price': match = p.sellingPrice == 0; break;
            case 'has_variants': match = p.hasVariants; break;
            case 'no_variants': match = !p.hasVariants; break;
            default:
              if (filter.startsWith('cat_')) {
                final cat = filter.substring(4);
                match = p.category == cat;
              }
              break;
          }
          if (!match) { matchesFilters = false; break; }
        }
      }
      return matchesSearch && matchesCategory && matchesStockRange && matchesPriceRange && matchesFilters;
    }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'qty_asc': return a.stock.compareTo(b.stock);
        case 'qty_desc': return b.stock.compareTo(a.stock);
        case 'price_asc': return a.sellingPrice.compareTo(b.sellingPrice);
        case 'price_desc': return b.sellingPrice.compareTo(a.sellingPrice);
        case 'value_asc': return (a.stock * a.sellingPrice).compareTo(b.stock * b.sellingPrice);
        case 'value_desc': return (b.stock * b.sellingPrice).compareTo(a.stock * a.sellingPrice);
        case 'name_desc': return b.name.compareTo(a.name);
        default: return a.name.compareTo(b.name);
      }
    });

    _filteredProducts = filtered;
  }

  Widget _buildFilterSection(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 0, children: chips),
        ],
      ),
    );
  }

  String _filterLabel(String value) {
    const labels = {
      'out_of_stock': 'Out of Stock', 'low_stock': 'Low Stock', 'excess': 'Excess',
      'negative': 'Negative', 'fast_moving': 'Fast', 'slow_moving': 'Slow',
      'no_sales': 'No Sales', 'sold_today': 'Today', 'sold_7d': '7 Days',
      'sold_30d': '30 Days', 'no_move_7d': 'No Move 7d', 'no_move_30d': 'No Move 30d',
      'no_move_60d': 'No Move 60d', 'no_move_90d': 'No Move 90d',
      'high_stock_value': 'High Value', 'med_stock_value': 'Med Value', 'low_stock_value': 'Low Value',
      'missing_purchase': 'No Purchase', 'missing_barcode': 'No Barcode',
      'dup_product': 'Dup Product', 'dup_barcode': 'Dup Barcode',
      'wrong_purchase': 'Wrong Cost', 'wrong_selling': 'Wrong Price',
      'no_tamil': 'No Tamil', 'no_category': 'No Category',
      'expiring': 'Expiring', 'expired': 'Expired',
      'below_cost': 'Below Cost', 'zero_price': 'Zero Price',
      'has_variants': 'Has Variants', 'no_variants': 'No Variants',
    };
    if (value.startsWith('cat_')) return value.substring(4);
    return labels[value] ?? value;
  }

  Widget _buildFilterChip(String label, String? value) {
    final isAll = value == null;
    final selected = isAll ? _activeFilters.isEmpty : _activeFilters.contains(value);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.black87)),
        selected: selected,
        selectedColor: const Color(0xFF667eea),
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        onSelected: (_) => setState(() {
          if (isAll) {
            _activeFilters.clear();
          } else {
            if (_activeFilters.contains(value)) {
              _activeFilters.remove(value);
            } else {
              _activeFilters.add(value);
            }
          }
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(productsProvider);
              _loadSalesStats();
              _loadCategories();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Inventory refreshed'),
                  backgroundColor: Color(0xFF059669),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List View' : 'Grid View',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportPdf,
            tooltip: 'Export PDF',
          ),
          IconButton(
            icon: const Icon(Icons.fact_check),
            onPressed: _showStockReconciliation,
            tooltip: 'Stock Reconciliation',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanBarcode,
            tooltip: 'Scan Barcode',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search + Sort row (shared)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      isDense: true,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      items: const [
                        DropdownMenuItem(value: 'name', child: Text('Name A-Z')),
                        DropdownMenuItem(value: 'name_desc', child: Text('Name Z-A')),
                        DropdownMenuItem(value: 'qty_asc', child: Text('Stock ↑')),
                        DropdownMenuItem(value: 'qty_desc', child: Text('Stock ↓')),
                        DropdownMenuItem(value: 'price_asc', child: Text('Price ↑')),
                        DropdownMenuItem(value: 'price_desc', child: Text('Price ↓')),
                        DropdownMenuItem(value: 'value_asc', child: Text('Value ↑')),
                        DropdownMenuItem(value: 'value_desc', child: Text('Value ↓')),
                      ],
                      onChanged: (v) => setState(() => _sortBy = v ?? 'name'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Filter toggle bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ActionChip(
                  avatar: Icon(
                    _showFilters ? Icons.filter_list_off : Icons.filter_list,
                    size: 18,
                  ),
                  label: Text(
                    _activeFilters.isEmpty
                        ? 'Filters'
                        : 'Filters (${_activeFilters.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () => setState(() => _showFilters = !_showFilters),
                  backgroundColor: _activeFilters.isNotEmpty
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                if (_activeFilters.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _activeFilters.clear()),
                    child: Text(
                      'Clear all',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_categories.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      children: [
                        _buildFilterChip('All', null),
                        ..._categories.map((cat) => _buildFilterChip(cat, 'cat_$cat')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Expandable filter panel
          if (_showFilters) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilterSection('Stock Health', [
                      _buildFilterChip('Out of Stock', 'out_of_stock'),
                      _buildFilterChip('Low Stock', 'low_stock'),
                      _buildFilterChip('Excess Stock', 'excess'),
                      _buildFilterChip('Negative Stock', 'negative'),
                    ]),
                    _buildFilterSection('Sales Velocity', [
                      _buildFilterChip('Fast Moving', 'fast_moving'),
                      _buildFilterChip('Slow Moving', 'slow_moving'),
                      _buildFilterChip('No Sales', 'no_sales'),
                      _buildFilterChip('Sold Today', 'sold_today'),
                      _buildFilterChip('Sold Last 7 Days', 'sold_7d'),
                      _buildFilterChip('Sold Last 30 Days', 'sold_30d'),
                    ]),
                    _buildFilterSection('No Movement', [
                      _buildFilterChip('No Move 7 Days', 'no_move_7d'),
                      _buildFilterChip('No Move 30 Days', 'no_move_30d'),
                      _buildFilterChip('No Move 60 Days', 'no_move_60d'),
                      _buildFilterChip('No Move 90 Days', 'no_move_90d'),
                    ]),
                    _buildFilterSection('Stock Value', [
                      _buildFilterChip('High Stock Value', 'high_stock_value'),
                      _buildFilterChip('Medium Stock Value', 'med_stock_value'),
                      _buildFilterChip('Low Stock Value', 'low_stock_value'),
                    ]),
                    _buildFilterSection('Data Quality', [
                      _buildFilterChip('Missing Purchase', 'missing_purchase'),
                      _buildFilterChip('Missing Barcode', 'missing_barcode'),
                      _buildFilterChip('Duplicate Product', 'dup_product'),
                      _buildFilterChip('Duplicate Barcode', 'dup_barcode'),
                      _buildFilterChip('Wrong Purchase Price', 'wrong_purchase'),
                      _buildFilterChip('Wrong Selling Price', 'wrong_selling'),
                      _buildFilterChip('No Tamil Name', 'no_tamil'),
                      _buildFilterChip('No Category', 'no_category'),
                      _buildFilterChip('Expiring Soon', 'expiring'),
                      _buildFilterChip('Expired', 'expired'),
                      _buildFilterChip('Below Cost', 'below_cost'),
                      _buildFilterChip('Zero Price', 'zero_price'),
                      _buildFilterChip('Has Variants', 'has_variants'),
                      _buildFilterChip('No Variants', 'no_variants'),
                    ]),
                  ],
                ),
              ),
            ),
          ],
          // Active filter chips (when panel collapsed)
          if (!_showFilters && _activeFilters.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: _activeFilters.where((f) => f.isNotEmpty).map((f) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildFilterChip(_filterLabel(f), f),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(productsProvider);
                _loadCategories();
              },
              child: productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(ErrorMessages.parse(e))),
                data: (products) {
                  _rebuildFilteredProducts(products);
                  final filtered = _filteredProducts;

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'No Products',
                      subtitle: 'Add products to get started',
                      actionLabel: 'Add Product',
                      onAction: () => _openAddProduct(),
                    );
                  }

                  if (_isGridView) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 1.5,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        return _buildGridItem(product);
                      },
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final product = filtered[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: product.isExpired
                                ? Colors.red.shade100
                                : product.isExpiringSoon
                                ? Colors.orange.shade100
                                : product.isLowStock
                                ? Colors.red.shade100
                                : Colors.green.shade100,
                            child: Icon(
                              product.isExpired
                                  ? Icons.event_busy
                                  : product.isExpiringSoon
                                  ? Icons.warning_amber_rounded
                                  : product.isLowStock
                                  ? Icons.warning
                                  : Icons.check,
                              color: product.isExpired
                                  ? Colors.red
                                  : product.isExpiringSoon
                                  ? Colors.orange
                                  : product.isLowStock
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (product.isExpired)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'EXPIRED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else if (product.isExpiringSoon)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${product.daysUntilExpiry}d left',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Rs.${product.sellingPrice} | Stock: ${product.stock} ${product.unit} | Worth: Rs.${(product.stock * product.purchasePrice).toStringAsFixed(0)}',
                              ),
                              if (product.expiryDate != null)
                                Text(
                                  'Exp: ${product.expiryDate!.day}/${product.expiryDate!.month}/${product.expiryDate!.year}${product.batchNumber != null ? ' | Batch: ${product.batchNumber}' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: product.isExpired
                                        ? Colors.red
                                        : product.isExpiringSoon
                                        ? Colors.orange
                                        : Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openEditProduct(product),
                          onLongPress: () => _showStockDialog(product),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick Stock Button
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.deepOrange],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: _showQuickStockSheet,
              backgroundColor: Colors.transparent,
              elevation: 0,
              heroTag: 'quickStock',
              child: const Icon(Icons.inventory, color: Colors.white),
            ),
          ),
          // Add Product Button
          Container(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667eea).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: () => _openAddProduct(),
              backgroundColor: Colors.transparent,
              elevation: 0,
              heroTag: 'addProduct',
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  List<Product> _getFilteredProducts(List<Product> products) {
    _rebuildFilteredProducts(products);
    return _filteredProducts;
  }

  static final _pdfCurrencyFormat = NumberFormat.currency(symbol: 'Rs ', decimalDigits: 2);
  static final _pdfDateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  static pw.Font? _pdfNotoSans;
  static pw.Font? _pdfNotoSansTamil;

  static Future<pw.Font> _getPdfFont() async {
    _pdfNotoSans ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    return _pdfNotoSans!;
  }

  static Future<pw.Font> _getPdfTamilFont() async {
    _pdfNotoSansTamil ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansTamil-Regular.ttf'));
    return _pdfNotoSansTamil!;
  }

  Future<void> _exportPdf() async {
    try {
      final productsAsync = ref.read(productsProvider);
      final products = productsAsync.value;
      if (products == null || products.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No products to export')));
        return;
      }

      final filtered = _getFilteredProducts(products);
      if (filtered.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No products match current filters')));
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Generating PDF for ${filtered.length} products...'),
          duration: const Duration(seconds: 2),
        ));
      }

      final f = await _getPdfFont();
      final ft = await _getPdfTamilFont();
      final now = AppTimezone.nowIst();
      final dateStr = _pdfDateFormat.format(now);

      final totalStockValue = filtered.fold(0.0, (sum, p) => sum + (p.stock * p.purchasePrice));
      final totalSellingValue = filtered.fold(0.0, (sum, p) => sum + (p.stock * p.sellingPrice));
      final totalStockQty = filtered.fold(0, (sum, p) => sum + p.stock);

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.portrait,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('IDEAL STORE', style: pw.TextStyle(font: f, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text(dateStr, style: pw.TextStyle(font: f, fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text('Inventory Report', style: pw.TextStyle(font: f, fontSize: 13, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text(
                '${filtered.length} products | Total Qty: $totalStockQty | Stock Value: ${_pdfCurrencyFormat.format(totalStockValue)} | Selling Value: ${_pdfCurrencyFormat.format(totalSellingValue)}',
                style: pw.TextStyle(font: f, fontSize: 8, color: PdfColors.grey600),
              ),
              pw.Divider(height: 10, color: PdfColors.grey400),
            ],
          ),
          footer: (context) => pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount} | IDEAL STORE',
              style: pw.TextStyle(font: f, fontSize: 7, color: PdfColors.grey),
            ),
          ),
          build: (context) => [
            // Custom table with Tamil support
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1.3),
                5: const pw.FlexColumnWidth(1.3),
                6: const pw.FlexColumnWidth(1.3),
                7: const pw.FlexColumnWidth(1),
              },
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor(0.33, 0.42, 0.92)),
                  children: ['#', 'Product Name', 'Category', 'Qty', 'Purchase Price', 'Selling Price', 'Stock Value', 'Expiry']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            child: pw.Text(h, style: pw.TextStyle(font: f, fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                          ))
                      .toList(),
                ),
                // Data rows
                ...filtered.asMap().entries.map((entry) {
                  final i = entry.key + 1;
                  final p = entry.value;
                  final expiry = p.expiryDate != null ? DateFormat('dd/MM/yy').format(p.expiryDate!) : '-';
                  final isOdd = i.isOdd;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isOdd ? const PdfColor(0.97, 0.97, 0.97) : PdfColors.white,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text('$i', style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(p.name, style: pw.TextStyle(font: f, fontSize: 7)),
                            if (p.tamilName != null && p.tamilName!.isNotEmpty)
                              pw.Text(p.tamilName!, style: pw.TextStyle(font: ft, fontSize: 6, color: PdfColors.grey600)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text(p.category ?? '-', style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text('${p.stock} ${p.unit}', style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text(_pdfCurrencyFormat.format(p.purchasePrice), style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text(_pdfCurrencyFormat.format(p.sellingPrice), style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text(_pdfCurrencyFormat.format(p.stock * p.purchasePrice), style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: pw.Text(expiry, style: pw.TextStyle(font: f, fontSize: 7)),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor(0.95, 0.95, 0.95),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total: ${filtered.length} products', style: pw.TextStyle(font: f, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Qty: $totalStockQty', style: pw.TextStyle(font: f, fontSize: 9)),
                  pw.Text('Stock Value: ${_pdfCurrencyFormat.format(totalStockValue)}', style: pw.TextStyle(font: f, fontSize: 9)),
                  pw.Text('Selling Value: ${_pdfCurrencyFormat.format(totalSellingValue)}', style: pw.TextStyle(font: f, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final dateStamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Inventory_Report_$dateStamp.pdf',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF export failed: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Widget _buildGridItem(Product product) {
    return Card(
      child: InkWell(
        onTap: () => _openEditProduct(product),
        onLongPress: () => _showStockDialog(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (product.isExpired)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'EXP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (product.isExpiringSoon)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${product.daysUntilExpiry}d',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Rs.${product.sellingPrice}',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    product.isLowStock ? Icons.warning : Icons.check,
                    size: 12,
                    color: product.isLowStock ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${product.stock} ${product.unit}',
                    style: TextStyle(
                      fontSize: 11,
                      color: product.isLowStock ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
              Text(
                'Worth: Rs.${(product.stock * product.purchasePrice).toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
              ),
              if (product.expiryDate != null)
                Text(
                  'Exp: ${product.expiryDate!.day}/${product.expiryDate!.month}/${product.expiryDate!.year}',
                  style: TextStyle(
                    fontSize: 9,
                    color: product.isExpired ? Colors.red : Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorFilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ExpiryFilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _ExpiryFilterChip({
    required this.label,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? chipColor : chipColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? chipColor : chipColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : chipColor,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Colors.teal,
        checkmarkColor: Colors.white,
        backgroundColor: Colors.grey.shade100,
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ReconciliationRow extends StatefulWidget {
  final Product product;
  final WidgetRef ref;

  const _ReconciliationRow({required this.product, required this.ref});

  @override
  State<_ReconciliationRow> createState() => _ReconciliationRowState();
}

class _ReconciliationRowState extends State<_ReconciliationRow> {
  late final TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: '${widget.product.stock}');
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.product.name),
      subtitle: Text('System Qty: ${widget.product.stock}'),
      trailing: SizedBox(
        width: 120,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Physical',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.save, size: 18, color: Colors.green),
              onPressed: () async {
                final physicalQty =
                    int.tryParse(_qtyController.text) ?? widget.product.stock;
                final success = await widget.ref
                    .read(productServiceProvider)
                    .reconcileStock(
                      widget.product.id,
                      physicalQty,
                      notes: 'Stock reconciliation',
                    );
                widget.ref.invalidate(productsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? '${widget.product.name}: ${widget.product.stock} → $physicalQty'
                            : 'Reconciliation saved but stock update failed. Check manually.',
                      ),
                      backgroundColor: success
                          ? (physicalQty >= widget.product.stock
                                ? Colors.green
                                : Colors.orange)
                          : Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
