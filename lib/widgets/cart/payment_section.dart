import 'package:flutter/material.dart';

class PaymentSection extends StatelessWidget {
  final TextEditingController discountController;
  final TextEditingController amountPaidController;
  final String paymentMethod;
  final bool isCredit;
  final double dueAmount;
  final ValueChanged<String> onPaymentMethodChanged;
  final VoidCallback onCreditToggled;
  final VoidCallback onChanged;
  final bool isSplitPayment;
  final double total;
  final TextEditingController cashAmountController;
  final TextEditingController upiAmountController;
  final ValueChanged<bool> onSplitPaymentToggled;

  const PaymentSection({
    super.key,
    required this.discountController,
    required this.amountPaidController,
    required this.paymentMethod,
    required this.isCredit,
    required this.dueAmount,
    required this.onPaymentMethodChanged,
    required this.onCreditToggled,
    required this.onChanged,
    this.isSplitPayment = false,
    this.total = 0,
    required this.cashAmountController,
    required this.upiAmountController,
    required this.onSplitPaymentToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Discount
        Row(
          children: [
            const Text('Discount: Rs '),
            SizedBox(
              width: 100,
              child: TextField(
                controller: discountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Payment Method + Credit Toggle
        Row(
          children: [
            const Text('Payment:'),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Cash'),
              selected: !isCredit && paymentMethod == 'cash',
              onSelected: (_) => onPaymentMethodChanged('cash'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Digital'),
              selected: !isCredit && paymentMethod == 'digital',
              onSelected: (_) => onPaymentMethodChanged('digital'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Credit'),
              selected: isCredit,
              onSelected: (_) => onCreditToggled(),
              backgroundColor: Colors.orange.shade100,
              selectedColor: Colors.orange,
            ),
          ],
        ),

        // Quick Cash Buttons (only for cash payment and not credit)
        if (!isCredit && paymentMethod == 'cash') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _quickCashBtn(50),
              _quickCashBtn(100),
              _quickCashBtn(200),
              _quickCashBtn(500),
              _quickCashBtn(1000),
            ],
          ),
        ],

        // Credit Details
        if (isCredit) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Amount Paid: Rs '),
              Expanded(
                child: TextField(
                  controller: amountPaidController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '0 for full credit',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Due: '),
              Text(
                'Rs ${dueAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: dueAmount > 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],

        // Split Payment Toggle (only when not credit)
        if (!isCredit) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Split Payment'),
              const SizedBox(width: 8),
              Switch(
                value: isSplitPayment,
                onChanged: onSplitPaymentToggled,
                activeThumbColor: Colors.green,
              ),
            ],
          ),

          // Split Payment Fields
          if (isSplitPayment) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Cash: Rs '),
                Expanded(
                  child: TextField(
                    controller: cashAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '0.00',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          cashAmountController.clear();
                          upiAmountController.text = total.toStringAsFixed(2);
                          onChanged();
                        },
                      ),
                    ),
                    onChanged: (val) {
                      final cash = double.tryParse(val) ?? 0;
                      final remaining = total - cash;
                      upiAmountController.text = remaining >= 0 ? remaining.toStringAsFixed(2) : '0';
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('UPI:   Rs '),
                Expanded(
                  child: TextField(
                    controller: upiAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '0.00',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          upiAmountController.clear();
                          cashAmountController.text = total.toStringAsFixed(2);
                          onChanged();
                        },
                      ),
                    ),
                    onChanged: (val) {
                      final upi = double.tryParse(val) ?? 0;
                      final remaining = total - upi;
                      cashAmountController.text = remaining >= 0 ? remaining.toStringAsFixed(2) : '0';
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (ctx) {
                final cash = double.tryParse(cashAmountController.text) ?? 0;
                final upi = double.tryParse(upiAmountController.text) ?? 0;
                final sum = cash + upi;
                final isValid = (sum - total).abs() < 0.01;
                return Row(
                  children: [
                    Text(
                      'Total: Rs${sum.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: isValid ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!isValid) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${sum > total ? "Over by" : "Under by"} Rs${(sum - total).abs().toStringAsFixed(2)})',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ],
      ],
    );
  }

  Widget _quickCashBtn(int amount) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              amountPaidController.text = amount.toStringAsFixed(2);
              onChanged();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: Text(
                'Rs$amount',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
