import 'package:flutter/material.dart';

import '../../config/desktop_billing_provider.dart';

class BillingPaymentPanel extends StatelessWidget {
  const BillingPaymentPanel({
    super.key,
    required this.session,
    required this.total,
    required this.billDiscountController,
    required this.billDiscountFocusNode,
    required this.extraChargesController,
    required this.extraChargesFocusNode,
    required this.paidController,
    required this.paidFocusNode,
    required this.splitCashController,
    required this.splitUpiController,
    required this.selectedTier,
    required this.selectedPayment,
    required this.creditFull,
    required this.isSplitPayment,
    required this.isProcessing,
    required this.editingSale,
    required this.customerCredit,
    required this.onTierChanged,
    required this.onPaymentChanged,
    required this.onCreditFullChanged,
    required this.onShowCustomerPicker,
    required this.onAddNewCustomer,
    required this.onCompleteSale,
    required this.onHoldBill,
    required this.onRetrieveBill,
    required this.onEditingSaleChanged,
    required this.onDiscountChanged,
    required this.onExtraChargesChanged,
    required this.onPaidChanged,
    required this.onSplitCashChanged,
    required this.onSplitUpiChanged,
  });

  final SaleSession session;
  final double total;
  final TextEditingController billDiscountController;
  final FocusNode billDiscountFocusNode;
  final TextEditingController extraChargesController;
  final FocusNode extraChargesFocusNode;
  final TextEditingController paidController;
  final FocusNode paidFocusNode;
  final TextEditingController splitCashController;
  final TextEditingController splitUpiController;
  final String selectedTier;
  final String selectedPayment;
  final bool creditFull;
  final bool isSplitPayment;
  final bool isProcessing;
  final dynamic editingSale;
  final double customerCredit;
  final ValueChanged<String> onTierChanged;
  final ValueChanged<String> onPaymentChanged;
  final ValueChanged<bool> onCreditFullChanged;
  final VoidCallback onShowCustomerPicker;
  final VoidCallback onAddNewCustomer;
  final VoidCallback onCompleteSale;
  final VoidCallback onHoldBill;
  final VoidCallback onRetrieveBill;
  final ValueChanged<dynamic> onEditingSaleChanged;
  final ValueChanged<String> onDiscountChanged;
  final ValueChanged<String> onExtraChargesChanged;
  final ValueChanged<String> onPaidChanged;
  final ValueChanged<String> onSplitCashChanged;
  final ValueChanged<String> onSplitUpiChanged;

  double get _discount => double.tryParse(billDiscountController.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final discount = _discount;
    final extraCharges = double.tryParse(extraChargesController.text) ?? 0;
    final rawTotal = (total - discount + extraCharges).clamp(
      0.0,
      double.infinity,
    );
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    final roundOffAmount = roundedTotal - rawTotal;
    final finalTotal = roundedTotal;
    final dueAmount = selectedPayment == 'credit'
        ? (creditFull
              ? finalTotal
              : finalTotal - (double.tryParse(paidController.text) ?? 0))
        : 0.0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGrandTotal(finalTotal, discount, extraCharges, roundOffAmount),
          const SizedBox(height: 8),
          _buildDiscountField(),
          const SizedBox(height: 10),
          _buildExtraChargesField(),
          const SizedBox(height: 10),
          _buildTierSection(session),
          const SizedBox(height: 10),
          _buildPaymentSection(session, finalTotal, dueAmount),
          const SizedBox(height: 12),
          _buildCustomerSection(session),
          const SizedBox(height: 8),
          if (editingSale != null) _buildEditBanner(),
          _buildCompleteSaleButton(session),
          const SizedBox(height: 8),
          _buildHoldRetrieveButtons(),
          const SizedBox(height: 6),
          _buildShortcutsHint(),
        ],
      ),
    );
  }

  Widget _buildGrandTotal(
    double finalTotal,
    double discount,
    double extraCharges,
    double roundOffAmount,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Text(
            'GRAND TOTAL',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Rs${finalTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (discount > 0)
            Text(
              'Discount: -Rs${discount.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          if (extraCharges > 0)
            Text(
              'Extra Charges: +Rs${extraCharges.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          if (roundOffAmount != 0)
            Text(
              'Round Off: ${roundOffAmount > 0 ? '+' : ''}Rs${roundOffAmount.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscountField() {
    return Row(
      children: [
        const Icon(Icons.discount, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            label: 'Bill discount in rupees',
            child: TextField(
              controller: billDiscountController,
              focusNode: billDiscountFocusNode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Bill Discount (Rs)',
                prefixText: 'Rs ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onChanged: onDiscountChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExtraChargesField() {
    return Row(
      children: [
        const Icon(Icons.local_shipping, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            label: 'Extra charges in rupees',
            child: TextField(
              controller: extraChargesController,
              focusNode: extraChargesFocusNode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Extra Charges (Rs)',
                prefixText: 'Rs ',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onChanged: onExtraChargesChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTierSection(SaleSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pricing Tier',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _tierButton('Normal', 'normal', Colors.blue, session),
            const SizedBox(width: 4),
            _tierButton('Wholesale', 'wholesale', Colors.orange, session),
            const SizedBox(width: 4),
            _tierButton('Bulk', 'bulk', Colors.purple, session),
          ],
        ),
      ],
    );
  }

  Widget _tierButton(
    String label,
    String tier,
    Color color,
    SaleSession session,
  ) {
    final isSelected = selectedTier == tier;
    return Expanded(
      child: SizedBox(
        height: 32,
        child: Semantics(
          label: '$label pricing tier',
          button: true,
          selected: isSelected,
          child: Material(
            color: isSelected
                ? color.withValues(alpha: 0.15)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: session.items.isEmpty
                  ? null
                  : () => onTierChanged(tier),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? color : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isSelected ? color : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentSection(
    SaleSession session,
    double finalTotal,
    double dueAmount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        _paymentOption('CASH', Colors.green, Icons.money, 'cash', session),
        const SizedBox(height: 4),
        _paymentOption(
          'UPI',
          Colors.purple,
          Icons.phone_android,
          'upi',
          session,
        ),
        const SizedBox(height: 4),
        _paymentOption(
          'CREDIT',
          Colors.orange,
          Icons.person,
          'credit',
          session,
        ),
        const SizedBox(height: 4),
        _paymentOption(
          'SPLIT',
          Colors.teal,
          Icons.call_split,
          'split',
          session,
        ),
        if (selectedPayment == 'credit') _buildCreditOptions(dueAmount, finalTotal),
        if (selectedPayment == 'split') _buildSplitOptions(finalTotal),
      ],
    );
  }

  Widget _paymentOption(
    String label,
    Color color,
    IconData icon,
    String value,
    SaleSession session,
  ) {
    final isSelected = selectedPayment == value;
    return Semantics(
      label: '$label payment method',
      button: true,
      selected: isSelected,
      child: SizedBox(
        height: 40,
        child: Material(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: session.items.isEmpty
                ? null
                : () => onPaymentChanged(value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? color : Colors.grey.shade300,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isSelected ? color : Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  if (isSelected)
                    Icon(Icons.check_circle, size: 16, color: color),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreditOptions(double dueAmount, double finalTotal) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Full Credit', style: TextStyle(fontSize: 12)),
            Semantics(
              label: 'Full credit',
              child: Radio<bool>(
                value: true,
                groupValue: creditFull,
                onChanged: (v) => onCreditFullChanged(v!),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Partial', style: TextStyle(fontSize: 12)),
            Semantics(
              label: 'Partial credit',
              child: Radio<bool>(
                value: false,
                groupValue: creditFull,
                onChanged: (v) => onCreditFullChanged(v!),
              ),
            ),
          ],
        ),
        if (!creditFull) ...[
          Semantics(
            label: 'Paid amount',
            child: TextField(
              controller: paidController,
              focusNode: paidFocusNode,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Paid Amount',
                prefixText: 'Rs ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onPaidChanged,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [100, 200, 500, 1000, 2000].map((amt) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ActionChip(
                  label: Text('₹$amt', style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    paidController.text = amt.toString();
                    onPaidChanged(amt.toString());
                  },
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text(
            'Due: Rs${dueAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            'Due: Rs${finalTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSplitOptions(double finalTotal) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Split Payment — Total: Rs${finalTotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Split cash amount',
                child: TextField(
                  controller: splitCashController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cash Amount',
                    prefixText: 'Rs ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: onSplitCashChanged,
                ),
              ),
              const SizedBox(height: 6),
              Semantics(
                label: 'Split UPI amount',
                child: TextField(
                  controller: splitUpiController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'UPI Amount',
                    prefixText: 'Rs ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: onSplitUpiChanged,
                ),
              ),
              const SizedBox(height: 6),
              Builder(builder: (ctx) {
                final cash =
                    double.tryParse(splitCashController.text) ?? 0;
                final upi =
                    double.tryParse(splitUpiController.text) ?? 0;
                final sum = cash + upi;
                final remaining = finalTotal - sum;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (remaining > 0.5)
                      Text(
                        'Remaining: Rs${remaining.toStringAsFixed(0)} → Credit',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (remaining < -0.5)
                      Text(
                        'Excess: Rs${(-remaining).toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (remaining.abs() <= 0.5)
                      const Text(
                        'Full amount covered',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerSection(SaleSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Customer',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: 'Select customer',
          button: true,
          child: GestureDetector(
            onTap: onShowCustomerPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      session.customerName ?? 'WALK-IN CUSTOMER',
                      style: TextStyle(
                        fontSize: 12,
                        color: session.customerName != null
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Add new customer',
          button: true,
          child: TextButton.icon(
            onPressed: onAddNewCustomer,
            icon: const Icon(Icons.person_add, size: 16),
            label: const Text(
              'Add New Customer',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (session.customerId != null &&
            session.customerId!.isNotEmpty &&
            customerCredit > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Previous Due: Rs${customerCredit.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEditBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Editing sale Rs${editingSale.finalAmount.toStringAsFixed(0)} (${editingSale.items.length} items)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
          Semantics(
            label: 'Cancel editing sale',
            button: true,
            child: GestureDetector(
              onTap: () => onEditingSaleChanged(null),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteSaleButton(SaleSession session) {
    return Semantics(
      label: editingSale != null ? 'Update sale' : 'Complete sale',
      button: true,
      child: SizedBox(
        height: 44,
        child: ElevatedButton(
          onPressed: (session.items.isEmpty || isProcessing)
              ? null
              : onCompleteSale,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            editingSale != null
                ? 'UPDATE SALE (SHIFT+ENTER)'
                : 'COMPLETE SALE (SHIFT+ENTER)',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHoldRetrieveButtons() {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Hold bill',
            button: true,
            child: OutlinedButton(
              onPressed: session.items.isEmpty ? null : onHoldBill,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text(
                'Hold (F6)',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            label: 'Retrieve held bill',
            button: true,
            child: OutlinedButton(
              onPressed: onRetrieveBill,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              child: const Text(
                'Retrieve (F7)',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutsHint() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keyboard Shortcuts',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tab/Shift+Tab: Navigate fields',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'Esc: Back / Cancel / Clear',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'F2: Edit item  F4: Customer',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'F6: Hold  F7: Retrieve',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'F8: Cash  F9: UPI  F10: Credit',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'F11: Split  F5: Tier cycle',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
          Text(
            'Shift+Enter: Complete Sale',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
