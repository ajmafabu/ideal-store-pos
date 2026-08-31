import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../utils/app_timezone.dart';

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime _selectedDate = AppTimezone.nowIst();
  bool _loading = false;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).toUtc();
      final end = start.add(const Duration(days: 1));
      final startStr = start.toIso8601String();
      final endStr = end.toIso8601String();

      // Fetch all data in parallel
      final results = await Future.wait([
        Supabase.instance.client.from('sales').select('final_amount, payment_method, is_credit, amount_paid, items').gte('created_at', startStr).lt('created_at', endStr),
        Supabase.instance.client.from('purchases').select('total_amount').gte('created_at', startStr).lt('created_at', endStr),
        Supabase.instance.client.from('expenses').select('amount').gte('created_at', startStr).lt('created_at', endStr),
      ]);

      final sales = results[0] as List;
      final purchases = results[1] as List;
      final expenses = results[2] as List;

      double totalSales = 0;
      double cashSales = 0;
      double digitalSales = 0;
      double creditSales = 0;
      double cashCollected = 0;
      int totalItems = 0;

      for (final sale in sales) {
        final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
        final method = (sale['payment_method'] as String? ?? 'cash').toLowerCase();
        final isCredit = sale['is_credit'] as bool? ?? false;
        final paid = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
        final items = sale['items'] as List? ?? [];

        totalSales += amount;
        totalItems += items.fold<int>(0, (sum, item) => sum + ((item['qty'] as int?) ?? 0));

        if (isCredit) {
          creditSales += amount;
        } else if (method == 'cash') {
          cashSales += amount;
        } else {
          digitalSales += amount;
        }

        if (paid > 0) cashCollected += paid;
      }

      double totalPurchases = 0;
      for (final p in purchases) {
        totalPurchases += (p['total_amount'] as num?)?.toDouble() ?? 0;
      }

      double totalExpenses = 0;
      for (final e in expenses) {
        totalExpenses += (e['amount'] as num?)?.toDouble() ?? 0;
      }

      setState(() {
        _report = {
          'total_sales': totalSales,
          'cash_sales': cashSales,
          'digital_sales': digitalSales,
          'credit_sales': creditSales,
          'cash_collected': cashCollected,
          'total_purchases': totalPurchases,
          'total_expenses': totalExpenses,
          'total_transactions': sales.length,
          'total_items_sold': totalItems,
        };
      });
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadReport();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Report (Z-Report)'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDate),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: theme.colorScheme.primary),
                            const SizedBox(width: 12),
                            Text(DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (_report == null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Text('No transactions on this day', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      _SummaryCard(
                        title: 'Total Sales',
                        value: 'Rs${(_report!['total_sales'] as double).toStringAsFixed(0)}',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(height: 12),
                      Text('Payment Breakdown', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _MiniCard(label: 'Cash', value: 'Rs${(_report!['cash_sales'] as double).toStringAsFixed(0)}', color: const Color(0xFF10B981))),
                          const SizedBox(width: 8),
                          Expanded(child: _MiniCard(label: 'Digital', value: 'Rs${(_report!['digital_sales'] as double).toStringAsFixed(0)}', color: const Color(0xFF6366F1))),
                          const SizedBox(width: 8),
                          Expanded(child: _MiniCard(label: 'Credit', value: 'Rs${(_report!['credit_sales'] as double).toStringAsFixed(0)}', color: const Color(0xFFF59E0B))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _StatRow(label: 'Total Purchases', value: 'Rs${(_report!['total_purchases'] as double).toStringAsFixed(0)}'),
                      _StatRow(label: 'Total Expenses', value: 'Rs${(_report!['total_expenses'] as double).toStringAsFixed(0)}'),
                      _StatRow(label: 'Cash Collected', value: 'Rs${(_report!['cash_collected'] as double).toStringAsFixed(0)}'),
                      _StatRow(label: 'Total Transactions', value: '${_report!['total_transactions']}'),
                      _StatRow(label: 'Items Sold', value: '${_report!['total_items_sold']}'),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Net Cash', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text(
                              'Rs${((_report!['cash_sales'] as double) - (_report!['total_expenses'] as double)).toStringAsFixed(0)}',
                              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
