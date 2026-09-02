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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              _buildStat('TOTAL ITEMS', '${session.itemCount}'),
              const SizedBox(width: 32),
              _buildStat('TOTAL QTY', '${session.totalQty}'),
              const Spacer(),
              if (billDiscount > 0) ...[
                Text(
                  '-₹${billDiscount.toStringAsFixed(0)}  ',
                  style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
                ),
              ],
              if (extraCharges > 0) ...[
                Text(
                  '+₹${extraCharges.toStringAsFixed(0)}  ',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w500),
                ),
              ],
              if (selectedTier != 'normal') ...[
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
                const SizedBox(width: 12),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SUBTOTAL',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '₹${roundedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFF0F172A),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ShortcutHint(label: 'Arrows', action: 'Navigate'),
              _Separator(),
              _ShortcutHint(label: 'Enter', action: 'Select/Edit'),
              _Separator(),
              _ShortcutHint(label: 'Shift+Enter', action: 'Complete Sale'),
              _Separator(),
              _ShortcutHint(label: 'F6', action: 'Hold'),
              _Separator(),
              _ShortcutHint(label: 'F7', action: 'Retrieve'),
              _Separator(),
              _ShortcutHint(label: 'F12', action: 'Calculator'),
              _Separator(),
              _ShortcutHint(label: 'Esc', action: 'Cancel'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }
}

class _ShortcutHint extends StatelessWidget {
  final String label;
  final String action;

  const _ShortcutHint({required this.label, required this.action});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
          TextSpan(
            text: ': $action',
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '|',
        style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3)),
      ),
    );
  }
}
