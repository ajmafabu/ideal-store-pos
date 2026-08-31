import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';

class CustomerPortalScreen extends ConsumerWidget {
  final String customerId;

  const CustomerPortalScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(_customerPortalProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
      ),
      body: customerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (customer) {
          if (customer == null) {
            return const Center(child: Text('Customer not found'));
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(_customerPortalProvider(customerId).future),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _HeaderCard(customer: customer),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent Transactions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  child: _TransactionList(customerId: customerId),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Customer customer;

  const _HeaderCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final isDue = customer.totalCredit > 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDue
              ? [Colors.orange.shade600, Colors.orange.shade800]
              : [Colors.green.shade600, Colors.green.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isDue ? Colors.orange : Colors.green).withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    if (customer.phone?.isNotEmpty ?? false)
                      Text(customer.phone!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isDue ? 'Amount Due' : 'Credit Balance', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Rs${customer.totalCredit.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (isDue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Tap to Pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  final String customerId;

  const _TransactionList({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(_customerSalesProvider(customerId));

    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (sales) {
        if (sales.isEmpty) {
          return const Center(child: Text('No transactions yet'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: sales.length,
          itemBuilder: (context, index) {
            final sale = sales[index];
            final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
            final date = DateTime.tryParse(sale['created_at'] ?? '') ?? DateTime.now();
            final isCredit = sale['is_credit'] as bool? ?? false;
            final due = (sale['due_amount'] as num?)?.toDouble() ?? 0;

            return _buildTransactionTile(context, amount, date, isCredit, due);
          },
        );
      },
    );
  }

  Widget _buildTransactionTile(BuildContext context, double amount, DateTime date, bool isCredit, double due) {
    final List<Widget> subtitleChildren = [];
    subtitleChildren.add(Text(DateFormat('dd MMM yyyy, hh:mm a').format(date)));
    if (isCredit && due > 0) {
      subtitleChildren.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Due: Rs${due.toStringAsFixed(2)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCredit ? Colors.orange.shade100 : Colors.green.shade100,
          child: Icon(isCredit ? Icons.credit_card : Icons.payment, color: isCredit ? Colors.orange : Colors.green),
        ),
        title: Text('Rs${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: subtitleChildren,
        ),
        trailing: Chip(
          label: Text(isCredit ? 'Credit' : 'Paid'),
          backgroundColor: isCredit ? Colors.orange.shade100 : Colors.green.shade100,
          labelStyle: TextStyle(
            color: isCredit ? Colors.orange : Colors.green,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

final _customerPortalProvider = FutureProvider.family<Customer?, String>((ref, customerId) async {
  try {
    final response = await Supabase.instance.client
        .from('customers')
        .select()
        .eq('id', customerId)
        .maybeSingle();
    if (response != null) return Customer.fromJson(response);
    return null;
  } catch (e) {
    return null;
  }
});

final _customerSalesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, customerId) async {
  try {
    final response = await Supabase.instance.client
        .from('sales')
        .select('id, final_amount, is_credit, amount_paid, due_amount, created_at')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(20);
    return (response as List).cast<Map<String, dynamic>>();
  } catch (e) {
    return [];
  }
});