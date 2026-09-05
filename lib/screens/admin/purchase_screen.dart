import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../utils/logger.dart';
import 'package:printing/printing.dart';
import '../../models/purchase.dart';
import '../../models/product.dart';
import '../../models/supplier.dart';
import '../../config/providers.dart';
import '../../services/barcode_service.dart';
import '../../services/product_service.dart';
import '../../widgets/barcode_scanner.dart';
import '../../utils/purchase_invoice_generator.dart';
import '../../widgets/empty_state.dart';
import '../shared/product_form_screen.dart';

class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key});

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen>
    with SingleTickerProviderStateMixin {
  final List<PurchaseItem> _cart = [];
  final _searchController = TextEditingController();
  final _amountPaidController = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<Supplier> _suppliers = [];
  Supplier? _selectedSupplier;
  String _supplierSearchQuery = '';
  bool _isCredit = false;
  String _paymentMethod = 'cash';
  bool _isLoading = false;
  TabController? _tabController;

  double get _total => _cart.fold(0.0, (sum, item) => sum + item.total);
  double get _amountPaid =>
      _isCredit ? (double.tryParse(_amountPaidController.text) ?? 0) : _total;
  double get _dueAmount => _isCredit ? (_total - _amountPaid) : 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(_onTabChange);
    _loadProducts();
    _loadSuppliers();
  }

  void _onTabChange() {
    if (_tabController?.index == 1) {
      ref.invalidate(purchasesProvider);
    }
  }

  Future<void> _loadProducts() async {
    final products = await ref.read(productServiceProvider).getAllProducts();
    setState(() {
      _allProducts = products;
      _filteredProducts = products;
    });
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await ref.read(supplierServiceProvider).getSuppliers();
      if (mounted) {
        setState(() => _suppliers = suppliers);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load suppliers: $e')));
      }
    }
  }

  void _addToCart(Product product) {
    final batchController = TextEditingController();
    final priceController = TextEditingController(
      text: product.purchasePrice.toStringAsFixed(2),
    );
    final sellPriceController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    DateTime? expiryDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(product.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.purchasePrice > 0 || product.sellingPrice > 0)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product.purchasePrice > 0)
                        Row(
                          children: [
                            const Icon(
                              Icons.history,
                              size: 16,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Past Purchase: Rs${product.purchasePrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      if (product.sellingPrice > 0)
                        Row(
                          children: [
                            const Icon(
                              Icons.sell,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Current Selling: Rs${product.sellingPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Purchase Price *',
                  border: OutlineInputBorder(),
                  prefixText: 'Rs ',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sellPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Selling Price *',
                  border: OutlineInputBorder(),
                  prefixText: 'Rs ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: batchController,
                decoration: const InputDecoration(
                  labelText: 'Batch Number (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., BATCH001',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry Date'),
                subtitle: Text(
                  expiryDate != null
                      ? '${expiryDate!.day}/${expiryDate!.month}/${expiryDate!.year}'
                      : 'Not set (tap to set)',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate:
                        expiryDate ??
                        DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) {
                    setDialogState(() => expiryDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final newPrice =
                    double.tryParse(priceController.text) ??
                    product.purchasePrice;
                final newSellPrice =
                    double.tryParse(sellPriceController.text) ??
                    product.sellingPrice;
                if (newPrice <= 0 || newSellPrice <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Enter valid prices')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                // Update product prices in DB if changed
                if (newPrice != product.purchasePrice ||
                    newSellPrice != product.sellingPrice) {
                  ref
                      .read(productServiceProvider)
                      .updateProduct(
                        Product(
                          id: product.id,
                          name: product.name,
                          barcode: product.barcode,
                          category: product.category,
                          purchasePrice: newPrice,
                          sellingPrice: newSellPrice,
                          stock: product.stock,
                          unit: product.unit,
                          lowStockAlert: product.lowStockAlert,
                          shopId: product.shopId,
                          gstRate: product.gstRate,
                          hsnCode: product.hsnCode,
                          expiryDate: product.expiryDate,
                          batchNumber: product.batchNumber,
                          hasVariants: product.hasVariants,
                          variants: product.variants,
                          tamilName: product.tamilName,
                          sfw: product.sfw,
                          unitType: product.unitType,
                          piecesPerUnit: product.piecesPerUnit,
                        ),
                      );
                }
                setState(() {
                  final existing = _cart.indexWhere(
                    (c) => c.productId == product.id,
                  );
                  if (existing >= 0) {
                    _cart[existing].qty += 1;
                  } else {
                    _cart.add(
                      PurchaseItem(
                        productId: product.id,
                        name: product.name,
                        price: newPrice,
                        qty: 1,
                        unit: product.unit,
                        gstRate: product.gstRate,
                        hsnCode: product.hsnCode,
                        batchNumber: batchController.text.isNotEmpty
                            ? batchController.text
                            : null,
                        expiryDate: expiryDate,
                      ),
                    );
                  }
                });
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateQty(int index, int delta) {
    setState(() {
      final newQty = _cart[index].qty + delta;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index].qty = newQty;
      }
    });
  }

  void _removeFromCart(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _editItemPrice(int index) {
    final item = _cart[index];
    final priceController = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );
    // Find the original product to show past price
    final product = _allProducts.firstWhere(
      (p) => p.id == item.productId,
      orElse: () => Product(
        id: '',
        name: '',
        purchasePrice: 0,
        sellingPrice: 0,
        stock: 0,
        unit: '',
      ),
    );
    final sellPriceController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Price - ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product.purchasePrice > 0 || product.sellingPrice > 0)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.purchasePrice > 0)
                      Row(
                        children: [
                          const Icon(
                            Icons.history,
                            size: 16,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'DB Purchase: Rs${product.purchasePrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    if (product.sellingPrice > 0)
                      Row(
                        children: [
                          const Icon(Icons.sell, size: 16, color: Colors.green),
                          const SizedBox(width: 6),
                          Text(
                            'DB Selling: Rs${product.sellingPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('Cart Price: Rs ${item.price.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'New Purchase Price',
                border: OutlineInputBorder(),
                prefixText: 'Rs ',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sellPriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'New Selling Price',
                border: OutlineInputBorder(),
                prefixText: 'Rs ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newPrice = double.tryParse(priceController.text);
              final newSellPrice = double.tryParse(sellPriceController.text);
              if (newPrice != null &&
                  newPrice > 0 &&
                  newSellPrice != null &&
                  newSellPrice > 0) {
                // Update product prices in DB
                if (product.id.isNotEmpty &&
                    (newPrice != product.purchasePrice ||
                        newSellPrice != product.sellingPrice)) {
                  ref
                      .read(productServiceProvider)
                      .updateProduct(
                        Product(
                          id: product.id,
                          name: product.name,
                          barcode: product.barcode,
                          category: product.category,
                          purchasePrice: newPrice,
                          sellingPrice: newSellPrice,
                          stock: product.stock,
                          unit: product.unit,
                          lowStockAlert: product.lowStockAlert,
                          shopId: product.shopId,
                          gstRate: product.gstRate,
                          hsnCode: product.hsnCode,
                          expiryDate: product.expiryDate,
                          batchNumber: product.batchNumber,
                          hasVariants: product.hasVariants,
                          variants: product.variants,
                          tamilName: product.tamilName,
                          sfw: product.sfw,
                          unitType: product.unitType,
                          piecesPerUnit: product.piecesPerUnit,
                        ),
                      );
                }
                setState(() {
                  _cart[index] = PurchaseItem(
                    productId: item.productId,
                    name: item.name,
                    price: newPrice,
                    qty: item.qty,
                    unit: item.unit,
                    gstRate: item.gstRate,
                    hsnCode: item.hsnCode,
                    batchNumber: item.batchNumber,
                    expiryDate: item.expiryDate,
                  );
                });
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter valid prices')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _editItemQty(int index) {
    final item = _cart[index];
    final qtyController = TextEditingController(text: '${item.qty}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Quantity - ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: ${item.qty} ${item.unit}'),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Quantity',
                border: OutlineInputBorder(),
              ),
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
            onPressed: () {
              final newQty = int.tryParse(qtyController.text);
              if (newQty != null && newQty > 0) {
                setState(() {
                  _cart[index] = PurchaseItem(
                    productId: item.productId,
                    name: item.name,
                    price: item.price,
                    qty: newQty,
                    unit: item.unit,
                  );
                });
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter valid quantity')),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanAndAdd() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result != null && mounted) {
      final product = await ref
          .read(productServiceProvider)
          .getProductByBarcode(result);
      if (product != null && mounted) {
        _addToCart(product);
      } else if (mounted) {
        _showProductNotFound(result);
      }
    }
  }

  void _showProductNotFound(String barcode) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final barcodeProduct = await BarcodeService.lookup(barcode);

    if (!mounted) return;
    Navigator.pop(context);

    if (barcodeProduct != null) {
      _showApiProductDialog(barcode, barcodeProduct);
    } else {
      _showManualCreateDialog(barcode);
    }
  }

  void _showApiProductDialog(String barcode, BarcodeProduct apiProduct) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, size: 48, color: Colors.green),
        title: const Text('Product Found Online!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name: ${apiProduct.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (apiProduct.brand.isNotEmpty) Text('Brand: ${apiProduct.brand}'),
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
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                    prefilledName: '${apiProduct.brand} ${apiProduct.name}'
                        .trim(),
                    prefilledCategory: apiProduct.category,
                    prefilledSellingPrice: apiProduct.mrp,
                  ),
                ),
              );
              if (result == true) {
                await _loadProducts();
                final product = await ref
                    .read(productServiceProvider)
                    .getProductByBarcode(barcode);
                if (product != null && mounted) {
                  _addToCart(product);
                }
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
        icon: const Icon(Icons.error_outline, size: 48, color: Colors.orange),
        title: const Text('Product Not Found'),
        content: Text('No product with barcode: $barcode'),
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
                  builder: (_) => ProductFormScreen(barcode: barcode),
                ),
              );
              if (result == true) {
                await _loadProducts();
                final product = await ref
                    .read(productServiceProvider)
                    .getProductByBarcode(barcode);
                if (product != null && mounted) {
                  _addToCart(product);
                }
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  void _showSupplierPicker() {
    final query = _supplierSearchQuery.toLowerCase();
    final filtered = query.isEmpty
        ? _suppliers
        : _suppliers.where((s) =>
            s.name.toLowerCase().contains(query) ||
            (s.phone?.toLowerCase().contains(query) ?? false)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search supplier...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  setState(() => _supplierSearchQuery = v);
                  // Rebuild bottom sheet
                  Navigator.pop(ctx);
                  _showSupplierPicker();
                },
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No suppliers found'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final s = filtered[i];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?'),
                          ),
                          title: Text(s.name),
                          subtitle: Text(s.phone ?? ''),
                          trailing: s.totalDues > 0
                              ? Text('Due: Rs${s.totalDues.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.orange, fontSize: 12))
                              : null,
                          onTap: () {
                            setState(() {
                              _selectedSupplier = s;
                              _supplierSearchQuery = '';
                            });
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNewSupplier() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<Supplier>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
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
              if (nameController.text.isNotEmpty) {
                final supplier = await ref
                    .read(supplierServiceProvider)
                    .addSupplier(
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty
                          ? phoneController.text
                          : null,
                    );
                Navigator.pop(ctx, supplier);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _suppliers.add(result);
        _selectedSupplier = result;
      });
    }
  }

  Future<void> _completePurchase() async {
    if (_cart.isEmpty) return;

    if (_isCredit && _selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a supplier for credit purchase'),
        ),
      );
      return;
    }

    if (_isCredit && _amountPaid >= _total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount paid is full! Uncheck Credit.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedSupplier != null)
              Text('Supplier: ${_selectedSupplier!.name}'),
            Text('Items: ${_cart.length}'),
            Text('Total: Rs ${_total.toStringAsFixed(2)}'),
            if (_isCredit) ...[
              const SizedBox(height: 8),
              Text('Amount Paid: Rs ${_amountPaid.toStringAsFixed(2)}'),
              Text(
                'Due: Rs ${_dueAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Text('Stock will be added automatically.'),
            const Text('Confirm?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final auth = ref.read(authServiceProvider);
      final user = auth.currentUser;

      final userId = user?.id;
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please login again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final purchase = Purchase(
        id: '',
        supplierName: _selectedSupplier?.name,
        items: _cart,
        totalAmount: _total,
        createdBy: userId,
        createdAt: DateTime.now(),
        supplierId: _selectedSupplier?.id,
        isCredit: _isCredit,
        amountPaid: _isCredit ? _amountPaid : _total,
        dueAmount: _dueAmount,
        paymentMethod: _paymentMethod,
      );

      final createdPurchase = await ref
          .read(purchaseServiceProvider)
          .createPurchase(purchase);

      ref.invalidate(purchasesProvider);
      ref.invalidate(productsProvider);

      if (mounted) {
        final invoiceAction = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_isCredit ? 'Credit Purchase!' : 'Purchase Completed!'),
            content: Text(
              _isCredit
                  ? 'Total: Rs ${_total.toStringAsFixed(2)}\nDue: Rs ${_dueAmount.toStringAsFixed(2)}'
                  : 'Total: Rs ${_total.toStringAsFixed(2)}\n\nPrint or share invoice?',
            ),
            actions: [
              if (_isCredit)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              if (!_isCredit) ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'skip'),
                  child: const Text('Skip'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'share'),
                  child: const Text('Share'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'print'),
                  child: const Text('Print'),
                ),
              ],
            ],
          ),
        );

        if (invoiceAction == 'print') {
          await PurchaseInvoiceGenerator.generateAndPrint(createdPurchase);
        } else if (invoiceAction == 'share') {
          await PurchaseInvoiceGenerator.shareInvoice(createdPurchase);
        }

        setState(() {
          _cart.clear();
          _amountPaidController.clear();
          _selectedSupplier = null;
          _isCredit = false;
          _paymentMethod = 'cash';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showProductPicker() async {
    // Always reload products when opening picker
    await _loadProducts();
    setState(() => _filteredProducts = _allProducts);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search product...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setSheetState(() {
                                _filteredProducts = _allProducts;
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.green,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProductFormScreen(),
                              ),
                            );
                            if (result == true) {
                              await _loadProducts();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  onChanged: (v) {
                    setSheetState(() {
                      _filteredProducts = _allProducts
                          .where(
                            (p) =>
                                p.name.toLowerCase().contains(
                                  v.toLowerCase(),
                                ) ||
                                (p.barcode?.toLowerCase().contains(
                                      v.toLowerCase(),
                                    ) ??
                                    false),
                          )
                          .toList();
                    });
                  },
                ),
              ),
              if (_filteredProducts.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No products found. Tap + to create new.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text(
                          'Purchase: Rs${product.purchasePrice} | Stock: ${product.stock}',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _addToCart(product);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChange);
    _tabController?.dispose();
    _searchController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Purchases'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'New Purchase'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // New Purchase
            Column(
              children: [
                // Supplier Selection
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.business, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _selectedSupplier != null
                            ? Chip(
                                label: Text(
                                  '${_selectedSupplier!.name} ${_selectedSupplier!.phone != null ? "(${_selectedSupplier!.phone})" : ""}',
                                ),
                                onDeleted: () =>
                                    setState(() => _selectedSupplier = null),
                              )
                            : TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search supplier...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: _supplierSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            setState(() => _supplierSearchQuery = '');
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (v) {
                                  setState(() => _supplierSearchQuery = v);
                                  if (v.isNotEmpty) _showSupplierPicker();
                                },
                                onTap: _showSupplierPicker,
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _addNewSupplier,
                        tooltip: 'Add New Supplier',
                      ),
                    ],
                  ),
                ),

                // Payment Method + Credit Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Text('Payment:'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Cash'),
                        selected: !_isCredit && _paymentMethod == 'cash',
                        onSelected: (_) => setState(() {
                          _paymentMethod = 'cash';
                          _isCredit = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Digital'),
                        selected: !_isCredit && _paymentMethod == 'digital',
                        onSelected: (_) => setState(() {
                          _paymentMethod = 'digital';
                          _isCredit = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Credit'),
                        selected: _isCredit,
                        onSelected: (_) => setState(() {
                          _isCredit = !_isCredit;
                          if (_isCredit) {
                            _amountPaidController.clear();
                          }
                        }),
                        backgroundColor: Colors.orange.shade100,
                        selectedColor: Colors.orange,
                      ),
                    ],
                  ),
                ),

                // Credit Details
                if (_isCredit) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text('Amount Paid: Rs '),
                        Expanded(
                          child: TextField(
                            controller: _amountPaidController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: '0 for full credit',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Text('Due: '),
                        Text(
                          'Rs ${_dueAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: _dueAmount > 0
                                ? Colors.orange
                                : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Scan and Pick Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _scanAndAdd,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showProductPicker,
                          icon: const Icon(Icons.search),
                          label: const Text('Pick Product'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Cart List
                Expanded(
                  child: _cart.isEmpty
                      ? const Center(child: Text('No items yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _cart.length,
                          itemBuilder: (context, index) {
                            final item = _cart[index];
                            return Card(
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (item.batchNumber != null &&
                                        item.batchNumber!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          item.batchNumber!,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      ),
                                    if (item.expiryDate != null)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              item.expiryDate!.isBefore(
                                                DateTime.now().add(
                                                  const Duration(days: 30),
                                                ),
                                              )
                                              ? Colors.orange.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.green.withValues(
                                                  alpha: 0.1,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Exp: ${item.expiryDate!.day}/${item.expiryDate!.month}/${item.expiryDate!.year}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color:
                                                item.expiryDate!.isBefore(
                                                  DateTime.now().add(
                                                    const Duration(days: 30),
                                                  ),
                                                )
                                                ? Colors.orange
                                                : Colors.green,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: GestureDetector(
                                  onTap: () => _editItemPrice(index),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Rs${item.price.toStringAsFixed(2)} x ${item.qty} = Rs${item.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      if (_allProducts
                                              .where(
                                                (p) => p.id == item.productId,
                                              )
                                              .isNotEmpty &&
                                          _allProducts
                                                  .firstWhere(
                                                    (p) =>
                                                        p.id == item.productId,
                                                  )
                                                  .purchasePrice !=
                                              item.price)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                          ),
                                          child: Text(
                                            '(was Rs${_allProducts.firstWhere((p) => p.id == item.productId).purchasePrice.toStringAsFixed(2)})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: () => _updateQty(index, -1),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _editItemQty(index),
                                      child: Text(
                                        '${item.qty}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                      onPressed: () => _updateQty(index, 1),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _removeFromCart(index),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Total and Complete Button
                if (_cart.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total:',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Rs${_total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _completePurchase,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isCredit
                                  ? Colors.orange
                                  : Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    _isCredit
                                        ? 'Complete Credit Purchase'
                                        : 'Complete Purchase',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // History
            _PurchaseHistory(),
          ],
        ),
      ),
    );
  }
}

class _PurchaseHistory extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PurchaseHistory> createState() => _PurchaseHistoryState();
}

class _PurchaseHistoryState extends ConsumerState<_PurchaseHistory> {
  Set<String> _paymentFilters = {};
  Set<String> _statusFilters = {};
  String _dateFilter = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(purchasesProvider),
      child: ref
          .watch(purchasesProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (purchases) {
              if (purchases.isEmpty) {
                return const EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'No Purchases',
                  subtitle: 'Purchase history will appear here',
                );
              }

              var filtered = purchases.where((p) {
                if (_paymentFilters.isNotEmpty && !_paymentFilters.contains(p.paymentMethod)) return false;
                if (_statusFilters.contains('credit') && !p.isCredit) return false;
                if (_statusFilters.contains('paid') && p.isCredit) return false;
                final now = DateTime.now();
                if (_dateFilter == 'today') {
                  if (p.createdAt.day != now.day || p.createdAt.month != now.month || p.createdAt.year != now.year) return false;
                } else if (_dateFilter == '7d') {
                  if (now.difference(p.createdAt).inDays > 7) return false;
                } else if (_dateFilter == '30d') {
                  if (now.difference(p.createdAt).inDays > 30) return false;
                }
                if (_searchQuery.isNotEmpty) {
                  final q = _searchQuery.toLowerCase();
                  final matchesSupplier = p.supplierName?.toLowerCase().contains(q) == true;
                  final matchesAmt = p.totalAmount.toString().contains(q);
                  if (!matchesSupplier && !matchesAmt) return false;
                }
                return true;
              }).toList();

              return Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by supplier or amount...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  // Payment method chips
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      children: [
                        _buildFilterChip('All', '', _paymentFilters, () => setState(() => _paymentFilters.clear())),
                        _buildFilterChip('Cash', 'cash', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('cash'); })),
                        _buildFilterChip('Digital', 'digital', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('digital'); })),
                        _buildFilterChip('UPI', 'upi', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('upi'); })),
                        _buildFilterChip('Bank', 'bank', _paymentFilters, () => setState(() { _paymentFilters.clear(); _paymentFilters.add('bank'); })),
                      ],
                    ),
                  ),
                  // Status + Date chips
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      children: [
                        _buildStatusChip('Paid', 'paid'),
                        _buildStatusChip('Credit Due', 'credit'),
                        const SizedBox(width: 8),
                        _buildDateChip('All', 'all'),
                        _buildDateChip('Today', 'today'),
                        _buildDateChip('7 Days', '7d'),
                        _buildDateChip('30 Days', '30d'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${filtered.length} purchases', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Export button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _exportPurchasesPdf(context, filtered),
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('Export PDF'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Purchase list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final purchase = filtered[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.shopping_cart),
                            ),
                            title: Text(
                              'Rs${purchase.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${purchase.items.length} items | ${purchase.supplierName ?? "No supplier"}',
                                ),
                                if (purchase.isCredit)
                                  Text(
                                    'Credit: Due Rs${purchase.dueAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'detail',
                                  child: Text('View Items'),
                                ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit Purchase'),
                                ),
                                const PopupMenuItem(
                                  value: 'share',
                                  child: Text('Share Invoice'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'detail') {
                                  _showPurchaseDetail(context, purchase);
                                } else if (value == 'edit') {
                                  _editPurchase(context, ref, purchase);
                                } else if (value == 'share') {
                                  _shareInvoice(context, purchase);
                                } else if (value == 'delete') {
                                  _confirmDelete(context, ref, purchase);
                                }
                              },
                              child: Text(
                                DateFormat('dd MMM').format(purchase.createdAt),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _exportPurchasesPdf(
    BuildContext context,
    List<Purchase> purchases,
  ) async {
    try {
      final pdf = pw.Document();
      double totalAll = 0;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'PURCHASE HISTORY',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
            ),
            pw.Text('Total Purchases: ${purchases.length}'),
            pw.SizedBox(height: 16),

            // Each purchase as a separate section
            ...purchases
                .asMap()
                .entries
                .map((entry) {
                  final i = entry.key + 1;
                  final p = entry.value;
                  totalAll += p.totalAmount;

                  return [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Purchase #$i',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.Text(
                            DateFormat('dd MMM yyyy').format(p.createdAt),
                          ),
                          pw.Text(
                            'Rs${p.totalAmount.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    if (p.supplierName != null)
                      pw.Text(
                        'Supplier: ${p.supplierName}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey700,
                        ),
                      ),
                    pw.SizedBox(height: 4),

                    // Items table
                    pw.TableHelper.fromTextArray(
                      headerStyle: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8,
                      ),
                      cellStyle: const pw.TextStyle(fontSize: 8),
                      headerDecoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      cellHeight: 18,
                      headers: ['Product', 'Qty', 'Price', 'Total'],
                      data: p.items
                          .map(
                            (item) => [
                              item.name,
                              '${item.qty}',
                              'Rs${item.price.toStringAsFixed(2)}',
                              'Rs${item.total.toStringAsFixed(2)}',
                            ],
                          )
                          .toList(),
                    ),
                    pw.SizedBox(height: 8),
                  ];
                })
                .expand((e) => e),

            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Grand Total: Rs${totalAll.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'Purchase_History.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editPurchase(
    BuildContext context,
    WidgetRef ref,
    Purchase purchase,
  ) async {
    final editedItems = purchase.items
        .map(
          (item) => PurchaseItem(
            productId: item.productId,
            name: item.name,
            price: item.price,
            qty: item.qty,
            unit: item.unit,
            gstRate: item.gstRate,
            hsnCode: item.hsnCode,
            batchNumber: item.batchNumber,
            expiryDate: item.expiryDate,
          ),
        )
        .toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) =>
          _EditPurchaseDialog(purchase: purchase, items: editedItems),
    );
    if (result == null || !context.mounted) return;

    final newItems = result['items'] as List<PurchaseItem>;
    final newTotal = result['total'] as double;
    final reason = (result['reason'] as String?)?.trim() ?? '';
    final isCredit = purchase.isCredit;
    final amountPaid = isCredit
        ? purchase.amountPaid.clamp(0.0, newTotal)
        : newTotal;
    final dueAmount = isCredit ? (newTotal - amountPaid) : 0.0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Changes?'),
        content: Text(
          'Original: Rs${purchase.totalAmount.toStringAsFixed(0)}\n'
          'New: Rs${newTotal.toStringAsFixed(0)}\n\n'
          'Stock, batches and accounts will be adjusted.\n'
          'Cannot edit if stock from this purchase was already sold.\n'
          'Reason: $reason',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await ref
          .read(purchaseServiceProvider)
          .editPurchaseAtomic(
            purchaseId: purchase.id,
            items: newItems,
            totalAmount: newTotal,
            supplierId: purchase.supplierId,
            supplierName: purchase.supplierName,
            isCredit: isCredit,
            amountPaid: amountPaid,
            dueAmount: dueAmount,
            paymentMethod: purchase.paymentMethod,
            reason: reason,
          );
      ref.invalidate(purchasesProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(todayTransactionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPurchaseDetail(BuildContext context, Purchase purchase) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Purchase - ${DateFormat('dd MMM yyyy').format(purchase.createdAt)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (purchase.supplierName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Supplier: ${purchase.supplierName}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: purchase.items.length,
                itemBuilder: (context, index) {
                  final item = purchase.items[index];
                  return ListTile(
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Rs${item.price.toStringAsFixed(2)} x ${item.qty}',
                    ),
                    trailing: Text(
                      'Rs${item.total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs${purchase.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareInvoice(BuildContext context, Purchase purchase) async {
    try {
      await PurchaseInvoiceGenerator.shareInvoice(purchase);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sharing invoice: $e')));
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Purchase purchase) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Purchase'),
        content: Text(
          'Delete Rs${purchase.totalAmount.toStringAsFixed(0)} purchase? Stock will be deducted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(purchaseServiceProvider)
                    .deletePurchase(purchase.id);
                ref.invalidate(purchasesProvider);
                ref.invalidate(productsProvider);
                ref.invalidate(accountsProvider);
                ref.invalidate(todayTransactionsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Purchase deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Set<String> selected, VoidCallback onTap) {
    final isSelected = value.isEmpty ? selected.isEmpty : selected.contains(value);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: const Color(0xFF667eea),
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value) {
    final isSelected = _statusFilters.contains(value);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: Colors.orange,
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() {
          if (isSelected) {
            _statusFilters.remove(value);
          } else {
            _statusFilters.add(value);
          }
        }),
      ),
    );
  }

  Widget _buildDateChip(String label, String value) {
    final isSelected = _dateFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: Colors.teal,
        backgroundColor: Colors.grey.shade100,
        checkmarkColor: Colors.white,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _dateFilter = value),
      ),
    );
  }
}

class _EditPurchaseDialog extends StatefulWidget {
  final Purchase purchase;
  final List<PurchaseItem> items;

  const _EditPurchaseDialog({required this.purchase, required this.items});

  @override
  State<_EditPurchaseDialog> createState() => _EditPurchaseDialogState();
}

class _EditPurchaseDialogState extends State<_EditPurchaseDialog> {
  late List<PurchaseItem> _items;
  List<Product> _allProducts = [];
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _loadProducts();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ProductService().getAllProducts();
      if (mounted) setState(() => _allProducts = products);
    } catch (e) {
      Logger.warning('Failed to load products for purchase screen: $e');
    }
  }

  double get _total => _items.fold(0.0, (sum, item) => sum + item.total);

  void _updateQty(int index, int delta) {
    setState(() {
      final newQty = _items[index].qty + delta;
      if (newQty <= 0) {
        _items.removeAt(index);
      } else {
        _items[index] = PurchaseItem(
          productId: _items[index].productId,
          name: _items[index].name,
          price: _items[index].price,
          qty: newQty,
          unit: _items[index].unit,
          gstRate: _items[index].gstRate,
          hsnCode: _items[index].hsnCode,
          batchNumber: _items[index].batchNumber,
          expiryDate: _items[index].expiryDate,
        );
      }
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _addProduct() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Add Product',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _allProducts.length,
                itemBuilder: (context, index) {
                  final product = _allProducts[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text('Cost: Rs${product.purchasePrice}'),
                    trailing: const Icon(Icons.add_circle, color: Colors.green),
                    onTap: () {
                      setState(() {
                        final existing = _items.indexWhere(
                          (i) => i.productId == product.id,
                        );
                        if (existing >= 0) {
                          final cur = _items[existing];
                          _items[existing] = PurchaseItem(
                            productId: cur.productId,
                            name: cur.name,
                            price: cur.price,
                            qty: cur.qty + 1,
                            unit: cur.unit,
                            gstRate: cur.gstRate,
                            hsnCode: cur.hsnCode,
                            batchNumber: cur.batchNumber,
                            expiryDate: cur.expiryDate,
                          );
                        } else {
                          _items.add(
                            PurchaseItem(
                              productId: product.id,
                              name: product.name,
                              price: product.purchasePrice,
                              qty: 1,
                              unit: product.unit,
                              gstRate: product.gstRate,
                              hsnCode: product.hsnCode,
                              tamilName: product.tamilName,
                            ),
                          );
                        }
                      });
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Edit Purchase - Rs${widget.purchase.totalAmount.toStringAsFixed(0)}',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${_items.length} items | Total: Rs${_total.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    child: ListTile(
                      dense: true,
                      title: Text(
                        item.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Row(
                        children: [
                          Text(
                            'Rs${item.price.toStringAsFixed(0)} x ${item.qty} = Rs${item.total.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (_allProducts
                                  .where((p) => p.id == item.productId)
                                  .isNotEmpty &&
                              _allProducts
                                      .firstWhere((p) => p.id == item.productId)
                                      .purchasePrice !=
                                  item.price)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '(was Rs${_allProducts.firstWhere((p) => p.id == item.productId).purchasePrice.toStringAsFixed(0)})',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                            ),
                            onPressed: () => _updateQty(index, -1),
                          ),
                          Text(
                            '${item.qty}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                            ),
                            onPressed: () => _updateQty(index, 1),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 18,
                              color: Colors.red,
                            ),
                            onPressed: () => _removeItem(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for edit *',
                hintText: 'e.g. Wrong qty entered',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Edit reason is required')),
              );
              return;
            }
            if (_items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Add at least one item')),
              );
              return;
            }
            Navigator.pop(context, {
              'items': _items,
              'total': _total,
              'reason': reason,
            });
          },
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}
