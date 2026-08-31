import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../config/providers.dart';
import '../../widgets/barcode_scanner.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? product;
  final String? barcode;
  final String? prefilledName;
  final String? prefilledCategory;
  final String? prefilledSellingPrice;

  const ProductFormScreen({
    super.key,
    this.product,
    this.barcode,
    this.prefilledName,
    this.prefilledCategory,
    this.prefilledSellingPrice,
  });

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _tamilNameController;
  late TextEditingController _sfwController;
  late TextEditingController _barcodeController;
  late TextEditingController _categoryController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _sellingPriceController;
  late TextEditingController _stockController;
  late TextEditingController _lowStockAlertController;
  late TextEditingController _hsnCodeController;
  late TextEditingController _batchNumberController;
  late TextEditingController _piecesPerUnitController;
  String _unit = 'pcs';
  String _unitType = 'pieces';
  double _gstRate = 0;
  bool _isLoading = false;
  DateTime? _expiryDate;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.product?.name ?? widget.prefilledName ?? '',
    );
    _tamilNameController = TextEditingController(
      text: widget.product?.tamilName ?? '',
    );
    _sfwController = TextEditingController(
      text:
          widget.product?.sfw ??
          _generateSfw(widget.product?.name ?? widget.prefilledName ?? ''),
    );
    _barcodeController = TextEditingController(
      text: widget.product?.barcode ?? widget.barcode ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.product?.category ?? widget.prefilledCategory ?? '',
    );
    _purchasePriceController = TextEditingController(
      text: widget.product != null
          ? widget.product!.purchasePrice.toString()
          : '',
    );
    _sellingPriceController = TextEditingController(
      text: widget.product != null
          ? widget.product!.sellingPrice.toString()
          : (widget.prefilledSellingPrice ?? ''),
    );
    _stockController = TextEditingController(
      text: widget.product != null ? widget.product!.stock.toString() : '0',
    );
    _lowStockAlertController = TextEditingController(
      text: widget.product != null
          ? widget.product!.lowStockAlert.toString()
          : '10',
    );
    _hsnCodeController = TextEditingController(
      text: widget.product?.hsnCode ?? '',
    );
    _batchNumberController = TextEditingController(
      text: widget.product?.batchNumber ?? '',
    );
    _piecesPerUnitController = TextEditingController(
      text: widget.product != null
          ? widget.product!.piecesPerUnit.toString()
          : '1',
    );
    _unit = widget.product?.unit ?? 'pcs';
    _unitType = widget.product?.unitType ?? 'pieces';
    _gstRate = widget.product?.gstRate ?? 0;
    _expiryDate = widget.product?.expiryDate;
  }

  String _generateSfw(String name) {
    if (name.isEmpty) return '';
    final words = name.trim().split(RegExp(r'\s+'));
    return words
        .map((w) => w.length >= 3 ? w.substring(0, 3) : w)
        .join('')
        .toLowerCase();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tamilNameController.dispose();
    _sfwController.dispose();
    _barcodeController.dispose();
    _categoryController.dispose();
    _purchasePriceController.dispose();
    _sellingPriceController.dispose();
    _stockController.dispose();
    _lowStockAlertController.dispose();
    _hsnCodeController.dispose();
    _batchNumberController.dispose();
    _piecesPerUnitController.dispose();
    super.dispose();
  }

  String _getBarcodeHint() {
    final barcode = _barcodeController.text;
    if (barcode.startsWith('890')) return 'Indian FMCG product';
    if (barcode.startsWith('891')) return 'Indian product';
    if (barcode.length >= 12) return 'UPC/EAN barcode';
    return 'Scan or type barcode';
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (result != null) {
      setState(() => _barcodeController.text = result);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final service = ref.read(productServiceProvider);

      final product = Product(
        id: widget.product?.id ?? '',
        name: _nameController.text.trim(),
        tamilName: _tamilNameController.text.trim().isEmpty
            ? null
            : _tamilNameController.text.trim(),
        sfw: _sfwController.text.trim().isEmpty
            ? null
            : _sfwController.text.trim().toLowerCase(),
        barcode: _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        purchasePrice: double.tryParse(_purchasePriceController.text) ?? 0,
        sellingPrice: double.tryParse(_sellingPriceController.text) ?? 0,
        stock: int.tryParse(_stockController.text) ?? 0,
        unit: _unit,
        unitType: _unitType,
        piecesPerUnit: int.tryParse(_piecesPerUnitController.text) ?? 1,
        lowStockAlert: int.tryParse(_lowStockAlertController.text) ?? 10,
        gstRate: _gstRate,
        hsnCode: _hsnCodeController.text.trim().isEmpty
            ? null
            : _hsnCodeController.text.trim(),
        expiryDate: _expiryDate,
        batchNumber: _batchNumberController.text.trim().isEmpty
            ? null
            : _batchNumberController.text.trim(),
      );

      if (_isEditing) {
        await service.updateProduct(product);
      } else {
        await service.createProduct(product);
      }

      ref.invalidate(productsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Product updated' : 'Product added'),
          ),
        );
        context.pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'Add Product'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteProduct,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Product Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tamilNameController,
                decoration: const InputDecoration(
                  labelText: 'தமிழ் பெயர் (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sfwController,
                decoration: const InputDecoration(
                  labelText: 'SFW (Short Finding Words)',
                  border: OutlineInputBorder(),
                  helperText:
                      'Short code for quick search (e.g., ml5 for marie light 5rs)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        labelText: 'Barcode',
                        border: const OutlineInputBorder(),
                        hintText: _getBarcodeHint(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _scanBarcode,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
              if (_barcodeController.text.startsWith('890'))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Indian Product - Type brand name (Himalaya, Parle, Nestle, etc.)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unitType,
                      decoration: const InputDecoration(
                        labelText: 'Unit Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pieces',
                          child: Text('Pieces'),
                        ),
                        DropdownMenuItem(value: 'pack', child: Text('Pack')),
                        DropdownMenuItem(value: 'saram', child: Text('Saram')),
                        DropdownMenuItem(value: 'box', child: Text('Box')),
                      ],
                      onChanged: (v) =>
                          setState(() => _unitType = v ?? 'pieces'),
                    ),
                  ),
                  if (_unitType != 'pieces') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _piecesPerUnitController,
                        decoration: InputDecoration(
                          labelText: 'Pieces per $_unitType',
                          border: const OutlineInputBorder(),
                          helperText: 'How many pieces in 1 $_unitType',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _purchasePriceController,
                      decoration: const InputDecoration(
                        labelText: 'Purchase Price',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _sellingPriceController,
                      decoration: const InputDecoration(
                        labelText: 'Selling Price',
                        border: OutlineInputBorder(),
                        prefixText: '₹ ',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockController,
                      decoration: const InputDecoration(
                        labelText: 'Stock',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pcs', child: Text('Pieces')),
                        DropdownMenuItem(value: 'kg', child: Text('Kg')),
                        DropdownMenuItem(value: 'box', child: Text('Box')),
                        DropdownMenuItem(value: 'pack', child: Text('Pack')),
                        DropdownMenuItem(value: 'saram', child: Text('Saram')),
                        DropdownMenuItem(value: 'litre', child: Text('Litre')),
                      ],
                      onChanged: (v) => setState(() => _unit = v ?? 'pcs'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _gstRate,
                      decoration: const InputDecoration(
                        labelText: 'GST Rate',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('0% (Exempt)')),
                        DropdownMenuItem(value: 5, child: Text('5%')),
                        DropdownMenuItem(value: 12, child: Text('12%')),
                        DropdownMenuItem(value: 18, child: Text('18%')),
                        DropdownMenuItem(value: 28, child: Text('28%')),
                      ],
                      onChanged: (v) => setState(() => _gstRate = v ?? 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hsnCodeController,
                      decoration: const InputDecoration(
                        labelText: 'HSN Code',
                        border: OutlineInputBorder(),
                        helperText: 'Product classification code',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lowStockAlertController,
                decoration: const InputDecoration(
                  labelText: 'Low Stock Alert',
                  border: OutlineInputBorder(),
                  helperText: 'Alert when stock goes below this',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _batchNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Batch Number',
                        border: OutlineInputBorder(),
                        helperText: 'Optional batch identifier',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _expiryDate ??
                              DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 10),
                          ),
                          helpText: 'SELECT EXPIRY DATE',
                        );
                        if (picked != null) {
                          setState(() => _expiryDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Expiry Date',
                          border: const OutlineInputBorder(),
                          suffixIcon: _expiryDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () =>
                                      setState(() => _expiryDate = null),
                                )
                              : const Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          _expiryDate != null
                              ? '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}'
                              : 'Optional',
                          style: TextStyle(
                            color: _expiryDate != null ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(
                        _isEditing ? 'Update Product' : 'Add Product',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Delete "${widget.product!.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(productServiceProvider).deleteProduct(widget.product!.id);
      ref.invalidate(productsProvider);
      if (mounted) context.pop();
    }
  }
}
