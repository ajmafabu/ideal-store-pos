import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../utils/app_timezone.dart';
import 'account_widgets.dart';

// ============================================
// MONTHLY SUMMARY CARD
// ============================================

class MonthlySummaryCard extends StatelessWidget {
  final Map<String, double> summary;

  const MonthlySummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final totalIn = summary['total_in'] ?? 0;
    final totalOut = summary['total_out'] ?? 0;
    final net = summary['net'] ?? 0;
    final now = AppTimezone.nowIst();
    final monthName = DateFormat('MMMM yyyy').format(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month, size: 18, color: Color(0xFF667eea)),
                const SizedBox(width: 8),
                Text('$monthName Summary', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: MiniStat(label: 'Money In', amount: totalIn, color: Colors.green, icon: Icons.arrow_downward)),
                const SizedBox(width: 8),
                Expanded(child: MiniStat(label: 'Money Out', amount: totalOut, color: Colors.red, icon: Icons.arrow_upward)),
                const SizedBox(width: 8),
                Expanded(child: MiniStat(label: 'Net', amount: net, color: net >= 0 ? Colors.green : Colors.red, icon: net >= 0 ? Icons.trending_up : Icons.trending_down)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// TODAY SUMMARY INLINE
// ============================================

class TodaySummaryInline extends ConsumerWidget {
  const TodaySummaryInline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(todayTransactionsProvider);

    return transactionsAsync.when(
      loading: () => const SizedBox(),
      error: (e, _) => const SizedBox(),
      data: (transactions) {
        double totalIn = 0, totalOut = 0;
        for (final t in transactions) {
          if (t.type == 'in') {
            totalIn += t.amount;
          } else {
            totalOut += t.amount;
          }
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Today\'s Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: MiniStat(label: 'Money In', amount: totalIn, color: Colors.green, icon: Icons.arrow_downward)),
                    const SizedBox(width: 8),
                    Expanded(child: MiniStat(label: 'Money Out', amount: totalOut, color: Colors.red, icon: Icons.arrow_upward)),
                    const SizedBox(width: 8),
                    Expanded(child: MiniStat(label: 'Net', amount: totalIn - totalOut, color: totalIn >= totalOut ? Colors.green : Colors.red, icon: totalIn >= totalOut ? Icons.trending_up : Icons.trending_down)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// CATEGORY BREAKDOWN
// ============================================

class CategoryBreakdown extends ConsumerWidget {
  final DateTime? filterStart;
  final DateTime? filterEnd;

  const CategoryBreakdown({super.key, this.filterStart, this.filterEnd});

  static String catLabel(String cat) {
    switch (cat) {
      case 'sale': return 'Sales';
      case 'purchase': return 'Purchases';
      case 'expense': return 'Expenses';
      case 'credit_collection': return 'Credit In';
      case 'credit_payment': return 'Credit Out';
      case 'transfer': return 'Transfer';
      case 'return_refund': return 'Returns';
      case 'opening': return 'Opening';
      case 'sale_reversal': return 'Sale Reversal';
      case 'purchase_reversal': return 'Purchase Reversal';
      case 'expense_reversal': return 'Expense Reversal';
      default: return 'Other';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<AccountTransaction>>(
      future: AccountService().getTransactions(
        startDate: filterStart,
        endDate: filterEnd,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
          return const SizedBox();
        }
        final transactions = snapshot.data!;

        final Map<String, double> breakdown = {};
        for (final t in transactions) {
          final key = '${catLabel(t.category)} (${t.type == 'in' ? 'In' : 'Out'})';
          breakdown[key] = (breakdown[key] ?? 0) + t.amount;
        }

        if (breakdown.isEmpty) return const SizedBox();

        final colors = [
          Colors.blue, Colors.green, Colors.orange, Colors.purple,
          Colors.teal, Colors.pink, Colors.indigo, Colors.amber,
        ];

        final sections = breakdown.entries.toList().asMap().entries.map((entry) {
          final index = entry.key;
          final e = entry.value;
          final total = breakdown.values.fold(0.0, (a, b) => a + b);
          final pct = total > 0 ? (e.value / total * 100) : 0.0;
          return PieChartSectionData(
            value: e.value,
            title: '${pct.toStringAsFixed(0)}%',
            color: colors[index % colors.length],
            radius: 50,
            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          );
        }).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filterStart != null ? 'Period Breakdown' : 'Today\'s Breakdown', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 160,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: PieChart(PieChartData(
                          sections: sections,
                          centerSpaceRadius: 24,
                          sectionsSpace: 2,
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: breakdown.entries.toList().asMap().entries.map((entry) {
                            final idx = entry.key;
                            final e = entry.value;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[idx % colors.length], borderRadius: BorderRadius.circular(3))),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                                  Text('Rs${e.value.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
