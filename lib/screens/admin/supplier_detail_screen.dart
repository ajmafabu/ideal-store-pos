import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/supplier.dart';
import '../../config/providers.dart';
import '../../services/statement_pdf_generator.dart';
import '../../utils/app_timezone.dart';

class SupplierDetailScreen extends ConsumerStatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  ConsumerState<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _purchases = [];
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
      final purchases = await ref.read(supplierServiceProvider).getPurchasesBySupplier(widget.supplier.id);
      final payments = await ref.read(supplierServiceProvider).getPaymentsBySupplier(widget.supplier.id);
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _payments = payments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> purchase) async {
    final dueAmount = (purchase['due_amount'] as num?)?.toDouble() ?? 0;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SupplierPaymentDialog(
        dueAmount: dueAmount,
        purchaseAmount: (purchase['total_amount'] as num?)?.toDouble() ?? 0,
        supplierId: widget.supplier.id,
        purchaseId: purchase['id'],
      ),
    );

    if (result == true) _loadData();
  }

  Future<void> _exportPdf() async {
    try {
      await StatementPdfGenerator.generateSupplierStatement(
        supplier: widget.supplier,
        purchases: _purchases,
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
        title: Text(widget.supplier.name),
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
            Tab(text: 'Credit Purchases'),
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
            color: widget.supplier.totalDues > 0 ? Colors.orange.shade50 : Colors.green.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.supplier.totalDues > 0 ? Icons.warning : Icons.check_circle,
                  color: widget.supplier.totalDues > 0 ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    const Text('Total Due to Supplier', style: TextStyle(fontSize: 12)),
                    Text(
                      'Rs ${widget.supplier.totalDues.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: widget.supplier.totalDues > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _purchases.isEmpty
                          ? const Center(child: Text('No credit purchases'))
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _purchases.length,
                                itemBuilder: (context, index) {
                                  final purchase = _purchases[index];
                                  final amount = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
                                  final paid = (purchase['amount_paid'] as num?)?.toDouble() ?? 0;
                                  final due = (purchase['due_amount'] as num?)?.toDouble() ?? 0;
                                  final date = DateTime.tryParse(purchase['created_at'] ?? '') ?? DateTime.now();

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
                                                  onPressed: () => _recordPayment(purchase),
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
                                                  color: due > 0 ? Colors.orange : Colors.green,
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

    for (final purchase in _purchases) {
      final date = DateTime.tryParse(purchase['created_at'] ?? '') ?? DateTime.now();
      final amount = (purchase['total_amount'] as num?)?.toDouble() ?? 0;
      final refNo = purchase['reference_number'] ?? (() { final s = purchase['id']?.toString() ?? ''; return s.length >= 8 ? s.substring(0, 8) : s; })() ?? '';
      allEntries.add(_FlowEntry(
        date: date,
        type: _FlowType.purchase,
        description: 'Purchase #$refNo',
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
      if (entry.type == _FlowType.purchase) {
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
          final isPurchase = entry.type == _FlowType.purchase;
          final color = isPurchase ? Colors.blue : Colors.green;
          final icon = isPurchase ? Icons.local_shipping : Icons.payment;
          final sign = isPurchase ? '+' : '-';

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

enum _FlowType { purchase, payment }

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

class _SupplierPaymentDialog extends StatefulWidget {
  final double dueAmount;
  final double purchaseAmount;
  final String supplierId;
  final String purchaseId;

  const _SupplierPaymentDialog({
    required this.dueAmount,
    required this.purchaseAmount,
    required this.supplierId,
    required this.purchaseId,
  });

  @override
  State<_SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends State<_SupplierPaymentDialog> {
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
          Text('Purchase Amount: Rs ${widget.purchaseAmount.toStringAsFixed(2)}'),
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
                await ref.read(supplierServiceProvider).recordPayment(
                  supplierId: widget.supplierId,
                  purchaseId: widget.purchaseId,
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
