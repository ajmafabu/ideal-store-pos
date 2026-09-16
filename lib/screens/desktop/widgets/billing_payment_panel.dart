import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/sale.dart';
import '../../../config/providers.dart';
import '../../../config/desktop_billing_provider.dart';
import '../../../utils/logger.dart';

class BillingPaymentPanel extends ConsumerWidget {
  final SaleSession session;
  final double total;
  final double billDiscount;
  final double extraCharges;
  final double customerCredit;
  final String selectedPayment;
  final String selectedTier;
  final bool creditFull;
  final bool isProcessing;
  final Sale? editingSale;
  final List<Map<String, dynamic>> heldBills;
  final TextEditingController billDiscountController;
  final TextEditingController extraChargesController;
  final TextEditingController paidController;
  final TextEditingController splitCashController;
  final TextEditingController splitUpiController;
  final FocusNode billDiscountFocusNode;
  final FocusNode extraChargesFocusNode;
  final FocusNode paidFocusNode;
  final VoidCallback onShowCustomerPicker;
  final VoidCallback onAddNewCustomer;
  final VoidCallback onCompleteSale;
  final VoidCallback onHoldBill;
  final VoidCallback onRetrieveBill;
  final void Function(String tier) onTierChanged;
  final void Function(String payment) onPaymentChanged;
  final void Function(bool full) onCreditFullChanged;
  final void Function(String value) onBillDiscountChanged;
  final void Function(String value) onExtraChargesChanged;
  final VoidCallback onEditCancelled;
  final StateSetter parentSetState;

  const BillingPaymentPanel({
    super.key,
    required this.session,
    required this.total,
    required this.billDiscount,
    required this.extraCharges,
    required this.customerCredit,
    required this.selectedPayment,
    required this.selectedTier,
    required this.creditFull,
    required this.isProcessing,
    this.editingSale,
    required this.heldBills,
    required this.billDiscountController,
    required this.extraChargesController,
    required this.paidController,
    required this.splitCashController,
    required this.splitUpiController,
    required this.billDiscountFocusNode,
    required this.extraChargesFocusNode,
    required this.paidFocusNode,
    required this.onShowCustomerPicker,
    required this.onAddNewCustomer,
    required this.onCompleteSale,
    required this.onHoldBill,
    required this.onRetrieveBill,
    required this.onTierChanged,
    required this.onPaymentChanged,
    required this.onCreditFullChanged,
    required this.onBillDiscountChanged,
    required this.onExtraChargesChanged,
    required this.onEditCancelled,
    required this.parentSetState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawTotal = (total - billDiscount + extraCharges).clamp(
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGrandTotal(finalTotal, discount: billDiscount, extraCharges: extraCharges, roundOffAmount: roundOffAmount),
          const SizedBox(height: 14),
          _buildPricingTier(session),
          const SizedBox(height: 14),
          _buildPaymentMethod(session),
          if (selectedPayment == 'credit') ...[
            const SizedBox(height: 10),
            _buildCreditOptions(finalTotal, dueAmount),
          ],
          if (selectedPayment == 'split') ...[
            const SizedBox(height: 10),
            _buildSplitPayment(finalTotal),
          ],
          const SizedBox(height: 14),
          _buildCustomerSection(session),
          const SizedBox(height: 10),
          _buildDiscountAndCharges(),
          const SizedBox(height: 14),
          if (editingSale != null) _buildEditBanner(),
          _buildCompleteButton(session),
          const SizedBox(height: 8),
          _buildHoldRetrieveButtons(session),
        ],
      ),
    );
  }

  Widget _buildGrandTotal(double finalTotal, {required double discount, required double extraCharges, required double roundOffAmount}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF059669),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Text(
            'GRAND TOTAL',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${finalTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (discount > 0)
            Text(
              'Discount: -₹${discount.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          if (extraCharges > 0)
            Text(
              'Extra Charges: +₹${extraCharges.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          if (roundOffAmount != 0)
            Text(
              'Round Off: ${roundOffAmount > 0 ? '+' : ''}₹${roundOffAmount.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildPricingTier(SaleSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRICING TIER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _tierButton('Normal', 'normal', const Color(0xFF2563EB), session),
            const SizedBox(width: 4),
            _tierButton('Wholesale', 'wholesale', const Color(0xFFF97316), session),
            const SizedBox(width: 4),
            _tierButton('Bulk', 'bulk', const Color(0xFF8B5CF6), session),
          ],
        ),
      ],
    );
  }

  Widget _tierButton(String label, String tier, Color color, SaleSession session) {
    final isSelected = selectedTier == tier;
    return Expanded(
      child: SizedBox(
        height: 34,
        child: Material(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: session.items.isEmpty
                ? null
                : () => onTierChanged(tier),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFE2E8F0),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethod(SaleSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAYMENT METHOD',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        _paymentOption('CASH', const Color(0xFF059669), Icons.money, 'cash', session),
        const SizedBox(height: 4),
        _paymentOption('UPI', const Color(0xFF8B5CF6), Icons.phone_android, 'upi', session),
        const SizedBox(height: 4),
        _paymentOption('CREDIT', const Color(0xFFF97316), Icons.person, 'credit', session),
        const SizedBox(height: 4),
        _paymentOption('SPLIT', const Color(0xFF0891B2), Icons.call_split, 'split', session),
      ],
    );
  }

  Widget _paymentOption(String label, Color color, IconData icon, String value, SaleSession session) {
    final isSelected = selectedPayment == value;
    return SizedBox(
      height: 40,
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
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
                color: isSelected ? color : const Color(0xFFE2E8F0),
                width: isSelected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? color : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isSelected ? color : const Color(0xFF64748B),
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
    );
  }

  Widget _buildCreditOptions(double finalTotal, double dueAmount) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Full Credit', style: TextStyle(fontSize: 12)),
              Radio<bool>(
                value: true,
                groupValue: creditFull,
                onChanged: (v) => onCreditFullChanged(v!),
              ),
              const SizedBox(width: 8),
              const Text('Partial', style: TextStyle(fontSize: 12)),
              Radio<bool>(
                value: false,
                groupValue: creditFull,
                onChanged: (v) => onCreditFullChanged(v!),
              ),
            ],
          ),
          if (!creditFull) ...[
            TextField(
              controller: paidController,
              focusNode: paidFocusNode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Paid Amount',
                prefixText: '₹ ',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                isDense: true,
              ),
              onChanged: (_) => parentSetState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [100, 200, 500, 1000, 2000].map((amt) {
                return ActionChip(
                  label: Text('₹$amt', style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    paidController.text = amt.toString();
                    parentSetState(() {});
                  },
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              'Due: ₹${dueAmount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF97316),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Due: ₹${finalTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF97316),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSplitPayment(double finalTotal) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFECFEFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA5F3FC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Split Payment — Total: ₹${finalTotal.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0891B2),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: splitCashController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Cash Amount',
              prefixText: '₹ ',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              isDense: true,
            ),
            onChanged: (_) => parentSetState(() {}),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: splitUpiController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'UPI Amount',
              prefixText: '₹ ',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              isDense: true,
            ),
            onChanged: (_) => parentSetState(() {}),
          ),
          const SizedBox(height: 6),
          Builder(builder: (ctx) {
            final cash = double.tryParse(splitCashController.text) ?? 0;
            final upi = double.tryParse(splitUpiController.text) ?? 0;
            final sum = cash + upi;
            final remaining = finalTotal - sum;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (remaining > 0.5)
                  Text(
                    'Remaining: ₹${remaining.toStringAsFixed(0)} → Credit',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFF97316),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (remaining < -0.5)
                  Text(
                    'Excess: ₹${(-remaining).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (remaining.abs() <= 0.5)
                  const Text(
                    'Full amount covered',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCustomerSection(SaleSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CUSTOMER',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onShowCustomerPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: session.customerName != null
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    session.customerName ?? 'Walk-in Customer',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: session.customerName != null
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onAddNewCustomer,
          icon: const Icon(Icons.person_add, size: 16, color: Color(0xFF2563EB)),
          label: const Text(
            '+ Add New Customer',
            style: TextStyle(fontSize: 12, color: Color(0xFF2563EB)),
          ),
        ),
        if (session.customerId != null &&
            session.customerId!.isNotEmpty &&
            customerCredit > 0) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text(
                  'Previous Due: ₹${customerCredit.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF97316),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDiscountAndCharges() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.discount, size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: billDiscountController,
                focusNode: billDiscountFocusNode,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Bill Discount',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF2563EB)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: onBillDiscountChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.local_shipping, size: 14, color: Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: extraChargesController,
                focusNode: extraChargesFocusNode,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Extra Charges',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF2563EB)),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: onExtraChargesChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEditBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFF97316)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 16, color: Color(0xFFF97316)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Editing sale ₹${editingSale!.finalAmount.toStringAsFixed(0)} (${editingSale!.items.length} items)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF97316),
              ),
            ),
          ),
          GestureDetector(
            onTap: onEditCancelled,
            child: const Text(
              'CANCEL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteButton(SaleSession session) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: (session.items.isEmpty || isProcessing)
            ? null
            : onCompleteSale,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCBD5E1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check, size: 18),
                const SizedBox(width: 8),
                Text(
                  editingSale != null ? 'UPDATE SALE' : 'COMPLETE SALE',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            Text(
              'SHIFT+ENTER',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoldRetrieveButtons(SaleSession session) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: session.items.isEmpty ? null : onHoldBill,
            icon: const Icon(Icons.pause, size: 14),
            label: const Text('F6 Hold Sale', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              foregroundColor: const Color(0xFF64748B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: heldBills.isEmpty ? null : onRetrieveBill,
            icon: const Icon(Icons.play_arrow, size: 14),
            label: Text(
              'F7 Retrieve${heldBills.isNotEmpty ? ' (${heldBills.length})' : ''}',
              style: const TextStyle(fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 10),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              foregroundColor: const Color(0xFF64748B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
