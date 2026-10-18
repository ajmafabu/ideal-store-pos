import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import 'cart_item_tile.dart' show rupees, rupees2;

enum PayMode { cash, upi, split, credit }

/// How the bill is paid, as confirmed in [CheckoutSheet].
class Checkout {
  Checkout({required this.mode, this.splitCash = 0, this.splitUpi = 0, this.creditPaid = 0, this.customer});
  final PayMode mode;
  final double splitCash;
  final double splitUpi;

  /// Paid at the counter on a credit bill.
  final double creditPaid;
  final Customer? customer;
}

/// Charge: the last look before the bill is saved (17 Oct 2026). One sheet
/// for every way of paying, replacing the old "Confirm?" box:
///  * Cash — what the customer gave and the change to give back;
///  * UPI — the amount to receive;
///  * Split — cash + UPI, which must add up to the total;
///  * Credit — the customer, what they pay now, and what they will owe.
class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({
    super.key,
    required this.total,
    required this.itemCount,
    required this.mode,
    required this.customer,
    required this.pickCustomer,
  });

  final double total;
  final int itemCount;
  final PayMode mode;
  final Customer? customer;

  /// Opens the customer list (a credit bill needs one).
  final Future<Customer?> Function() pickCustomer;

  static Future<Checkout?> show(
    BuildContext context, {
    required double total,
    required int itemCount,
    required PayMode mode,
    required Customer? customer,
    required Future<Customer?> Function() pickCustomer,
  }) {
    return showModalBottomSheet<Checkout>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CheckoutSheet(
        total: total,
        itemCount: itemCount,
        mode: mode,
        customer: customer,
        pickCustomer: pickCustomer,
      ),
    );
  }

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  late PayMode _mode = widget.mode;
  late Customer? _customer = widget.customer;
  final _given = TextEditingController();
  late final _cash = TextEditingController(text: _plain(widget.total));
  final _upi = TextEditingController(text: '0');
  final _paidNow = TextEditingController();
  String? _error;

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  static double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  double get _total => widget.total;

  @override
  void dispose() {
    _given.dispose();
    _cash.dispose();
    _upi.dispose();
    _paidNow.dispose();
    super.dispose();
  }

  /// Notes a customer is likely to hand over: the exact amount, then the
  /// next round 10, 50, 100, 500 and 2000.
  List<double> get _quickNotes {
    final out = <double>{_total};
    for (final step in const [10, 50, 100, 500, 2000]) {
      final up = (_total / step).ceil() * step.toDouble();
      if (up > _total) out.add(up);
    }
    return out.toList()..sort();
  }

  void _complete() {
    setState(() => _error = null);
    switch (_mode) {
      case PayMode.cash:
        final given = _num(_given);
        if (given > 0 && given + 0.004 < _total) {
          setState(() => _error = 'Customer gave less than the total');
          return;
        }
        Navigator.pop(context, Checkout(mode: PayMode.cash, customer: _customer));
      case PayMode.upi:
        Navigator.pop(context, Checkout(mode: PayMode.upi, customer: _customer));
      case PayMode.split:
        final cash = _num(_cash), upi = _num(_upi);
        if ((cash + upi - _total).abs() > 0.01) {
          setState(() => _error = 'Cash + UPI must be ${rupees2(_total)}');
          return;
        }
        if (cash <= 0 || upi <= 0) {
          setState(() => _error = 'Split needs both cash and UPI');
          return;
        }
        Navigator.pop(context, Checkout(mode: PayMode.split, splitCash: cash, splitUpi: upi, customer: _customer));
      case PayMode.credit:
        if (_customer == null) {
          setState(() => _error = 'Choose the customer for a credit bill');
          return;
        }
        final paid = _num(_paidNow);
        if (paid + 0.004 >= _total) {
          setState(() => _error = 'That pays the whole bill: choose Cash or UPI');
          return;
        }
        Navigator.pop(context, Checkout(mode: PayMode.credit, creditPaid: paid, customer: _customer));
    }
  }

  Future<void> _chooseCustomer() async {
    final c = await widget.pickCustomer();
    if (c != null && mounted) setState(() => _customer = c);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.itemCount} item${widget.itemCount == 1 ? '' : 's'}',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                Text(rupees2(_total), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<PayMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PayMode.cash, label: Text('Cash')),
                ButtonSegment(value: PayMode.upi, label: Text('UPI')),
                ButtonSegment(value: PayMode.split, label: Text('Split')),
                ButtonSegment(value: PayMode.credit, label: Text('Credit')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            ..._details(scheme),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _complete,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: _mode == PayMode.credit ? Colors.orange.shade800 : Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                _mode == PayMode.credit ? 'Save credit bill' : 'Complete ${rupees2(_total)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details(ColorScheme scheme) {
    switch (_mode) {
      case PayMode.cash:
        final given = _num(_given);
        final back = given - _total;
        return [
          Text('Customer gave (optional)', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in _quickNotes)
                ChoiceChip(
                  label: Text(n == _total ? 'Exact' : rupees(n), style: const TextStyle(fontSize: 15)),
                  selected: (given - n).abs() < 0.005,
                  onSelected: (_) => setState(() => _given.text = _plain(n)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _moneyField(_given, 'Amount given'),
          if (given > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                back >= -0.004 ? 'Give back ${rupees2(back < 0 ? 0 : back)}' : 'Short by ${rupees2(-back)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: back >= -0.004 ? Colors.green.shade700 : scheme.error,
                ),
              ),
            ),
        ];
      case PayMode.upi:
        return [
          Row(
            children: [
              Icon(Icons.qr_code_2, size: 40, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Check that ${rupees2(_total)} is received on UPI before completing.',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ];
      case PayMode.split:
        return [
          Row(
            children: [
              Expanded(
                child: _moneyField(_cash, 'Cash', onChanged: (v) {
                  final rest = _total - (double.tryParse(v) ?? 0);
                  _upi.text = _plain(rest < 0 ? 0 : rest);
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _moneyField(_upi, 'UPI', onChanged: (v) {
                  final rest = _total - (double.tryParse(v) ?? 0);
                  _cash.text = _plain(rest < 0 ? 0 : rest);
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type one; the other fills itself.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ];
      case PayMode.credit:
        final paid = _num(_paidNow);
        final due = (_total - paid).clamp(0, double.infinity).toDouble();
        final owedBefore = _customer?.totalCredit ?? 0;
        return [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(_customer?.name ?? 'Choose customer'),
            subtitle: _customer == null
                ? const Text('A credit bill needs a customer')
                : Text(owedBefore > 0.004 ? 'Owes ${rupees2(owedBefore)} now' : 'Owes nothing now'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _chooseCustomer,
          ),
          const SizedBox(height: 6),
          _moneyField(_paidNow, 'Paid now (0 if nothing)'),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('This bill adds', style: TextStyle(color: scheme.onSurfaceVariant)),
              const Spacer(),
              Text(rupees2(due), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.error)),
            ],
          ),
          if (_customer != null)
            Row(
              children: [
                Text('They will owe', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Text(rupees2(owedBefore + due), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
        ];
    }
  }

  Widget _moneyField(TextEditingController c, String label, {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      style: const TextStyle(fontSize: 18),
      decoration: InputDecoration(labelText: label, prefixText: '₹ ', border: const OutlineInputBorder()),
      onChanged: (v) {
        onChanged?.call(v);
        setState(() => _error = null);
      },
    );
  }
}
