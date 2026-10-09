import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/expense.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../utils/error_messages.dart';
import '../../utils/payment_methods.dart';
import '../../widgets/empty_state.dart';

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  // no silent default: every expense was "Rent" unless changed (QA #39)
  String? _selectedCategory;
  String? _amountError;
  String? _categoryError;
  DateTime _selectedDate = DateTime.now();
  String _paymentMethod = PaymentMethods.cash; // which account pays (#12)

  static const _categories = [
    'Rent', 'Salary', 'Electricity', 'Water', 'Internet',
    'Transport', 'Packaging', 'Maintenance', 'Other',
  ];

  Future<void> _addExpense() async {
    final amount = double.tryParse(_amountController.text.trim());
    final category = _selectedCategory;
    // shown on the fields themselves: the message used to hide under the keyboard
    setState(() {
      _amountError = amount == null || amount <= 0 ? 'Enter an amount above ₹0' : null;
      _categoryError = category == null ? 'Choose a category' : null;
    });
    if (amount == null || amount <= 0 || category == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: $category'),
            Text('Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}'),
            Text('Amount: ₹${amount.toStringAsFixed(2)}'),
            Text('Paid from: ${PaymentMethods.label(_paymentMethod)}'),
            if (_descriptionController.text.isNotEmpty)
              Text('Note: ${_descriptionController.text}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final auth = ref.read(authServiceProvider);
      final user = auth.currentUser;

      final expense = Expense(
        id: '',
        category: category,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        amount: amount,
        createdBy: user?.id ?? '',
        createdAt: _selectedDate,
        paymentMethod: _paymentMethod,
      );

      // the database books it out of cash or bank by the payment method
      await ref.read(expenseServiceProvider).createExpense(expense, paymentMethod: _paymentMethod);

      ref.invalidate(expensesProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(todayTransactionsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added')),
        );
        _amountController.clear();
        _descriptionController.clear();
        setState(() => _selectedDate = DateTime.now());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ErrorMessages.parse(e))));
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Expense expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense'),
        content: Text('Delete Rs${expense.amount.toStringAsFixed(0)} ${expense.category} expense?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(expenseServiceProvider).deleteExpense(expense.id);
                ref.invalidate(expensesProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Expense deleted'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ErrorMessages.parse(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Expenses'),
          bottom: const TabBar(tabs: [Tab(text: 'Add Expense'), Tab(text: 'History')]),
        ),
        body: TabBarView(
          children: [
            // Add Expense
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      errorText: _categoryError,
                    ),
                    hint: const Text('Choose'),
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedCategory = v;
                      _categoryError = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('dd MMM yyyy').format(_selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: const OutlineInputBorder(),
                      prefixText: '₹ ',
                      errorText: _amountError,
                    ),
                    onChanged: (_) {
                      if (_amountError != null) setState(() => _amountError = null);
                    },
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
                      ButtonSegment(value: 'upi', label: Text('UPI'), icon: Icon(Icons.qr_code)),
                      ButtonSegment(value: 'bank', label: Text('Bank'), icon: Icon(Icons.account_balance)),
                    ],
                    selected: {_paymentMethod},
                    onSelectionChanged: (v) => setState(() => _paymentMethod = v.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _addExpense,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Add Expense', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
            // History
            RefreshIndicator(
              onRefresh: () async => ref.invalidate(expensesProvider),
              child: expensesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(ErrorMessages.parse(e))),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return const EmptyState(
                    icon: Icons.money_off,
                    title: 'No Expenses',
                    subtitle: 'Track expenses to manage your finances',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: expenses.length,
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.expenseGradient.colors.first.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.money_off, color: Color(0xFFeb3349)),
                        ),
                        title: Text(
                          expense.category,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          (expense.description ?? '').trim().isEmpty ? 'No description' : expense.description!,
                        ),
                        // Delete was hidden behind tapping the amount (QA #85)
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Rs${expense.amount.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                              ),
                              Text(
                                DateFormat('dd MMM').format(expense.createdAt),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF757575)),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Delete expense',
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
                            onPressed: () => _confirmDelete(context, ref, expense),
                          ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            ),
          ],
        ),
      ),
    );
  }
}
