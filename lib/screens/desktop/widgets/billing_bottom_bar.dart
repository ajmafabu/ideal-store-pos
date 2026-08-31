import 'package:flutter/material.dart';

import '../../../config/desktop_billing_provider.dart';

class BillingBottomBar extends StatelessWidget {
  final SaleSession session;
  final double billDiscount;
  final double extraCharges;
  final String selectedTier;

  const BillingBottomBar({
    super.key,
    required this.session,
    required this.billDiscount,
    required this.extraCharges,
    required this.selectedTier,
  });

  @override
  Widget build(BuildContext context) {
    final rawTotal = (session.total - billDiscount + extraCharges).clamp(
      0.0,
      double.infinity,
    );
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Spacer(),
              if (session.customerName != null)
                Text(
                  '${session.customerName} | ',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              Text(
                '${session.itemCount} items | ${session.totalQty} pcs',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              if (selectedTier != 'normal') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selectedTier == 'wholesale'
                        ? Colors.orange.shade100
                        : Colors.purple.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    selectedTier.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: selectedTier == 'wholesale'
                          ? Colors.orange.shade800
                          : Colors.purple.shade800,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 16),
              if (billDiscount > 0)
                Text(
                  '-Rs${billDiscount.toStringAsFixed(0)} | ',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              if (extraCharges > 0)
                Text(
                  '+Rs${extraCharges.toStringAsFixed(0)} | ',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              Text(
                'TOTAL: Rs${roundedTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.grey.shade100,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Arrows: Navigate  |  Enter: Select/Edit  |  Shift+Enter: Complete Sale  |  F6: Hold  |  F7: Retrieve  |  F12: Calculator  |  Esc: Cancel',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
