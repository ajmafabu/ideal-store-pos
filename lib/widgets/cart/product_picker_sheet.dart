import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../screens/shared/product_form_screen.dart';

class ProductPickerSheet extends StatefulWidget {
  final List<Product> allProducts;
  final ValueChanged<Product> onProductSelected;

  const ProductPickerSheet({
    super.key,
    required this.allProducts,
    required this.onProductSelected,
  });

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  late List<Product> _filteredProducts;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.allProducts.where((p) => p.stock > 0).toList();
  }

  List<String> get _categories {
    return widget.allProducts
        .where((p) => p.stock > 0 && p.category != null && p.category!.isNotEmpty)
        .map((p) => p.category!)
        .toSet()
        .toList()
      ..sort();
  }

  void _filterProducts(String query, String? category) {
    setState(() {
      _filteredProducts = widget.allProducts
          .where((p) =>
              p.stock > 0 &&
              p.name.toLowerCase().contains(query.toLowerCase()) &&
              (category == null || p.category == category))
          .toList();
    });
  }

  void _addNewProduct() async {
    Navigator.pop(context);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (result == true && context.mounted) {
      // Refresh products
      Navigator.pop(context, true); // Return true to indicate refresh needed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          children: [
            // Header with Add button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search product...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (v) {
                        setSheetState(() => _filterProducts(v, _selectedCategory));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addNewProduct,
                    icon: const Icon(Icons.add, size: 20),
                    tooltip: 'Add New Product',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('All', style: TextStyle(fontSize: 12)),
                        selected: _selectedCategory == null,
                        onSelected: (_) {
                          setSheetState(() {
                            _selectedCategory = null;
                            _filterProducts('', null);
                          });
                        },
                        selectedColor: Colors.blue.withValues(alpha: 0.2),
                      ),
                    ),
                    ..._categories.map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text(cat, style: const TextStyle(fontSize: 12)),
                            selected: _selectedCategory == cat,
                            onSelected: (_) {
                              setSheetState(() {
                                _selectedCategory = cat;
                                _filterProducts('', cat);
                              });
                            },
                            selectedColor: Colors.blue.withValues(alpha: 0.2),
                          ),
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredProducts.isEmpty
                  ? const Center(child: Text('No products found'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ListTile(
                          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Rs${product.sellingPrice} | Stock: ${product.stock}'),
                          onTap: () {
                            widget.onProductSelected(product);
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
}
