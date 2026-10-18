import 'package:flutter/material.dart';

import '../../models/sale.dart';
import '../../utils/qty_format.dart';

/// "₹9.33", "₹60" — exact paise, no rounding (the old line showed ₹9.33 as
/// "Rs9", so the bill on screen did not add up).
String rupees(double v) =>
    '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

/// "₹80.00": totals always with paise.
String rupees2(double v) => '₹${v.toStringAsFixed(2)}';

/// One bill line on the phone (rebuilt 17 Oct 2026): name and Tamil name,
/// the exact price each, − qty + right on the line (the old line had no
/// buttons, every change opened a box), and the line total.
/// Tap the line to change quantity, price, rate or discount; swipe it away
/// to remove (the screen offers Undo).
class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEdit,
    required this.onRemove,
    this.lowStock = false,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  /// More on the bill than in stock.
  final bool lowStock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasDiscount = item.discount > 0;
    final details = <String>[
      if ((item.tamilName ?? '').isNotEmpty) item.tamilName!,
      '${rupees(item.price)} each',
      if ((item.rateLabel ?? '').isNotEmpty) item.rateLabel!,
    ];

    return Dismissible(
      key: ObjectKey(item),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: scheme.errorContainer,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 6),
            Text('Remove', style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details.join('  ·  '),
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasDiscount || lowStock)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          spacing: 6,
                          children: [
                            if (hasDiscount)
                              _tag(
                                context,
                                '${formatQty(item.discount)}% off  −${rupees(item.discountAmount)}',
                                scheme.tertiaryContainer,
                                scheme.onTertiaryContainer,
                              ),
                            if (lowStock)
                              _tag(context, 'Low stock', scheme.errorContainer, scheme.onErrorContainer),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _StepButton(icon: Icons.remove, tooltip: 'One less', onTap: onDecrement),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 38),
                child: Text(
                  formatQty(item.qty),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              _StepButton(icon: Icons.add, tooltip: 'One more', onTap: onIncrement),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 70),
                child: Text(
                  rupees2(item.total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.outlined(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(icon),
        onPressed: onTap,
      ),
    );
  }
}
