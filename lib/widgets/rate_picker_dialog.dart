import 'package:flutter/material.dart';
import '../models/product.dart';

class RatePickerResult {
  final double price;
  final String? label;
  const RatePickerResult(this.price, this.label);
}

class RatePickerDialog extends StatelessWidget {
  final Product product;
  const RatePickerDialog({super.key, required this.product});

  static Future<RatePickerResult?> show(BuildContext context, Product product) {
    if (!product.hasDualRates) {
      return Future.value(RatePickerResult(product.sellingPrice, null));
    }
    return showDialog<RatePickerResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RatePickerDialog(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rate1Label = product.sellingPrice2Label ?? 'Rate 1';
    final rate2Label = 'Rate 2';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.attach_money, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose selling rate:',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _RateCard(
            label: rate1Label,
            price: product.sellingPrice,
            color: Colors.blue,
            icon: Icons.star,
            onTap: () => Navigator.pop(
              context,
              RatePickerResult(product.sellingPrice, null),
            ),
          ),
          const SizedBox(height: 12),
          _RateCard(
            label: rate2Label,
            price: product.sellingPrice2!,
            color: Colors.orange,
            icon: Icons.star_border,
            onTap: () => Navigator.pop(
              context,
              RatePickerResult(product.sellingPrice2!, product.sellingPrice2Label),
            ),
          ),
        ],
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  final String label;
  final double price;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _RateCard({
    required this.label,
    required this.price,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
