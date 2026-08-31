import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/product.dart';

class AllTopProductsScreen extends StatefulWidget {
  const AllTopProductsScreen({super.key});

  @override
  State<AllTopProductsScreen> createState() => _AllTopProductsScreenState();
}

class _AllTopProductsScreenState extends State<AllTopProductsScreen> {
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select()
          .order('name');
      setState(() {
        _products = (response as List).map((e) => Product.fromJson(e)).toList();
        _products.sort((a, b) {
          final profitA = (a.sellingPrice - a.purchasePrice) * a.stock;
          final profitB = (b.sellingPrice - b.purchasePrice) * b.stock;
          return profitB.compareTo(profitA);
        });
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final profitable = _products
        .where((p) => p.sellingPrice > 0 && p.stock > 0)
        .toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Top Profitable Products',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headers: [
              '#',
              'Product',
              'Sell Price',
              'Cost Price',
              'Stock',
              'Profit',
              'Margin%',
            ],
            data: profitable.asMap().entries.map((entry) {
              final i = entry.key + 1;
              final p = entry.value;
              final profit = (p.sellingPrice - p.purchasePrice) * p.stock;
              final margin = p.sellingPrice > 0
                  ? ((p.sellingPrice - p.purchasePrice) / p.sellingPrice * 100)
                  : 0.0;
              return [
                '$i',
                p.name,
                'Rs${p.sellingPrice.toStringAsFixed(0)}',
                'Rs${p.purchasePrice.toStringAsFixed(0)}',
                '${p.stock}',
                'Rs${profit.toStringAsFixed(0)}',
                '${margin.toStringAsFixed(0)}%',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Top_Profitable_Products.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Profitable Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportPdf,
            tooltip: 'Export PDF',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _products
                  .where((p) => p.sellingPrice > 0 && p.stock > 0)
                  .length,
              itemBuilder: (context, index) {
                final profitable = _products
                    .where((p) => p.sellingPrice > 0 && p.stock > 0)
                    .toList();
                final product = profitable[index];
                final profit =
                    (product.sellingPrice - product.purchasePrice) *
                    product.stock;
                final margin = product.sellingPrice > 0
                    ? ((product.sellingPrice - product.purchasePrice) /
                          product.sellingPrice *
                          100)
                    : 0.0;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: profit >= 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : Colors.red.shade50,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: profit >= 0
                            ? const Color(0xFF10B981)
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Rs${product.sellingPrice.toStringAsFixed(0)} | Stock: ${product.stock} | Margin: ${margin.toStringAsFixed(0)}%',
                  ),
                  trailing: Text(
                    'Rs${profit.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: profit >= 0 ? const Color(0xFF10B981) : Colors.red,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
