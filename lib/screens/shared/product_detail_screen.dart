import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../models/product.dart';
import '../../models/stock_move.dart';
import '../../services/product_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/qty_format.dart';
import '../admin/stock_check_screen.dart';
import '../admin/supplier_return_screen.dart';
import 'product_form_screen.dart';

/// Every movement of one product, newest first.
/// No automatic retry: a failure (e.g. the database update not run yet)
/// showed as a spinner for ever; pull down to try again.
final stockHistoryProvider = FutureProvider.autoDispose.family<List<StockMove>, String>(
  (ref, productId) => ref.read(productServiceProvider).getStockHistory(productId),
  retry: (_, __) => null,
);

String _inr(double v, {int decimals = 0}) =>
    '₹${NumberFormat('#,##,##0${decimals > 0 ? '.${'0' * decimals}' : ''}', 'en_IN').format(v)}';

/// One product (23 Oct 2026): stock, prices, quick actions and the full
/// stock history, so "why is this wrong?" has an answer.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  static const _band = Color(0xFFCFEAF7);
  static const _navy = Color(0xFF0A3550);
  static const _muted = Color(0xFF3F6278);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // the latest copy: stock changes after a count or Stock In
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final p = products.where((x) => x.id == product.id).firstOrNull ?? product;
    final isAdmin = ref.watch(profileProvider).value?.isAdmin ?? false;
    final history = ref.watch(stockHistoryProvider(p.id));

    Future<void> refresh() async {
      ProductService.invalidateCache();
      ref.invalidate(productsProvider);
      ref.invalidate(stockHistoryProvider(p.id));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      appBar: AppBar(
        backgroundColor: _band,
        foregroundColor: _navy,
        titleTextStyle: const TextStyle(color: _navy, fontSize: 20, fontWeight: FontWeight.w800),
        title: const Text('Product'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Edit product',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
                await refresh();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _header(context, p, isAdmin, history.value),
            if (isAdmin) _actions(context, ref, p, refresh),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Stock history',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _navy),
                    ),
                  ),
                  Text('newest first', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  ProductService.isMissingFunction(e)
                      ? 'The stock history appears after the database update (sql/2026_10_inventory_tools.sql).'
                      : ErrorMessages.parse(e),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
              data: (moves) => moves.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No movements yet', style: TextStyle(color: Colors.grey.shade700)),
                    )
                  : Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          for (var i = 0; i < moves.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _MoveRow(move: moves[i], unit: p.unit),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Product p, bool isAdmin, List<StockMove>? moves) {
    final status = stockStatus(p);
    final lastSold = moves?.where((m) => m.kind == 'Sale').firstOrNull?.at;
    final lastBought = moves?.where((m) => m.kind == 'Purchase').firstOrNull?.at;
    String day(DateTime? d) => d == null ? '—' : DateFormat('d MMM yyyy').format(d);
    return Container(
      decoration: const BoxDecoration(
        color: _band,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            p.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _navy),
          ),
          if ((p.tamilName ?? '').isNotEmpty) Text(p.tamilName!, style: const TextStyle(fontSize: 15, color: _muted)),
          const SizedBox(height: 4),
          Text(
            [if ((p.category ?? '').isNotEmpty) p.category!, if ((p.barcode ?? '').isNotEmpty) p.barcode!].join(' · '),
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          if (p.isHidden) ...[
            const SizedBox(height: 8),
            const Text(
              'Hidden: empty for 30 days. It comes back with the next purchase.',
              style: TextStyle(color: Color(0xFF4C3A8F), fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatQty(p.stock),
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1, color: status.fg),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(p.unit, style: const TextStyle(fontSize: 16, color: _muted)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: status.bg, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  status.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: status.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fact('Selling price', _inr(p.sellingPrice, decimals: 2)),
              if (isAdmin) _fact('Cost price', _inr(p.purchasePrice, decimals: 2)),
              if (isAdmin) _fact('Stock value at cost', _inr(p.stockOnHand * p.purchasePrice)),
              _fact('Last sold', day(lastSold)),
              _fact('Last bought', day(lastBought)),
              _fact('Low stock alert at', formatQty(p.lowStockAlert)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 15, color: _navy, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context, WidgetRef ref, Product p, Future<void> Function() refresh) {
    Widget button(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          foregroundColor: _navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          button(Icons.fact_check_outlined, 'Count', () async {
            final r = await showCountSheet(context, p);
            if (r != null) await refresh();
          }),
          const SizedBox(width: 8),
          button(Icons.swap_vert_rounded, 'Stock In / Out', () async {
            final done = await showStockInOutSheet(context, ref, p);
            if (done == true) await refresh();
          }),
          const SizedBox(width: 8),
          button(Icons.assignment_return_outlined, 'Return to supplier', () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierReturnScreen(initialProduct: p)));
            await refresh();
          }),
        ],
      ),
    );
  }
}

/// The colours and words for a product's stock (one place for every list).
({String label, Color bg, Color fg, IconData icon}) stockStatus(Product p) {
  final s = p.totalStock;
  if (p.isExpired)
    return (label: 'Expired', bg: const Color(0xFFFDE8E6), fg: const Color(0xFF8F1D14), icon: Icons.event_busy);
  if (s < -0.0005) {
    return (
      label: 'Purchase pending',
      bg: const Color(0xFFFDEFE0),
      fg: const Color(0xFF9A3412),
      icon: Icons.local_shipping_outlined,
    );
  }
  if (s.abs() < 0.0005) {
    return (
      label: 'Out of stock',
      bg: const Color(0xFFFDE8E6),
      fg: const Color(0xFF8F1D14),
      icon: Icons.remove_shopping_cart_outlined,
    );
  }
  if (p.lowStockAlert > 0 && s <= p.lowStockAlert) {
    return (label: 'Low', bg: const Color(0xFFFFF4DE), fg: const Color(0xFF6B3A00), icon: Icons.warning_amber_rounded);
  }
  if (p.isExpiringSoon) {
    return (label: 'Expiring', bg: const Color(0xFFFFF4DE), fg: const Color(0xFF6B3A00), icon: Icons.schedule);
  }
  return (
    label: 'In stock',
    bg: const Color(0xFFE3F5EA),
    fg: const Color(0xFF0F7A4E),
    icon: Icons.check_circle_outline,
  );
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.move, required this.unit});
  final StockMove move;
  final String unit;

  static IconData _icon(String kind) => switch (kind) {
    'Sale' => Icons.receipt_long_outlined,
    'Purchase' => Icons.local_shipping_outlined,
    'Customer return' => Icons.undo,
    'Damaged' => Icons.broken_image_outlined,
    'Count' => Icons.fact_check_outlined,
    'Correction' => Icons.build_outlined,
    'Stock In' => Icons.add_box_outlined,
    'Stock Out' => Icons.indeterminate_check_box_outlined,
    'Returned to supplier' => Icons.assignment_return_outlined,
    _ => Icons.swap_vert,
  };

  @override
  Widget build(BuildContext context) {
    final inColor = const Color(0xFF0F7A4E);
    final outColor = const Color(0xFFA3301C);
    final zero = move.qty.abs() < 0.0005;
    return ListTile(
      dense: true,
      leading: Icon(_icon(move.kind), color: const Color(0xFF3F6278)),
      title: Text(
        [move.kind, if ((move.ref ?? '').isNotEmpty) move.ref!].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [DateFormat('d MMM yyyy, h:mm a').format(move.at), if ((move.note ?? '').isNotEmpty) move.note!].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            zero ? 'matched' : '${move.isIn ? '+' : '−'}${formatQty(move.qty.abs())}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: zero ? const Color(0xFF0F7A4E) : (move.isIn ? inColor : outColor),
            ),
          ),
          Text('→ ${formatQty(move.stockAfter)} $unit', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

/// Stock In / Stock Out with a reason, so the history says why.
Future<bool?> showStockInOutSheet(BuildContext context, WidgetRef ref, Product p) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StockInOutSheet(product: p, ref: ref),
  );
}

class _StockInOutSheet extends StatefulWidget {
  const _StockInOutSheet({required this.product, required this.ref});
  final Product product;
  final WidgetRef ref;

  @override
  State<_StockInOutSheet> createState() => _StockInOutSheetState();
}

class _StockInOutSheetState extends State<_StockInOutSheet> {
  static const _inReasons = ['Free goods', 'Found on shelf', 'Opening stock', 'Other'];
  static const _outReasons = ['Used in shop', 'Given away', 'Sample', 'Other'];
  final _qty = TextEditingController();
  bool _in = true;
  String _reason = _inReasons.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _error = 'Enter a quantity more than 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = widget.ref.read(productServiceProvider);
      final left = _in
          ? await service.addStock(widget.product.id, qty, reason: _reason)
          : await service.deductStock(widget.product.id, qty, reason: _reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_in ? 'Stock In' : 'Stock Out'} done — now ${formatQty(left)} in stock')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ErrorMessages.parse(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final reasons = _in ? _inReasons : _outReasons;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Now ${formatQty(p.stock)} ${p.unit}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Stock In'), icon: Icon(Icons.add)),
                ButtonSegment(value: false, label: Text('Stock Out'), icon: Icon(Icons.remove)),
              ],
              selected: {_in},
              onSelectionChanged: (v) => setState(() {
                _in = v.first;
                _reason = (_in ? _inReasons : _outReasons).first;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}'))],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(labelText: 'Quantity (${p.unit})', border: const OutlineInputBorder()),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            const Text('Why?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in reasons)
                  ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
              ],
            ),
            if (!_in)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Damaged or expired? Use Damaged. Going back to the agency? Use Return to supplier.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))
                  : Text(_in ? 'Add to stock' : 'Take out of stock'),
            ),
          ],
        ),
      ),
    );
  }
}
