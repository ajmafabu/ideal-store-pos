import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../models/customer.dart';
import '../../config/providers.dart';
import '../../services/email_service.dart';
import '../../widgets/barcode_scanner.dart';
import '../../utils/invoice_generator.dart';
import '../../utils/thermal_invoice.dart';
import '../../utils/error_messages.dart';
import '../../utils/logger.dart';
import '../../utils/voice_billing.dart';
import '../../services/thermal_printer_service.dart';
import '../../widgets/cart/cart_item_tile.dart';
import '../../widgets/cart/customer_picker.dart';
import '../../widgets/cart/payment_section.dart';
import '../../widgets/rate_picker_dialog.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen>
    with AutomaticKeepAliveClientMixin {
  final _discountController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _searchController = TextEditingController();
  final _cashAmountController = TextEditingController();
  final _upiAmountController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _productSearchFocusNode = FocusNode();
  String _paymentMethod = 'cash';
  Customer? _selectedCustomer;
  bool _isCredit = false;
  bool _isSplitPayment = false;
  bool _isProcessing = false;
  bool _showPaymentOptions = false;
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _showCustomerSearch = false;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _topSoldProducts = [];
  String _productSearchQuery = '';
  bool _isListening = false;
  bool _useTamilVoice = false;
  final VoiceBilling _voiceBilling = VoiceBilling();
  String _partialText = '';

  // Hold/Recall bills
  final List<Map<String, dynamic>> _heldBills = [];

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
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await ref.read(customerServiceProvider).getCustomers();
      if (mounted) {
        setState(() {
          _customers = customers;
          _filteredCustomers = customers;
        });
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
          _allProducts = products.where((p) => p.stock > 0).toList();
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
          .getTopSoldProducts(limit: 6, days: 7);
      if (mounted && topSold.isNotEmpty) {
        setState(() => _topSoldProducts = topSold);
      }
    } catch (e) {
      Logger.warning('Failed to load top sold products: $e');
    }
  }

  void _filterProducts(String query) {
    _productSearchQuery = query;
    if (query.isEmpty) {
      _filteredProducts = List.from(_allProducts);
    } else {
      final q = query.toLowerCase();
      _filteredProducts = _allProducts.where((p) {
        return p.name.toLowerCase().contains(q) ||
            (p.tamilName?.toLowerCase().contains(q) ?? false) ||
            (p.category?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
  }

  void _showQtyPopup(Product product) {
    String qtyText = '1';
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
              'Rs${product.sellingPrice.toStringAsFixed(0)} / ${product.unit}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            StatefulBuilder(
              builder: (ctx, setDialogState) => TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: TextEditingController(text: '1'),
                autofocus: true,
                onChanged: (v) => qtyText = v,
                onSubmitted: (_) {
                  final qty = int.tryParse(qtyText) ?? 0;
                  if (qty > 0) {
                    _addToCartWithQty(product, qty);
                    Navigator.pop(ctx);
                  }
                },
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
            onPressed: () {
              final qty = int.tryParse(qtyText) ?? 0;
              if (qty > 0) {
                _addToCartWithQty(product, qty);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCartWithQty(Product product, int qty) async {
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
    if (product.variants.isNotEmpty) return product.variants.first.purchasePrice;
    return 0;
  }

  void _filterCustomers(String query) {
    setState(() {
      _filteredCustomers = _customers
          .where(
            (c) =>
                c.name.toLowerCase().contains(query.toLowerCase()) ||
                (c.phone?.contains(query) ?? false),
          )
          .toList();
    });
  }

  Future<void> _addToCart(Product product) async {
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
            qty: 1,
            unit: product.unit,
            purchasePrice: _effectivePurchasePrice(product),
            gstRate: product.gstRate,
            hsnCode: product.hsnCode,
            tamilName: product.tamilName,
            rateLabel: rateLabel,
          ),
        );
    setState(() {});
  }

  void _removeFromCart(int index) {
    ref.read(cartProvider.notifier).removeItem(index);
    setState(() {});
  }

  void _editItemPrice(int index) {
    final item = _cart[index];
    final priceController = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Price - ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current: Rs ${item.price.toStringAsFixed(2)}'),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Price',
                border: OutlineInputBorder(),
                prefixText: 'Rs ',
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
              final newPrice = double.tryParse(priceController.text);
              if (newPrice != null && newPrice > 0) {
                ref
                    .read(cartProvider.notifier)
                    .updateItemPrice(index, newPrice);
                setState(() {});
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Enter valid price')),
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
    String qtyText = '${item.qty}';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(item.name, style: const TextStyle(fontSize: 14)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Current qty display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      'Rs${item.price.toStringAsFixed(0)} × $qtyText',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '= Rs${(item.price * (int.tryParse(qtyText) ?? 0)).toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Number pad
              _buildNumberPad(qtyText, (val) {
                setDialogState(() => qtyText = val);
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final newQty = int.tryParse(qtyText);
                if (newQty != null && newQty > 0) {
                  final delta = newQty - item.qty;
                  ref.read(cartProvider.notifier).updateQty(index, delta);
                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberPad(String currentVal, ValueChanged<String> onChanged) {
    return Column(
      children: [
        Row(
          children: [
            _numPadBtn('1', currentVal, onChanged),
            _numPadBtn('2', currentVal, onChanged),
            _numPadBtn('3', currentVal, onChanged),
          ],
        ),
        Row(
          children: [
            _numPadBtn('4', currentVal, onChanged),
            _numPadBtn('5', currentVal, onChanged),
            _numPadBtn('6', currentVal, onChanged),
          ],
        ),
        Row(
          children: [
            _numPadBtn('7', currentVal, onChanged),
            _numPadBtn('8', currentVal, onChanged),
            _numPadBtn('9', currentVal, onChanged),
          ],
        ),
        Row(
          children: [
            _numPadBtn('C', currentVal, onChanged, isAction: true),
            _numPadBtn('0', currentVal, onChanged),
            _numPadBtn('⌫', currentVal, onChanged, isAction: true),
          ],
        ),
      ],
    );
  }

  Widget _numPadBtn(
    String label,
    String currentVal,
    ValueChanged<String> onChanged, {
    bool isAction = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isAction ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              if (label == 'C') {
                onChanged('0');
              } else if (label == '⌫') {
                if (currentVal.length > 1) {
                  onChanged(currentVal.substring(0, currentVal.length - 1));
                } else {
                  onChanged('0');
                }
              } else {
                if (currentVal == '0') {
                  onChanged(label);
                } else {
                  onChanged(currentVal + label);
                }
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isAction ? Colors.grey.shade700 : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateQty(int index, int delta) {
    ref.read(cartProvider.notifier).updateQty(index, delta);
    setState(() {});
  }

  void _updateItemDiscount(int index, double discount) {
    ref.read(cartProvider.notifier).updateDiscount(index, discount);
    setState(() {});
  }

  Widget _buildProductChip(Product product) {
    final inCart = _cart.where((c) => c.productId == product.id).length;
    return InkWell(
      onTap: () => _showQtyPopup(product),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: inCart > 0
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: inCart > 0 ? Colors.green.shade300 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: inCart > 0 ? Colors.green.shade700 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (inCart > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$inCart',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              '₹${product.sellingPrice.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
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
        if (product.stock <= 0) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Out of stock!')));
          return;
        }
        _addToCart(product);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No product found: $result')));
      }
    }
  }

  Future<void> _toggleVoiceBilling() async {
    if (_isListening) {
      await _voiceBilling.stopListening();
      setState(() => _isListening = false);
      return;
    }

    if (_allProducts.isEmpty) {
      await _loadProducts();
    }
    if (_allProducts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No products loaded. Wait a moment.')),
        );
      }
      return;
    }

    setState(() {
      _isListening = true;
      _partialText = '';
    });

    await _voiceBilling.startListening(
      useTamil: _useTamilVoice,
      onPartialResult: (text) {
        if (mounted) setState(() => _partialText = text);
      },
      onResults: (results) async {
        if (!mounted) return;
        setState(() => _isListening = false);

        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _useTamilVoice
                    ? 'பொருள் கண்டறிய முடியவில்லை'
                    : 'Could not recognize any product',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        for (final result in results) {
          if (result.alternatives.isNotEmpty) {
            // Show product picker
            final selected = await _showVoiceProductPicker(
              spokenText: result.spokenText,
              primary: result.product,
              alternatives: result.alternatives,
              qty: result.qty,
            );
            if (selected != null) {
              _addVoiceItem(selected, result.qty);
            }
          } else {
            _addVoiceItem(result.product, result.qty);
          }
        }
      },
      products: _allProducts,
    );
  }

  void _addVoiceItem(Product product, double qty) {
    if (product.stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _useTamilVoice
                ? '${product.tamilName ?? product.name} இருப்பு இல்லை'
                : '${product.name} is out of stock',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    ref.read(cartProvider.notifier).addItem(
      CartItem(
        productId: product.id,
        name: product.name,
        tamilName: product.tamilName,
        price: product.sellingPrice,
        qty: qty.toInt(),
        unit: product.unit,
        purchasePrice: _effectivePurchasePrice(product),
        gstRate: product.gstRate,
        hsnCode: product.hsnCode,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _useTamilVoice
              ? '${product.tamilName ?? product.name} × ${qty.toInt()} சேர்க்கப்பட்டது'
              : '${product.name} × ${qty.toInt()} added',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<Product?> _showVoiceProductPicker({
    required String spokenText,
    required Product primary,
    required List<Product> alternatives,
    required double qty,
  }) async {
    final all = [primary, ...alternatives];
    return showDialog<Product>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _useTamilVoice ? 'பொருளைத் தேர்ந்தெடுக்கவும்' : 'Select Product',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              '"$spokenText"',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: all.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final p = all[i];
              final displayName = _useTamilVoice && p.tamilName != null && p.tamilName!.isNotEmpty
                  ? '${p.tamilName} (${p.name})'
                  : p.name;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: i == 0 ? Colors.green.shade50 : Colors.grey.shade100,
                  child: Icon(
                    i == 0 ? Icons.check : Icons.inventory_2_outlined,
                    size: 20,
                    color: i == 0 ? Colors.green : Colors.grey,
                  ),
                ),
                title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(
                  '₹${p.sellingPrice.toStringAsFixed(2)} • Stock: ${p.stock.toInt()} ${p.unit}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                onTap: () {
                  Navigator.of(ctx).pop(p);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCustomerDialog() async {
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
              if (nameController.text.isNotEmpty) {
                final customer = await ref
                    .read(customerServiceProvider)
                    .addCustomer(
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty
                          ? phoneController.text
                          : null,
                    );
                Navigator.pop(ctx, customer);
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
        _filteredCustomers.add(result);
      });
    }
  }

  Future<void> _completeSale() async {
    if (_cart.isEmpty || _isProcessing) return;

    // Check connectivity before attempting sale
    final offlineService = ref.read(offlineServiceProvider);
    final isOnline = await offlineService.isOnline();
    if (!isOnline) {
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

    if (_isCredit && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer for credit sale'),
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

    // Validate split payment
    if (_isSplitPayment && !_isCredit) {
      final cashAmount = double.tryParse(_cashAmountController.text) ?? 0;
      final upiAmount = double.tryParse(_upiAmountController.text) ?? 0;
      if ((cashAmount + upiAmount - _total).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash + UPI must equal total')),
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete Sale'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Items: ${_cart.length}'),
            Text('Total: Rs ${_total.toStringAsFixed(2)}'),
            if (_isSplitPayment && !_isCredit) ...[
              const SizedBox(height: 4),
              Text(
                'Cash: Rs${(double.tryParse(_cashAmountController.text) ?? 0).toStringAsFixed(2)}',
              ),
              Text(
                'UPI: Rs${(double.tryParse(_upiAmountController.text) ?? 0).toStringAsFixed(2)}',
              ),
            ],
            if (_isCredit) ...[
              const SizedBox(height: 8),
              Text('Customer: ${_selectedCustomer?.name ?? ""}'),
              Text('Amount Paid: Rs ${_amountPaid.toStringAsFixed(2)}'),
              Text(
                'Due: Rs ${_dueAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            Text(
              'Payment: ${_isCredit
                  ? "Credit"
                  : _isSplitPayment
                  ? "Split (Cash + UPI)"
                  : _paymentMethod}',
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

    setState(() => _isProcessing = true);
    try {
      final auth = ref.read(authServiceProvider);
      final user = auth.currentUser;

      // Calculate total item-level discount
      final totalItemDiscount = _cart.fold(
        0.0,
        (sum, item) => sum + item.discountAmount,
      );

      final sale = Sale(
        id: '',
        items: _cart,
        totalAmount: _cart.fold(
          0.0,
          (sum, item) => sum + (item.price * item.qty),
        ),
        discount: _discount,
        totalDiscount: totalItemDiscount,
        finalAmount: _total,
        paymentMethod: _isCredit
            ? 'credit'
            : (_isSplitPayment ? 'split' : _paymentMethod),
        createdBy: user?.id ?? '',
        createdAt: DateTime.now(),
        customerId: _selectedCustomer?.id,
        isCredit: _isCredit,
        amountPaid: _isCredit ? _amountPaid : _total,
        dueAmount: _dueAmount,
        cashAmount: _isSplitPayment && !_isCredit
            ? (double.tryParse(_cashAmountController.text) ?? 0)
            : (_paymentMethod == 'cash' && !_isCredit ? _total : 0),
        digitalAmount: _isSplitPayment && !_isCredit
            ? (double.tryParse(_upiAmountController.text) ?? 0)
            : ((_paymentMethod == 'digital' || _paymentMethod == 'upi') &&
                      !_isCredit
                  ? _total
                  : 0),
      );

      final offlineService = ref.read(offlineServiceProvider);
      bool savedOffline = false;
      final isOnline = await offlineService.isOnline();
      if (!isOnline) {
        savedOffline = true;
        final saleJson = sale.toInsertJson();
        saleJson['id'] = sale.id.isNotEmpty
            ? sale.id
            : DateTime.now().millisecondsSinceEpoch.toString();
        await offlineService.saveSaleOffline(saleJson);
        ref.invalidate(salesHistoryProvider);
      } else {
        try {
          await ref.read(saleServiceProvider).createSale(sale);
        } catch (e) {
          savedOffline = true;
          final saleJson = sale.toInsertJson();
          saleJson['id'] = sale.id.isNotEmpty
              ? sale.id
              : DateTime.now().millisecondsSinceEpoch.toString();
          await offlineService.saveSaleOffline(saleJson);
          ref.invalidate(salesHistoryProvider);
        }
      }

      if (mounted) {
        if (savedOffline) {
          ScaffoldMessenger.of(context).showSnackBar(
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
            content: _isCredit
                ? Text(
                    'Total: Rs ${_total.toStringAsFixed(2)}\nDue: Rs ${_dueAmount.toStringAsFixed(2)}',
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: Rs ${_total.toStringAsFixed(2)}${savedOffline ? "\n(Saved offline)" : ""}',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'PRINT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.print,
                            label: 'Print',
                            action: 'bluetooth_print',
                            color: Colors.blue,
                          ),
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.usb,
                            label: 'USB Print',
                            action: 'print',
                            color: Colors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'SHARE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.picture_as_pdf,
                            label: 'PDF',
                            action: 'share',
                            color: Colors.green,
                          ),
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.message,
                            label: 'WhatsApp',
                            action: 'whatsapp',
                            color: Colors.green,
                          ),
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.text_snippet,
                            label: 'Text',
                            action: 'thermal_share',
                            color: Colors.green,
                          ),
                          _invoiceActionBtn(
                            ctx,
                            icon: Icons.email,
                            label: 'Email',
                            action: 'email',
                            color: Colors.green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
            actions: [
              if (_isCredit)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
            ],
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
              ScaffoldMessenger.of(context).showSnackBar(
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
              ScaffoldMessenger.of(context).showSnackBar(
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
            fileName: 'invoice_${sale.id.length >= 8 ? sale.id.substring(0, 8) : sale.id}',
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

        setState(() {
          ref.read(cartProvider.notifier).clear();
          _discountController.clear();
          _amountPaidController.clear();
          _cashAmountController.clear();
          _upiAmountController.clear();
          _paymentMethod = 'cash';
          _selectedCustomer = null;
          _isCredit = false;
          _isSplitPayment = false;
        });
        ref.invalidate(salesHistoryProvider);
        ref.invalidate(todaySalesProvider);
        ref.invalidate(accountsProvider);
        ref.invalidate(todayTransactionsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMessages.parse(e))));
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
    return SizedBox(
      width: 100,
      child: Material(
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
                    color: color.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
              if (email.isEmpty || !email.contains('@')) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate/send email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _holdBill() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    final heldBill = {
      'cart': List<CartItem>.from(_cart),
      'customer': _selectedCustomer,
      'discount': _discountController.text,
      'paymentMethod': _paymentMethod,
      'isCredit': _isCredit,
      'amountPaid': _amountPaidController.text,
      'timestamp': DateTime.now(),
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
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bill held (${_heldBills.length} held)'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _recallBill(int index) {
    if (index < 0 || index >= _heldBills.length) return;

    final heldBill = _heldBills[index];
    setState(() {
      ref.read(cartProvider.notifier).clear();
      _cart.addAll(heldBill['cart'] as List<CartItem>);
      _selectedCustomer = heldBill['customer'] as Customer?;
      _discountController.text = heldBill['discount'] as String;
      _paymentMethod = heldBill['paymentMethod'] as String;
      _isCredit = heldBill['isCredit'] as bool;
      _amountPaidController.text = heldBill['amountPaid'] as String;
      _heldBills.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bill recalled'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showHeldBills() {
    if (_heldBills.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No held bills')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Held Bills (${_heldBills.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _heldBills.length,
                itemBuilder: (context, index) {
                  final bill = _heldBills[index];
                  final cart = bill['cart'] as List<CartItem>;
                  final total = cart.fold(0.0, (sum, item) => sum + item.total);
                  final timestamp = bill['timestamp'] as DateTime;
                  final customer = bill['customer'] as Customer?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      customer != null ? customer.name : 'Walk-in Customer',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '${cart.length} items • Rs${total.toStringAsFixed(0)} • ${TimeOfDay.fromDateTime(timestamp).format(context)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _recallBill(index);
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
  void dispose() {
    _discountController.dispose();
    _amountPaidController.dispose();
    _searchController.dispose();
    _cashAmountController.dispose();
    _upiAmountController.dispose();
    _productSearchController.dispose();
    _productSearchFocusNode.dispose();
    _voiceBilling.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Sale'),
        actions: [
          if (_heldBills.isNotEmpty)
            IconButton(
              icon: Badge(
                label: Text('${_heldBills.length}'),
                child: const Icon(Icons.history),
              ),
              onPressed: _showHeldBills,
              tooltip: 'Recall held bill',
            ),
          IconButton(
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: _holdBill,
            tooltip: 'Hold current bill',
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _scanAndAdd,
            tooltip: 'Scan Barcode',
          ),
          if (Platform.isAndroid) ...[
            IconButton(
              icon: Icon(
                _useTamilVoice ? Icons.language : Icons.translate,
                color: _useTamilVoice ? Colors.orange : Colors.grey,
                size: 20,
              ),
              onPressed: () => setState(() => _useTamilVoice = !_useTamilVoice),
              tooltip: _useTamilVoice
                  ? 'Tamil voice (tap for English)'
                  : 'English voice (tap for Tamil)',
            ),
            IconButton(
              icon: Icon(
                Icons.mic,
                color: _isListening ? Colors.red : Colors.grey,
              ),
              onPressed: _toggleVoiceBilling,
              tooltip: _useTamilVoice
                  ? 'தமிழ் குரல் பில்லிங்'
                  : 'Voice billing',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_isListening)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.mic, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _partialText.isEmpty
                          ? (_useTamilVoice ? 'கேட்கிறது...' : 'Listening...')
                          : _partialText,
                      style: TextStyle(
                        fontSize: 14,
                        color: _partialText.isEmpty
                            ? Colors.red.shade300
                            : Colors.red.shade700,
                        fontStyle: _partialText.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _useTamilVoice ? Colors.orange : Colors.blue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _useTamilVoice ? 'தமி' : 'EN',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleVoiceBilling,
                    child: const Icon(
                      Icons.stop_circle,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          // Always-visible search bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _productSearchController,
              decoration: InputDecoration(
                hintText: 'Search product by name or Tamil...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _productSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _productSearchController.clear();
                          setState(() {
                            _productSearchQuery = '';
                            _filterProducts('');
                          });
                          _productSearchFocusNode.requestFocus();
                        },
                      )
                    : IconButton(
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        onPressed: _scanAndAdd,
                      ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filterProducts(v)),
              focusNode: _productSearchFocusNode,
            ),
          ),
          // Product grid
          SizedBox(
            height: 110,
            child: _productSearchQuery.isNotEmpty
                ? _filteredProducts.isEmpty
                    ? const Center(
                        child: Text(
                          'No products found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: _filteredProducts.length > 30
                            ? 30
                            : _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return _buildProductChip(product);
                        },
                      )
                : _topSoldProducts.isEmpty
                    ? const Center(
                        child: Text(
                          'Start selling to see top products',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: _topSoldProducts.length,
                        itemBuilder: (context, index) {
                          final entry = _topSoldProducts[index];
                          final pid = entry['product_id'] as String;
                          final product = _allProducts
                              .where((p) => p.id == pid)
                              .firstOrNull;
                          if (product == null) return const SizedBox();
                          return _buildProductChip(product);
                        },
                      ),
          ),
          // Divider
          if (_cart.isNotEmpty)
            const Divider(height: 1),
          // Cart items
          Expanded(
            child: _cart.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart,
                          size: 60,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap a product above to add',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return CartItemTile(
                        item: item,
                        onIncrement: () => _updateQty(index, 1),
                        onDecrement: () => _updateQty(index, -1),
                        onRemove: () => _removeFromCart(index),
                        onEditPrice: () => _editItemPrice(index),
                        onEditQty: () => _editItemQty(index),
                        onDiscountChanged: (discount) =>
                            _updateItemDiscount(index, discount),
                      );
                    },
                  ),
          ),
          if (_cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Customer info with due (if selected)
                  if (_selectedCustomer != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (_selectedCustomer!.totalCredit ?? 0) > 0
                            ? Colors.orange.withValues(alpha: 0.1)
                            : Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 14,
                            color: (_selectedCustomer!.totalCredit ?? 0) > 0
                                ? Colors.orange
                                : Colors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _selectedCustomer!.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: (_selectedCustomer!.totalCredit ?? 0) > 0
                                  ? Colors.orange
                                  : Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if ((_selectedCustomer!.totalCredit ?? 0) > 0)
                            Text(
                              'Due: Rs${(_selectedCustomer!.totalCredit ?? 0).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  // Compact summary
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_cart.length} product${_cart.length != 1 ? 's' : ''} · Subtotal: Rs${_subtotal.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Rs ${_total.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Always-visible payment method chips
                  Row(
                    children: [
                      const Text('Payment: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      ChoiceChip(
                        label: const Text('Cash', style: TextStyle(fontSize: 11)),
                        selected: !_isCredit && _paymentMethod == 'cash',
                        onSelected: (_) => setState(() {
                          _paymentMethod = 'cash';
                          _isCredit = false;
                          _isSplitPayment = false;
                        }),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Digital', style: TextStyle(fontSize: 11)),
                        selected: !_isCredit && _paymentMethod == 'digital',
                        onSelected: (_) => setState(() {
                          _paymentMethod = 'digital';
                          _isCredit = false;
                          _isSplitPayment = false;
                        }),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Credit', style: TextStyle(fontSize: 11)),
                        selected: _isCredit,
                        onSelected: (_) => setState(() {
                          _isCredit = !_isCredit;
                          if (_isCredit) _amountPaidController.clear();
                          _isSplitPayment = false;
                        }),
                        backgroundColor: Colors.orange.shade100,
                        selectedColor: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Complete button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _completeSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCredit
                            ? Colors.orange
                            : Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _isCredit ? 'Complete Credit Sale' : 'Complete Sale',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Expandable payment options
                  GestureDetector(
                    onTap: () => setState(
                      () => _showPaymentOptions = !_showPaymentOptions,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _showPaymentOptions
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Payment Options',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const Spacer(),
                          if (!_showPaymentOptions)
                            Text(
                              _isCredit
                                  ? 'Credit'
                                  : _paymentMethod.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Expandable content
                  if (_showPaymentOptions) ...[
                    const SizedBox(height: 8),
                    CustomerPicker(
                      selectedCustomer: _selectedCustomer,
                      filteredCustomers: _filteredCustomers,
                      searchController: _searchController,
                      showSearch: _showCustomerSearch,
                      onToggleSearch: () => setState(
                        () => _showCustomerSearch = !_showCustomerSearch,
                      ),
                      onClearCustomer: () =>
                          setState(() => _selectedCustomer = null),
                      onAddCustomer: _showAddCustomerDialog,
                      onSearchChanged: _filterCustomers,
                      onSelectCustomer: (customer) {
                        setState(() {
                          _selectedCustomer = customer;
                          _showCustomerSearch = false;
                          _searchController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    PaymentSection(
                      discountController: _discountController,
                      amountPaidController: _amountPaidController,
                      paymentMethod: _paymentMethod,
                      isCredit: _isCredit,
                      dueAmount: _dueAmount,
                      total: _total,
                      isSplitPayment: _isSplitPayment,
                      cashAmountController: _cashAmountController,
                      upiAmountController: _upiAmountController,
                      onPaymentMethodChanged: (method) => setState(() {
                        _paymentMethod = method;
                        _isCredit = false;
                        _isSplitPayment = false;
                      }),
                      onCreditToggled: () => setState(() {
                        _isCredit = !_isCredit;
                        if (_isCredit) _amountPaidController.clear();
                      }),
                      onSplitPaymentToggled: (val) => setState(() {
                        _isSplitPayment = val;
                        if (val) {
                          _cashAmountController.text = _total.toStringAsFixed(
                            2,
                          );
                          _upiAmountController.text = '0.00';
                        } else {
                          _cashAmountController.clear();
                          _upiAmountController.clear();
                        }
                      }),
                      onChanged: () => setState(() {}),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
