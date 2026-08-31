import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

  double get _total => _activeSession.subtotal;

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
      const rowHeight = 56.0;
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
      color: Colors.black.withValues(alpha: 0.3),
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Processing...', style: TextStyle(fontSize: 14)),
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

        // Enter: context-sensitive
        if (key == LogicalKeyboardKey.enter) {
          if (_selectedProduct == null && _results.isNotEmpty) {
            _selectResult();
          } else if (_selectedProduct != null && _qtyFocus.hasFocus) {
            _confirmQty();
          } else if (_selectedProduct != null && _priceFocus.hasFocus) {
            _confirmPrice();
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
        color: const Color(0xFFF5F5F5),
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  height: 46,
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => ref.read(currentTabProvider.notifier).state = 0,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back, color: Colors.white70, size: 18),
                            SizedBox(width: 6),
                            Text('Menu', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            SizedBox(width: 12),
                          ],
                        ),
                      ),
                      _purchaseTab(
                        'NEW PURCHASE',
                        !_showHistory,
                        () => setState(() => _showHistory = false),
                      ),
                      _purchaseTab(
                        'PURCHASE HISTORY',
                        _showHistory,
                        () => setState(() => _showHistory = true),
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
        alignment: Alignment.center,
        color: selected ? const Color(0xFF11998e) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseHistory() {
    final purchases = ref.watch(purchasesProvider);
    return purchases.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('No purchases yet'));
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(purchasesProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final purchase = items[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(
                    'Rs${purchase.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${purchase.items.length} products | ${purchase.supplierName ?? 'No supplier'} | ${AppTimezone.formatDateTime(purchase.createdAt)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'details',
                        child: Text('View Items'),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit Purchase'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
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
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref
                              .read(purchaseServiceProvider)
                              .deletePurchase(purchase.id);
                          ref.invalidate(purchasesProvider);
                          ref.invalidate(productsProvider);
                        }
                      }
                    },
                  ),
                ),
              );
            },
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
                  decoration: const InputDecoration(
                    labelText: 'Type product name or code...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _search,
                  onSubmitted: (_) => _selectResult(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _addNewProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Product'),
              ),
              if (_selectedProduct != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _qtyController,
                    focusNode: _qtyFocus,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirmQty(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _priceController,
                    focusNode: _priceFocus,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Purchase Price',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirmPrice(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _batchController,
                    focusNode: _batchFocus,
                    decoration: const InputDecoration(
                      labelText: 'Batch (optional)',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
              ],
            ],
          ),
          if (_selectedProduct != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedProduct!.name} — ENTER after batch to add',
                    style: const TextStyle(
                      color: Color(0xFF667eea),
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickExpiry,
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(
                    _expiryDate == null
                        ? 'Expiry'
                        : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                  ),
                ),
              ],
            ),
          if (_results.isNotEmpty)
            Container(
              height: 500,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ListView.builder(
                controller: _resultsScrollController,
                itemCount: _results.length,
                itemBuilder: (_, index) {
                  final isSelected = index == _resultIndex;
                  return Container(
                    color: isSelected ? const Color(0xFFCCFBF1) : null,
                    child: ListTile(
                      selected: isSelected,
                      selectedTileColor: const Color(0xFFCCFBF1),
                      title: Text(
                        _results[index].name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? const Color(0xFF065F46) : null,
                          fontSize: isSelected ? 15 : 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_results[index].tamilName != null &&
                              _results[index].tamilName!.isNotEmpty)
                            Text(
                              _results[index].tamilName!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          Text(
                            'Purchase: Rs${_results[index].purchasePrice} | Sell: Rs${_results[index].sellingPrice} | Stock: ${_results[index].stock}',
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF065F46)
                                  : Colors.grey[700],
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
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
      margin: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF11998e),
            padding: const EdgeInsets.all(10),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    'Product',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    'Qty',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Price',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Total',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _activeSession.items.isEmpty
                ? const Center(child: Text('Type a product to start purchase'))
                : ListView.builder(
                    controller: _cartScrollController,
                    itemCount: _activeSession.items.length,
                    itemBuilder: (_, index) {
                      final item = _activeSession.items[index];
                      final isCartSelected = index == _cartIndex;
                      return Container(
                        color: isCartSelected
                            ? const Color(0xFFE0F2FE)
                            : index.isEven
                                ? Colors.grey.shade50
                                : Colors.white,
                        child: ListTile(
                        dense: true,
                        title: Text(item.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.tamilName != null &&
                                item.tamilName!.isNotEmpty)
                              Text(
                                item.tamilName!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            Builder(
                              builder: (context) {
                                final product = _products
                                    .where((p) => p.id == item.productId)
                                    .firstOrNull;
                                final sellPrice = product?.sellingPrice ?? 0;
                                return Text(
                                  '${item.batchNumber ?? 'No batch'} | Sell: Rs${sellPrice.toStringAsFixed(0)}${item.expiryDate == null ? '' : ' | Exp ${item.expiryDate!.day}/${item.expiryDate!.month}/${item.expiryDate!.year}'}',
                                );
                              },
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    final qtyController = TextEditingController(text: item.qty.toString());
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Edit Qty - ${item.name}'),
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
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${item.qty}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.edit, size: 12, color: Colors.grey[500]),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '× Rs${item.price.toStringAsFixed(0)}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            const SizedBox(width: 24),
                            Text(
                              'Rs${item.total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              onPressed: () => _editPurchasePrice(index),
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.blue,
                                size: 16,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                ref
                                    .read(desktopPurchaseProvider.notifier)
                                    .removeItem(index);
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.close,
                                color: Colors.red,
                                size: 16,
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

  Widget _buildFooter() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Products: ${_activeSession.items.length} | Total: Rs${_total.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          'Ctrl+1 New | Ctrl+2 History | Ctrl+F Search | Ctrl+D Discount | Ctrl+Enter Complete | Esc Back',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    ),
  );

  Widget _buildPaymentPanel() {
    final session = _activeSession;
    final finalTotal = (session.subtotal - session.discount).clamp(
      0.0,
      double.infinity,
    );
    final roundedTotal = finalTotal.roundToDouble();
    final roundOff = roundedTotal - finalTotal;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PURCHASE TOTAL\nRs${roundedTotal.toStringAsFixed(0)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF11998e),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _selectSupplier,
            icon: const Icon(Icons.business, size: 18),
            label: Text(session.supplier?.name ?? 'Select Supplier'),
          ),
          if (session.supplier != null && _supplierDues > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Previous Dues: Rs${_supplierDues.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          TextButton.icon(
            onPressed: _addSupplier,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text('Add New Supplier'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Discount: ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: TextField(
                  controller: _discountController,
                  focusNode: _discountFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: '0',
                    prefixText: 'Rs ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (val) {
                    ref
                        .read(desktopPurchaseProvider.notifier)
                        .setDiscount(double.tryParse(val) ?? 0);
                  },
                ),
              ),
            ],
          ),
          if (roundOff != 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Round Off', style: TextStyle(fontSize: 13)),
                Text(
                  roundOff > 0
                      ? '+Rs${roundOff.toStringAsFixed(2)}'
                      : '-Rs${(-roundOff).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: roundOff > 0 ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildPaymentMethodButton('CASH', 'cash', false),
          const SizedBox(height: 6),
          _buildPaymentMethodButton('UPI / DIGITAL', 'upi', false),
          const SizedBox(height: 6),
          _buildPaymentMethodButton('CREDIT', 'credit', true),
          const Spacer(),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: session.items.isEmpty || _loading
                  ? null
                  : _completePurchase,
              child: Text(_loading ? 'Saving...' : 'COMPLETE PURCHASE (ENTER)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodButton(String label, String value, bool isCredit) {
    final session = _activeSession;
    final isActive = isCredit
        ? session.isCredit
        : (session.paymentMethod == value && !session.isCredit);
    final color = isActive ? const Color(0xFF11998e) : Colors.grey.shade200;
    final textColor = isActive ? Colors.white : Colors.black87;
    final borderColor = isActive
        ? const Color(0xFF11998e)
        : Colors.grey.shade300;
    return Focus(
      child: GestureDetector(
        onTap: () =>
            ref.read(desktopPurchaseProvider.notifier).setPaymentMethod(value),
        child: Builder(
          builder: (ctx) {
            final focused = Focus.of(ctx).hasFocus;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: focused ? const Color(0xFF667eea) : borderColor,
                  width: focused ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
            );
          },
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
