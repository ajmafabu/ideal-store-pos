import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/product.dart';
import '../../models/damaged_product.dart';

class DamagedScreen extends ConsumerStatefulWidget {
  const DamagedScreen({super.key});

  @override
  ConsumerState<DamagedScreen> createState() => _DamagedScreenState();
}

class _DamagedScreenState extends ConsumerState<DamagedScreen> {
  @override
  Widget build(BuildContext context) {
    final damagedAsync = ref.watch(damagedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Damaged Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(damagedProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(damagedProvider),
        child: damagedAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(child: Text('No damaged products recorded'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final d = items[index] as DamagedProduct;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.broken_image, color: Colors.red),
                    ),
                    title: Text(
                      d.productName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Qty: ${d.quantity} | Rs${(d.unitPrice * d.quantity).toStringAsFixed(0)}\n${d.reason ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      DateFormat('dd MMM\nhh:mm a').format(d.createdAt),
                      style: const TextStyle(fontSize: 11),
                      textAlign: TextAlign.end,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.red, Colors.deepOrange]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddDamaged(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Damaged', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  void _showAddDamaged(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddDamagedSheet(),
    ).then((_) => ref.invalidate(damagedProvider));
  }
}

class _AddDamagedSheet extends ConsumerStatefulWidget {
  const _AddDamagedSheet();

  @override
  ConsumerState<_AddDamagedSheet> createState() => _AddDamagedSheetState();
}

class _AddDamagedSheetState extends ConsumerState<_AddDamagedSheet> {
  Product? _selectedProduct;
  final _qtyController = TextEditingController(text: '1');
  final _reasonController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Record Damaged Product',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Stock will be reduced by the quantity entered',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // Product selection
            productsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (products) {
                final available = products.where((p) => p.stock > 0).toList();
                return DropdownButtonFormField<Product>(
                  value: _selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'Product',
                    border: OutlineInputBorder(),
                  ),
                  items: available.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (Stock: ${p.stock})'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedProduct = v),
                );
              },
            ),
            const SizedBox(height: 12),

            // Quantity
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Reason
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'broken', child: Text('Broken')),
                DropdownMenuItem(value: 'expired', child: Text('Expired')),
                DropdownMenuItem(value: 'stolen', child: Text('Stolen')),
                DropdownMenuItem(
                  value: 'water_damage',
                  child: Text('Water Damage'),
                ),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => _reasonController.text = v ?? '',
            ),
            const SizedBox(height: 16),

            // Submit
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Record Damaged',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a product')));
      return;
    }

    final qty = int.tryParse(_qtyController.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter valid quantity')));
      return;
    }

    if (qty > _selectedProduct!.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity exceeds available stock')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final damaged = DamagedProduct(
        id: '',
        productId: _selectedProduct!.id,
        productName: _selectedProduct!.name,
        quantity: qty,
        unitPrice: _selectedProduct!.purchasePrice,
        reason: _reasonController.text.isNotEmpty
            ? _reasonController.text
            : null,
        createdAt: DateTime.now(),
      );

      await ref.read(damagedServiceProvider).createDamaged(damaged);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Damaged product recorded'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
