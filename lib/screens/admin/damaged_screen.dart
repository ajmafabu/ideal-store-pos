import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/product.dart';
import '../../models/damaged_product.dart';
import '../../utils/error_messages.dart';
import '../../utils/qty_format.dart';
import '../../widgets/search_picker.dart';

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
          error: (e, _) => Center(child: Text('Error: ${ErrorMessages.parse(e)}')),
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
                      'Qty: ${formatQty(d.quantity)} | Rs${(d.unitPrice * d.quantity).toStringAsFixed(0)}\n${d.reason ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('dd MMM\nhh:mm a').format(d.createdAt),
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.end,
                        ),
                        // a wrong entry stayed forever (QA #86)
                        IconButton(
                          tooltip: 'Delete entry',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmDelete(d),
                        ),
                      ],
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

  Future<void> _confirmDelete(DamagedProduct d) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete damaged entry?'),
        content: Text(
          '${d.productName} × ${formatQty(d.quantity)} goes back into stock and its loss leaves the profit figures.\n\n'
          'To correct a wrong entry, delete it and enter it again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(damagedServiceProvider).deleteDamaged(d.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted — ${formatQty(d.quantity)} back in stock'), backgroundColor: Colors.green),
      );
    } catch (e) {
      final text = e.toString().contains('delete_damaged_atomic')
          ? 'Not deleted: the database needs sql/2026_10_stage2_fixes.sql first'
          : 'Not deleted: ${ErrorMessages.parse(e)}';
      messenger.showSnackBar(
        SnackBar(content: Text(text), backgroundColor: Colors.red, duration: const Duration(seconds: 8)),
      );
    }
    ref.invalidate(damagedProvider);
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
              error: (e, _) => Text('Error: ${ErrorMessages.parse(e)}'),
              data: (products) {
                final available = products.where((p) => p.stock > 0).toList();
                // search box instead of a 1,000-item dropdown (QA #30)
                return InkWell(
                  onTap: () async {
                    final picked = await showSearchPicker<Product>(
                      context: context,
                      title: 'Damaged product',
                      hint: 'Type name, Tamil name or barcode',
                      items: available,
                      label: (p) => p.name,
                      subtitle: (p) => 'Stock: ${formatQty(p.stock)} ${p.unit}',
                      searchText: (p) => '${p.tamilName ?? ''} ${p.barcode ?? ''}',
                    );
                    if (picked != null) setState(() => _selectedProduct = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Product',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.search),
                    ),
                    child: Text(
                      _selectedProduct == null
                          ? 'Tap to search'
                          : '${_selectedProduct!.name} (Stock: ${formatQty(_selectedProduct!.stock)})',
                      style: TextStyle(color: _selectedProduct == null ? Colors.grey.shade700 : null),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Quantity
            TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                DropdownMenuItem(value: 'Broken', child: Text('Broken')),
                DropdownMenuItem(value: 'Expired', child: Text('Expired')),
                DropdownMenuItem(value: 'Stolen', child: Text('Stolen')),
                DropdownMenuItem(value: 'Water damage', child: Text('Water damage')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
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

    final qty = double.tryParse(_qtyController.text.trim()) ?? 0; // decimals for kg/litre (QA #60)
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
          SnackBar(content: Text('Error: ${ErrorMessages.parse(e)}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
