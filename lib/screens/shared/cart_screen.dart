import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../models/customer.dart';
import '../../config/providers.dart';
import '../../services/email_service.dart';
import '../../services/sale_service.dart';
import '../../utils/payment_methods.dart';
import '../../widgets/barcode_scanner.dart';
import '../../utils/invoice_generator.dart';
import '../../utils/thermal_invoice.dart';
import '../../utils/error_messages.dart';
import '../../utils/logger.dart';
import '../../utils/voice_billing.dart';
import '../../utils/voice_parser.dart';
import '../../widgets/voice_confirm_sheet.dart';
import '../../services/thermal_printer_service.dart';
import '../../widgets/cart/cart_item_tile.dart';
import '../../widgets/cart/checkout_sheet.dart';
import '../../widgets/cart/customer_sheet.dart';
import '../../widgets/cart/line_edit_sheet.dart';
import '../../utils/product_search.dart';
import '../../widgets/rate_picker_dialog.dart';
import '../../utils/qty_format.dart';
import '../../utils/readable_color.dart';

/// What the Sale toolbar shows about the cart: held bills, the voice
/// language, and whether the mic is on.
class CartStatus {
  const CartStatus({this.held = 0, this.tamil = false, this.listening = false});
  final int held;
  final bool tamil;
  final bool listening;

  @override
  bool operator ==(Object other) =>
      other is CartStatus && other.held == held && other.tamil == tamil && other.listening == listening;

  @override
  int get hashCode => Object.hash(held, tamil, listening);
}

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key, this.status});

  /// Kept up to date for the toolbar above the cart.
  final ValueNotifier<CartStatus>? status;

  @override
  ConsumerState<CartScreen> createState() => CartScreenState();
}

class CartScreenState extends ConsumerState<CartScreen>
    with AutomaticKeepAliveClientMixin {
  final _discountController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _cashAmountController = TextEditingController();
  final _upiAmountController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();
  String _paymentMethod = 'cash';
  Customer? _selectedCustomer;
  bool _isCredit = false;
  bool _isSplitPayment = false;
  bool _isProcessing = false;
  List<Customer> _customers = [];
  // the cart's own message area: messages sit above the totals and do not
  // push the app's round middle button onto Charge (it covered it)
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  ScaffoldMessengerState get _messenger => _messengerKey.currentState ?? ScaffoldMessenger.of(context);

  // the payment chosen on the bar; Charge opens the checkout on it
  PayMode _payMode = PayMode.cash;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _topSoldProducts = [];
  String _productSearchQuery = '';
  bool _isListening = false;
  bool _useTamilVoice = false;
  final VoiceBilling _voiceBilling = VoiceBilling();
  String _partialText = '';

  // Hold/Recall bills — persisted to Hive
  List<Map<String, dynamic>> _heldBills = [];

  // Cart from global provider
  List<CartItem> get _cart => ref.read(cartProvider);

  double get _subtotal => _cart.fold(0.0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _total => _subtotal - _discount;
  double get _amountPaid =>
      _isCredit ? (double.tryParse(_amountPaidController.text) ?? 0) : _total;
  double get _dueAmount => _isCredit ? (_total - _amountPaid) : 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadProducts();
    _loadTopSoldProducts();
    _loadHeldBills();
    // the voice language the shop chose last time
    SharedPreferences.getInstance().then((p) {
      final tamil = p.getBool('voice_tamil');
      if (tamil != null && mounted) setState(() => _useTamilVoice = tamil);
    }).catchError((_) {});
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await ref.read(customerServiceProvider).getCustomers();
      if (mounted) {
        setState(() => _customers = customers);
      }
    } catch (e) {
      Logger.error('loadCustomers', e);
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ref.read(productServiceProvider).getAllProducts();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _filterProducts(_productSearchQuery);
        });
      }
    } catch (e) {
      Logger.error('loadProducts', e);
    }
  }

  Future<void> _loadTopSoldProducts() async {
    try {
      final topSold = await ref
          .read(saleServiceProvider)
          .getTopSoldProducts(limit: 12, days: 30);
      if (mounted && topSold.isNotEmpty) {
        setState(() => _topSoldProducts = topSold);
      }
    } catch (e) {
      Logger.warning('Failed to load top sold products: $e');
    }
  }

  Future<void> _loadHeldBills() async {
    try {
      final offlineService = ref.read(offlineServiceProvider);
      final saved = offlineService.getHeldBills();
      if (mounted && saved.isNotEmpty) {
        setState(() => _heldBills = saved);
      }
    } catch (e) {
      Logger.warning('Failed to load held bills: $e');
    }
  }

  Future<void> _persistHeldBills() async {
    try {
      final offlineService = ref.read(offlineServiceProvider);
      await offlineService.saveHeldBills(_heldBills);
    } catch (e) {
      Logger.warning('Failed to persist held bills: $e');
    }
  }

  void _filterProducts(String query) {
    _productSearchQuery = query;
    // best matches first: barcode, name start, word start (product_search)
    _filteredProducts = query.trim().isEmpty ? List.from(_allProducts) : searchProducts(_allProducts, query);
  }

  void _showQtyPopup(Product product) {
    String qtyText = '1';
    // "1" starts selected, so typing 3 gives 3 and not 13 (QA #25)
    final qtyController = TextEditingController(text: '1')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 1);
    // Close this box first, then add: adding opens the rate picker for
    // products with a second rate, and popping after that closed the picker
    // instead — the item went in at the first rate and this box stayed open,
    // so a second "Add" added it again (QA #22).
    void addAndClose(BuildContext ctx) {
      final qty = double.tryParse(qtyText) ?? 0;
      if (qty <= 0) return;
      Navigator.pop(ctx);
      _addToCartWithQty(product, qty);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          product.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${rupees(product.sellingPrice)} / ${product.unit}  ·  stock ${formatQty(product.stock)}',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setDialogState) => TextField(
                // decimal for loose goods (1.5 kg)
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: qtyController,
                autofocus: true,
                onChanged: (v) => qtyText = v,
                onSubmitted: (_) => addAndClose(ctx),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => addAndClose(ctx),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCartWithQty(Product product, double qty) async {
    final picked = await RatePickerDialog.show(context, product);
    final price = picked?.price ?? product.sellingPrice;
    final rateLabel = picked?.label;

    ref
        .read(cartProvider.notifier)
        .addItem(
          CartItem(
            productId: product.id,
            name: product.name,
            price: price,
            qty: qty,
            unit: product.unit,
            purchasePrice: _effectivePurchasePrice(product),
            gstRate: product.gstRate,
            hsnCode: product.hsnCode,
            tamilName: product.tamilName,
            rateLabel: rateLabel,
            unitType: product.unitType,
            piecesPerUnit: product.piecesPerUnit,
            stockFactor: 1, // sold in the product's own stock unit
          ),
        );
    _productSearchController.clear();
    setState(() {
      _productSearchQuery = '';
      _filterProducts('');
    });
    _productSearchFocusNode.requestFocus();
  }

  double _effectivePurchasePrice(Product product) {
    if (product.purchasePrice > 0) return product.purchasePrice;
    if (product.variants.isNotEmpty)
      return product.variants.first.purchasePrice;
    return 0;
  }

  /// Takes a line off the bill, with Undo for a slip of the finger
  /// (the old ✕ deleted at once).
  void _removeFromCart(int index) {
    final item = _cart[index];
    ref.read(cartProvider.notifier).removeItem(index);
    setState(() {});
    final messenger = _messenger..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${item.name} removed'),
        duration: const Duration(seconds: 4),
        // a message with a button stays until tapped unless told otherwise
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            ref.read(cartProvider.notifier).insertItem(index, item);
            setState(() {});
          },
        ),
      ),
    );
  }

  Product? _productOf(CartItem item) => _allProducts.where((p) => p.id == item.productId).firstOrNull;

  /// More of this product on the bill than in stock (all its lines).
  bool _overStock(CartItem item) {
    final p = _productOf(item);
    if (p == null) return false;
    final onBill = _cart.where((c) => c.productId == item.productId).fold<double>(0, (t, c) => t + c.totalPieces);
    return onBill > p.stock + 0.0001;
  }

  /// Tap a line: quantity, price, rate and discount in one sheet.
  Future<void> _editLine(int index) async {
    final item = _cart[index];
    final edit = await LineEditSheet.show(context, item, product: _productOf(item));
    if (edit == null || !mounted || index >= _cart.length || !identical(_cart[index], item)) return;
    if (edit.remove) {
      _removeFromCart(index);
      return;
    }
    final changed = item.copyWith(
      qty: edit.qty,
      price: edit.price,
      discount: edit.discount,
      rateLabel: edit.rateLabel,
      clearRateLabel: edit.rateLabel == null,
    );
    ref.read(cartProvider.notifier).replaceItem(index, changed);
    setState(() {});
  }

  /// − on a line: one less; at 1 it takes the line off (with Undo).
  void _decrement(int index) {
    final item = _cart[index];
    final step = _isLoose(item.unit) && item.qty < 1 ? item.qty : 1.0;
    if (item.qty - step <= 0.0001) {
      _removeFromCart(index);
    } else {
      ref.read(cartProvider.notifier).setQty(index, item.qty - step);
      setState(() {});
    }
  }

  static bool _isLoose(String unit) =>
      const {'kg', 'g', 'gm', 'gram', 'ltr', 'litre', 'l', 'ml'}.contains(unit.toLowerCase().trim());

  /// A quick product tapped: one more of it.
  Future<void> _addOne(Product product) async {
    final picked = await RatePickerDialog.show(context, product);
    if (picked == null || !mounted) return;
    ref.read(cartProvider.notifier).addItem(
          CartItem(
            productId: product.id,
            name: product.name,
            price: picked.price,
            qty: 1,
            unit: product.unit,
            purchasePrice: _effectivePurchasePrice(product),
            gstRate: product.gstRate,
            hsnCode: product.hsnCode,
            tamilName: product.tamilName,
            rateLabel: picked.label,
            unitType: product.unitType,
            piecesPerUnit: product.piecesPerUnit,
            stockFactor: 1,
          ),
        );
    HapticFeedback.selectionClick();
    setState(() {});
  }

  /// Customer bar / credit: choose the bill's customer.
  Future<Customer?> _pickCustomer() async {
    final choice = await CustomerSheet.show(
      context,
      customers: _customers,
      selected: _selectedCustomer,
      onAddNew: _showAddCustomerDialog,
    );
    if (choice == null || !mounted) return null;
    setState(() {
      _selectedCustomer = choice.customer;
      if (choice.customer == null && _payMode == PayMode.credit) _payMode = PayMode.cash;
    });
    return choice.customer;
  }

  /// Discount on the whole bill, in rupees.
  Future<void> _editBillDiscount() async {
    final c = TextEditingController(text: _discountController.text);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bill discount'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: InputDecoration(
            prefixText: '₹ ',
            border: const OutlineInputBorder(),
            helperText: 'Bill ${rupees2(_subtotal)}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('No discount')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Apply')),
        ],
      ),
    );
    c.dispose();
    if (value == null || !mounted) return;
    final d = double.tryParse(value) ?? 0;
    if (d > _subtotal) {
      _messenger.showSnackBar(
        const SnackBar(content: Text('Discount is more than the bill')),
      );
      return;
    }
    setState(() => _discountController.text = d > 0 ? value : '');
  }

  /// Charge: the checkout sheet, then the sale is saved as before.
  Future<void> _charge() async {
    if (_cart.isEmpty || _isProcessing) return;
    final result = await CheckoutSheet.show(
      context,
      total: _total,
      itemCount: _cart.length,
      mode: _payMode,
      customer: _selectedCustomer,
      pickCustomer: _pickCustomer,
    );
    if (result == null || !mounted) return;
    setState(() {
      _payMode = result.mode;
      _selectedCustomer = result.customer;
      _isCredit = result.mode == PayMode.credit;
      _isSplitPayment = result.mode == PayMode.split;
      _paymentMethod = result.mode == PayMode.upi ? 'upi' : 'cash';
      _amountPaidController.text = _isCredit && result.creditPaid > 0 ? result.creditPaid.toStringAsFixed(2) : '';
      _cashAmountController.text = _isSplitPayment ? result.splitCash.toStringAsFixed(2) : '';
      _upiAmountController.text = _isSplitPayment ? result.splitUpi.toStringAsFixed(2) : '';
    });
    await _completeSale(confirmed: true);
  }

  Future<void> scanAndAdd() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (result != null && mounted) {
      final product = await ref
          .read(productServiceProvider)
          .getProductByBarcode(result);
      if (product != null && mounted) {
        _addOne(product);
      } else if (mounted) {
        _messenger.showSnackBar(SnackBar(content: Text('No product found: $result')));
      }
    }
  }

  /// Mic: listen, then show what was heard with choices (VoiceConfirmSheet).
  /// Nothing is added until the shop taps "Add".
  Future<void> toggleMic() async {
    if (_isListening) {
      await _voiceBilling.stop(); // ends the order: the sheet opens
      return;
    }

    if (_allProducts.isEmpty) {
      await _loadProducts();
    }
    if (!mounted) return;
    if (_allProducts.isEmpty) {
      _messenger.showSnackBar(
        const SnackBar(content: Text('No products loaded. Wait a moment.')),
      );
      return;
    }

    final tamil = _useTamilVoice;
    if (tamil && !_tamilChecked) {
      _tamilChecked = true;
      if (!await _voiceBilling.hasTamil() && mounted) {
        await _showTamilVoiceHelp();
        if (!mounted) return;
      }
    }

    setState(() {
      _isListening = true;
      _partialText = '';
    });

    final ok = await _voiceBilling.startOrder(
      useTamil: tamil,
      onText: (text) {
        if (mounted) setState(() => _partialText = text);
      },
      onEnd: (text, guesses) {
        if (mounted) setState(() => _isListening = false);
        _onVoiceHeard(text, guesses, tamil);
      },
    );

    if (!ok && mounted) {
      setState(() => _isListening = false);
      _messenger.showSnackBar(
        const SnackBar(
          content: Text('Speech recognition not available on this device'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool _tamilChecked = false;
  bool _voiceSheetOpen = false;
  Future<void> _showTamilVoiceHelp() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('தமிழ் குரல் இல்லை'),
        content: const Text(
          'This phone has no Tamil voice typing yet, so Tamil may be heard '
          'as English.\n\n'
          'To add it: Settings → System → Languages → On-screen keyboard → '
          'Gboard → Voice typing → Languages → add தமிழ் (Tamil, India). '
          'Turn on "Offline speech recognition" to download it.\n\n'
          'You can still try now.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _onVoiceHeard(String spoken, List<List<String>> guesses, bool tamil) async {
    if (!mounted || _voiceSheetOpen) return;
    setState(() => _isListening = false);
    if (spoken.trim().isEmpty) return;

    final learned = await VoiceMemory.load();
    final words = await VoiceWords.load();
    final products = _allProducts;
    // finding where items start and end, over all the phone's guesses,
    // takes a moment: do it off the screen's thread so nothing freezes
    if (mounted) setState(() => _partialText = tamil ? 'சரிபார்க்கிறது…' : 'Checking…');
    final parser = VoiceParser(products, learned: learned, words: words);
    VoiceOrder order;
    try {
      order = await parseVoiceOrderInBackground(products, learned, words, guesses);
    } catch (e) {
      // never lose the order: read it here instead (slower, but it works)
      Logger.error('Voice background parse', e);
      order = parser.parseBest(guesses);
    }
    final text = order.heard.isEmpty ? spoken : order.heard;
    final lines = order.lines;
    if (mounted) setState(() => _partialText = '');
    if (!mounted) return;
    if (lines.isEmpty) {
      _messenger.showSnackBar(
        SnackBar(
          content: Text(
            tamil
                ? 'பொருள் புரியவில்லை: “$text”'
                : 'No product heard in “$text”',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    _voiceSheetOpen = true;
    final picks = await VoiceConfirmSheet.show(
      context,
      heard: text,
      lines: lines,
      tamil: tamil,
      products: _allProducts,
      reparse: parser.parse,
      rememberWords: VoiceWords.add,
    );
    _voiceSheetOpen = false;
    if (picks == null || picks.isEmpty || !mounted) return;

    await VoiceMemory.remember({
      for (final p in picks)
        if (p.worthRemembering) p.line.phrase: p.product.id,
    });
    for (final p in picks) {
      if (!mounted) return;
      await _addVoiceItem(p.product, p.qty);
    }
    if (!mounted) return;
    _messenger.showSnackBar(
      SnackBar(
        content: Text(
          tamil
              ? '${picks.length} பொருள் சேர்க்கப்பட்டது'
              : '${picks.length} item${picks.length == 1 ? '' : 's'} added',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Adds a confirmed voice line like a tapped product: the two-rate picker
  /// for products with a second rate, then the cart.
  Future<void> _addVoiceItem(Product product, double qty) async {
    final picked = await RatePickerDialog.show(context, product);
    if (picked == null) return; // rate picker cancelled
    ref
        .read(cartProvider.notifier)
        .addItem(
          CartItem(
            productId: product.id,
            name: product.name,
            tamilName: product.tamilName,
            price: picked.price,
            rateLabel: picked.label,
            qty: qty <= 0 ? 1.0 : qty,
            unit: product.unit,
            purchasePrice: _effectivePurchasePrice(product),
            gstRate: product.gstRate,
            hsnCode: product.hsnCode,
            unitType: product.unitType,
            piecesPerUnit: product.piecesPerUnit,
            stockFactor: 1,
          ),
        );
    setState(() {});
  }

  Future<Customer?> _showAddCustomerDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Customer'),
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
              if (nameController.text.trim().isEmpty) return;
              try {
                // offline, the customer is saved on this phone and synced
                // before the bills that use it
                final customer = await ref
                    .read(customerServiceProvider)
                    .addCustomer(
                      name: nameController.text.trim(),
                      phone: phoneController.text.isNotEmpty
                          ? phoneController.text
                          : null,
                    );
                if (ctx.mounted) Navigator.pop(ctx, customer);
              } catch (e) {
                // a refusal (e.g. no permission) used to leave the dialog
                // open with no message
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(ErrorMessages.parse(e)),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _selectedCustomer = result;
        _customers.add(result);
      });
    }
    return result;
  }

  Future<void> _completeSale({bool confirmed = false}) async {
    if (_cart.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _completeSaleInner(confirmed: confirmed);
    } finally {
      // every early return (validation message, cancelled dialog) lands
      // here, so the checkout button can never stay disabled (#4)
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _completeSaleInner({bool confirmed = false}) async {
    // No separate "are we online?" check first (a server round trip before
    // every bill): the save goes offline by itself on a network error.
    if (_total < 0) {
      _messenger.showSnackBar(
        const SnackBar(content: Text('Discount is more than the bill total')),
      );
      return;
    }

    if (_isCredit && _selectedCustomer == null) {
      _messenger.showSnackBar(
        const SnackBar(
          content: Text('Please select a customer for credit sale'),
        ),
      );
      return;
    }

    if (_isCredit && _amountPaid >= _total) {
      _messenger.showSnackBar(
        const SnackBar(content: Text('Amount paid is full! Uncheck Credit.')),
      );
      return;
    }

    // Credit limit, same check as the desktop (QA #24). Offline: let it through.
    if (_isCredit && _selectedCustomer != null) {
      try {
        final cust = await Supabase.instance.client
            .from('customers')
            .select('total_credit, credit_limit')
            .eq('id', _selectedCustomer!.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));
        if (cust != null) {
          final current = (cust['total_credit'] as num?)?.toDouble() ?? 0;
          final limit = (cust['credit_limit'] as num?)?.toDouble() ?? 0;
          final newTotal = current + _dueAmount;
          if (limit > 0 && newTotal > limit) {
            if (!mounted) return;
            _messenger.showSnackBar(
              SnackBar(
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
                content: Text(
                  'Credit limit crossed. Limit ₹${limit.toStringAsFixed(0)}, '
                  'already owes ₹${current.toStringAsFixed(0)}, '
                  'after this bill ₹${newTotal.toStringAsFixed(0)}.',
                ),
              ),
            );
            return;
          }
        }
      } catch (e) {
        Logger.warning('Credit limit check skipped: $e');
      }
      if (!mounted) return;
    }

    // Validate split payment
    if (_isSplitPayment && !_isCredit) {
      final cashAmount = double.tryParse(_cashAmountController.text) ?? 0;
      final upiAmount = double.tryParse(_upiAmountController.text) ?? 0;
      if ((cashAmount + upiAmount - _total).abs() > 0.01) {
        _messenger.showSnackBar(
          const SnackBar(content: Text('Cash + UPI must equal total')),
        );
        return;
      }
    }

    final confirm = confirmed
        ? true
        : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items: ${_cart.length}'),
            Text('Total: ₹${_total.toStringAsFixed(2)}'),
            if (_isSplitPayment && !_isCredit) ...[
              const SizedBox(height: 4),
              Text(
                'Cash: ₹${(double.tryParse(_cashAmountController.text) ?? 0).toStringAsFixed(2)}',
              ),
              Text(
                'UPI: ₹${(double.tryParse(_upiAmountController.text) ?? 0).toStringAsFixed(2)}',
              ),
            ],
            if (_isCredit) ...[
              const SizedBox(height: 8),
              Text('Customer: ${_selectedCustomer?.name ?? ""}'),
              Text('Amount Paid: ₹${_amountPaid.toStringAsFixed(2)}'),
              Text(
                'Due: ₹${_dueAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFFC62828),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            Text(
              'Payment: ${_isCredit
                  ? "Credit"
                  : _isSplitPayment
                  ? "Split (Cash + UPI)"
                  : PaymentMethods.label(_paymentMethod)}',
            ),
            const SizedBox(height: 8),
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

    try {
      final auth = ref.read(authServiceProvider);
      final user = auth.currentUser;

      // Calculate total item-level discount
      final totalItemDiscount = _cart.fold(
        0.0,
        (sum, item) => sum + item.discountAmount,
      );

      final method = _isCredit
          ? PaymentMethods.credit
          : (_isSplitPayment
                ? PaymentMethods.split
                : PaymentMethods.normalize(_paymentMethod));
      final splitCash = double.tryParse(_cashAmountController.text) ?? 0;
      final splitUpi = double.tryParse(_upiAmountController.text) ?? 0;
      double cashAmount = 0;
      double digitalAmount = 0;
      if (_isCredit) {
        cashAmount = _amountPaid; // money taken at the counter on a credit bill
      } else if (_isSplitPayment) {
        cashAmount = splitCash;
        digitalAmount = splitUpi;
      } else if (method == PaymentMethods.cash) {
        cashAmount = _total;
      } else {
        digitalAmount = _total;
      }

      final draft = Sale(
        // same id online/offline: a retried sale is never billed twice (#5)
        id: newDocumentId(),
        items: _cart,
        totalAmount: _cart.fold(0.0, (sum, item) => sum + item.total),
        discount: _discount,
        totalDiscount: totalItemDiscount,
        finalAmount: _total < 0 ? 0 : _total,
        paymentMethod: method,
        createdBy: user?.id ?? '',
        createdAt: DateTime.now(),
        customerId: _selectedCustomer?.id,
        customerName: _selectedCustomer?.name,
        isCredit: _isCredit,
        amountPaid: _isCredit ? _amountPaid : _total,
        dueAmount: _isCredit ? _dueAmount : 0,
        cashAmount: cashAmount,
        digitalAmount: digitalAmount,
        // GST split is computed by the database from the customer's state
      );

      bool savedOffline = false;
      Sale sale = draft;
      try {
        sale = await ref.read(saleServiceProvider).createSale(draft);
      } on SaleSavedOffline {
        savedOffline = true;
      }
      ref.invalidate(salesHistoryProvider);
      ref.invalidate(productsProvider);

      if (mounted) {
        HapticFeedback.heavyImpact();
        if (savedOffline) {
          _messenger.showSnackBar(
            const SnackBar(
              content: Text('Sale saved offline, will sync when online'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
        final invoiceAction = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_isCredit ? 'Credit Sale!' : 'Sale Completed!'),
            // credit customers get a bill too (it used to show only "OK")
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total: ₹${_total.toStringAsFixed(2)}'
                  '${_isCredit ? '\nDue: ₹${_dueAmount.toStringAsFixed(2)}' : ''}'
                  '${savedOffline ? "\n(Saved offline)" : ""}',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.print,
                        label: 'Bluetooth',
                        action: 'bluetooth_print',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.usb,
                        label: 'USB Print',
                        action: 'print',
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.picture_as_pdf,
                        label: 'PDF',
                        action: 'share',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.message,
                        label: 'WhatsApp',
                        action: 'whatsapp',
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.text_snippet,
                        label: 'Text',
                        action: 'thermal_share',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _invoiceActionBtn(
                        ctx,
                        icon: Icons.email,
                        label: 'Email',
                        action: 'email',
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'skip'),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Skip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        if (invoiceAction == 'bluetooth_print') {
          final thermalService = ThermalPrinterService();
          final isConfigured = await thermalService.isConfigured();
          if (isConfigured) {
            final prefs = await SharedPreferences.getInstance();
            final printLang = prefs.getString('print_language') ?? 'english';
            final useTamilBT = printLang == 'tamil' || printLang == 'bilingual';

            final profile = ref.read(profileProvider).value;
            final receiptData = ThermalInvoice.generate(
              sale: sale,
              shopName: profile?.shopName ?? 'IDEAL STORE',
              shopTagline: 'Smart Store - Smart Business',
              shopAddress: profile?.shopAddress,
              customerName: _selectedCustomer?.name,
              gstin: profile?.gstin,
              useTamil: useTamilBT,
            );
            final success = await thermalService.printText(
              receiptData.toText(),
              hasTamil: useTamilBT,
            );
            if (mounted) {
              _messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Printed!'
                        : 'Print failed — check printer connection',
                  ),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            }
          } else {
            if (mounted) {
              _messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'No printer configured. Go to More → Printer Setup',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } else if (invoiceAction == 'print') {
          final profile = ref.read(profileProvider).value;
          await InvoiceGenerator.generateAndPrint(
            sale,
            shopName: profile?.shopName,
            shopAddress: profile?.shopAddress,
          );
        } else if (invoiceAction == 'share') {
          final profile = ref.read(profileProvider).value;
          await InvoiceGenerator.shareInvoice(
            sale,
            shopName: profile?.shopName,
            shopAddress: profile?.shopAddress,
          );
        } else if (invoiceAction == 'thermal_share') {
          final thermalService = ThermalPrinterService();
          final profile = ref.read(profileProvider).value;
          final receiptData = ThermalInvoice.generate(
            sale: sale,
            shopName: profile?.shopName ?? 'IDEAL STORE',
            shopTagline: 'Smart Store - Smart Business',
            shopAddress: profile?.shopAddress,
            customerName: _selectedCustomer?.name,
            gstin: profile?.gstin,
          );
          await thermalService.shareAsTextFile(
            receiptData.toText(),
            fileName: 'invoice_${sale.invoiceLabel}',
          );
        } else if (invoiceAction == 'whatsapp') {
          final profile = ref.read(profileProvider).value;
          final receiptData = ThermalInvoice.generate(
            sale: sale,
            shopName: profile?.shopName ?? 'IDEAL STORE',
            shopTagline: 'Smart Store - Smart Business',
            shopAddress: profile?.shopAddress,
            customerName: _selectedCustomer?.name,
            gstin: profile?.gstin,
          );
          await Share.share(receiptData.toText());
        } else if (invoiceAction == 'email') {
          _showEmailDialog(context, sale);
        }

        _messenger.hideCurrentSnackBar();
        setState(() {
          ref.read(cartProvider.notifier).clear();
          _discountController.clear();
          _amountPaidController.clear();
          _cashAmountController.clear();
          _upiAmountController.clear();
          _paymentMethod = 'cash';
          _payMode = PayMode.cash;
          _selectedCustomer = null;
          _isCredit = false;
          _isSplitPayment = false;
        });
        _loadTopSoldProducts();
        ref.invalidate(salesHistoryProvider);
        ref.invalidate(todaySalesProvider);
        ref.invalidate(accountsProvider);
        ref.invalidate(todayTransactionsProvider);
      }
    } catch (e) {
      if (mounted) {
        _messenger.showSnackBar(SnackBar(content: Text(ErrorMessages.parse(e))));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _invoiceActionBtn(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required String action,
    required MaterialColor color,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => Navigator.pop(ctx, action),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: readableText(color.shade700),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEmailDialog(BuildContext context, Sale sale) {
    final emailController = TextEditingController();
    showDialog(
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
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty ||
                  !email.contains('@') ||
                  !email.contains('.')) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid email'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              await _sendEmailInvoice(sale, email);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmailInvoice(Sale sale, String email) async {
    try {
      final profile = ref.read(profileProvider).value;
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a5,
          build: (context) => [
            InvoiceGenerator.buildInvoice(
              sale,
              shopName: profile?.shopName,
              shopAddress: profile?.shopAddress,
            ),
          ],
        ),
      );
      final pdfBytes = await pdf.save();

      final emailService = EmailService();
      await emailService.sendInvoiceEmail(
        context: context,
        toEmail: email,
        sale: sale,
        pdfBytes: pdfBytes,
        shopName: 'IDEAL STORE',
      );
    } catch (e) {
      if (mounted) {
        _messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to generate/send email: ${ErrorMessages.parse(e)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void toggleLang() {
    setState(() => _useTamilVoice = !_useTamilVoice);
    SharedPreferences.getInstance().then((p) => p.setBool('voice_tamil', _useTamilVoice)).catchError((_) => true);
    _messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(_useTamilVoice ? 'Voice: தமிழ் (Tamil)' : 'Voice: English'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  bool get hasItems => _cart.isNotEmpty;

  /// Opens the list of held bills: resume one into the cart, or delete it.
  void showHeldBills() {
    if (_heldBills.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: StatefulBuilder(
          builder: (sheetCtx, setSheet) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              Text(
                'Bills on hold (${_heldBills.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _heldBills.length; i++)
                _heldBillTile(sheetCtx, setSheet, i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heldBillTile(BuildContext sheetCtx, StateSetter setSheet, int i) {
    final bill = _heldBills[i];
    final lines = (bill['cart'] as List?) ?? const [];
    final when = DateTime.tryParse(bill['timestamp']?.toString() ?? '');
    final customer = (bill['customer'] as Map?)?['name']?.toString();
    final total = (bill['total'] as num?)?.toDouble() ?? 0;
    final info = [
      if (customer != null && customer.isNotEmpty) customer,
      if (when != null)
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
    ].join(' · ');
    return Card(
      child: ListTile(
        title: Text(
          '${rupees2(total)} · ${lines.length} item${lines.length == 1 ? '' : 's'}',
        ),
        subtitle: info.isEmpty ? null : Text(info),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Delete held bill',
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: sheetCtx,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete held bill?'),
                    content: Text(
                      '${rupees2(total)} · ${lines.length} items. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Keep'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Color(0xFFC62828)),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                setState(() => _heldBills.removeAt(i));
                _persistHeldBills();
                if (_heldBills.isEmpty) {
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                } else {
                  setSheet(() {});
                }
              },
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheetCtx);
                _resumeHeldBill(i);
              },
              child: const Text('Resume'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resumeHeldBill(int index) async {
    if (index < 0 || index >= _heldBills.length) return;
    _messenger.hideCurrentSnackBar();
    var bill = _heldBills[index];
    if (_cart.isNotEmpty) {
      final hold = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('The current bill has items'),
          content: const Text('Hold the current bill and open the other one?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Hold & open'),
            ),
          ],
        ),
      );
      if (hold != true || !mounted) return;
      holdBill();
    }
    final items = <CartItem>[];
    for (final l in (bill['cart'] as List?) ?? const []) {
      try {
        items.add(CartItem.fromJson(Map<String, dynamic>.from(l as Map)));
      } catch (_) {
        // a line from an old, unreadable held bill is skipped
      }
    }
    Customer? customer;
    final c = bill['customer'];
    if (c is Map) {
      final id = c['id']?.toString();
      customer =
          _customers.where((x) => x.id == id).firstOrNull ??
          Customer.fromJson(Map<String, dynamic>.from(c));
    }
    setState(() {
      _heldBills.remove(bill);
      ref.read(cartProvider.notifier).replaceAll(items);
      _selectedCustomer = customer;
      _discountController.text = bill['discount']?.toString() ?? '';
      _paymentMethod = bill['paymentMethod']?.toString() ?? 'cash';
      _isCredit = bill['isCredit'] == true;
      _payMode = _isCredit
          ? PayMode.credit
          : (PaymentMethods.normalize(_paymentMethod) == PaymentMethods.upi ? PayMode.upi : PayMode.cash);
      _amountPaidController.text = bill['amountPaid']?.toString() ?? '';
    });
    _persistHeldBills();
  }

  void holdBill() {
    _messenger.hideCurrentSnackBar(); // an Undo for this bill must not reach the next
    if (_cart.isEmpty) {
      _messenger.showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    // plain data only: CartItem/Customer/DateTime objects could not be
    // stored, so held bills were lost on restart (QA #23)
    final heldBill = <String, dynamic>{
      'cart': _cart.map((i) => i.toJson()).toList(),
      'customer': _selectedCustomer?.toJson(),
      'discount': _discountController.text,
      'paymentMethod': _paymentMethod,
      'isCredit': _isCredit,
      'amountPaid': _amountPaidController.text,
      'timestamp': DateTime.now().toIso8601String(),
      'total': _total,
    };

    setState(() {
      _heldBills.add(heldBill);
      ref.read(cartProvider.notifier).clear();
      _discountController.clear();
      _amountPaidController.clear();
      _cashAmountController.clear();
      _upiAmountController.clear();
      _selectedCustomer = null;
      _isCredit = false;
      _isSplitPayment = false;
      _paymentMethod = 'cash';
      _payMode = PayMode.cash;
    });
    _persistHeldBills();

    _messenger.showSnackBar(
      SnackBar(
        content: Text('Bill held (${_heldBills.length} held)'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void dispose() {
    _discountController.dispose();
    _amountPaidController.dispose();
    _cashAmountController.dispose();
    _upiAmountController.dispose();
    _productSearchController.dispose();
    _productSearchFocusNode.dispose();
    _voiceBilling.dispose();
    super.dispose();
  }

  // ── layout (rebuilt 17 Oct 2026) ─────────────────────────────────────────
  // customer bar · search · quick products / results · bill lines · totals
  // and payment · Charge. Big text, exact paise, nothing hidden behind ⚙.

  void _publishStatus() {
    final status = CartStatus(held: _heldBills.length, tamil: _useTamilVoice, listening: _isListening);
    final notifier = widget.status;
    if (notifier == null || notifier.value == status) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifier.value = status);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    _publishStatus();
    final searching = _productSearchQuery.isNotEmpty;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        bottomNavigationBar: _cart.isEmpty ? null : (searching ? _slimTotals() : _totalsPanel()),
        body: Column(
          children: [
            if (_isListening) _voiceBanner(),
            _customerBar(),
            _searchField(),
            if (searching)
              Expanded(child: _searchResults())
            else ...[
              if (_topSoldProducts.isNotEmpty) _quickProducts(),
              if (_heldBills.isNotEmpty && _cart.isEmpty) _heldBanner(),
              Expanded(child: _cart.isEmpty ? _emptyCart() : _cartLines()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _voiceBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            Icon(Icons.mic, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _partialText.isEmpty
                    ? (_useTamilVoice ? 'சொல்லுங்கள்… முடிந்ததும் ■ அழுத்தவும்' : 'Speak… tap ■ when done')
                    : _partialText,
                style: TextStyle(fontSize: 15, color: scheme.onErrorContainer),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.onErrorContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _useTamilVoice ? 'தமிழ்' : 'EN',
                style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Stop',
              onPressed: toggleMic,
              icon: Icon(Icons.stop_circle, color: scheme.onErrorContainer, size: 30),
            ),
          ],
        ),
      ),
    );
  }

  /// Always on screen: who the bill is for and what they owe.
  Widget _customerBar() {
    final scheme = Theme.of(context).colorScheme;
    final c = _selectedCustomer;
    final owes = (c?.totalCredit ?? 0) > 0.004;
    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: _pickCustomer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Icon(c == null ? Icons.storefront_outlined : Icons.person, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: c?.name ?? 'Walk-in customer',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (owes)
                        TextSpan(
                          text: '  ·  due ${rupees(c!.totalCredit)}',
                          style: TextStyle(fontSize: 14, color: scheme.error, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(c == null ? 'Choose' : 'Change', style: TextStyle(color: scheme.primary)),
              Icon(Icons.chevron_right, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        controller: _productSearchController,
        focusNode: _productSearchFocusNode,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search name, Tamil name or barcode',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _productSearchQuery.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _productSearchController.clear();
                    setState(() => _filterProducts(''));
                  },
                )
              : IconButton(tooltip: 'Scan barcode', icon: const Icon(Icons.qr_code_scanner), onPressed: scanAndAdd),
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onChanged: (v) => setState(() => _filterProducts(v)),
      ),
    );
  }

  /// Best sellers of the last 30 days: one tap adds one.
  Widget _quickProducts() {
    final scheme = Theme.of(context).colorScheme;
    final products = _topSoldProducts
        .map((e) => _allProducts.where((p) => p.id == e['product_id']).firstOrNull)
        .whereType<Product>()
        .toList();
    if (products.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 124,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.40,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          final onBill = _cart.where((c) => c.productId == p.id).fold<double>(0, (t, c) => t + c.qty);
          final active = onBill > 0;
          return Material(
            color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _addOne(p),
              onLongPress: () => _showQtyPopup(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: active ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                    Text(
                      active ? '${rupees(p.sellingPrice)}  ·  ${formatQty(onBill)} on bill' : rupees(p.sellingPrice),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchResults() {
    final scheme = Theme.of(context).colorScheme;
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Text(
          'No product "${_productSearchQuery.trim()}"',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _filteredProducts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _filteredProducts[i];
        final onBill = _cart.where((c) => c.productId == p.id).fold<double>(0, (t, c) => t + c.qty);
        final out = p.stock <= 0;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          title: Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              if ((p.tamilName ?? '').isNotEmpty) p.tamilName!,
              out ? 'out of stock' : 'stock ${formatQty(p.stock)}',
            ].join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: out ? scheme.error : scheme.onSurfaceVariant),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rupees(p.sellingPrice), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (onBill > 0)
                Text('${formatQty(onBill)} on bill', style: TextStyle(fontSize: 12, color: scheme.primary)),
            ],
          ),
          onTap: () => _showQtyPopup(p),
        );
      },
    );
  }

  Widget _heldBanner() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: showHeldBills,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.pause_circle_filled, color: scheme.onTertiaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_heldBills.length} bill${_heldBills.length == 1 ? '' : 's'} on hold',
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer),
                ),
              ),
              Text('Open', style: TextStyle(color: scheme.onTertiaryContainer)),
              Icon(Icons.chevron_right, color: scheme.onTertiaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyCart() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 8),
          Text('Empty bill', style: TextStyle(fontSize: 17, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            'Search, scan, tap a quick product, or use the mic',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _cartLines() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _cart.length,
      itemBuilder: (_, index) {
        final item = _cart[index];
        return CartItemTile(
          item: item,
          lowStock: _overStock(item),
          onIncrement: () {
            ref.read(cartProvider.notifier).setQty(index, item.qty + 1);
            setState(() {});
          },
          onDecrement: () => _decrement(index),
          onEdit: () => _editLine(index),
          onRemove: () => _removeFromCart(index),
        );
      },
    );
  }

  /// While searching (keyboard up): one line, so the results have room.
  Widget _slimTotals() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.receipt_long, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '${_cart.length} item${_cart.length == 1 ? '' : 's'} on the bill',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(rupees2(_total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  /// Items, discount, total, how they pay, and Charge.
  Widget _totalsPanel() {
    final scheme = Theme.of(context).colorScheme;
    final pieces = _cart.fold<double>(0, (t, c) => t + c.qty);
    final lineDiscounts = _cart.fold<double>(0, (t, c) => t + c.discountAmount);
    final allDiscount = lineDiscounts + _discount;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    '${_cart.length} item${_cart.length == 1 ? '' : 's'}  ·  ${formatQty(pieces)} pcs',
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _editBillDiscount,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        allDiscount > 0.004 ? 'Discount −${rupees2(allDiscount)}' : '+ Discount',
                        style: TextStyle(fontSize: 14, color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Total', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Text(rupees2(_total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<PayMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.standard),
                  segments: const [
                    ButtonSegment(value: PayMode.cash, label: Text('Cash')),
                    ButtonSegment(value: PayMode.upi, label: Text('UPI')),
                    ButtonSegment(value: PayMode.split, label: Text('Split')),
                    ButtonSegment(value: PayMode.credit, label: Text('Credit')),
                  ],
                  selected: {_payMode},
                  onSelectionChanged: (v) async {
                    setState(() => _payMode = v.first);
                    // credit needs a customer: ask now, not at the end
                    if (v.first == PayMode.credit && _selectedCustomer == null) {
                      final c = await _pickCustomer();
                      if (c == null && mounted) setState(() => _payMode = PayMode.cash);
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isProcessing ? null : _charge,
                  style: FilledButton.styleFrom(
                    backgroundColor: _payMode == PayMode.credit ? Colors.orange.shade800 : Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                        )
                      : Text(
                          _payMode == PayMode.credit ? 'Credit bill ${rupees2(_total)}' : 'Charge ${rupees2(_total)}',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
