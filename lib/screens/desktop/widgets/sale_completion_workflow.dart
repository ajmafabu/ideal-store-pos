import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/sale.dart';
import '../../../models/product.dart';
import '../../../config/providers.dart';
import '../../../config/desktop_billing_provider.dart';
import '../../../utils/logger.dart';

class SaleCompletionResult {
  final bool success;
  final String? error;
  final Sale? sale;

  SaleCompletionResult({required this.success, this.error, this.sale});
}

class SaleCompletionWorkflow {
  final BuildContext context;
  final WidgetRef ref;

  SaleCompletionWorkflow(this.context, this.ref);

  Future<SaleCompletionResult> completeSale({
    required SaleSession session,
    required String selectedPayment,
    required String selectedTier,
    required bool creditFull,
    required double billDiscount,
    required double extraCharges,
    required TextEditingController paidController,
    required TextEditingController splitCashController,
    required TextEditingController splitUpiController,
    required TextEditingController extraChargesController,
    required List<Product> allProducts,
    Sale? editingSale,
  }) async {
    if (session.items.isEmpty) {
      return SaleCompletionResult(success: false, error: 'Cart is empty');
    }

    // Check connectivity
    final offlineService = ref.read(offlineServiceProvider);
    final isOnline = await offlineService.isOnline();
    if (!isOnline) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Internet Connection'),
          content: const Text(
            'You are offline. The sale will be saved locally and synced when you reconnect.\n\n'
            'Do you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('Save Offline'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return SaleCompletionResult(success: false, error: 'Cancelled');
      }
    }

    // Credit validation: customer required
    if (selectedPayment == 'credit' &&
        (session.customerId == null || session.customerId!.isEmpty)) {
      return SaleCompletionResult(success: false, error: 'Select a customer for credit sale');
    }

    final discount = billDiscount;
    final charges = extraCharges;
    final rawTotal = session.total - discount + charges;
    final roundedTotal = (rawTotal + 0.5).floorToDouble();
    final roundOffAmount = roundedTotal - rawTotal;
    final total = roundedTotal;
    final double paid = selectedPayment == 'credit'
        ? (creditFull ? 0 : double.tryParse(paidController.text) ?? 0)
        : total;
    final double credit = selectedPayment == 'credit' ? (total - paid) : 0;

    // Validate split payment
    double splitCash = 0;
    double splitUpi = 0;
    double splitCredit = 0;
    bool splitIsCredit = false;
    if (selectedPayment == 'split') {
      splitCash = double.tryParse(splitCashController.text) ?? 0;
      splitUpi = double.tryParse(splitUpiController.text) ?? 0;
      if (splitCash < 0 || splitUpi < 0) {
        return SaleCompletionResult(success: false, error: 'Split amounts cannot be negative');
      }
      final splitTotal = splitCash + splitUpi;
      if (splitTotal > total + 0.5) {
        return SaleCompletionResult(
          success: false,
          error: 'Split amounts (₹${splitCash.toStringAsFixed(0)} + ₹${splitUpi.toStringAsFixed(0)} = ₹${splitTotal.toStringAsFixed(0)}) exceed total ₹${total.toStringAsFixed(0)}',
        );
      }
      if ((total - splitTotal) > 0.5) {
        splitCredit = total - splitTotal;
        splitIsCredit = true;
        if (session.customerId == null || session.customerId!.isEmpty) {
          return SaleCompletionResult(
            success: false,
            error: 'Select a customer — remaining balance goes to credit',
          );
        }
      }
    }

    // Validate partial credit payment
    if (selectedPayment == 'credit' && !creditFull) {
      if (paid < 0 || paid >= total) {
        return SaleCompletionResult(
          success: false,
          error: 'Paid amount must be between 0 and total',
        );
      }
    }

    // Credit limit validation
    if (selectedPayment == 'credit' &&
        session.customerId != null &&
        session.customerId!.isNotEmpty) {
      try {
        final custRes = await Supabase.instance.client
            .from('customers')
            .select('total_credit, credit_limit')
            .eq('id', session.customerId!)
            .maybeSingle();
        if (custRes != null) {
          final currentCredit = (custRes['total_credit'] as num?)?.toDouble() ?? 0;
          final creditLimit = (custRes['credit_limit'] as num?)?.toDouble() ?? 0;
          final newTotalCredit = currentCredit + credit;
          if (creditLimit > 0 && newTotalCredit > creditLimit) {
            return SaleCompletionResult(
              success: false,
              error: 'Credit limit exceeded! Limit: ₹${creditLimit.toStringAsFixed(0)}, Current: ₹${currentCredit.toStringAsFixed(0)}, New total: ₹${newTotalCredit.toStringAsFixed(0)}',
            );
          }
        }
      } catch (e) {
        Logger.warning('Credit limit validation failed: $e');
      }
    }

    // Re-validate stock
    for (final item in session.items) {
      final product = allProducts.where((p) => p.id == item.productId).firstOrNull;
      if (product == null) {
        return SaleCompletionResult(
          success: false,
          error: '${item.name} no longer exists',
        );
      }
    }

    // Save sale
    return await _saveSale(
      session: session,
      paymentMethod: selectedPayment,
      amountPaid: splitIsCredit ? (splitCash + splitUpi) : paid,
      isCredit: splitIsCredit ? true : selectedPayment == 'credit',
      creditAmount: splitIsCredit ? splitCredit : credit,
      roundOffAmount: roundOffAmount,
      selectedTier: selectedTier,
      billDiscount: discount,
      extraCharges: charges,
      paidController: paidController,
      splitCashController: splitCashController,
      splitUpiController: splitUpiController,
      extraChargesController: extraChargesController,
      editingSale: editingSale,
    );
  }

  Future<SaleCompletionResult> _saveSale({
    required SaleSession session,
    required String paymentMethod,
    required double amountPaid,
    required bool isCredit,
    required double creditAmount,
    required double roundOffAmount,
    required String selectedTier,
    required double billDiscount,
    required double extraCharges,
    required TextEditingController paidController,
    required TextEditingController splitCashController,
    required TextEditingController splitUpiController,
    required TextEditingController extraChargesController,
    Sale? editingSale,
  }) async {
    try {
      final auth = ref.read(authServiceProvider);
      final user = auth.currentUser;
      final discount = billDiscount;
      final charges = extraCharges;
      final rawTotal = session.total - discount + charges;
      final roundedTotal = (rawTotal + 0.5).floorToDouble();
      final finalAmount = roundedTotal;

      double totalItemDiscount = 0;
      for (final item in session.items) {
        final itemTotal = item.price * item.qty;
        totalItemDiscount += itemTotal * (item.discount / 100);
      }

      double cashAmt = 0;
      double digitalAmt = 0;
      if (paymentMethod == 'split') {
        cashAmt = double.tryParse(splitCashController.text) ?? 0;
        digitalAmt = double.tryParse(splitUpiController.text) ?? 0;
      } else if (paymentMethod == 'cash') {
        cashAmt = amountPaid;
      } else if (!isCredit) {
        digitalAmt = amountPaid;
      }

      final sale = Sale(
        id: '',
        items: session.items
            .map(
              (item) => CartItem(
                productId: item.productId,
                name: item.name,
                price: item.price,
                qty: item.qty,
                unit: item.unit,
                purchasePrice: item.purchasePrice,
                gstRate: item.gstRate,
                hsnCode: item.hsnCode,
                tamilName: item.tamilName,
                discount: item.discount,
                tier: selectedTier,
              ),
            )
            .toList(),
        totalAmount: session.subtotal,
        totalDiscount: totalItemDiscount,
        discount: discount,
        finalAmount: finalAmount,
        roundOff: roundOffAmount,
        paymentMethod: paymentMethod,
        createdBy: user?.id ?? '',
        createdAt: DateTime.now(),
        customerId: session.customerId,
        isCredit: isCredit,
        amountPaid: amountPaid,
        dueAmount: creditAmount,
        cashAmount: cashAmt,
        digitalAmount: digitalAmt,
        extraCharges: extraCharges,
        dueDate: isCredit ? DateTime.now().add(const Duration(days: 30)) : null,
      );

      // If editing an existing sale, update it
      if (editingSale != null) {
        try {
          final reasonCtrl = TextEditingController();
          final reason = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Reason for Edit'),
              content: TextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (reasonCtrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, reasonCtrl.text.trim());
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
          if (reason == null || reason.isEmpty) {
            return SaleCompletionResult(success: false, error: 'Edit cancelled');
          }
          await ref
              .read(saleServiceProvider)
              .editSaleAtomic(
                saleId: editingSale.id,
                items: sale.items,
                totalAmount: sale.totalAmount,
                discount: sale.discount,
                finalAmount: sale.finalAmount,
                isCredit: sale.isCredit,
                amountPaid: sale.amountPaid,
                dueAmount: sale.dueAmount,
                paymentMethod: sale.paymentMethod,
                cashAmount: sale.cashAmount,
                digitalAmount: sale.digitalAmount,
                reason: reason,
              );
          return SaleCompletionResult(success: true, sale: sale);
        } catch (e) {
          Logger.error('Failed to edit sale: $e');
          return SaleCompletionResult(success: false, error: 'Failed to edit sale: $e');
        }
      }

      // Create new sale
      try {
        final created = await ref.read(saleServiceProvider).createSale(sale);
        return SaleCompletionResult(success: true, sale: created);
      } catch (e) {
        Logger.error('Failed to create sale: $e');
        return SaleCompletionResult(success: false, error: 'Failed to save sale: $e');
      }
    } catch (e) {
      Logger.error('Sale completion failed: $e');
      return SaleCompletionResult(success: false, error: 'Sale failed: $e');
    }
  }
}
