import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/providers.dart';
import '../../config/desktop_billing_provider.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../services/email_service.dart';

import '../../services/thermal_printer_service.dart';
import '../../services/offline_service.dart';
import '../../utils/app_timezone.dart';
import '../../utils/invoice_generator.dart';
import '../../utils/logger.dart';
import '../../utils/thermal_invoice.dart';
import '../../utils/pin_auth.dart';
import '../shared/product_form_screen.dart';
import '../admin/barcode_label_screen.dart';

import '../../utils/error_messages.dart';
import 'billing_shortcuts_mixin.dart';
import 'widgets/billing_bottom_bar.dart';
import 'widgets/billing_processing_overlay.dart';
import 'widgets/billing_sale_tabs.dart';
import '../../widgets/rate_picker_dialog.dart';
import 'dialogs/customer_picker_dialog.dart';
import 'dialogs/sales_history_dialog.dart';
import 'dialogs/invoice_options_dialog.dart';

class DesktopBillingScreen extends ConsumerStatefulWidget {
  const DesktopBillingScreen({super.key});

  @override
  ConsumerState<DesktopBillingScreen> createState() =>
      _DesktopBillingScreenState();
}

class _DesktopBillingScreenState extends ConsumerState<DesktopBillingScreen> with BillingShortcutsMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _qtyController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _totalController = TextEditingController();
  final _qtyFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();
  final _totalFocusNode = FocusNode();
  final _itemDiscountController = TextEditingController();
  final _costController = TextEditingController();
  final _costFocusNode = FocusNode();
  final _billDiscountController = TextEditingController();
  final _billDiscountFocusNode = FocusNode();
  final _extraChargesController = TextEditingController();
  final _extraChargesFocusNode = FocusNode();
  final _paidController = TextEditingController();
  final _paidFocusNode = FocusNode();
  final _resultsScrollController = ScrollController();
  final _cartScrollController = ScrollController();

  // Field navigation order (left→right)
  List<FocusNode> get _entryFieldOrder {
    final fields = <FocusNode>[
      if (_selectedProduct == null) _searchFocusNode,
      _qtyFocusNode,
      _priceFocusNode,
      _totalFocusNode,
      _costFocusNode,
    ];
    return fields;
  }
  List<FocusNode> get _paymentFieldOrder => [
    _billDiscountFocusNode,
    _extraChargesFocusNode,
    _paidFocusNode,
  ];

  List<Product> _allProducts = [];
  List<Product> _searchResults = [];
  Product? _selectedProduct;
  int _selectedResultIndex = 0;
  bool _showResults = false;
  final _keyboardFocusNode = FocusNode();
  int _selectedCartIndex = -1;
  int _editingCartIndex = -1;
  List<Map<String, dynamic>> _heldBills = [];
  bool _isSyncing = false;
  bool _isProcessing = false;
  double _customerCredit = 0;
  String _searchMode = 'code'; // 'code' or 'products'
  String _selectedUnitType = 'pieces';
  int _piecesPerUnit = 1;
  String? _selectedRateLabel;
  Sale? _editingSale; // Track sale being edited from sales history
  Timer? _searchDebounce;

  // Payment state
  String _selectedPayment = 'cash';
  bool _creditFull = true;
  bool _isSplitPayment = false;
  final _splitCashController = TextEditingController();
  final _splitUpiController = TextEditingController();

  // Session lock timer
  Timer? _inactivityTimer;
  static const _inactivityTimeout = Duration(minutes: 5);
  String? _unlockErrorText;

  // Product list state
  List<Map<String, dynamic>> _recentlySold = [];
  String _selectedTier = 'normal';

  double get _billDiscount =>
      double.tryParse(_billDiscountController.text) ?? 0;

  // ── Mixin abstract method implementations ──
  @override
  bool get isProcessing => _isProcessing;
  @override
  bool get hasActiveSessionItems {
    final session = ref.read(desktopBillingProvider).elementAt(
        ref.read(desktopBillingProvider.notifier).activeSessionIndex);
    return session.items.isNotEmpty;
  }
  @override
  bool get isSearchFocused => _searchFocusNode.hasFocus;
  @override
  bool get hasSearchText => _searchController.text.isNotEmpty;
  @override
  bool get hasSelectedProduct => _selectedProduct != null;
  @override
  bool get isQtyFocused => _qtyFocusNode.hasFocus;
  @override
  bool get isPriceFocused => _priceFocusNode.hasFocus;
  @override
  bool get isTotalFocused => _totalFocusNode.hasFocus;
  @override
  bool get isCostFocused => _costFocusNode.hasFocus;
  @override
  bool get hasSelectedCartIndex => _selectedCartIndex >= 0;
  @override
  bool get showResults => _showResults;

  @override
  void onF2() {
    if (_selectedCartIndex >= 0) _editCartItem(_selectedCartIndex);
  }

  @override
  void onF3() {
    setState(() {
      _searchMode = _searchMode == 'code' ? 'products' : 'code';
    });
  }

  @override
  void onF4() => _showCustomerPicker();

  @override
  void onF5() {
    const tiers = ['normal', 'wholesale', 'bulk'];
    final nextIndex = (tiers.indexOf(_selectedTier) + 1) % tiers.length;
    setState(() => _selectedTier = tiers[nextIndex]);
    ref
        .read(desktopBillingProvider.notifier)
        .updateAllItemPricesFromCurrent(_selectedTier);
  }

  @override
  void onF6() => _holdBill();

  @override
  void onF7() => _retrieveBill();

  @override
  void onF8() {
    setState(() {
      _selectedPayment = 'cash';
      _isSplitPayment = false;
    });
  }

  @override
  void onF9() {
    setState(() {
      _selectedPayment = 'upi';
      _isSplitPayment = false;
    });
  }

  @override
  void onF10() {
    setState(() {
      _selectedPayment = 'credit';
      _creditFull = true;
      _isSplitPayment = false;
    });
  }

  @override
  void onF11() {
    final session = ref.read(desktopBillingProvider).elementAt(
        ref.read(desktopBillingProvider.notifier).activeSessionIndex);
    setState(() {
      _isSplitPayment = !_isSplitPayment;
      if (_isSplitPayment) {
        _selectedPayment = 'split';
        _splitCashController.text = (session.total).toStringAsFixed(0);
        _splitUpiController.text = '0';
      } else {
        _selectedPayment = 'cash';
      }
    });
  }

  @override
  void onF12() {
    if (Platform.isWindows) {
      Process.run('calc', []);
    }
  }

  @override
  void onCtrlShiftN() => _addNewProduct();

  @override
  void onCtrlD() => _addNewCustomer();

  @override
  void onCtrlDelete() => _confirmClearCart();

  @override
  void onShiftEnter() => _completeSale();

  @override
  void onEnter() {
    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      _onSearchEnter();
    } else if (_selectedProduct != null && _qtyFocusNode.hasFocus) {
      _confirmQty();
    } else if (_selectedProduct != null && _priceFocusNode.hasFocus) {
      _confirmPrice();
    } else if (_selectedProduct != null && _totalFocusNode.hasFocus) {
      _confirmTotal();
    } else if (_selectedProduct != null && _costFocusNode.hasFocus) {
      _confirmTotal();
    } else if (_selectedCartIndex >= 0 && _selectedProduct == null) {
      _editCartItem(_selectedCartIndex);
    }
  }

  @override
  void onTab(bool isShift) => _focusNextField(isShift: isShift);

  @override
  void onCtrlTab() => _billDiscountFocusNode.requestFocus();

  @override
  void onArrowDown() {
    if (_showResults && _selectedResultIndex < _searchResults.length - 1) {
      setState(() => _selectedResultIndex++);
      _scrollSelectedResultIntoView();
    } else if (!_showResults) {
      final session = ref.read(desktopBillingProvider).elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex);
      if (_selectedCartIndex < session.items.length - 1) {
        setState(() {
          _selectedCartIndex++;
          _editingCartIndex = -1;
        });
      }
    }
  }

  @override
  void onArrowUp() {
    if (_showResults && _selectedResultIndex > 0) {
      setState(() => _selectedResultIndex--);
      _scrollSelectedResultIntoView();
    } else if (!_showResults && _selectedCartIndex > 0) {
      setState(() {
        _selectedCartIndex--;
        _editingCartIndex = -1;
      });
    }
  }

  @override
  void onDelete() => _deleteSelectedCartItem();

  @override
  void onPlus() => _adjustCartQty(_selectedCartIndex, 1);

  @override
  void onMinus() => _adjustCartQty(_selectedCartIndex, -1);

  @override
  void onEscape() {
    if (_editingCartIndex >= 0) {
      _cancelEdit();
    } else if (_selectedProduct != null) {
      setState(() {
        _selectedProduct = null;
        _editingCartIndex = -1;
      });
      _searchController.clear();
      _searchFocusNode.requestFocus();
    } else if (_selectedCartIndex >= 0) {
      setState(() {
        _selectedCartIndex = -1;
      });
      _searchFocusNode.requestFocus();
    } else if (_showResults) {
      setState(() {
        _showResults = false;
        _selectedResultIndex = 0;
      });
      _searchFocusNode.requestFocus();
    } else {
      _searchController.clear();
      _searchFocusNode.requestFocus();
    }
  }

  @override
  void onResetInactivityTimer() => _resetInactivityTimer();

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadHeldBills();
    _loadRecentlySold();
    _startInactivityTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ref.read(productServiceProvider).getAllProducts();
      Logger.info('Loaded ${products.length} products');
      if (mounted) {
        setState(() {
          _allProducts = products;
        });
      }
    } catch (e) {
      Logger.error('Failed to load products', e);
    }
  }

  Future<void> _loadRecentlySold() async {
    try {
      final service = ref.read(saleServiceProvider);
      final products = await service.getTopSoldProducts(limit: 10);
      if (mounted) {
        setState(() {
          _recentlySold = products;
        });
      }
    } catch (e) {
      Logger.warning('Failed to load recently sold: $e');
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _onInactivityTimeout);
  }

  void _resetInactivityTimer() {
    _startInactivityTimer();
  }

  void _onInactivityTimeout() {
    if (_isProcessing) return;
    final session = ref.read(desktopBillingProvider).elementAt(
        ref.read(desktopBillingProvider.notifier).activeSessionIndex);
    if (session.items.isNotEmpty) {
      _holdBill();
    }
    _showUnlockDialog();
  }

  void _showUndoToast() {
    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (ctx) => Positioned(
        bottom: 80,
        left: MediaQuery.of(ctx).size.width / 2 - 150,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Item removed', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlay);
    Future.delayed(const Duration(seconds: 3), () {
      overlay?.remove();
    });
  }

  void _showUnlockDialog() {
    final pinController = TextEditingController();
    bool obscurePin = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.orange),
              SizedBox(width: 8),
              Text('Session Locked'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter PIN to unlock'),
              const SizedBox(height: 12),
              TextField(
                controller: pinController,
                obscureText: obscurePin,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  errorText: _unlockErrorText,
                  suffixIcon: IconButton(
                    icon: Icon(obscurePin ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setDialogState(() => obscurePin = !obscurePin),
                  ),
                ),
                onSubmitted: (_) => _verifyUnlockPin(ctx, pinController, setDialogState),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startInactivityTimer();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => _verifyUnlockPin(ctx, pinController, setDialogState),
              child: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  void _verifyUnlockPin(BuildContext ctx, TextEditingController controller, StateSetter setDialogState) {
    final pin = controller.text.trim();
    if (pin.isEmpty) return;

    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setDialogState(() => _unlockErrorText = 'Profile not loaded');
      return;
    }

    final storedHash = profile.pin;
    if (storedHash == null || PinAuth.verifyPin(pin, storedHash)) {
      _unlockErrorText = null;
      _startInactivityTimer();
      Navigator.pop(ctx);
    } else {
      setDialogState(() => _unlockErrorText = 'Incorrect PIN');
      controller.clear();
    }
  }

  Future<void> _loadHeldBills() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('desktop_held_bills');
      if (data == null || data.isEmpty) return;
      final list = (jsonDecode(data) as List);
      _heldBills = list.map((e) {
        final m = e as Map<String, dynamic>;
        final s = m['session'] as Map<String, dynamic>;
        final items = (s['items'] as List).map((i) {
          final im = i as Map<String, dynamic>;
          return DesktopCartItem(
            productId: im['product_id'] as String,
            name: im['name'] as String,
            price: (im['price'] as num).toDouble(),
            qty: (im['qty'] as num).toInt(),
            unit: im['unit'] as String? ?? 'pcs',
            purchasePrice: (im['purchase_price'] as num?)?.toDouble() ?? 0,
            gstRate: (im['gst_rate'] as num?)?.toDouble() ?? 0,
            hsnCode: im['hsn_code'] as String?,
            tamilName: im['tamil_name'] as String?,
            discount: (im['discount'] as num?)?.toDouble() ?? 0,
          );
        }).toList();
        return {
          'session': SaleSession(
            id: s['id'] as String,
            items: items,
            customerId: s['customer_id'] as String?,
            customerName: s['customer_name'] as String?,
            totalDiscount: (s['total_discount'] as num?)?.toDouble() ?? 0,
            paymentMethod: s['payment_method'] as String? ?? 'cash',
            isCredit: s['is_credit'] as bool? ?? false,
            amountPaid: (s['amount_paid'] as num?)?.toDouble() ?? 0,
          ),
          'time': DateTime.tryParse(m['time'] as String? ?? '') ?? DateTime.now(),
        };
      }).toList();
    } catch (e) {
      Logger.warning('Failed to load held bills: $e');
    }
  }

  Future<void> _saveHeldBills() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _heldBills.map((bill) {
        final session = bill['session'] as SaleSession;
        return {
          'session': {
            'id': session.id,
            'items': session.items
                .map((i) => {
                      'product_id': i.productId,
                      'name': i.name,
                      'price': i.price,
                      'qty': i.qty,
                      'unit': i.unit,
                      'purchase_price': i.purchasePrice,
                      'gst_rate': i.gstRate,
                      'hsn_code': i.hsnCode,
                      'tamil_name': i.tamilName,
                      'discount': i.discount,
                    })
                .toList(),
            'customer_id': session.customerId,
            'customer_name': session.customerName,
            'total_discount': session.totalDiscount,
            'payment_method': session.paymentMethod,
            'is_credit': session.isCredit,
            'amount_paid': session.amountPaid,
          },
          'time': (bill['time'] as DateTime).toIso8601String(),
        };
      }).toList();
      await prefs.setString('desktop_held_bills', jsonEncode(data));
    } catch (e) {
      Logger.warning('Failed to save held bills: $e');
    }
  }

  Future<void> _addNewProduct() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );

    // ProductFormScreen closes without a result in some flows, so always reload.
    ref.invalidate(productsProvider);
    await _loadProducts();
    if (mounted) {
      setState(() {
        _searchController.clear();
        _searchResults = [];
        _showResults = false;
        _selectedProduct = null;
      });
      _searchFocusNode.requestFocus();
    }
  }

  Future<void> _loadCustomerCredit(String customerId) async {
    try {
      final res = await Supabase.instance.client
          .from('customers')
          .select('total_credit')
          .eq('id', customerId)
          .maybeSingle();
      if (res != null && mounted) {
        setState(
          () =>
              _customerCredit = (res['total_credit'] as num?)?.toDouble() ?? 0,
        );
      }
    } catch (e) {
      Logger.warning('Failed to fetch customer credit: $e');
    }
  }

  // ── FIELD NAVIGATION ──
  void _focusNextField({required bool isShift}) {
    final fields = _selectedProduct != null
        ? _entryFieldOrder
        : _paymentFieldOrder;
    final currentIdx = fields.indexWhere((f) => f.hasFocus);
    if (currentIdx == -1) {
      fields.first.requestFocus();
    } else if (isShift) {
      final prev = currentIdx > 0 ? currentIdx - 1 : fields.length - 1;
      fields[prev].requestFocus();
    } else {
      final next = (currentIdx + 1) % fields.length;
      fields[next].requestFocus();
    }
  }

  // ── SEARCH ──
  Future<void> _searchProducts(String query) async {
    Logger.info(
      'Search called with: "$query", products count: ${_allProducts.length}',
    );
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
        _selectedProduct = null;
      });
      return;
    }

    // If products not loaded yet, load them first
    if (_allProducts.isEmpty) {
      Logger.info('Products empty, loading...');
      _loadProducts().then((_) {
        if (mounted) _searchProducts(query);
      });
      return;
    }

    final q = query.toLowerCase().replaceAll(RegExp(r'\broses?\b'), 'rose');
    final results = _allProducts.where((p) {
      if (_searchMode == 'code') {
        // Code mode: search against code field
        final code = (p.sfw ?? '').toLowerCase();
        return code.contains(q);
      } else {
        // Products mode: search against name and barcode
        final pName = p.name.toLowerCase().replaceAll(
          RegExp(r'\broses?\b'),
          'rose',
        );
        return pName.contains(q) ||
            (p.barcode?.toLowerCase().contains(query.toLowerCase()) ?? false);
      }
    }).toList();

    Logger.info('Search "$q" found ${results.length} matches');
    if (results.isNotEmpty) {
      Logger.info('First 3: ${results.take(3).map((p) => p.name).join(", ")}');
    }

    results.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      if (aName == q && bName != q) return -1;
      if (aName != q && bName == q) return 1;
      if (aName.startsWith(q) && !bName.startsWith(q)) return -1;
      if (!aName.startsWith(q) && bName.startsWith(q)) return 1;
      return 0;
    });

    setState(() {
      _searchResults = results;
      _selectedResultIndex = 0;
      _showResults = results.isNotEmpty;
      if (results.length == 1) {
        final p = results.first;
        if (p.stock <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${p.name} is out of stock'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() {
            _searchResults = results;
            _selectedProduct = null;
            _showResults = true;
          });
        } else {
          final cost = (p.purchasePrice > 0)
              ? p.purchasePrice
              : (p.variants.isNotEmpty
                  ? p.variants.first.purchasePrice
                  : 0.0);
          _selectedProduct = p;
          _qtyController.text = '1';
          _costController.text = cost.toStringAsFixed(2);
          _searchResults = [];
          _showResults = false;
        }
      } else {
        _selectedProduct = null;
      }
    });
    if (_selectedProduct != null) {
      // Show rate picker if product has dual rates
      final picked = await RatePickerDialog.show(context, _selectedProduct!);
      final price = picked?.price ?? _selectedProduct!.sellingPrice;
      final rateLabel = picked?.label;
      setState(() {
        _selectedRateLabel = rateLabel;
        _priceController.text = price.toStringAsFixed(2);
        _totalController.text = price.toStringAsFixed(2);
      });
      _qtyFocusNode.requestFocus();
      _qtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _qtyController.text.length,
      );
    } else {
      _scrollSelectedResultIntoView();
    }
  }

  void _scrollSelectedResultIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_resultsScrollController.hasClients || _searchResults.isEmpty)
        return;
      const rowHeight = 60.0;
      final targetTop = _selectedResultIndex * rowHeight;
      final targetBottom = targetTop + rowHeight;
      final viewportTop = _resultsScrollController.offset;
      final viewportBottom =
          viewportTop + _resultsScrollController.position.viewportDimension;

      if (targetTop < viewportTop) {
        _resultsScrollController.animateTo(
          targetTop,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      } else if (targetBottom > viewportBottom) {
        _resultsScrollController.animateTo(
          targetBottom - _resultsScrollController.position.viewportDimension,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _onSearchEnter() async {
    if (_searchResults.isNotEmpty) {
      _selectSearchResult();
    } else if (_searchController.text.isNotEmpty) {
      final q = _searchController.text.toLowerCase();
      final match = _allProducts
          .where((p) => p.name.toLowerCase() == q)
          .firstOrNull;
      if (match != null) {
        if ((match.stock as num).toInt() <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product has no stock. Add stock before billing.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        setState(() {
          _selectedProduct = match;
          final price = (match.sellingPrice as num).toDouble();
          _priceController.text = price.toStringAsFixed(2);
          _totalController.text = (price * 1).toStringAsFixed(2);
          _searchController.clear();
          _showResults = false;
          _itemDiscountController.clear();
          final cost = (match.purchasePrice > 0)
              ? match.purchasePrice
              : (match.variants.isNotEmpty
                  ? match.variants.first.purchasePrice
                  : 0.0);
          _costController.text = cost.toStringAsFixed(2);
        });
        _qtyFocusNode.requestFocus();
      }
    }
  }

  Future<void> _selectSearchResult() async {
    if (_searchResults.isEmpty) return;
    final product = _searchResults[_selectedResultIndex];

    if ((product.stock as num).toInt() <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product has no stock. Add stock before billing.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _selectedProduct = product;

    final cost = (product.purchasePrice > 0)
        ? product.purchasePrice
        : (product.variants.isNotEmpty
            ? product.variants.first.purchasePrice
            : 0.0);
    final qty = int.tryParse(_qtyController.text) ?? 1;

    setState(() {
      _selectedUnitType = product.unitType;
      _piecesPerUnit = product.piecesPerUnit;
      _qtyController.text = qty.toString();
      _costController.text = cost.toStringAsFixed(2);
      _searchController.clear();
      _searchResults = [];
      _showResults = false;
      _itemDiscountController.clear();
    });

    // Show rate picker if product has dual rates
    final picked = await RatePickerDialog.show(context, _selectedProduct!);
    final price = picked?.price ?? _selectedProduct!.sellingPrice;
    final rateLabel = picked?.label;

    setState(() {
      _selectedRateLabel = rateLabel;
      _priceController.text = price.toStringAsFixed(2);
      _totalController.text = (price * qty).toStringAsFixed(2);
    });

    _qtyFocusNode.requestFocus();
    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  // ── TWO-WAY PRICE/TOTAL SYNC ──
  void _syncTotalFromPrice() {
    if (_isSyncing) return;
    _isSyncing = true;
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final price = double.tryParse(_priceController.text) ?? 0;
    _totalController.text = (price * qty).toStringAsFixed(2);
    _isSyncing = false;
  }

  void _syncPriceFromTotal() {
    if (_isSyncing) return;
    _isSyncing = true;
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final total = double.tryParse(_totalController.text) ?? 0;
    if (qty > 0) {
      _priceController.text = (total / qty).toStringAsFixed(2);
    }
    _isSyncing = false;
  }

  // ── ENTRY PROGRESSION ──
  void _confirmQty() {
    _syncTotalFromPrice();
    _priceFocusNode.requestFocus();
    _priceController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _priceController.text.length,
    );
  }

  void _confirmPrice() {
    _syncTotalFromPrice();
    _totalFocusNode.requestFocus();
    _totalController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _totalController.text.length,
    );
  }

  void _confirmTotal() {
    if (_selectedProduct == null && _editingCartIndex < 0) return;

    final qty = int.tryParse(_qtyController.text) ?? 1;
    final total = double.tryParse(_totalController.text) ?? 0;
    final double effectivePrice = qty > 0 ? total / qty : 0;
    final itemDiscount = double.tryParse(_itemDiscountController.text) ?? 0;
    final costPrice = double.tryParse(_costController.text) ?? 0;

    // Validate price and qty
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantity must be at least 1'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (effectivePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Price must be greater than 0'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );

    if (_editingCartIndex >= 0) {
      // UPDATE existing cart item
      final oldItem = session.items[_editingCartIndex];
        ref
            .read(desktopBillingProvider.notifier)
            .updateItem(
              _editingCartIndex,
              DesktopCartItem(
                productId: oldItem.productId,
                name: oldItem.name,
                price: effectivePrice,
                qty: qty,
                unit: oldItem.unit,
                purchasePrice: costPrice,
                gstRate: oldItem.gstRate,
                hsnCode: oldItem.hsnCode,
                tamilName: oldItem.tamilName,
                discount: itemDiscount,
                rateLabel: _selectedRateLabel,
              ),
            );
    } else {
      // ADD new item
      final existingIndex = session.items.indexWhere(
        (i) => i.productId == (_selectedProduct?.id ?? ''),
      );
      if (existingIndex >= 0) {
        final existingItem = session.items[existingIndex];
        ref
            .read(desktopBillingProvider.notifier)
            .updateItemQty(existingIndex, existingItem.qty + qty);
      } else {
        ref
            .read(desktopBillingProvider.notifier)
            .addItem(
              DesktopCartItem(
                productId: _selectedProduct!.id,
                name: _selectedProduct!.name,
                price: effectivePrice,
                qty: qty,
                unit: _selectedProduct!.unit,
                purchasePrice: costPrice,
                gstRate: _selectedProduct!.gstRate,
                hsnCode: _selectedProduct!.hsnCode,
                tamilName: _selectedProduct!.tamilName,
                discount: itemDiscount,
                unitType: _selectedUnitType,
                piecesPerUnit: _piecesPerUnit,
                rateLabel: _selectedRateLabel,
              ),
            );
      }
    }

    setState(() {
      _selectedProduct = null;
      _editingCartIndex = -1;
      _selectedCartIndex = -1;
      _selectedUnitType = 'pieces';
      _piecesPerUnit = 1;
      _selectedRateLabel = null;
      _qtyController.text = '1';
      _priceController.clear();
      _totalController.clear();
      _itemDiscountController.clear();
      _costController.clear();
    });

    _scrollCartToBottom();
    _searchFocusNode.requestFocus();
  }

  // ── CART ──
  void _editCartItem(int index) {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    if (index < 0 || index >= session.items.length) return;

    final item = session.items[index];
    final product = _allProducts
        .where((p) => p.id == item.productId)
        .firstOrNull;

    setState(() {
      _editingCartIndex = index;
      _selectedCartIndex = index;
      _selectedProduct = product;
      _selectedRateLabel = item.rateLabel;
      _searchController.clear();
      _searchResults = [];
      _showResults = false;
      _qtyController.text = item.qty.toString();
      _priceController.text = item.price.toStringAsFixed(2);
      _totalController.text = (item.qty * item.price).toStringAsFixed(2);
      _itemDiscountController.text = item.discount > 0
          ? item.discount.toStringAsFixed(0)
          : '';
      _costController.text = item.purchasePrice.toStringAsFixed(2);
    });

    _qtyFocusNode.requestFocus();
    _qtyController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _qtyController.text.length,
    );
  }

  void _cancelEdit() {
    setState(() {
      _editingCartIndex = -1;
      _selectedProduct = null;
      _selectedCartIndex = -1;
      _qtyController.text = '1';
      _priceController.clear();
      _totalController.clear();
      _itemDiscountController.clear();
      _costController.clear();
      _selectedUnitType = 'pieces';
      _piecesPerUnit = 1;
    });
    _searchFocusNode.requestFocus();
  }

  void _showPiecesPerUnitDialog(String unitType) {
    final ctrl = TextEditingController(text: '$_piecesPerUnit');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('How many pieces per $unitType?'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Pieces per $unitType',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text) ?? 1;
              setState(() => _piecesPerUnit = val > 0 ? val : 1);
              Navigator.pop(ctx);
              _qtyFocusNode.requestFocus();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedCartItem() {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    if (_selectedCartIndex >= 0 && _selectedCartIndex < session.items.length) {
      ref.read(desktopBillingProvider.notifier).removeItem(_selectedCartIndex);
      setState(() {
        // Re-read session after removal to get correct length
        final updatedSession = ref
            .read(desktopBillingProvider)
            .elementAt(
              ref.read(desktopBillingProvider.notifier).activeSessionIndex,
            );
        if (_selectedCartIndex >= updatedSession.items.length) {
          _selectedCartIndex = updatedSession.items.length - 1;
        }
      });
    }
  }

  void _adjustCartQty(int index, int delta) {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    if (index < 0 || index >= session.items.length) return;
    final item = session.items[index];
    final newQty = item.qty + delta;
    if (newQty < 1) return;
    ref.read(desktopBillingProvider.notifier).updateItemQty(index, newQty);
    setState(() {});
  }

  // ── HOLD / RETRIEVE ──
  void _holdBill() {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    if (session.items.isEmpty) return;

    _heldBills.add({
      'session': SaleSession(
        id: session.id,
        items: List<DesktopCartItem>.from(session.items),
        customerId: session.customerId,
        customerName: session.customerName,
        totalDiscount: session.totalDiscount,
        paymentMethod: session.paymentMethod,
        isCredit: session.isCredit,
        amountPaid: session.amountPaid,
      ),
      'time': DateTime.now(),
    });

    ref
        .read(desktopBillingProvider.notifier)
        .clearSession(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    setState(() {});
    _saveHeldBills();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sale paused'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _restoreHeldBill(int index) {
    final bill = _heldBills[index];
    final session = bill['session'] as SaleSession;
    final notifier = ref.read(desktopBillingProvider.notifier);
    notifier.clearSession(notifier.activeSessionIndex);
    for (final item in session.items) {
      notifier.addItem(item);
    }
    notifier.setCustomer(session.customerId, session.customerName);
    final activeSession =
        ref.read(desktopBillingProvider)[notifier.activeSessionIndex];
    activeSession.totalDiscount = session.totalDiscount;
    activeSession.paymentMethod = session.paymentMethod;
    activeSession.isCredit = session.isCredit;
    activeSession.amountPaid = session.amountPaid;
    _heldBills.removeAt(index);
    setState(() {});
    _saveHeldBills();
  }

  void _resetSaleState() {
    setState(() {
      _selectedPayment = 'cash';
      _creditFull = true;
      _isSplitPayment = false;
      _selectedTier = 'normal';
      _billDiscountController.clear();
      _extraChargesController.clear();
      _paidController.clear();
      _splitCashController.clear();
      _splitUpiController.clear();
      _selectedProduct = null;
      _selectedCartIndex = -1;
      _qtyController.text = '1';
      _priceController.clear();
      _totalController.clear();
      _customerCredit = 0;
      _itemDiscountController.clear();
      _costController.clear();
    });
  }

  void _confirmClearCart() {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    final itemCount = session.items.length;
    final total = session.total;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cart?'),
        content: Text(
          'Remove all $itemCount item(s) worth Rs${total.toStringAsFixed(2)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final notifier = ref.read(desktopBillingProvider.notifier);
              notifier.clearSession(notifier.activeSessionIndex);
              setState(() {
                _selectedCartIndex = -1;
                _editingCartIndex = -1;
                _selectedProduct = null;
                _searchController.clear();
                _showResults = false;
                _selectedPayment = 'cash';
                _creditFull = true;
                _billDiscountController.clear();
                _extraChargesController.clear();
                _paidController.clear();
              });
              _searchFocusNode.requestFocus();
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _retrieveBill() {
    if (_heldBills.isEmpty) return;
    int heldSelectedIndex = 0;

    final heldFocusNode = FocusNode();
    showDialog(
      context: context,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          heldFocusNode.requestFocus();
        });
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Paused Sales'),
            content: SizedBox(
              width: 400,
              child: KeyboardListener(
                focusNode: heldFocusNode,
                onKeyEvent: (event) {
                  if (event is! KeyDownEvent) return;
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    if (heldSelectedIndex < _heldBills.length - 1) {
                      setDialogState(() => heldSelectedIndex++);
                    }
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    if (heldSelectedIndex > 0) {
                      setDialogState(() => heldSelectedIndex--);
                    }
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    if (_heldBills.isNotEmpty && heldSelectedIndex < _heldBills.length) {
                      _restoreHeldBill(heldSelectedIndex);
                      Navigator.pop(ctx);
                    }
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.pop(ctx);
                  }
                },
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _heldBills.length,
                  itemBuilder: (context, index) {
                    final bill = _heldBills[index];
                    final session = bill['session'] as SaleSession;
                    final time = bill['time'] as DateTime;
                    final isSelected = index == heldSelectedIndex;
                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.blue.shade50,
                      title: Text(
                        'Rs${session.total.toStringAsFixed(0)} — ${session.customerName ?? "Walk-in"}',
                      ),
                      subtitle: Text(
                        '${session.itemCount} items • ${AppTimezone.formatTime(time)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _restoreHeldBill(index);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── SALE COMPLETION ──
  Future<void> _completeSale() async {
    final session = ref
        .read(desktopBillingProvider)
        .elementAt(
          ref.read(desktopBillingProvider.notifier).activeSessionIndex,
        );
    if (session.items.isEmpty) return;

    // Check connectivity before attempting sale
    final offlineService = ref.read(offlineServiceProvider);
    final isOnline = await offlineService.isOnline();
    if (!isOnline) {
      if (mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No Internet Connection'),
            content: const Text(
              'You are offline. The sale will be saved locally and synced when you reconnect.\n\n'
              'Do you want to proceed?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('Save Offline'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    // Credit validation: customer required
    if (_selectedPayment == 'credit' &&
        (session.customerId == null || session.customerId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a customer for credit sale'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final discount = _billDiscount;
    final extraCharges = double.tryParse(_extraChargesController.text) ?? 0;
    final rawTotal = session.total - discount + extraCharges;
    // Half-up rounding (not banker's rounding)
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    final roundOffAmount = roundedTotal - rawTotal;
    final total = roundedTotal;
    final double paid = _selectedPayment == 'credit'
        ? (_creditFull ? 0 : double.tryParse(_paidController.text) ?? 0)
        : total;
    final double credit = _selectedPayment == 'credit' ? (total - paid) : 0;

    // Validate split payment
    double splitCash = 0;
    double splitUpi = 0;
    double splitCredit = 0;
    bool splitIsCredit = false;
    if (_selectedPayment == 'split') {
      splitCash = double.tryParse(_splitCashController.text) ?? 0;
      splitUpi = double.tryParse(_splitUpiController.text) ?? 0;
      if (splitCash < 0 || splitUpi < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Split amounts cannot be negative'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final splitTotal = splitCash + splitUpi;
      if (splitTotal > total + 0.5) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Split amounts (Rs${splitCash.toStringAsFixed(0)} + Rs${splitUpi.toStringAsFixed(0)} = Rs${splitTotal.toStringAsFixed(0)}) exceed total Rs${total.toStringAsFixed(0)}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      // If split doesn't cover full amount, remainder goes to credit
      if ((total - splitTotal) > 0.5) {
        splitCredit = total - splitTotal;
        splitIsCredit = true;
        // Require customer for credit portion
        if (session.customerId == null || session.customerId!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Select a customer — remaining balance goes to credit'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
    }

    // Validate partial credit payment
    if (_selectedPayment == 'credit' && !_creditFull) {
      if (paid < 0 || paid >= total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paid amount must be between 0 and total'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_selectedPayment == 'credit' &&
        session.customerId != null &&
        session.customerId!.isNotEmpty) {
      try {
        final custRes = await Supabase.instance.client
            .from('customers')
            .select('total_credit, credit_limit')
            .eq('id', session.customerId!)
            .maybeSingle();
        if (custRes != null) {
          final currentCredit =
              (custRes['total_credit'] as num?)?.toDouble() ?? 0;
          final creditLimit =
              (custRes['credit_limit'] as num?)?.toDouble() ?? 0;
          final newTotalCredit = currentCredit + credit;
          if (creditLimit > 0 && newTotalCredit > creditLimit) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Credit limit exceeded! Limit: Rs${creditLimit.toStringAsFixed(0)}, Current: Rs${currentCredit.toStringAsFixed(0)}, New total: Rs${newTotalCredit.toStringAsFixed(0)}',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }
      } catch (e) {
        Logger.warning('Credit limit validation failed: $e');
      }
    }

    // Re-validate stock before saving
    for (final item in session.items) {
      final product = _allProducts.where((p) => p.id == item.productId).firstOrNull;
      if (product == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${item.name} no longer exists'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      if (product.stock < item.qty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${item.name}: insufficient stock (${product.stock.toInt()} available, ${item.qty} in cart)',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    await _saveSale(
      _selectedPayment,
      splitIsCredit ? (splitCash + splitUpi) : paid,
      splitIsCredit ? true : _selectedPayment == 'credit',
      splitIsCredit ? splitCredit : credit,
      roundOffAmount,
    );
  }

  Future<void> _saveSale(
    String paymentMethod,
    double amountPaid,
    bool isCredit,
    double creditAmount, [
    double roundOffAmount = 0,
  ]) async {
    final sessionIndex = ref
        .read(desktopBillingProvider.notifier)
        .activeSessionIndex;
    final session = ref.read(desktopBillingProvider).elementAt(sessionIndex);
    if (session.items.isEmpty) return;

    setState(() => _isProcessing = true);

    final auth = ref.read(authServiceProvider);
    final user = auth.currentUser;
    final discount = _billDiscount;
    final extraCharges = double.tryParse(_extraChargesController.text) ?? 0;
    final rawTotal = session.total - discount + extraCharges;
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    final finalAmount = roundedTotal;

    double totalItemDiscount = 0;
    for (final item in session.items) {
      final itemTotal = item.price * item.qty;
      totalItemDiscount += itemTotal * (item.discount / 100);
    }

    double cashAmt = 0;
    double digitalAmt = 0;
    if (paymentMethod == 'split') {
      cashAmt = double.tryParse(_splitCashController.text) ?? 0;
      digitalAmt = double.tryParse(_splitUpiController.text) ?? 0;
    } else if (paymentMethod == 'cash') {
      cashAmt = amountPaid;
    } else if (!isCredit) {
      digitalAmt = amountPaid;
    }

    final sale = Sale(
      id: '',
      items: session.items
          .map(
            (item) => CartItem(
              productId: item.productId,
              name: item.name,
              price: item.price,
              qty: item.qty,
              unit: item.unit,
              purchasePrice: item.purchasePrice,
              gstRate: item.gstRate,
              hsnCode: item.hsnCode,
              tamilName: item.tamilName,
              discount: item.discount,
              tier: _selectedTier,
            ),
          )
          .toList(),
      totalAmount: session.subtotal,
      totalDiscount: totalItemDiscount,
      discount: discount,
      finalAmount: finalAmount,
      roundOff: roundOffAmount,
      paymentMethod: paymentMethod,
      createdBy: user?.id ?? '',
      createdAt: DateTime.now(),
      customerId: session.customerId,
      isCredit: isCredit,
      amountPaid: amountPaid,
      dueAmount: creditAmount,
      cashAmount: cashAmt,
      digitalAmount: digitalAmt,
      extraCharges: extraCharges,
      dueDate: isCredit ? DateTime.now().add(const Duration(days: 30)) : null,
    );

    try {

      // If editing an existing sale, update it instead of creating new
      if (_editingSale != null) {
        try {
          final reasonCtrl = TextEditingController();
          final reason = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Reason for Edit'),
              content: TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (reasonCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, reasonCtrl.text.trim());
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (reason == null || reason.isEmpty) {
            if (mounted) setState(() => _isProcessing = false);
            return;
          }
          await ref
              .read(saleServiceProvider)
              .editSaleAtomic(
                saleId: _editingSale!.id,
                items: sale.items,
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
                reason: reason,
              );
          ref
              .read(desktopBillingProvider.notifier)
              .resetAfterSale(sessionIndex);
          ref.invalidate(salesHistoryProvider);
          ref.invalidate(productsProvider);
          _editingSale = null;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sale updated'),
                backgroundColor: Colors.green,
              ),
            );
            _resetSaleState();
          }
          return; // Don't create new sale
        } catch (e) {
          _editingSale = null;
          if (mounted) {
            setState(() => _isProcessing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Edit failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return; // Don't create new sale on failure
        }
      }

      final offlineService = ref.read(offlineServiceProvider);
      final isOnline = await offlineService.isOnline();
      if (!isOnline) {
        final saleJson = sale.toInsertJson();
        saleJson['id'] = sale.id.isNotEmpty
            ? sale.id
            : DateTime.now().millisecondsSinceEpoch.toString();
        await offlineService.saveSaleOffline(saleJson);
        ref.invalidate(salesHistoryProvider);
        ref.read(desktopBillingProvider.notifier).resetAfterSale(sessionIndex);
        if (mounted) {
          _resetSaleState();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sale saved offline, will sync when online'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      await ref.read(saleServiceProvider).createSale(sale);
      ref.read(desktopBillingProvider.notifier).resetAfterSale(sessionIndex);
      ref.invalidate(salesHistoryProvider);
      ref.invalidate(productsProvider);

      if (mounted) {
        _resetSaleState();

        // Show invoice options (non-blocking)
        _showInvoiceOptions(sale);
      }
    } catch (e) {
      try {
        final offlineService = ref.read(offlineServiceProvider);
        final saleJson = sale.toInsertJson();
        saleJson['id'] = sale.id.isNotEmpty
            ? sale.id
            : DateTime.now().millisecondsSinceEpoch.toString();
        await offlineService.saveSaleOffline(saleJson);
        ref.invalidate(salesHistoryProvider);
      } catch (e) {
        Logger.warning('Failed to save sale offline: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale saved offline, will sync when online'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      ref.read(desktopBillingProvider.notifier).resetAfterSale(sessionIndex);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showInvoiceOptions(Sale sale) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => InvoiceOptionsDialog(sale: sale),
    );

    if (action == 'skip' || action == null) return;

    final prefs = await SharedPreferences.getInstance();
    final printLang = prefs.getString('print_language') ?? 'english';
    final useTamil = printLang == 'tamil' || printLang == 'bilingual';

    Map<String, String>? tamilNames;
    if (useTamil) {
      tamilNames = {};
      for (final item in sale.items) {
        final product = _allProducts
            .where((p) => p.id == item.productId)
            .firstOrNull;
        if (product?.tamilName != null && product!.tamilName!.isNotEmpty) {
          tamilNames[item.productId] = product.tamilName!;
        }
      }
    }

    final profile = ref.read(profileProvider).value;
    final shopName = profile?.shopName ?? 'IDEAL STORE';
    final shopAddress = profile?.shopAddress;
    final shopNameTamil =
        profile?.shopName; // TODO: Add Tamil shop name field to profile
    final gstin = profile?.gstin;

    try {
      if (action == 'print_usb') {
        final receiptData = ThermalInvoice.generate(
          sale: sale,
          shopName: shopName,
          shopTagline: 'Smart Store - Smart Business',
          shopAddress: shopAddress,
          gstin: gstin,
          useTamil: useTamil,
          tamilNames: tamilNames,
          shopNameTamil: shopNameTamil,
        );
        final success = await ThermalPrinterService().printStructured(
          receiptData,
          title: 'Receipt',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success ? 'Sent to printer' : 'Print cancelled'),
              backgroundColor: success ? Colors.green : Colors.orange,
            ),
          );
        }
      } else if (action == 'print') {
        await InvoiceGenerator.generateAndPrint(
          sale,
          shopName: shopName,
          shopAddress: shopAddress,
          useTamil: useTamil,
          tamilNames: tamilNames,
        );
      } else if (action == 'pdf') {
        await InvoiceGenerator.shareInvoice(
          sale,
          shopName: shopName,
          shopAddress: shopAddress,
          useTamil: useTamil,
          tamilNames: tamilNames,
        );
      } else if (action == 'whatsapp') {
        final receiptData = ThermalInvoice.generate(
          sale: sale,
          shopName: shopName,
          shopTagline: 'Smart Store - Smart Business',
          shopAddress: shopAddress,
          useTamil: useTamil,
          tamilNames: tamilNames,
        );
        await Share.share(receiptData.toText());
      } else if (action == 'email') {
        String? custName;
        if (sale.customerId != null) {
          try {
            final custRes = await Supabase.instance.client
                .from('customers')
                .select('name')
                .eq('id', sale.customerId!)
                .maybeSingle();
            custName = custRes?['name'] as String?;
          } catch (e) {
            Logger.warning('Failed to fetch customer name for email: $e');
          }
        }
        if (mounted) {
          await _showEmailDialog(
            sale,
            shopName: shopName,
            customerName: custName,
          );
        }
      } else if (action == 'barcode') {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BarcodeLabelScreen()),
          );
        }
      }
    } catch (e) {
      final msg = e.toString();
      String userMsg = 'Action failed';
      if (msg.contains('SocketException') || msg.contains('Connection')) {
        userMsg = 'Network error — check internet connection';
      } else if (msg.contains('TimeoutException')) {
        userMsg = 'Connection timed out — try again';
      } else if (msg.contains('Printer') || msg.contains('bluetooth')) {
        userMsg = 'Printer error — check connection';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userMsg: ${msg.length > 80 ? msg.substring(0, 80) : msg}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEmailDialog(
    Sale sale, {
    String? shopName,
    String? customerName,
  }) async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter customer email to send invoice:'),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
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
            onPressed: () => Navigator.pop(ctx, emailController.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty || !email.contains('@')) return;

    try {
      final pdf = await _buildPdf(sale, shopName: shopName);
      final emailService = EmailService();
      await emailService.sendInvoiceEmail(
        context: context,
        toEmail: email,
        sale: sale,
        pdfBytes: pdf,
        shopName: shopName ?? 'IDEAL STORE',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<List<int>> _buildPdf(Sale sale, {String? shopName}) async {
    final font = await InvoiceGenerator.getNotoSans();
    final fontBold = await InvoiceGenerator.getNotoSansBold();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        build: (context) => [
          InvoiceGenerator.buildInvoice(
            sale,
            shopName: shopName,
            shopAddress: null,
            font: font,
            fontBold: fontBold,
          ),
        ],
      ),
    );
    return pdf.save();
  }

  // ── CUSTOMER ──
  void _showCustomerPicker() {
    showDialog(
      context: context,
      builder: (ctx) => CustomerPickerDialog(
        onSelect: (id, name) {
          ref.read(desktopBillingProvider.notifier).setCustomer(id, name);
          setState(() {
            if (id.isEmpty) _customerCredit = 0;
          });
          if (id.isNotEmpty) _loadCustomerCredit(id);
        },
      ),
    );
  }

  Future<void> _addNewCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Address',
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
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(ctx, {
                  'name': nameController.text,
                  'phone': phoneController.text,
                  'address': addressController.text,
                });
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final response = await Supabase.instance.client
            .from('customers')
            .insert({
              'name': result['name'],
              'phone': result['phone'],
              'address': result['address'] ?? '',
            })
            .select()
            .single();
        ref
            .read(desktopBillingProvider.notifier)
            .setCustomer(response['id'], response['name']);
        if (mounted) {
          setState(() {});
          _loadCustomerCredit(response['id']);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Customer added'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(desktopBillingProvider);
    final notifier = ref.read(desktopBillingProvider.notifier);
    final activeSession = sessions[notifier.activeSessionIndex];
    final total = activeSession.total;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: handleKeyEvent,
      child: Material(
        color: const Color(0xFFF5F5F5),
        child: Stack(
          children: [
            Column(
              children: [
                BillingSaleTabs(
                  sessions: sessions,
                  notifier: notifier,
                  selectedCartIndex: _selectedCartIndex,
                  onCartIndexChanged: (index) => setState(() => _selectedCartIndex = index),
                  onSearchFocusRequested: () => _searchFocusNode.requestFocus(),
                  onEditSale: (sale) => setState(() => _editingSale = sale),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _buildSearchBar(),
                            // Function buttons row
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _functionButton(
                                    Icons.pause_circle,
                                    'Hold\n(F6)',
                                    activeSession.items.isEmpty
                                        ? null
                                        : _holdBill,
                                  ),
                                  _functionButton(
                                    Icons.play_circle,
                                    'Retrieve\n(F7)',
                                    _retrieveBill,
                                  ),
                                  _functionButton(
                                    Icons.person,
                                    'Customer\n(F4)',
                                    _showCustomerPicker,
                                  ),
                                  _functionButton(
                                    Icons.calculate,
                                    'Calc\n(F12)',
                                    () {
                                      if (Platform.isWindows)
                                        Process.run('calc', []);
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Search results take full height when showing
                            if (_showResults && _searchResults.isNotEmpty)
                              Expanded(child: _buildSearchResults()),
                            // Cart table + bottom bar only when not searching
                            if (!(_showResults &&
                                _searchResults.isNotEmpty)) ...[
                              Expanded(child: _buildCartTable(activeSession)),
                              BillingBottomBar(
                                session: activeSession,
                                billDiscount: _billDiscount,
                                extraCharges: double.tryParse(_extraChargesController.text) ?? 0,
                                selectedTier: _selectedTier,
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildPaymentPanel(activeSession, total),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            BillingProcessingOverlay(isProcessing: _isProcessing),
          ],
        ),
      ),
    );
  }

  // ── SEARCH BAR (search-only first, then qty/price/total) ──
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedProduct == null && _editingCartIndex < 0) ...[
            // SEARCH ONLY MODE
            Row(
              children: [
                // Code/Name toggle
                GestureDetector(
                  onTap: () => setState(() {
                    _searchMode = _searchMode == 'code' ? 'products' : 'code';
                    _searchController.clear();
                    _searchResults = [];
                    _showResults = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _searchMode == 'code'
                          ? const Color(0xFF667eea)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      _searchMode == 'code' ? 'Code' : 'Name',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _searchMode == 'code'
                            ? Colors.white
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: _searchMode == 'code'
                          ? 'Search by product code...'
                          : 'Type product name or code...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 200),
                        () => _searchProducts(value),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addNewProduct,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Product'),
                ),
              ],
            ),
          ] else ...[
            // ENTRY MODE: Qty | Price | Total
            Row(
              children: [
                // EDITING label + cancel
                if (_editingCartIndex >= 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'EDIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_editingCartIndex >= 0
                                  ? Colors.orange
                                  : const Color(0xFF667eea))
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedProduct?.name ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _editingCartIndex >= 0
                            ? Colors.orange
                            : const Color(0xFF667eea),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Unit Type dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedUnitType,
                    isDense: true,
                    underline: const SizedBox(),
                    style: const TextStyle(fontSize: 11, color: Colors.black),
                    items: const [
                      DropdownMenuItem(value: 'pieces', child: Text('Pcs')),
                      DropdownMenuItem(value: 'pack', child: Text('Pack')),
                      DropdownMenuItem(value: 'saram', child: Text('Saram')),
                      DropdownMenuItem(value: 'box', child: Text('Box')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedUnitType = v);
                        if (v != 'pieces') {
                          _showPiecesPerUnitDialog(v);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                // Qty
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _qtyController,
                    focusNode: _qtyFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    onSubmitted: (_) => _confirmQty(),
                    onChanged: (_) => _syncTotalFromPrice(),
                  ),
                ),
                const SizedBox(width: 8),
                // Price
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _priceController,
                    focusNode: _priceFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => _confirmPrice(),
                    onChanged: (_) => _syncTotalFromPrice(),
                  ),
                ),
                const SizedBox(width: 8),
                // Total
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _totalController,
                    focusNode: _totalFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'Total',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    onSubmitted: (_) => _confirmTotal(),
                    onChanged: (_) => _syncPriceFromTotal(),
                  ),
                ),
                const SizedBox(width: 8),
                // Cost Price
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _costController,
                    focusNode: _costFocusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'Cost',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => _confirmTotal(),
                  ),
                ),
                if (_editingCartIndex >= 0) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: _cancelEdit,
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    tooltip: 'Cancel edit (ESC)',
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _functionButton(IconData icon, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: Colors.blue),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Colors.blue),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── SEARCH RESULTS (full height list) ──
  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF667eea),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(
                  '${_searchResults.length} products found',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _showResults = false;
                    _searchController.clear();
                    _searchResults = [];
                    _selectedProduct = null;
                  }),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ],
            ),
          ),
          // Product list
          Expanded(
            child: RawScrollbar(
              controller: _resultsScrollController,
              thumbVisibility: true,
              thickness: 10,
              radius: const Radius.circular(8),
              child: ListView.builder(
                controller: _resultsScrollController,
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final product = _searchResults[index];
                  final isSelected = index == _selectedResultIndex;
                  return Container(
                    color: isSelected
                        ? const Color(0xFF667eea).withValues(alpha: 0.1)
                        : null,
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF667eea).withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? const Color(0xFF667eea)
                                : Colors.grey,
                          ),
                        ),
                      ),
                      title: Text(
                        product.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.tamilName != null &&
                              product.tamilName!.isNotEmpty)
                            Text(
                              product.tamilName!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          Text(
                            'Rs${product.sellingPrice.toStringAsFixed(0)} | Stock: ${product.stock}',
                          ),
                        ],
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF667eea),
                            )
                          : null,
                      onTap: () {
                        setState(() => _selectedResultIndex = index);
                        _selectSearchResult();
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CART TABLE ──
  Widget _buildCartTable(SaleSession session) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '#',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'Product',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Price',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    'Total',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 40),
              ],
            ),
          ),
          Expanded(
            child: session.items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No items in cart',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Type product name to add',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _cartScrollController,
                    itemCount: session.items.length,
                    itemBuilder: (context, index) {
                      final item = session.items[index];
                      final isSelected = index == _selectedCartIndex;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        color: isSelected
                            ? const Color(0xFF667eea).withValues(alpha: 0.1)
                            : null,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedCartIndex = index),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    if (item.tamilName != null &&
                                        item.tamilName!.isNotEmpty)
                                      Text(
                                        item.tamilName!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (item.rateLabel != null &&
                                        item.rateLabel!.isNotEmpty)
                                      Text(
                                        item.rateLabel!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.orange[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                '${item.qty}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Rs${item.price.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Rs${item.total.toStringAsFixed(0)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // Edit button
                            SizedBox(
                              width: 24,
                              child: GestureDetector(
                                onTap: () => _editCartItem(index),
                                child: const Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            // Delete button
                            SizedBox(
                              width: 24,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.red,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  ref
                                      .read(desktopBillingProvider.notifier)
                                      .removeItem(index);
                                  setState(() {
                                    if (_selectedCartIndex >=
                                        session.items.length) {
                                      _selectedCartIndex =
                                          session.items.length - 1;
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── PAYMENT PANEL (no quick cash) ──
  Widget _buildPaymentPanel(SaleSession session, double total) {
    final discount = _billDiscount;
    final extraCharges = double.tryParse(_extraChargesController.text) ?? 0;
    final rawTotal = (total - discount + extraCharges).clamp(
      0.0,
      double.infinity,
    );
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    final roundOffAmount = roundedTotal - rawTotal;
    final finalTotal = roundedTotal;
    final dueAmount = _selectedPayment == 'credit'
        ? (_creditFull
              ? finalTotal
              : finalTotal - (double.tryParse(_paidController.text) ?? 0))
        : 0.0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GRAND TOTAL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'GRAND TOTAL',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rs${finalTotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (discount > 0)
                  Text(
                    'Discount: -Rs${discount.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                if (extraCharges > 0)
                  Text(
                    'Extra Charges: +Rs${extraCharges.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                if (roundOffAmount != 0)
                  Text(
                    'Round Off: ${roundOffAmount > 0 ? '+' : ''}Rs${roundOffAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Bill Discount
          Row(
            children: [
              const Icon(Icons.discount, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _billDiscountController,
                  focusNode: _billDiscountFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bill Discount (Rs)',
                    prefixText: 'Rs ',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Extra Charges (delivery, handling, etc.)
          Row(
            children: [
              const Icon(Icons.local_shipping, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _extraChargesController,
                  focusNode: _extraChargesFocusNode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Extra Charges (Rs)',
                    prefixText: 'Rs ',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pricing Tier: Normal / Wholesale / Bulk
          const Text(
            'Pricing Tier',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _tierButton('Normal', 'normal', Colors.blue, session),
              const SizedBox(width: 4),
              _tierButton('Wholesale', 'wholesale', Colors.orange, session),
              const SizedBox(width: 4),
              _tierButton('Bulk', 'bulk', Colors.purple, session),
            ],
          ),
          const SizedBox(height: 10),

          // Payment: CASH / UPI / CREDIT / SPLIT
          const Text(
            'Payment',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          _paymentOption('CASH', Colors.green, Icons.money, 'cash', session),
          const SizedBox(height: 4),
          _paymentOption(
            'UPI',
            Colors.purple,
            Icons.phone_android,
            'upi',
            session,
          ),
          const SizedBox(height: 4),
          _paymentOption(
            'CREDIT',
            Colors.orange,
            Icons.person,
            'credit',
            session,
          ),
          const SizedBox(height: 4),
          _paymentOption(
            'SPLIT',
            Colors.teal,
            Icons.call_split,
            'split',
            session,
          ),

          // Credit options
          if (_selectedPayment == 'credit') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Full Credit', style: TextStyle(fontSize: 12)),
                Radio<bool>(
                  value: true,
                  groupValue: _creditFull,
                  onChanged: (v) => setState(() => _creditFull = v!),
                ),
                const SizedBox(width: 8),
                const Text('Partial', style: TextStyle(fontSize: 12)),
                Radio<bool>(
                  value: false,
                  groupValue: _creditFull,
                  onChanged: (v) => setState(() => _creditFull = v!),
                ),
              ],
            ),
            if (!_creditFull) ...[
              TextField(
                controller: _paidController,
                focusNode: _paidFocusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Paid Amount',
                  prefixText: 'Rs ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              // Quick cash buttons
              Row(
                children: [100, 200, 500, 1000, 2000].map((amt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ActionChip(
                      label: Text('₹$amt', style: const TextStyle(fontSize: 11)),
                      onPressed: () {
                        _paidController.text = amt.toString();
                        setState(() {});
                      },
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
              Text(
                'Due: Rs${dueAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(
                'Due: Rs${finalTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ],

          // Split Payment options
          if (_selectedPayment == 'split') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split Payment — Total: Rs${finalTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _splitCashController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cash Amount',
                      prefixText: 'Rs ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _splitUpiController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'UPI Amount',
                      prefixText: 'Rs ',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Builder(builder: (ctx) {
                    final cash = double.tryParse(_splitCashController.text) ?? 0;
                    final upi = double.tryParse(_splitUpiController.text) ?? 0;
                    final sum = cash + upi;
                    final remaining = finalTotal - sum;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (remaining > 0.5)
                          Text(
                            'Remaining: Rs${remaining.toStringAsFixed(0)} → Credit',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (remaining < -0.5)
                          Text(
                            'Excess: Rs${(-remaining).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (remaining.abs() <= 0.5)
                          const Text(
                            'Full amount covered',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Customer
          const Text(
            'Customer',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _showCustomerPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.customerName ?? 'WALK-IN CUSTOMER',
                      style: TextStyle(
                        fontSize: 12,
                        color: session.customerName != null
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _addNewCustomer,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text(
              'Add New Customer',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (session.customerId != null &&
              session.customerId!.isNotEmpty &&
              _customerCredit > 0) ...[
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
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Previous Due: Rs${_customerCredit.toStringAsFixed(2)}',
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
          const SizedBox(height: 8),

          // Edit mode banner
          if (_editingSale != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Editing sale Rs${_editingSale!.finalAmount.toStringAsFixed(0)} (${_editingSale!.items.length} items)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _editingSale = null;
                      });
                      final idx = ref
                          .read(desktopBillingProvider.notifier)
                          .activeSessionIndex;
                      ref
                          .read(desktopBillingProvider.notifier)
                          .resetAfterSale(idx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Edit cancelled'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    },
                    child: const Text(
                      'CANCEL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Complete Sale
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: (session.items.isEmpty || _isProcessing)
                  ? null
                  : _completeSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _editingSale != null
                    ? 'UPDATE SALE (SHIFT+ENTER)'
                    : 'COMPLETE SALE (SHIFT+ENTER)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Hold/Retrieve
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: session.items.isEmpty ? null : _holdBill,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text(
                    'Hold (F6)',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: _heldBills.isEmpty ? null : _retrieveBill,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text(
                    'Retrieve (F7) [${_heldBills.length}]',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Keyboard shortcuts help
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Keyboard Shortcuts',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tab/Shift+Tab: Navigate fields',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'Esc: Back / Cancel / Clear',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'F2: Edit item  F4: Customer',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'F6: Hold  F7: Retrieve',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'F8: Cash  F9: UPI  F10: Credit',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'F11: Split  F5: Tier cycle',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
                Text(
                  'Shift+Enter: Complete Sale',
                  style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierButton(
    String label,
    String tier,
    Color color,
    SaleSession session,
  ) {
    final isSelected = _selectedTier == tier;
    return Expanded(
      child: SizedBox(
        height: 32,
        child: Material(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: session.items.isEmpty
                ? null
                : () {
                    setState(() => _selectedTier = tier);
                    ref
                        .read(desktopBillingProvider.notifier)
                        .updateAllItemPricesFromCurrent(tier);
                  },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? color : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: isSelected ? color : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentOption(
    String label,
    Color color,
    IconData icon,
    String value,
    SaleSession session,
  ) {
    final isSelected = _selectedPayment == value;
    return SizedBox(
      height: 40,
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: session.items.isEmpty
              ? null
              : () => setState(() {
                  _selectedPayment = value;
                  if (value == 'credit') _creditFull = true;
                }),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSelected ? color : Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(Icons.check_circle, size: 16, color: color),
              ],
            ),
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

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    _totalController.dispose();
    _qtyFocusNode.dispose();
    _priceFocusNode.dispose();
    _totalFocusNode.dispose();
    _itemDiscountController.dispose();
    _costController.dispose();
    _costFocusNode.dispose();
    _billDiscountController.dispose();
    _billDiscountFocusNode.dispose();
    _extraChargesController.dispose();
    _extraChargesFocusNode.dispose();
    _paidController.dispose();
    _paidFocusNode.dispose();
    _resultsScrollController.dispose();
    _cartScrollController.dispose();
    _keyboardFocusNode.dispose();
    _splitCashController.dispose();
    _splitUpiController.dispose();
    _inactivityTimer?.cancel();
    super.dispose();
  }
}