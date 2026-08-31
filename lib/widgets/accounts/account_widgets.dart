import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../utils/app_timezone.dart';

// ============================================
// BALANCE CARD
// ============================================

class BalanceCard extends StatelessWidget {
  final String title;
  final double balance;
  final IconData icon;
  final Gradient gradient;

  const BalanceCard({
    super.key,
    required this.title,
    required this.balance,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 24),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Rs${balance.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ============================================
// MINI STAT
// ============================================

class MiniStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const MiniStat({super.key, required this.label, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          'Rs${amount.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

// ============================================
// FILTER CHIP
// ============================================

class AccountFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const AccountFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF667eea) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? const Color(0xFF667eea) : Colors.grey.shade300),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// TRANSACTION TILE
// ============================================

class TransactionTile extends StatelessWidget {
  final AccountTransaction transaction;

  const TransactionTile({super.key, required this.transaction});

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'sale': return 'Sale';
      case 'purchase': return 'Purchase';
      case 'expense': return 'Expense';
      case 'credit_collection': return 'Credit Collection';
      case 'credit_payment': return 'Credit Payment';
      case 'transfer': return 'Transfer';
      case 'return_refund': return 'Return Refund';
      case 'opening': return 'Opening Balance';
      case 'sale_reversal': return 'Sale Reversal';
      case 'purchase_reversal': return 'Purchase Reversal';
      case 'expense_reversal': return 'Expense Reversal';
      default: return 'Other';
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'sale': return Icons.shopping_bag;
      case 'purchase': return Icons.local_shipping;
      case 'expense': return Icons.receipt;
      case 'credit_collection': return Icons.person_add;
      case 'credit_payment': return Icons.person_remove;
      case 'transfer': return Icons.swap_horiz;
      case 'return_refund': return Icons.undo;
      case 'opening': return Icons.account_balance_wallet;
      case 'sale_reversal': return Icons.shopping_bag;
      case 'purchase_reversal': return Icons.local_shipping;
      case 'expense_reversal': return Icons.receipt;
      default: return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIn = transaction.type == 'in';
    final color = isIn ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_getCategoryIcon(transaction.category), color: color, size: 20),
        ),
        title: Text(
          _getCategoryLabel(transaction.category),
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          transaction.description ?? '',
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isIn ? '+' : '-'}Rs${transaction.amount.toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
            ),
            Text(
               AppTimezone.formatDateTime(transaction.createdAt),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// TRANSACTIONS LIST
// ============================================

class TransactionsList extends ConsumerWidget {
  final DateTime? filterStart;
  final DateTime? filterEnd;
  final String searchQuery;

  const TransactionsList({super.key, this.filterStart, this.filterEnd, required this.searchQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountService = ref.watch(accountServiceProvider);

    return FutureBuilder<List<AccountTransaction>>(
      future: accountService.getTransactions(
        startDate: filterStart,
        endDate: filterEnd,
        searchQuery: searchQuery.isNotEmpty ? searchQuery : null,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }
        final transactions = snapshot.data ?? [];
        if (transactions.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No transactions found', style: TextStyle(color: Colors.grey)),
              ),
            ),
          );
        }
        return Column(
          children: transactions.map((t) => TransactionTile(transaction: t)).toList(),
        );
      },
    );
  }
}
