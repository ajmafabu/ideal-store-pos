import 'package:flutter/material.dart';

class CartSummary extends StatelessWidget {
  final double subtotal;
  final double discount;
  final double total;
  final bool isCredit;
  final int itemCount;
  final double customerDue;
  final String? customerName;
  final VoidCallback onCompleteSale;

  const CartSummary({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.isCredit,
    required this.itemCount,
    this.customerDue = 0,
    this.customerName,
    required this.onCompleteSale,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Customer info (if selected)
        if (customerName != null && customerName!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: customerDue > 0 ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.person, size: 14, color: customerDue > 0 ? Colors.orange : Colors.blue),
                const SizedBox(width: 4),
                Text(customerName!, style: TextStyle(fontSize: 11, color: customerDue > 0 ? Colors.orange : Colors.blue, fontWeight: FontWeight.w500)),
                if (customerDue > 0) ...[
                  const Spacer(),
                  Text('Due: Rs${customerDue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
        // Item count + subtotal row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$itemCount item${itemCount != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              'Subtotal: Rs ${subtotal.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        if (discount > 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Discount:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('-Rs ${discount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, color: Colors.green)),
            ],
          ),
        const SizedBox(height: 4),
        // Total row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              'Rs ${total.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Complete button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: onCompleteSale,
            style: ElevatedButton.styleFrom(
              backgroundColor: isCredit ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              isCredit ? 'Complete Credit Sale' : 'Complete Sale',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
