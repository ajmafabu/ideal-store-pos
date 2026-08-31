import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/providers.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';

// ============================================
// TRANSFER SHEET
// ============================================

class TransferSheet extends ConsumerStatefulWidget {
  final List<Account> accounts;

  const TransferSheet({super.key, required this.accounts});

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  String _fromAccount = 'cash';
  String _toAccount = 'bank';
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Transfer Between Accounts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            const Text('From', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _AccountChoice(
                  label: 'Cash', icon: Icons.money,
                  selected: _fromAccount == 'cash',
                  onTap: () => setState(() {
                    _fromAccount = 'cash';
                    if (_toAccount == 'cash') _toAccount = 'bank';
                  }),
                )),
                const SizedBox(width: 8),
                Expanded(child: _AccountChoice(
                  label: 'Bank', icon: Icons.account_balance,
                  selected: _fromAccount == 'bank',
                  onTap: () => setState(() {
                    _fromAccount = 'bank';
                    if (_toAccount == 'bank') _toAccount = 'cash';
                  }),
                )),
              ],
            ),
            const SizedBox(height: 16),

            const Center(child: Icon(Icons.arrow_downward, color: Color(0xFF667eea), size: 28)),
            const SizedBox(height: 16),

            const Text('To', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _AccountChoice(
                  label: 'Cash', icon: Icons.money,
                  selected: _toAccount == 'cash',
                  onTap: () => setState(() {
                    _toAccount = 'cash';
                    if (_fromAccount == 'cash') _fromAccount = 'bank';
                  }),
                )),
                const SizedBox(width: 8),
                Expanded(child: _AccountChoice(
                  label: 'Bank', icon: Icons.account_balance,
                  selected: _toAccount == 'bank',
                  onTap: () => setState(() {
                    _toAccount = 'bank';
                    if (_fromAccount == 'bank') _fromAccount = 'cash';
                  }),
                )),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (Rs)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _transfer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667eea),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _transfer() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid amount')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final service = AccountService();
      final fromAcc = widget.accounts.firstWhere((a) => a.accountType == _fromAccount);
      final toAcc = widget.accounts.firstWhere((a) => a.accountType == _toAccount);

      await service.transferBetweenAccounts(
        fromAccountId: fromAcc.id,
        toAccountId: toAcc.id,
        amount: amount,
        description: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accountsProvider);
        ref.invalidate(todayTransactionsProvider);
        ref.invalidate(monthlySummaryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer completed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ============================================
// ADD ENTRY SHEET
// ============================================

class AddEntrySheet extends ConsumerStatefulWidget {
  const AddEntrySheet({super.key});

  @override
  ConsumerState<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<AddEntrySheet> {
  String _selectedAccount = 'cash';
  String _selectedType = 'in';
  String _selectedCategory = 'sale';
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _loading = false;

  final _categories = {
    'in': ['sale', 'credit_collection', 'opening', 'other'],
    'out': ['purchase', 'expense', 'credit_payment', 'other'],
  };

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Entry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _AccountChoice(
                  label: 'Cash', icon: Icons.money,
                  selected: _selectedAccount == 'cash',
                  onTap: () => setState(() => _selectedAccount = 'cash'),
                )),
                const SizedBox(width: 8),
                Expanded(child: _AccountChoice(
                  label: 'Bank/UPI', icon: Icons.account_balance,
                  selected: _selectedAccount == 'bank',
                  onTap: () => setState(() => _selectedAccount = 'bank'),
                )),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _AccountChoice(
                  label: 'Money In', icon: Icons.arrow_downward,
                  selected: _selectedType == 'in',
                  onTap: () => setState(() {
                    _selectedType = 'in';
                    _selectedCategory = _categories['in']!.first;
                  }),
                )),
                const SizedBox(width: 8),
                Expanded(child: _AccountChoice(
                  label: 'Money Out', icon: Icons.arrow_upward,
                  selected: _selectedType == 'out',
                  onTap: () => setState(() {
                    _selectedType = 'out';
                    _selectedCategory = _categories['out']!.first;
                  }),
                )),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _categories[_selectedType]!.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(_label(cat)));
              }).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v!),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (Rs)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF667eea),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _label(String cat) {
    switch (cat) {
      case 'sale': return 'Sale';
      case 'purchase': return 'Purchase';
      case 'expense': return 'Expense';
      case 'credit_collection': return 'Credit Collection';
      case 'credit_payment': return 'Credit Payment';
      case 'opening': return 'Opening Balance';
      default: return 'Other';
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid amount')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final service = AccountService();
      final accounts = await service.getAccounts();
      final account = accounts.firstWhere(
        (a) => a.accountType == _selectedAccount,
        orElse: () => accounts.first,
      );

      await service.addTransaction(
        accountId: account.id,
        type: _selectedType,
        amount: amount,
        category: _selectedCategory,
        description: _noteController.text.isNotEmpty ? _noteController.text : null,
      );

      if (mounted) {
        Navigator.pop(context);
        ref.invalidate(accountsProvider);
        ref.invalidate(todayTransactionsProvider);
        ref.invalidate(monthlySummaryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry added'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ============================================
// ACCOUNT CHOICE (shared)
// ============================================

class _AccountChoice extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AccountChoice({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF667eea).withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF667eea) : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? const Color(0xFF667eea) : Colors.grey),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? const Color(0xFF667eea) : Colors.grey,
            )),
          ],
        ),
      ),
    );
  }
}
