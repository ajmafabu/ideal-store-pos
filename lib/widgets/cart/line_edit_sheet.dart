import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../models/sale.dart';
import '../../utils/qty_format.dart';
import 'cart_item_tile.dart' show rupees, rupees2;

/// What the shop changed on one bill line.
class LineEdit {
  LineEdit({required this.qty, required this.price, required this.discount, this.rateLabel, this.remove = false});
  final double qty;
  final double price;
  final double discount; // %
  final String? rateLabel;
  final bool remove;
}

/// Tap a bill line: quantity, price, the product's second rate and a
/// discount, all in one place (17 Oct 2026). Before, price was a tap on
/// small underlined text, and a line discount could only be changed once it
/// already had one, so it could never be given.
class LineEditSheet extends StatefulWidget {
  const LineEditSheet({super.key, required this.item, this.product});

  final CartItem item;

  /// For the second rate (box / wholesale) and the stock figure.
  final Product? product;

  static Future<LineEdit?> show(BuildContext context, CartItem item, {Product? product}) {
    return showModalBottomSheet<LineEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LineEditSheet(item: item, product: product),
    );
  }

  @override
  State<LineEditSheet> createState() => _LineEditSheetState();
}

class _LineEditSheetState extends State<LineEditSheet> {
  late final _qty = TextEditingController(text: formatQty(widget.item.qty));
  late final _price = TextEditingController(text: _plain(widget.item.price));
  late final _discount =
      TextEditingController(text: widget.item.discount > 0 ? formatQty(widget.item.discount) : '');
  late String? _rateLabel = widget.item.rateLabel;
  String? _error;

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // pieces and packs are whole numbers; loose goods (kg, litre) may be 1.5
  bool get _wholeOnly => !const {'kg', 'g', 'gm', 'gram', 'ltr', 'litre', 'l', 'ml'}
      .contains(widget.item.unit.toLowerCase().trim());

  double get _qtyValue => double.tryParse(_qty.text) ?? 0;
  double get _priceValue => double.tryParse(_price.text) ?? 0;
  double get _discountValue => (double.tryParse(_discount.text) ?? 0).clamp(0, 100).toDouble();

  double get _lineTotal => _priceValue * _qtyValue * (1 - _discountValue / 100);

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _discount.dispose();
    super.dispose();
  }

  void _step(double d) {
    final next = (_qtyValue + d).clamp(_wholeOnly ? 1.0 : 0.25, 99999.0);
    setState(() => _qty.text = formatQty(next));
  }

  void _save() {
    final qty = _qtyValue;
    final price = _priceValue;
    if (qty <= 0) return setState(() => _error = 'Enter a quantity');
    if (_wholeOnly && qty != qty.roundToDouble()) {
      return setState(() => _error = 'Whole ${widget.item.unit} only');
    }
    if (price <= 0) return setState(() => _error = 'Enter a price');
    Navigator.pop(
      context,
      LineEdit(qty: qty, price: price, discount: _discountValue, rateLabel: _rateLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final p = widget.product;
    final belowCost = item.purchasePrice > 0 && _priceValue > 0 && _priceValue < item.purchasePrice;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if ((item.tamilName ?? '').isNotEmpty)
              Text(item.tamilName!, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (p != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Stock ${formatQty(p.stock)} ${p.unit}',
                  style: TextStyle(fontSize: 13, color: p.stock < _qtyValue ? scheme.error : scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 16),

            // quantity
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Less',
                  iconSize: 26,
                  onPressed: () => _step(_wholeOnly ? -1 : -0.25),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _qty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    keyboardType: TextInputType.numberWithOptions(decimal: !_wholeOnly),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(_wholeOnly ? r'^\d*' : r'^\d*\.?\d{0,3}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Quantity (${item.unit})',
                      border: const OutlineInputBorder(),
                    ),
                    onTap: () => _qty.selection = TextSelection(baseOffset: 0, extentOffset: _qty.text.length),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'More',
                  iconSize: 26,
                  onPressed: () => _step(_wholeOnly ? 1 : 0.25),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // the product's two rates
            if (p != null && p.hasDualRates) ...[
              SegmentedButton<String?>(
                segments: [
                  ButtonSegment(value: null, label: Text('Normal ${rupees(p.sellingPrice)}')),
                  ButtonSegment(
                    value: (p.sellingPrice2Label?.trim().isNotEmpty ?? false) ? p.sellingPrice2Label!.trim() : 'Rate 2',
                    label: Text(
                      '${(p.sellingPrice2Label?.trim().isNotEmpty ?? false) ? p.sellingPrice2Label!.trim() : 'Rate 2'} '
                      '${rupees(p.sellingPrice2!)}',
                    ),
                  ),
                ],
                selected: {_rateLabel},
                onSelectionChanged: (v) => setState(() {
                  _rateLabel = v.first;
                  _price.text = _plain(_rateLabel == null ? p.sellingPrice : p.sellingPrice2!);
                }),
              ),
              const SizedBox(height: 14),
            ],

            // price and discount
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    decoration: const InputDecoration(
                      labelText: 'Price each',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                    decoration: const InputDecoration(
                      labelText: 'Discount',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final pct in const [0, 5, 10, 15, 20])
                  ChoiceChip(
                    label: Text(pct == 0 ? 'No discount' : '$pct%'),
                    selected: _discountValue == pct,
                    onSelected: (_) => setState(() => _discount.text = pct == 0 ? '' : '$pct'),
                  ),
              ],
            ),
            if (belowCost)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Below cost ${rupees2(item.purchasePrice)}: loses ${rupees2(item.purchasePrice - _priceValue)} each',
                  style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Line total', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Text(rupees2(_lineTotal), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    LineEdit(qty: 0, price: item.price, discount: item.discount, remove: true),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: const Size(0, 52),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    child: const Text('Save', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
