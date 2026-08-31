import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';
import '../../config/providers.dart';
import '../../services/statement_pdf_generator.dart';
import '../../utils/app_timezone.dart';

class DebtDetailScreen extends ConsumerStatefulWidget {
  final Customer customer;

  const DebtDetailScreen({super.key, required this.customer});

  @override
  ConsumerState<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends ConsumerState<DebtDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final sales = await ref.read(customerServiceProvider).getSalesByCustomer(widget.customer.id);
      final payments = await ref.read(customerServiceProvider).getPaymentsByCustomer(widget.customer.id);
      if (mounted) {
        setState(() {
          _sales = sales;
          _payments = payments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> sale) async {
    final dueAmount = (sale['due_amount'] as num?)?.toDouble() ?? 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PaymentDialog(
        dueAmount: dueAmount,
        saleAmount: (sale['final_amount'] as num?)?.toDouble() ?? 0,
        customerId: widget.customer.id,
        saleId: sale['id'],
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _markAllPaid() async {
    final totalDue = widget.customer.totalCredit;
    if (totalDue <= 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All Paid'),
        content: Text('Record Rs ${totalDue.toStringAsFixed(2)} payment for all dues?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Pay each credit sale that has due > 0
      for (final sale in _sales) {
        final due = (sale['due_amount'] as num?)?.toDouble() ?? 0;
        if (due > 0) {
          await ref.read(customerServiceProvider).recordPayment(
            customerId: widget.customer.id,
            saleId: sale['id'],
            amount: due,
            paymentMethod: 'cash',
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All dues marked as paid'), backgroundColor: Colors.green),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportPdf() async {
    try {
      await StatementPdfGenerator.generateCustomerStatement(
        customer: widget.customer,
        sales: _sales,
        payments: _payments,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _exportPdf,
            tooltip: 'Export Statement PDF',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Credit Sales'),
            Tab(text: 'Payment History'),
            Tab(text: 'Money Flow'),
          ],
        ),
      ),
      body: Column(
        children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: widget.customer.totalCredit > 0 ? Colors.orange.shade50 : Colors.green.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.customer.totalCredit > 0 ? Icons.warning : Icons.check_circle,
                    color: widget.customer.totalCredit > 0 ? Colors.orange : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      const Text('Total Due', style: TextStyle(fontSize: 12)),
                      Text(
                        'Rs ${widget.customer.totalCredit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: widget.customer.totalCredit > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  if (widget.customer.totalCredit > 0) ...[
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _markAllPaid,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Mark All Paid'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _sales.isEmpty
                          ? const Center(child: Text('No credit sales'))
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _sales.length,
                                itemBuilder: (context, index) {
                                  final sale = _sales[index];
                                  final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
                                  final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
                                  final due = (sale['due_amount'] as num?)?.toDouble() ?? 0;
                                  final date = DateTime.tryParse(sale['created_at'] ?? '') ?? DateTime.now();

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                DateFormat('dd MMM yyyy, hh:mm a').format(date),
                                                style: const TextStyle(color: Colors.grey),
                                              ),
                                              if (due > 0)
                                                ElevatedButton(
                                                  onPressed: () => _recordPayment(sale),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green,
                                                    foregroundColor: Colors.white,
                                                  ),
                                                  child: const Text('Pay'),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Total:'),
                                              Text('Rs ${amount.toStringAsFixed(2)}'),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Paid:'),
                                              Text('Rs ${paid.toStringAsFixed(2)}'),
                                            ],
                                          ),
                                          const Divider(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Due:', style: TextStyle(fontWeight: FontWeight.bold)),
                                              Text(
                                                'Rs ${due.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color: due > 0 ? Colors.red : Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                      _payments.isEmpty
                          ? const Center(child: Text('No payments recorded'))
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _payments.length,
                                itemBuilder: (context, index) {
                                  final payment = _payments[index];
                                  final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
                                  final date = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();
                                  final method = payment['payment_method'] ?? 'cash';
                                  final notes = payment['notes'] as String?;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.green,
                                        child: const Icon(Icons.check, color: Colors.white),
                                      ),
                                      title: Text(
                                        'Rs ${amount.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(DateFormat('dd MMM yyyy, hh:mm a').format(date)),
                                          Text('Method: $method'),
                                          if (notes != null && notes.isNotEmpty)
                                            Text('Notes: $notes'),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                      _buildMoneyFlowTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoneyFlowTab() {
    final allEntries = <_FlowEntry>[];

    for (final sale in _sales) {
      final date = DateTime.tryParse(sale['created_at'] ?? '') ?? DateTime.now();
      final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
      final saleId = sale['invoice_number'] ?? (() { final s = sale['id']?.toString() ?? ''; return s.length >= 8 ? s.substring(0, 8) : s; })() ?? '';
      allEntries.add(_FlowEntry(
        date: date,
        type: _FlowType.sale,
        description: 'Sale #$saleId',
        amount: amount,
      ));
    }

    for (final payment in _payments) {
      final date = DateTime.tryParse(payment['created_at'] ?? '') ?? DateTime.now();
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
      final method = payment['payment_method'] ?? 'cash';
      allEntries.add(_FlowEntry(
        date: date,
        type: _FlowType.payment,
        description: 'Payment ($method)',
        amount: amount,
      ));
    }

    allEntries.sort((a, b) => b.date.compareTo(a.date));

    if (allEntries.isEmpty) {
      return const Center(child: Text('No transactions'));
    }

    double runningBalance = 0;
    for (final entry in allEntries.reversed) {
      if (entry.type == _FlowType.sale) {
        runningBalance += entry.amount;
      } else {
        runningBalance -= entry.amount;
      }
      entry.runningBalance = runningBalance;
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allEntries.length,
        itemBuilder: (context, index) {
          final entry = allEntries[index];
          final isSale = entry.type == _FlowType.sale;
          final color = isSale ? Colors.orange : Colors.green;
          final icon = isSale ? Icons.shopping_cart : Icons.payment;
          final sign = isSale ? '+' : '-';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(icon, color: color, size: 20),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(entry.description, style: const TextStyle(fontSize: 14)),
                  ),
                  Text(
                    '$sign Rs ${entry.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              subtitle: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(entry.date),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    'Bal: Rs ${entry.runningBalance.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: entry.runningBalance > 0 ? Colors.orange : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _FlowType { sale, payment }

class _FlowEntry {
  final DateTime date;
  final _FlowType type;
  final String description;
  final double amount;
  double runningBalance;

  _FlowEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    this.runningBalance = 0,
  });
}

class _PaymentDialog extends StatefulWidget {
  final double dueAmount;
  final double saleAmount;
  final String customerId;
  final String saleId;

  const _PaymentDialog({
    required this.dueAmount,
    required this.saleAmount,
    required this.customerId,
    required this.saleId,
  });

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late TextEditingController _amountController;
  String _selectedMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: widget.dueAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sale Amount: Rs ${widget.saleAmount.toStringAsFixed(2)}'),
          Text('Due: Rs ${widget.dueAmount.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Payment Amount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Method:'),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Cash'),
                selected: _selectedMethod == 'cash',
                onSelected: (_) => setState(() => _selectedMethod = 'cash'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('UPI'),
                selected: _selectedMethod == 'upi',
                onSelected: (_) => setState(() => _selectedMethod = 'upi'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Bank'),
                selected: _selectedMethod == 'bank',
                onSelected: (_) => setState(() => _selectedMethod = 'bank'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final amount = double.tryParse(_amountController.text) ?? 0;
            if (amount > 0 && amount <= widget.dueAmount) {
              try {
                final ref = ProviderScope.containerOf(context);
                await ref.read(customerServiceProvider).recordPayment(
                  customerId: widget.customerId,
                  saleId: widget.saleId,
                  amount: amount,
                  paymentMethod: _selectedMethod,
                );
                ref.invalidate(accountsProvider);
                ref.invalidate(todayTransactionsProvider);
                Navigator.pop(context, true);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            }
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
