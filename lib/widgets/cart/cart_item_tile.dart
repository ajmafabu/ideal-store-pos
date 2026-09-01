import 'package:flutter/material.dart';
import '../../models/sale.dart';

class CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback onEditPrice;
  final VoidCallback onEditQty;
  final ValueChanged<double> onDiscountChanged;

  const CartItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditPrice,
    required this.onEditQty,
    required this.onDiscountChanged,
  });

  void _showDiscountSheet(BuildContext context) {
    final controller = TextEditingController(
      text: item.discount > 0 ? item.discount.toStringAsFixed(0) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Discount - ${item.name}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Discount %',
                border: OutlineInputBorder(),
                suffixText: '%',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [0, 5, 10, 15, 20, 25, 30, 50].map((pct) {
                return ActionChip(
                  label: Text('$pct%', style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    controller.text = pct.toString();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      onDiscountChanged(0);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final val = double.tryParse(controller.text) ?? 0;
                      final clamped = val.clamp(0.0, 100.0);
                      onDiscountChanged(clamped);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDiscount = item.discount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDiscount
              ? Colors.green.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Product name + price info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasDiscount)
                      GestureDetector(
                        onTap: () => _showDiscountSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${item.discount.toStringAsFixed(0)}%',
                            style: const TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                if (item.tamilName != null && item.tamilName!.isNotEmpty)
                  Text(
                    item.tamilName!,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (item.rateLabel != null && item.rateLabel!.isNotEmpty)
                  Text(
                    item.rateLabel!,
                    style: TextStyle(fontSize: 10, color: Colors.orange[700], fontWeight: FontWeight.w500),
                  ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: onEditPrice,
                  child: Text(
                    hasDiscount
                        ? 'Rs${item.price.toStringAsFixed(0)} x ${item.qty} = Rs${item.total.toStringAsFixed(0)}'
                        : 'Rs${item.price.toStringAsFixed(0)} x ${item.qty} = Rs${item.total.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: hasDiscount ? Colors.green : Colors.blue,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quantity — tap to edit
          GestureDetector(
            onTap: onEditQty,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '×${item.qty}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Delete
          InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.close, size: 16, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
