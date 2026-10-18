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
    'Transport', 'Packaging', 'Maintenance',
    // owner, 18 Oct 2026
    'Food Expense', 'Personal Expense',
    'Other',
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
      _reloadHistory();
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
        content: Text('Delete ₹${expense.amount.toStringAsFixed(2)} ${expense.category} expense of ${DateFormat('dd MMM yyyy').format(expense.createdAt)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(expenseServiceProvider).deleteExpense(expense.id);
                ref.invalidate(expensesProvider);
                _reloadHistory();
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
            // History, with date and category filters (owner, 13 Oct 2026)
            _buildHistory(),
          ],
        ),
      ),
    );
  }

  // ── History filters ──
  static const _periods = {
    'today': 'Today',
    'yesterday': 'Yesterday',
    'week': 'This week',
    'month': 'This month',
    'last_month': 'Last month',
    'custom': 'Custom',
    'all': 'All',
  };
  String _period = 'month';
  DateTimeRange? _customRange;
  String? _filterCategory; // null = all categories
  Future<List<Expense>>? _historyFuture;

  /// [from, to) for the chosen period, in local (shop) time.
  (DateTime?, DateTime?) _periodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'today':
        return (today, today.add(const Duration(days: 1)));
      case 'yesterday':
        return (today.subtract(const Duration(days: 1)), today);
      case 'week':
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (monday, today.add(const Duration(days: 1)));
      case 'month':
        return (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case 'last_month':
        return (DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
      case 'custom':
        final r = _customRange;
        if (r == null) return (null, null);
        return (r.start, DateTime(r.end.year, r.end.month, r.end.day + 1));
      default:
        return (null, null);
    }
  }

  void _reloadHistory() {
    final (from, to) = _periodRange();
    setState(() {
      _historyFuture = ref.read(expenseServiceProvider).getExpensesFiltered(
            from: from,
            to: to,
            category: _filterCategory,
          );
    });
  }

  Future<void> _choosePeriod(String period) async {
    if (period == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: now,
        initialDateRange: _customRange ??
            DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
      );
      if (picked == null) return;
      _customRange = picked;
    }
    _period = period;
    _reloadHistory();
  }

  String _periodLabel() {
    if (_period == 'custom' && _customRange != null) {
      final f = DateFormat('dd MMM');
      return '${f.format(_customRange!.start)} – ${f.format(_customRange!.end)}';
    }
    return _periods[_period]!;
  }

  Widget _buildHistory() {
    _historyFuture ??= () {
      final (from, to) = _periodRange();
      return ref.read(expenseServiceProvider).getExpensesFiltered(from: from, to: to);
    }();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in _periods.entries)
                ChoiceChip(
                  label: Text(e.key == 'custom' && _period == 'custom' ? _periodLabel() : e.value),
                  selected: _period == e.key,
                  onSelected: (_) => _choosePeriod(e.key),
                ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String?>(
                  value: _filterCategory,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    ..._categories.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) {
                    _filterCategory = v;
                    _reloadHistory();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reloadHistory(),
            child: FutureBuilder<List<Expense>>(
              future: _historyFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(ErrorMessages.parse(snap.error!)));
                }
                final expenses = snap.data ?? const <Expense>[];
                final total = expenses.fold<double>(0, (s, e) => s + e.amount);
                final what = '${_periodLabel()}${_filterCategory != null ? ' · $_filterCategory' : ''}';
                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$what · ${expenses.length} expense${expenses.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: expenses.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 40),
                              EmptyState(
                                icon: Icons.money_off,
                                title: 'No expenses here',
                                subtitle: 'Try another period or category',
                              ),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              itemCount: expenses.length,
                              itemBuilder: (context, index) => _expenseTile(expenses[index]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _expenseTile(Expense expense) {
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
          '${(expense.description ?? '').trim().isEmpty ? 'No description' : expense.description!}'
          ' · ${PaymentMethods.label(expense.paymentMethod)}',
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
                  '₹${expense.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(expense.createdAt),
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
  }
}
