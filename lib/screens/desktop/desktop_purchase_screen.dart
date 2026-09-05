import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_timezone.dart';
import '../../utils/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/providers.dart';
import '../../config/desktop_purchase_provider.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import '../shared/product_form_screen.dart';
import '../../utils/purchase_invoice_generator.dart';

class DesktopPurchaseScreen extends ConsumerStatefulWidget {
  const DesktopPurchaseScreen({super.key});

  @override
  ConsumerState<DesktopPurchaseScreen> createState() =>
      _DesktopPurchaseScreenState();
}

class _DesktopPurchaseScreenState extends ConsumerState<DesktopPurchaseScreen> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _batchController = TextEditingController();
  late final FocusNode _searchFocus;
  final _resultsScrollController = ScrollController();
  final _cartScrollController = ScrollController();
  final _qtyFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _batchFocus = FocusNode();
  final _discountFocus = FocusNode();

  List<Product> _products = [];
  List<Product> _results = [];
  DateTime? _expiryDate;
  int _resultIndex = 0;
  int _cartIndex = -1;
  Product? _selectedProduct;
  bool _loading = false;
  bool _showHistory = false;
  bool _isProcessing = false;
  double _supplierDues = 0;
  final _discountController = TextEditingController();

  // Use ref.watch in build, this getter is for non-build methods
  PurchaseSession get _activeSession => ref
      .read(desktopPurchaseProvider)
      .elementAt(ref.read(desktopPurchaseProvider.notifier).activeSessionIndex);

  @override
  void initState() {
    super.initState();
    _searchFocus = FocusNode(onKeyEvent: _handleSearchKey);
    _loadProducts();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  KeyEventResult _handleSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _results.isEmpty)
      return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _resultIndex = (_resultIndex + 1) % _results.length);
      _scrollSelectedResultIntoView();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _resultIndex =
            (_resultIndex - 1 + _results.length) % _results.length,
      );
      _scrollSelectedResultIntoView();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollSelectedResultIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_resultsScrollController.hasClients || _results.isEmpty) return;
      const rowHeight = 80.0;
      final top = _resultIndex * rowHeight;
      final bottom = top + rowHeight;
      final offset = _resultsScrollController.offset;
      final viewport = _resultsScrollController.position.viewportDimension;
      if (top < offset) {
        _resultsScrollController.animateTo(
          top,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      } else if (bottom > offset + viewport) {
        _resultsScrollController.animateTo(
          bottom - viewport,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadProducts() async {
    final products = await ref.read(productServiceProvider).getAllProducts();
    if (mounted) setState(() => _products = products);
  }

  Future<void> _loadSupplierDues(String supplierId) async {
    try {
      final res = await Supabase.instance.client
          .from('suppliers')
          .select('total_dues')
          .eq('id', supplierId)
          .maybeSingle();
      if (res != null && mounted) {
        setState(
          () => _supplierDues = (res['total_dues'] as num?)?.toDouble() ?? 0,
        );
      }
    } catch (e) {
      Logger.warning('Failed to load supplier dues: $e');
    }
  }

  void _search(String value) {
    final query = value.trim().toLowerCase();
    final matches = query.isEmpty
        ? <Product>[]
        : _products
              .where(
                (p) =>
                    p.name.toLowerCase().contains(query) ||
                    (p.barcode?.toLowerCase().contains(query) ?? false),
              )
              .toList();
    setState(() {
      _results = matches;
      _resultIndex = 0;
    });
  }

  void _selectResult() {
    if (_results.isEmpty) return;
    final product = _results[_resultIndex];
    setState(() {
      _selectedProduct = product;
      _priceController.text = product.purchasePrice.toStringAsFixed(2);
      _qtyController.text = '1';
      _results = [];
      _searchController.clear();
    });
    _qtyFocus.requestFocus();
    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  void _confirmQty() {
    _priceFocus.requestFocus();
    _priceController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _priceController.text.length,
    );
  }

  void _confirmPrice() {
    _batchFocus.requestFocus();
  }

  void _addItem() {
    final product = _selectedProduct;
    final qty = int.tryParse(_qtyController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    if (product == null || qty <= 0 || price <= 0) return;

    ref
        .read(desktopPurchaseProvider.notifier)
        .addItem(
          PurchaseItem(
            productId: product.id,
            name: product.name,
            price: price,
            qty: qty,
            unit: product.unit,
            gstRate: product.gstRate,
            hsnCode: product.hsnCode,
            tamilName: product.tamilName,
            batchNumber: _batchController.text.trim().isEmpty
                ? null
                : _batchController.text.trim(),
            expiryDate: _expiryDate,
          ),
        );
    setState(() {
      _selectedProduct = null;
      _qtyController.text = '1';
      _priceController.clear();
      _batchController.clear();
      _expiryDate = null;
      _cartIndex = -1;
    });
    _scrollCartToBottom();
    _focusProductSearch();
  }

  void _focusProductSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    });
  }

  Future<void> _selectSupplier() async {
    final suppliers = await ref.read(supplierServiceProvider).getSuppliers();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = query.isEmpty
                ? suppliers
                : suppliers.where((s) =>
                    s.name.toLowerCase().contains(query.toLowerCase()) ||
                    (s.phone?.toLowerCase().contains(query.toLowerCase()) ?? false)).toList();
            return AlertDialog(
              title: const Text('Select Supplier'),
              content: SizedBox(
                width: 400,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search supplier...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setDialogState(() => query = ''),
                              )
                            : null,
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No suppliers found'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, index) => ListTile(
                                title: Text(filtered[index].name),
                                subtitle: Text(
                                  filtered[index].totalDues > 0
                                      ? 'Dues: Rs${filtered[index].totalDues.toStringAsFixed(2)}'
                                      : (filtered[index].phone ?? ''),
                                  style: TextStyle(
                                    color: filtered[index].totalDues > 0
                                        ? Colors.orange
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: filtered[index].totalDues > 0
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Rs${filtered[index].totalDues.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange.shade800,
                                          ),
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  ref
                                      .read(desktopPurchaseProvider.notifier)
                                      .setSupplier(filtered[index]);
                                  _loadSupplierDues(filtered[index].id);
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _addSupplier();
                  },
                  child: const Text('Add New Supplier'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final result = await showDialog<Supplier>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Supplier name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final supplier = await ref
                  .read(supplierServiceProvider)
                  .addSupplier(
                    name: name.text.trim(),
                    phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx, supplier);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    if (result != null && mounted)
      ref.read(desktopPurchaseProvider.notifier).setSupplier(result);
  }

  void _editPurchasePrice(int index) {
    final item = _activeSession.items[index];
    final controller = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );
    final product = _products.firstWhere(
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
    final sellController = TextEditingController(
      text: product.sellingPrice.toStringAsFixed(2),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Prices - ${item.name}'),
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
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: 'Rs ',
                labelText: 'New Purchase Price',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sellController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: 'Rs ',
                labelText: 'New Selling Price',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) =>
                  _savePurchasePrice(ctx, index, controller, sellController),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              sellController.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                _savePurchasePrice(ctx, index, controller, sellController),
            child: const Text('Update'),
          ),
        ],
      ),
    ).then((_) {
      controller.dispose();
      sellController.dispose();
    });
  }

  void _savePurchasePrice(
    BuildContext ctx,
    int index,
    TextEditingController controller,
    TextEditingController sellController,
  ) {
    final price = double.tryParse(controller.text);
    final sellPrice = double.tryParse(sellController.text);
    if (price == null || price <= 0 || sellPrice == null || sellPrice <= 0)
      return;
    final item = _activeSession.items[index];
    // Update product prices in DB if changed
    final product = _products.firstWhere(
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
    if (product.id.isNotEmpty &&
        (price != product.purchasePrice || sellPrice != product.sellingPrice)) {
      ref
          .read(productServiceProvider)
          .updateProduct(
            Product(
              id: product.id,
              name: product.name,
              barcode: product.barcode,
              category: product.category,
              purchasePrice: price,
              sellingPrice: sellPrice,
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
    ref
        .read(desktopPurchaseProvider.notifier)
        .updateItem(
          index,
          PurchaseItem(
            productId: item.productId,
            name: item.name,
            price: price,
            qty: item.qty,
            unit: item.unit,
            gstRate: item.gstRate,
            hsnCode: item.hsnCode,
            tamilName: item.tamilName,
            batchNumber: item.batchNumber,
            expiryDate: item.expiryDate,
          ),
        );
    Navigator.pop(ctx);
    setState(() {}); // Force rebuild
  }

  Future<void> _completePurchase() async {
    final session = _activeSession;
    if (session.items.isEmpty || _loading) return;
    if (session.isCredit && session.supplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select supplier for credit purchase')),
      );
      return;
    }
    setState(() {
      _loading = true;
      _isProcessing = true;
    });
    try {
      final user = ref.read(authServiceProvider).currentUser;
      final discount = double.tryParse(_discountController.text) ?? 0;
      final rawTotal = (session.subtotal - discount).clamp(
        0.0,
        double.infinity,
      );
      final roundedTotal = rawTotal.roundToDouble();
      final roundOffAmount = roundedTotal - rawTotal;
      final purchase = Purchase(
        id: '',
        supplierId: session.supplier?.id,
        supplierName: session.supplier?.name,
        items: List.from(session.items),
        totalAmount: roundedTotal,
        roundOff: roundOffAmount,
        createdBy: user?.id ?? '',
        createdAt: DateTime.now(),
        isCredit: session.isCredit,
        amountPaid: session.isCredit ? 0 : roundedTotal,
        dueAmount: session.isCredit ? roundedTotal : 0,
        paymentMethod: session.paymentMethod,
        dueDate: session.isCredit
            ? DateTime.now().add(const Duration(days: 30))
            : null,
      );
      final created = await ref
          .read(purchaseServiceProvider)
          .createPurchase(purchase);
      ref.invalidate(productsProvider);
      ref.invalidate(purchasesProvider);
      await _loadProducts();
      if (mounted) {
        ref.read(desktopPurchaseProvider.notifier).resetAfterPurchase();
        setState(() {
          _discountController.clear();
        });
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Purchase Completed'),
            content: Text('Total: Rs${created.totalAmount.toStringAsFixed(2)}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await PurchaseInvoiceGenerator.generateAndPrint(created);
                },
                child: const Text('Print'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await PurchaseInvoiceGenerator.shareInvoice(created);
                },
                child: const Text('Share'),
              ),
            ],
          ),
        );
        _searchFocus.requestFocus();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
          _isProcessing = false;
        });
    }
  }

  Widget _buildProcessingOverlay() {
    if (!_isProcessing) return const SizedBox.shrink();
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF059669),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Processing Purchase...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the provider to trigger rebuilds on changes
    final sessions = ref.watch(desktopPurchaseProvider);
    final notifier = ref.read(desktopPurchaseProvider.notifier);
    final _activeSession = sessions[notifier.activeSessionIndex];

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final key = event.logicalKey;
        final ctrl = HardwareKeyboard.instance.isControlPressed;
        final alt = HardwareKeyboard.instance.isAltPressed;

        // Ctrl+Enter: Complete purchase
        if (ctrl && key == LogicalKeyboardKey.enter) {
          if (_activeSession.items.isNotEmpty && !_loading) _completePurchase();
          return;
        }

        // Ctrl+1 / F1: New Purchase tab
        if ((ctrl && key == LogicalKeyboardKey.digit1) || key == LogicalKeyboardKey.f1) {
          setState(() => _showHistory = false);
          _searchFocus.requestFocus();
          return;
        }

        // Ctrl+2 / F2: Purchase History tab
        if ((ctrl && key == LogicalKeyboardKey.digit2) || key == LogicalKeyboardKey.f2) {
          setState(() => _showHistory = true);
          ref.invalidate(purchasesProvider);
          return;
        }

        // Ctrl+F or /: Focus search
        if ((ctrl && key == LogicalKeyboardKey.keyF) || key == LogicalKeyboardKey.slash) {
          if (!_showHistory) {
            setState(() {
              _results.clear();
              _selectedProduct = null;
              _expiryDate = null;
            });
            _searchFocus.requestFocus();
          }
          return;
        }

        // Ctrl+N: New product
        if (ctrl && key == LogicalKeyboardKey.keyN) {
          _addNewProduct();
          return;
        }

        // Ctrl+D: Focus discount
        if (ctrl && key == LogicalKeyboardKey.keyD) {
          _discountFocus.requestFocus();
          return;
        }

        // F5: Refresh purchase history
        if (key == LogicalKeyboardKey.f5) {
          ref.invalidate(purchasesProvider);
          return;
        }

        // Alt+1: Cash, Alt+2: UPI, Alt+3: Credit
        if (alt) {
          if (key == LogicalKeyboardKey.digit1) {
            ref.read(desktopPurchaseProvider.notifier).setPaymentMethod('cash');
            return;
          }
          if (key == LogicalKeyboardKey.digit2) {
            ref.read(desktopPurchaseProvider.notifier).setPaymentMethod('upi');
            return;
          }
          if (key == LogicalKeyboardKey.digit3) {
            ref.read(desktopPurchaseProvider.notifier).setPaymentMethod('credit');
            return;
          }
        }

        // Enter: context-sensitive — skip if entry field has focus (handled by onSubmitted)
        if (key == LogicalKeyboardKey.enter) {
          if (_selectedProduct == null && _results.isNotEmpty) {
            _selectResult();
          } else if (_selectedProduct != null && _batchFocus.hasFocus) {
            _addItem();
          } else if (_discountFocus.hasFocus) {
            // Complete purchase from discount field
            if (_activeSession.items.isNotEmpty && !_loading) _completePurchase();
          }
        } else if (key == LogicalKeyboardKey.arrowDown) {
          if (_results.isNotEmpty) {
            setState(() => _resultIndex = (_resultIndex + 1) % _results.length);
          } else if (_selectedProduct == null && _activeSession.items.isNotEmpty) {
            setState(() {
              _cartIndex = (_cartIndex + 1) % _activeSession.items.length;
            });
            _scrollCartToIndex(_cartIndex);
          }
        } else if (key == LogicalKeyboardKey.arrowUp) {
          if (_results.isNotEmpty) {
            setState(
              () => _resultIndex =
                  (_resultIndex - 1 + _results.length) % _results.length,
            );
          } else if (_selectedProduct == null && _activeSession.items.isNotEmpty) {
            setState(() {
              _cartIndex = _cartIndex <= 0
                  ? _activeSession.items.length - 1
                  : _cartIndex - 1;
            });
            _scrollCartToIndex(_cartIndex);
          }
        } else if (key == LogicalKeyboardKey.delete && _cartIndex >= 0 && _selectedProduct == null) {
          if (_cartIndex < _activeSession.items.length) {
            ref.read(desktopPurchaseProvider.notifier).removeItem(_cartIndex);
            setState(() {
              if (_activeSession.items.isEmpty) {
                _cartIndex = -1;
              } else if (_cartIndex >= _activeSession.items.length) {
                _cartIndex = _activeSession.items.length - 1;
              }
            });
          }
        } else if (key == LogicalKeyboardKey.escape) {
          setState(() {
            _results.clear();
            _selectedProduct = null;
            _expiryDate = null;
            _cartIndex = -1;
          });
          _searchFocus.requestFocus();
        }
      },
      child: Material(
        color: const Color(0xFFF1F5F9),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 48,
                  color: const Color(0xFF0F172A),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => ref.read(currentTabProvider.notifier).state = 0,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 14),
                            Icon(Icons.menu, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Menu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(width: 14),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      const SizedBox(width: 8),
                      _purchaseTab(
                        'NEW PURCHASE',
                        !_showHistory,
                        () => setState(() => _showHistory = false),
                      ),
                      const SizedBox(width: 4),
                      _purchaseTab(
                        'PURCHASE HISTORY',
                        _showHistory,
                        () {
                          setState(() => _showHistory = true);
                          ref.invalidate(purchasesProvider);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _showHistory
                      ? _buildPurchaseHistory()
                      : Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                children: [
                                  _buildEntryBar(),
                                  Expanded(child: _buildItemsTable()),
                                  _buildFooter(),
                                ],
                              ),
                            ),
                            SizedBox(width: 300, child: _buildPaymentPanel()),
                          ],
                        ),
                ),
              ],
            ),
            _buildProcessingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _purchaseTab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseHistory() {
    final purchases = ref.watch(purchasesProvider);
    return purchases.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF059669))),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text('Error: $e', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('No purchases yet', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  'F1 to start a new purchase',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(purchasesProvider),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: const Color(0xFF0F172A),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                      onPressed: () {
                        ref.invalidate(purchasesProvider);
                        ref.invalidate(productsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Purchase history refreshed'),
                            backgroundColor: Color(0xFF059669),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      tooltip: 'Refresh',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(width: 40, child: Text('#', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('SUPPLIER', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
                    const SizedBox(width: 80, child: Text('ITEMS', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
                    const SizedBox(width: 120, child: Text('AMOUNT', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
                    const SizedBox(width: 140, child: Text('DATE', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5))),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final purchase = items[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: const Color(0xFF059669).withValues(alpha: 0.1),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                purchase.supplierName ?? 'No Supplier',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '${purchase.items.length}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Text(
                                '₹${purchase.totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              child: Text(
                                AppTimezone.formatDateTime(purchase.createdAt),
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                              ),
                            ),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'details', child: Text('View Items')),
                                PopupMenuItem(value: 'edit', child: Text('Edit Purchase')),
                                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                              onSelected: (action) async {
                                if (action == 'details') {
                                  _showPurchaseDetails(purchase);
                                } else if (action == 'edit') {
                                  await _editPurchase(purchase);
                                } else if (action == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Purchase?'),
                                      content: const Text(
                                        'This will deduct stock and reverse account entries. This action cannot be undone.',
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await ref.read(purchaseServiceProvider).deletePurchase(purchase.id);
                                    ref.invalidate(purchasesProvider);
                                    ref.invalidate(productsProvider);
                                  }
                                }
                              },
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
      },
    );
  }

  void _showPurchaseDetails(Purchase purchase) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Purchase Items'),
        content: SizedBox(
          width: 500,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (purchase.supplierName != null &&
                  purchase.supplierName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Supplier: ${purchase.supplierName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ...purchase.items.map(
                (item) => ListTile(
                  dense: true,
                  title: Text(item.name),
                  subtitle: Text(
                    'ID: ${item.productId} | ${item.qty} × Rs${item.price.toStringAsFixed(2)}${item.batchNumber != null ? ' | Batch: ${item.batchNumber}' : ''}',
                  ),
                  trailing: Text('Rs${item.total.toStringAsFixed(2)}'),
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'TOTAL: Rs${purchase.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
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

  Future<void> _editPurchase(Purchase purchase) async {
    setState(() => _isProcessing = true);
    final items = purchase.items
        .map(
          (item) => PurchaseItem(
            productId: item.productId,
            name: item.name,
            price: item.price,
            qty: item.qty,
            unit: item.unit,
            gstRate: item.gstRate,
            hsnCode: item.hsnCode,
            tamilName: item.tamilName,
            batchNumber: item.batchNumber,
            expiryDate: item.expiryDate,
          ),
        )
        .toList();

    String? editSupplierId = purchase.supplierId;
    String? editSupplierName = purchase.supplierName;
    String editPaymentMethod = purchase.paymentMethod ?? 'cash';
    bool editIsCredit = purchase.isCredit;
    final reasonController = TextEditingController();
    final searchController = TextEditingController();
    final discountController = TextEditingController();
    List<Product> editResults = [];
    int editResultIndex = 0;
    Product? editSelectedProduct;
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController();
    final batchController = TextEditingController();

    setState(() => _isProcessing = false); // Show dialog now

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final itemsTotal = items.fold(0.0, (s, i) => s + i.total);
            final discount = double.tryParse(discountController.text) ?? 0;
            final finalTotal = (itemsTotal - discount).clamp(
              0.0,
              double.infinity,
            );

            void doSearch(String query) {
              final q = query.trim().toLowerCase();
              if (q.isEmpty) {
                setLocal(() {
                  editResults = [];
                  editResultIndex = 0;
                });
                return;
              }
              final matches = _products
                  .where(
                    (p) =>
                        p.name.toLowerCase().contains(q) ||
                        (p.barcode?.toLowerCase().contains(q) ?? false),
                  )
                  .toList();
              setLocal(() {
                editResults = matches;
                editResultIndex = 0;
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(child: Text('Edit Purchase')),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${items.length} items',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Rs${finalTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF11998e),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Search product to add...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: doSearch,
                          ),
                        ),
                      ],
                    ),
                    if (editResults.isNotEmpty)
                      Container(
                        height: 160,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListView.builder(
                          itemCount: editResults.length,
                          itemBuilder: (_, index) {
                            final product = editResults[index];
                            final isSel = index == editResultIndex;
                            return Container(
                              color: isSel ? const Color(0xFFCCFBF1) : null,
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  product.name,
                                  style: TextStyle(
                                    fontWeight: isSel ? FontWeight.bold : null,
                                    color: isSel
                                        ? const Color(0xFF065F46)
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  'Purchase: Rs${product.purchasePrice} | Sell: Rs${product.sellingPrice} | Stock: ${product.stock}',
                                  style: TextStyle(
                                    color: isSel
                                        ? const Color(0xFF065F46)
                                        : null,
                                  ),
                                ),
                                onTap: () {
                                  setLocal(() {
                                    editSelectedProduct = product;
                                    priceController.text = product.purchasePrice
                                        .toStringAsFixed(2);
                                    qtyController.text = '1';
                                    editResults = [];
                                    searchController.clear();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    if (editSelectedProduct != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF11998e)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                editSelectedProduct!.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 70,
                              child: TextField(
                                controller: qtyController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Qty',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: priceController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Price',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: batchController,
                                decoration: const InputDecoration(
                                  labelText: 'Batch',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle,
                                color: Color(0xFF11998e),
                                size: 28,
                              ),
                              onPressed: () {
                                final qty =
                                    int.tryParse(qtyController.text) ?? 0;
                                final price =
                                    double.tryParse(priceController.text) ?? 0;
                                if (qty <= 0 || price <= 0) return;
                                setLocal(() {
                                  items.add(
                                    PurchaseItem(
                                      productId: editSelectedProduct!.id,
                                      name: editSelectedProduct!.name,
                                      price: price,
                                      qty: qty,
                                      unit: editSelectedProduct!.unit,
                                      gstRate: editSelectedProduct!.gstRate,
                                      hsnCode: editSelectedProduct!.hsnCode,
                                      tamilName: editSelectedProduct!.tamilName,
                                      batchNumber:
                                          batchController.text.trim().isEmpty
                                          ? null
                                          : batchController.text.trim(),
                                    ),
                                  );
                                  editSelectedProduct = null;
                                  qtyController.text = '1';
                                  priceController.clear();
                                  batchController.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      color: const Color(0xFF11998e),
                      child: const Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Product',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Qty',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              'Price',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              'Total',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: Text(
                              'Actions',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(
                              child: Text(
                                'No items. Search above to add products.',
                              ),
                            )
                          : ListView.builder(
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final item = items[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (item.batchNumber != null ||
                                                item.tamilName != null)
                                              Text(
                                                '${item.batchNumber != null ? 'Batch: ${item.batchNumber}' : ''}${item.batchNumber != null && item.tamilName != null ? ' | ' : ''}${item.tamilName ?? ''}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: () => setLocal(() {
                                                if (item.qty > 1) {
                                                  items[index] = PurchaseItem(
                                                    productId: item.productId,
                                                    name: item.name,
                                                    price: item.price,
                                                    qty: item.qty - 1,
                                                    unit: item.unit,
                                                    gstRate: item.gstRate,
                                                    hsnCode: item.hsnCode,
                                                    tamilName: item.tamilName,
                                                    batchNumber:
                                                        item.batchNumber,
                                                    expiryDate: item.expiryDate,
                                                  );
                                                }
                                              }),
                                              child: const Icon(
                                                Icons.remove_circle_outline,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                  ),
                                              child: Text(
                                                '${item.qty}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => setLocal(() {
                                                items[index] = PurchaseItem(
                                                  productId: item.productId,
                                                  name: item.name,
                                                  price: item.price,
                                                  qty: item.qty + 1,
                                                  unit: item.unit,
                                                  gstRate: item.gstRate,
                                                  hsnCode: item.hsnCode,
                                                  tamilName: item.tamilName,
                                                  batchNumber: item.batchNumber,
                                                  expiryDate: item.expiryDate,
                                                );
                                              }),
                                              child: const Icon(
                                                Icons.add_circle_outline,
                                                size: 16,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: GestureDetector(
                                          onTap: () async {
                                            final ctrl = TextEditingController(
                                              text: item.price.toStringAsFixed(
                                                2,
                                              ),
                                            );
                                            final newPrice =
                                                await showDialog<double>(
                                                  context: ctx,
                                                  builder: (pctx) => AlertDialog(
                                                    title: Text(
                                                      'Price - ${item.name}',
                                                    ),
                                                    content: TextField(
                                                      controller: ctrl,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      autofocus: true,
                                                      decoration:
                                                          const InputDecoration(
                                                            prefixText: 'Rs ',
                                                            border:
                                                                OutlineInputBorder(),
                                                          ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(pctx),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          final p =
                                                              double.tryParse(
                                                                ctrl.text,
                                                              );
                                                          if (p != null &&
                                                              p > 0)
                                                            Navigator.pop(
                                                              pctx,
                                                              p,
                                                            );
                                                        },
                                                        child: const Text('OK'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                            if (newPrice != null) {
                                              setLocal(() {
                                                items[index] = PurchaseItem(
                                                  productId: item.productId,
                                                  name: item.name,
                                                  price: newPrice,
                                                  qty: item.qty,
                                                  unit: item.unit,
                                                  gstRate: item.gstRate,
                                                  hsnCode: item.hsnCode,
                                                  tamilName: item.tamilName,
                                                  batchNumber: item.batchNumber,
                                                  expiryDate: item.expiryDate,
                                                );
                                              });
                                            }
                                          },
                                          child: Text(
                                            'Rs${item.price.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          'Rs${item.total.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 80,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: () async {
                                                final ctrl =
                                                    TextEditingController(
                                                      text:
                                                          item.batchNumber ??
                                                          '',
                                                    );
                                                final newBatch = await showDialog<String>(
                                                  context: ctx,
                                                  builder: (bctx) => AlertDialog(
                                                    title: Text(
                                                      'Batch - ${item.name}',
                                                    ),
                                                    content: TextField(
                                                      controller: ctrl,
                                                      autofocus: true,
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText:
                                                                'Batch Number',
                                                            border:
                                                                OutlineInputBorder(),
                                                          ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(bctx),
                                                        child: const Text(
                                                          'Cancel',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              bctx,
                                                              ctrl.text.trim(),
                                                            ),
                                                        child: const Text('OK'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (newBatch != null) {
                                                  setLocal(() {
                                                    items[index] = PurchaseItem(
                                                      productId: item.productId,
                                                      name: item.name,
                                                      price: item.price,
                                                      qty: item.qty,
                                                      unit: item.unit,
                                                      gstRate: item.gstRate,
                                                      hsnCode: item.hsnCode,
                                                      tamilName: item.tamilName,
                                                      batchNumber:
                                                          newBatch.isEmpty
                                                          ? null
                                                          : newBatch,
                                                      expiryDate:
                                                          item.expiryDate,
                                                    );
                                                  });
                                                }
                                              },
                                              child: const Icon(
                                                Icons.edit_note,
                                                size: 18,
                                                color: Colors.orange,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => setLocal(
                                                () => items.removeAt(index),
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 18,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
                    Divider(height: 1, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final suppliers = await ref
                                  .read(supplierServiceProvider)
                                  .getSuppliers();
                              if (!ctx.mounted) return;
                              final selected = await showDialog<Supplier>(
                                context: ctx,
                                builder: (sctx) {
                                  String eq = '';
                                  return StatefulBuilder(
                                    builder: (sctx, setDialogState) {
                                      final filtered = eq.isEmpty
                                          ? suppliers
                                          : suppliers.where((s) =>
                                              s.name.toLowerCase().contains(eq.toLowerCase()) ||
                                              (s.phone?.toLowerCase().contains(eq.toLowerCase()) ?? false)).toList();
                                      return AlertDialog(
                                        title: const Text('Select Supplier'),
                                        content: SizedBox(
                                          width: 350,
                                          height: 380,
                                          child: Column(
                                            children: [
                                              TextField(
                                                autofocus: true,
                                                decoration: InputDecoration(
                                                  hintText: 'Search supplier...',
                                                  prefixIcon: const Icon(Icons.search, size: 20),
                                                  border: const OutlineInputBorder(),
                                                  isDense: true,
                                                  suffixIcon: eq.isNotEmpty
                                                      ? IconButton(
                                                          icon: const Icon(Icons.clear, size: 18),
                                                          onPressed: () => setDialogState(() => eq = ''),
                                                        )
                                                      : null,
                                                ),
                                                onChanged: (v) => setDialogState(() => eq = v),
                                              ),
                                              const SizedBox(height: 8),
                                              Expanded(
                                                child: filtered.isEmpty
                                                    ? const Center(child: Text('No suppliers found'))
                                                    : ListView.builder(
                                                        itemCount: filtered.length,
                                                        itemBuilder: (_, i) => ListTile(
                                                          title: Text(filtered[i].name),
                                                          subtitle: Text(
                                                            filtered[i].totalDues > 0
                                                                ? 'Dues: Rs${filtered[i].totalDues.toStringAsFixed(0)}'
                                                                : (filtered[i].phone ?? ''),
                                                          ),
                                                          onTap: () =>
                                                              Navigator.pop(sctx, filtered[i]),
                                                        ),
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(sctx),
                                            child: const Text('Cancel'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              );
                              if (selected != null)
                                setLocal(() {
                                  editSupplierId = selected.id;
                                  editSupplierName = selected.name;
                                });
                            },
                            icon: const Icon(Icons.business, size: 16),
                            label: Text(editSupplierName ?? 'Select Supplier'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text(
                            'CASH',
                            style: TextStyle(fontSize: 11),
                          ),
                          selected:
                              editPaymentMethod == 'cash' && !editIsCredit,
                          onSelected: (_) => setLocal(() {
                            editPaymentMethod = 'cash';
                            editIsCredit = false;
                          }),
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text(
                            'UPI',
                            style: TextStyle(fontSize: 11),
                          ),
                          selected: editPaymentMethod == 'upi' && !editIsCredit,
                          onSelected: (_) => setLocal(() {
                            editPaymentMethod = 'upi';
                            editIsCredit = false;
                          }),
                        ),
                        const SizedBox(width: 4),
                        ChoiceChip(
                          label: const Text(
                            'CREDIT',
                            style: TextStyle(fontSize: 11),
                          ),
                          selected: editIsCredit,
                          onSelected: (_) => setLocal(() {
                            editPaymentMethod = 'credit';
                            editIsCredit = true;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: discountController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Discount',
                              prefixText: 'Rs ',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setLocal(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: reasonController,
                            decoration: const InputDecoration(
                              labelText: 'Reason for edit *',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty || items.isEmpty) return;
                    Navigator.pop(ctx, {
                      'items': List<PurchaseItem>.from(items),
                      'total': finalTotal,
                      'reason': reason,
                      'supplierId': editSupplierId,
                      'supplierName': editSupplierName,
                      'paymentMethod': editPaymentMethod,
                      'isCredit': editIsCredit,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    reasonController.dispose();
    searchController.dispose();
    discountController.dispose();
    qtyController.dispose();
    priceController.dispose();
    batchController.dispose();
    if (mounted) setState(() => _isProcessing = false);
    if (result == null || !mounted) return;

    final newItems = result['items'] as List<PurchaseItem>;
    final newTotal = result['total'] as double;
    final reason = result['reason'] as String;
    final supplierId = result['supplierId'] as String?;
    final supplierName = result['supplierName'] as String?;
    final paymentMethod = result['paymentMethod'] as String;
    final isCredit = result['isCredit'] as bool;

    final amountPaid = isCredit
        ? (purchase.isCredit ? purchase.amountPaid.clamp(0.0, newTotal) : 0.0)
        : newTotal;
    final dueAmount = isCredit ? (newTotal - amountPaid) : 0.0;

    try {
      await ref
          .read(purchaseServiceProvider)
          .editPurchaseAtomic(
            purchaseId: purchase.id,
            items: newItems,
            totalAmount: newTotal,
            supplierId: supplierId,
            supplierName: supplierName,
            isCredit: isCredit,
            amountPaid: amountPaid,
            dueAmount: dueAmount,
            paymentMethod: paymentMethod,
            reason: reason,
          );
      ref.invalidate(purchasesProvider);
      ref.invalidate(productsProvider);
      ref.invalidate(accountsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildEntryBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Scan barcode or type product name...',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onChanged: _search,
                  onSubmitted: (_) => _selectResult(),
                ),
              ),
              const SizedBox(width: 8),
              _buildActionPill(
                icon: Icons.add_circle_outline,
                label: 'NEW PRODUCT',
                onTap: _addNewProduct,
              ),
              if (_selectedProduct != null) ...[
                const SizedBox(width: 8),
                _buildEntryField(_qtyController, _qtyFocus, 'Qty', 70),
                const SizedBox(width: 6),
                _buildEntryField(_priceController, _priceFocus, 'Price', 100),
                const SizedBox(width: 6),
                _buildEntryField(_batchController, _batchFocus, 'Batch', 130),
              ],
            ],
          ),
          if (_selectedProduct != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _selectedProduct!.name,
                      style: const TextStyle(
                        color: Color(0xFF059669),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '→ ENTER after batch to add',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickExpiry,
                    icon: const Icon(Icons.event, size: 16, color: Color(0xFF64748B)),
                    label: Text(
                      _expiryDate == null
                          ? 'Set Expiry'
                          : 'Exp: ${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            ),
          if (_results.isNotEmpty)
            Container(
              height: 400,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.builder(
                controller: _resultsScrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _results.length,
                itemBuilder: (_, index) {
                  final isSelected = index == _resultIndex;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFECFDF5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF059669).withValues(alpha: 0.3) : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      title: Text(
                        _results[index].name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? const Color(0xFF065F46) : const Color(0xFF1E293B),
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_results[index].tamilName != null &&
                              _results[index].tamilName!.isNotEmpty)
                            Text(
                              _results[index].tamilName!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _buildInfoChip('Buy', '₹${_results[index].purchasePrice}'),
                              const SizedBox(width: 8),
                              _buildInfoChip('Sell', '₹${_results[index].sellingPrice}'),
                              const SizedBox(width: 8),
                              _buildInfoChip('Stock', '${_results[index].stock}'),
                            ],
                          ),
                        ],
                      ),
                      onTap: () {
                        setState(() => _resultIndex = index);
                        _selectResult();
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryField(
    TextEditingController controller,
    FocusNode focus,
    String label,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        focusNode: focus,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          isDense: true,
        ),
        onSubmitted: (_) {
          if (label == 'Qty') _confirmQty();
          if (label == 'Price') _confirmPrice();
          if (label == 'Batch') _addItem();
        },
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.w500),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _addNewProduct() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    // ProductFormScreen currently closes without returning a result.
    // Reload on every return so newly saved products appear immediately.
    await _loadProducts();
    if (mounted) _searchFocus.requestFocus();
  }

  Widget _buildItemsTable() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    'PRODUCT',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    'QTY',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'PRICE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'TOTAL',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SizedBox(width: 64),
              ],
            ),
          ),
          Expanded(
            child: _activeSession.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text(
                          'Scan a product or type to search',
                          style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ctrl+F to focus search',
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _cartScrollController,
                    itemCount: _activeSession.items.length,
                    itemBuilder: (_, index) {
                      final item = _activeSession.items[index];
                      final isCartSelected = index == _cartIndex;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        padding: isCartSelected ? const EdgeInsets.only(left: 3) : null,
                        decoration: BoxDecoration(
                          color: isCartSelected
                              ? const Color(0xFFEFF6FF)
                              : index.isEven
                                  ? Colors.grey.shade50
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCartSelected
                                ? const Color(0xFF2563EB).withValues(alpha: 0.3)
                                : Colors.transparent,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: isCartSelected ? FontWeight.w600 : FontWeight.w500,
                                        fontSize: 13,
                                        color: const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        if (item.tamilName != null && item.tamilName!.isNotEmpty)
                                          Text(
                                            '${item.tamilName} · ',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                          ),
                                        Text(
                                          item.batchNumber ?? 'No batch',
                                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                        ),
                                        const SizedBox(width: 6),
                                        Builder(
                                          builder: (context) {
                                            final product = _products
                                                .where((p) => p.id == item.productId)
                                                .firstOrNull;
                                            final sellPrice = product?.sellingPrice ?? 0;
                                            return Text(
                                              '· Sell ₹$sellPrice',
                                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                            );
                                          },
                                        ),
                                        if (item.expiryDate != null) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              'Exp ${item.expiryDate!.day}/${item.expiryDate!.month}/${item.expiryDate!.year}',
                                              style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 70,
                                child: GestureDetector(
                                  onTap: () {
                                    final qtyController = TextEditingController(text: item.qty.toString());
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Edit Qty — ${item.name}'),
                                        content: TextField(
                                          controller: qtyController,
                                          autofocus: true,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'Quantity',
                                            border: OutlineInputBorder(),
                                          ),
                                          onSubmitted: (_) {
                                            final q = int.tryParse(qtyController.text);
                                            if (q != null && q > 0) {
                                              ref.read(desktopPurchaseProvider.notifier).updateItemQty(index, q);
                                              setState(() {});
                                            }
                                            Navigator.pop(ctx);
                                          },
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                          ElevatedButton(
                                            onPressed: () {
                                              final q = int.tryParse(qtyController.text);
                                              if (q != null && q > 0) {
                                                ref.read(desktopPurchaseProvider.notifier).updateItemQty(index, q);
                                                setState(() {});
                                              }
                                              Navigator.pop(ctx);
                                            },
                                            child: const Text('Update'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${item.qty}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.edit, size: 11, color: Colors.grey[500]),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  '₹${item.price.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  '₹${item.total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 64,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _editPurchasePrice(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(Icons.edit, size: 14, color: Colors.blue.shade600),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        ref.read(desktopPurchaseProvider.notifier).removeItem(index);
                                        setState(() {});
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Icon(Icons.close, size: 14, color: Colors.red.shade400),
                                      ),
                                    ),
                                  ],
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
    );
  }

  Widget _buildFooter() {
    final session = _activeSession;
    final finalTotal = (session.subtotal - session.discount).clamp(0.0, double.infinity);
    final roundedTotal = finalTotal.roundToDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              _buildFooterStat('TOTAL ITEMS', '${session.itemCount}'),
              const SizedBox(width: 32),
              _buildFooterStat('TOTAL QTY', '${session.totalQty}'),
              const Spacer(),
              if (session.discount > 0) ...[
                Text(
                  '-₹${session.discount.toStringAsFixed(0)}  ',
                  style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
                ),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SUBTOTAL',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '₹${roundedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF0F172A),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShortcutHint(label: 'F1', action: 'New Purchase'),
              _Separator(),
              _ShortcutHint(label: 'F2', action: 'History'),
              _Separator(),
              _ShortcutHint(label: 'F5', action: 'Refresh'),
              _Separator(),
              _ShortcutHint(label: 'Ctrl+F', action: 'Search'),
              _Separator(),
              _ShortcutHint(label: 'Ctrl+Enter', action: 'Complete'),
              _Separator(),
              _ShortcutHint(label: 'Ctrl+D', action: 'Discount'),
              _Separator(),
              _ShortcutHint(label: 'Del', action: 'Remove'),
              _Separator(),
              _ShortcutHint(label: 'Esc', action: 'Cancel'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }

  Widget _buildPaymentPanel() {
    final session = _activeSession;
    final finalTotal = (session.subtotal - session.discount).clamp(
      0.0,
      double.infinity,
    );
    final roundedTotal = finalTotal.roundToDouble();
    final roundOff = roundedTotal - finalTotal;
    return Container(
      color: const Color(0xFFF8FAFC),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF059669),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'PURCHASE TOTAL',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${roundedTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                if (roundOff != 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    roundOff > 0
                        ? '+₹${roundOff.toStringAsFixed(2)} round off'
                        : '-₹${(-roundOff).toStringAsFixed(2)} round off',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionLabel('SUPPLIER'),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _selectSupplier,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.business, size: 16, color: Color(0xFF059669)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.supplier?.name ?? 'Select Supplier',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: session.supplier != null
                                        ? const Color(0xFF1E293B)
                                        : Colors.grey[500],
                                  ),
                                ),
                                if (session.supplier != null && _supplierDues > 0)
                                  Text(
                                    'Dues: ₹${_supplierDues.toStringAsFixed(0)}',
                                    style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                                  ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _addSupplier,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF64748B)),
                          SizedBox(width: 4),
                          Text(
                            'Add New Supplier',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (session.supplier != null && _supplierDues > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Previous Dues: ₹${_supplierDues.toStringAsFixed(0)}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildSectionLabel('DISCOUNT'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _discountController,
                    focusNode: _discountFocus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: '0',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    onChanged: (val) {
                      ref.read(desktopPurchaseProvider.notifier).setDiscount(double.tryParse(val) ?? 0);
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildSectionLabel('PAYMENT METHOD'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildPaymentMethodButton('CASH', 'cash', false)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildPaymentMethodButton('UPI', 'upi', false)),
                      const SizedBox(width: 6),
                      Expanded(child: _buildPaymentMethodButton('CREDIT', 'credit', true)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Total: ', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      Text(
                        '₹${roundedTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: session.items.isEmpty || _loading
                    ? null
                    : _completePurchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _loading ? 'Saving...' : 'COMPLETE PURCHASE',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildPaymentMethodButton(String label, String value, bool isCredit) {
    final session = _activeSession;
    final isActive = isCredit
        ? session.isCredit
        : (session.paymentMethod == value && !session.isCredit);
    return GestureDetector(
      onTap: () => ref.read(desktopPurchaseProvider.notifier).setPaymentMethod(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF059669) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF059669) : Colors.grey.shade300,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF475569),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _scrollCartToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cartScrollController.hasClients) {
        _cartScrollController.animateTo(
          _cartScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollCartToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_cartScrollController.hasClients) {
        final offset = index * 64.0;
        _cartScrollController.animateTo(
          offset.clamp(0.0, _cartScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    _batchController.dispose();
    _discountController.dispose();
    _searchFocus.dispose();
    _qtyFocus.dispose();
    _priceFocus.dispose();
    _batchFocus.dispose();
    _discountFocus.dispose();
    _resultsScrollController.dispose();
    _cartScrollController.dispose();
    super.dispose();
  }
}

class _ShortcutHint extends StatelessWidget {
  final String label;
  final String action;

  const _ShortcutHint({required this.label, required this.action});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
          TextSpan(
            text: ': $action',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3)),
      ),
    );
  }
}
