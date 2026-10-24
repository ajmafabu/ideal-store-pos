import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../models/product.dart';
import '../../models/sale.dart' show newDocumentId;
import '../../models/supplier.dart';
import '../../services/product_service.dart';
import '../../services/supplier_return_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/product_search.dart';
import '../../utils/qty_format.dart';
import '../../widgets/barcode_scanner.dart';

String _inr(double v) => '₹${NumberFormat('#,##,##0.##', 'en_IN').format(v)}';

class _Line {
  _Line(this.product, double qty, double price)
    : qty = TextEditingController(text: formatQty(qty)),
      price = TextEditingController(text: price == 0 ? '' : price.toStringAsFixed(2));
  final Product product;
  final TextEditingController qty;
  final TextEditingController price;

  double get q => double.tryParse(qty.text.trim()) ?? 0;
  double get p => double.tryParse(price.text.trim()) ?? 0;
  double get total => q * p;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Goods going back to the agency (23 Oct 2026): expired, damaged, wrong
/// item, not selling. The stock comes out at its real cost; the value first
/// comes off what the shop owes that supplier, the rest is money received
/// back.
class SupplierReturnScreen extends ConsumerStatefulWidget {
  const SupplierReturnScreen({super.key, this.initialProduct});
  final Product? initialProduct;

  @override
  ConsumerState<SupplierReturnScreen> createState() => _SupplierReturnScreenState();
}

class _SupplierReturnScreenState extends ConsumerState<SupplierReturnScreen> {
  static const _reasons = ['Expired', 'Damaged', 'Wrong item', 'Not selling', 'Other'];
  final _service = SupplierReturnService();
  final _search = TextEditingController();
  final _lines = <_Line>[];
  Supplier? _supplier;
  String _reason = _reasons.first;
  String _method = 'cash';
  String _query = '';
  bool _saving = false;

  /// One id per return: a retried save is recognised by the database.
  String _id = newDocumentId();

  @override
  void initState() {
    super.initState();
    final p = widget.initialProduct;
    if (p != null) _lines.add(_Line(p, 1, p.purchasePrice));
  }

  @override
  void dispose() {
    _search.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  void _add(Product p) {
    setState(() {
      if (!_lines.any((l) => l.product.id == p.id)) _lines.add(_Line(p, 1, p.purchasePrice));
      _search.clear();
      _query = '';
    });
  }

  Future<void> _scan(List<Product> products) async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code == null || !mounted) return;
    final p = products.where((x) => (x.barcode ?? '') == code.trim()).firstOrNull;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No product with barcode $code')));
    } else {
      _add(p);
    }
  }

  Future<void> _save() async {
    final bad = _lines.where((l) => l.q <= 0 || l.p < 0).toList();
    if (_lines.isEmpty || bad.isNotEmpty) {
      _snack(_lines.isEmpty ? 'Add the products going back' : 'Check the quantity of ${bad.first.product.name}');
      return;
    }
    final over = _lines.where((l) => l.q > l.product.stock + 0.0005).toList();
    if (over.isNotEmpty) {
      final p = over.first.product;
      _snack('Only ${formatQty(p.stock)} ${p.unit} of ${p.name} in stock');
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await _service.create(
        id: _id,
        supplierId: _supplier?.id,
        supplierName: _supplier?.name ?? 'Supplier',
        lines: [
          for (final l in _lines)
            SupplierReturnLine(productId: l.product.id, name: l.product.name, qty: l.q, price: l.p),
        ],
        refundMethod: _method,
        reason: _reason,
      );
      ref.invalidate(productsProvider);
      ref.invalidate(suppliersProvider);
      if (!mounted) return;
      _snack(
        [
          'Returned ${_inr(r.total)} to ${r.supplierName}',
          if (r.credit > 0) '${_inr(r.credit)} off what you owe',
          if (r.refund > 0) '${_inr(r.refund)} received back',
        ].join(' · '),
      );
      setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines.clear();
        _id = newDocumentId();
        _saving = false;
      });
      if (widget.initialProduct != null) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(
          ProductService.isMissingFunction(e)
              ? 'Return to supplier needs the database update (sql/2026_10_inventory_tools.sql)'
              : ErrorMessages.parse(e),
        );
      }
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];
    final found = _query.trim().isEmpty ? const <Product>[] : searchProducts(products, _query).take(8).toList();
    final total = _lines.fold<double>(0, (t, l) => t + l.total);
    final dues = _supplier?.totalDues ?? 0;
    final credit = total < dues ? total : dues;
    final refund = total - credit;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Return to supplier'),
        actions: [
          IconButton(
            tooltip: 'Past returns',
            icon: const Icon(Icons.history),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierReturnsListScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _supplier?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Supplier', border: OutlineInputBorder()),
            items: [
              for (final s in suppliers)
                DropdownMenuItem(
                  value: s.id,
                  child: Text(
                    s.totalDues > 0 ? '${s.name}  ·  you owe ${_inr(s.totalDues)}' : s.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(() => _supplier = suppliers.where((s) => s.id == id).firstOrNull),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Add a product: name, Tamil name or barcode',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Platform.isAndroid
                  ? IconButton(
                      tooltip: 'Scan barcode',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () => _scan(products),
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (v) {
              final exact = products.where((p) => (p.barcode ?? '') == v.trim()).toList();
              if (exact.length == 1) {
                _add(exact.first);
              } else if (found.isNotEmpty) {
                _add(found.first);
              }
            },
          ),
          for (final p in found)
            ListTile(
              dense: true,
              title: Text(p.name),
              subtitle: Text('${formatQty(p.stock)} ${p.unit} in stock · cost ${_inr(p.purchasePrice)}'),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _add(p),
            ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No products added yet',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final l in _lines)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _lines.remove(l);
                            l.dispose();
                          }),
                        ),
                      ],
                    ),
                    Text(
                      '${formatQty(l.product.stock)} ${l.product.unit} in stock',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: l.qty,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
                            decoration: InputDecoration(
                              labelText: 'Qty (${l.product.unit})',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: l.price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                            decoration: const InputDecoration(
                              labelText: 'Value each ₹',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 84,
                          child: Text(
                            _inr(l.total),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('Why?', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _reasons)
                ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 14),
            Card(
              color: const Color(0xFFEAF6FC),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total returned ${_inr(total)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (credit > 0) Text('${_inr(credit)} comes off what you owe ${_supplier!.name}'),
                    if (refund > 0) ...[
                      Text('${_inr(refund)} received back now, by:'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final m in const [('cash', 'Cash'), ('upi', 'UPI'), ('bank', 'Bank')])
                            ChoiceChip(
                              label: Text(m.$2),
                              selected: _method == m.$1,
                              onSelected: (_) => setState(() => _method = m.$1),
                            ),
                        ],
                      ),
                    ],
                    if (_supplier == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Pick the supplier to take it off what you owe them.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _saving || _lines.isEmpty ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
                : const Icon(Icons.assignment_return_outlined),
            label: Text(total > 0 ? 'Save return · ${_inr(total)}' : 'Save return'),
          ),
        ),
      ),
    );
  }
}

/// Returns already made, newest first; one can be deleted if it was a mistake.
class SupplierReturnsListScreen extends ConsumerStatefulWidget {
  const SupplierReturnsListScreen({super.key});

  @override
  ConsumerState<SupplierReturnsListScreen> createState() => _SupplierReturnsListScreenState();
}

class _SupplierReturnsListScreenState extends ConsumerState<SupplierReturnsListScreen> {
  final _service = SupplierReturnService();
  late Future<List<SupplierReturn>> _future = _service.recent();

  Future<void> _delete(SupplierReturn r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this return?'),
        content: Text(
          'The goods go back into stock, ${_inr(r.credit)} goes back onto what you owe '
          '${r.supplierName}${r.refund > 0 ? ', and the ${_inr(r.refund)} received is taken back out' : ''}.',
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
      await _service.delete(r.id);
      ref.invalidate(productsProvider);
      ref.invalidate(suppliersProvider);
      setState(() => _future = _service.recent());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.parse(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past returns to suppliers')),
      body: FutureBuilder<List<SupplierReturn>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  ProductService.isMissingFunction(snap.error!) || '${snap.error}'.contains('supplier_returns')
                      ? 'Return to supplier needs the database update (sql/2026_10_inventory_tools.sql).'
                      : ErrorMessages.parse(snap.error!),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final list = snap.data ?? const <SupplierReturn>[];
          if (list.isEmpty) return const Center(child: Text('No returns yet'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = list[i];
              return ListTile(
                title: Text(
                  '${r.supplierName} · ${_inr(r.total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    DateFormat('d MMM yyyy').format(r.at),
                    r.items.map((x) => '${x['name']} × ${formatQty((x['qty'] as num?) ?? 0)}').join(', '),
                    if (r.credit > 0) '${_inr(r.credit)} off dues',
                    if (r.refund > 0) '${_inr(r.refund)} back by ${r.refundMethod.toUpperCase()}',
                    if ((r.reason ?? '').isNotEmpty) r.reason!,
                  ].join(' · '),
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
