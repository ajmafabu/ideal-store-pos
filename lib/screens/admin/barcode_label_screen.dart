import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/product.dart';
import '../../config/providers.dart';

class BarcodeLabelScreen extends ConsumerStatefulWidget {
  const BarcodeLabelScreen({super.key});

  @override
  ConsumerState<BarcodeLabelScreen> createState() => _BarcodeLabelScreenState();
}

class _BarcodeLabelScreenState extends ConsumerState<BarcodeLabelScreen> {
  Product? _selectedProduct;
  String _labelSize = '38x25';
  int _quantity = 1;
  String _searchQuery = '';

  static const Map<String, List<double>> _labelSizes = {
    '38x25': [38, 25],
    '50x30': [50, 30],
    '50x40': [50, 40],
  };

  double get _currentWidth => _labelSizes[_labelSize]![0] * PdfPageFormat.mm;
  double get _currentHeight => _labelSizes[_labelSize]![1] * PdfPageFormat.mm;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode Labels'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search products...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _labelSize,
                    decoration: const InputDecoration(
                      labelText: 'Label Size',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: '38x25', child: Text('38 x 25 mm')),
                      DropdownMenuItem(value: '50x30', child: Text('50 x 30 mm')),
                      DropdownMenuItem(value: '50x40', child: Text('50 x 40 mm')),
                    ],
                    onChanged: (v) => setState(() => _labelSize = v ?? '38x25'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: '1',
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _quantity = int.tryParse(v) ?? 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (products) {
                final filtered = products.where((p) {
                  return p.name.toLowerCase().contains(_searchQuery) ||
                      (p.barcode?.toLowerCase().contains(_searchQuery) ?? false);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No products found'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    final isSelected = _selectedProduct?.id == product.id;
                    return Card(
                      color: isSelected ? const Color(0xFF667eea).withValues(alpha: 0.1) : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? const Color(0xFF667eea)
                              : Colors.grey.shade200,
                          child: Icon(
                            Icons.qr_code,
                            color: isSelected ? Colors.white : Colors.grey,
                          ),
                        ),
                        title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'Rs.${product.sellingPrice} | ${product.barcode ?? 'No barcode'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Color(0xFF667eea))
                            : null,
                        onTap: () => setState(() => _selectedProduct = product),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _selectedProduct == null ? null : _printLabels,
            icon: const Icon(Icons.print),
            label: Text('Print $_quantity Label${_quantity > 1 ? 's' : ''}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF667eea),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              disabledBackgroundColor: Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printLabels() async {
    final product = _selectedProduct;
    if (product == null) return;

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        final labelWidth = _currentWidth;
        final labelHeight = _currentHeight;

        for (int i = 0; i < _quantity; i++) {
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(labelWidth, labelHeight, marginAll: 1 * PdfPageFormat.mm),
              build: (pw.Context context) {
                return _buildLabel(product, labelWidth, labelHeight);
              },
            ),
          );
        }

        return doc.save();
      },
      name: 'Labels_${product.name.replaceAll(' ', '_')}',
    );
  }

  pw.Widget _buildLabel(Product product, double width, double height) {
    final isSmall = _labelSize == '38x25';
    final nameFontSize = isSmall ? 7.0 : 9.0;
    final priceFontSize = isSmall ? 10.0 : 14.0;
    final barcodeHeight = isSmall ? 12.0 : 18.0;

    return pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          product.name,
          style: pw.TextStyle(
            fontSize: nameFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
          textAlign: pw.TextAlign.center,
          maxLines: isSmall ? 1 : 2,
          overflow: pw.TextOverflow.clip,
        ),
        pw.SizedBox(height: 2),
        if (product.barcode != null && product.barcode!.isNotEmpty)
          pw.BarcodeWidget(
            data: product.barcode!,
            barcode: pw.Barcode.code128(),
            width: width * 0.8,
            height: barcodeHeight,
            drawText: false,
          ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Rs.${product.sellingPrice.toStringAsFixed(0)}',
          style: pw.TextStyle(
            fontSize: priceFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (!isSmall && product.batchNumber != null && product.batchNumber!.isNotEmpty)
          pw.Text(
            'Batch: ${product.batchNumber}',
            style: const pw.TextStyle(fontSize: 6),
          ),
      ],
    );
  }
}
