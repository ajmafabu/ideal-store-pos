import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/providers.dart';
import '../../utils/app_timezone.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  DateTime _startDate = AppTimezone.nowIst().subtract(
    const Duration(days: 365),
  );
  DateTime _endDate = AppTimezone.nowIst();

  @override
  Widget build(BuildContext context) {
    final monthlyAsync = ref.watch(
      monthlySalesSummaryProvider(
        DateTimeRange(start: _startDate, end: _endDate),
      ),
    );
    final categoryAsync = ref.watch(
      categorySalesProvider(DateTimeRange(start: _startDate, end: _endDate)),
    );
    final dailyAsync = ref.watch(
      dailySalesTrendProvider(DateTimeRange(start: _startDate, end: _endDate)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final range = DateTimeRange(start: _startDate, end: _endDate);
              ref.invalidate(monthlySalesSummaryProvider(range));
              ref.invalidate(categorySalesProvider(range));
              ref.invalidate(dailySalesTrendProvider(range));
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final range = DateTimeRange(start: _startDate, end: _endDate);
          ref.invalidate(monthlySalesSummaryProvider(range));
          ref.invalidate(categorySalesProvider(range));
          ref.invalidate(dailySalesTrendProvider(range));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildDateRangeFilter(),
            const SizedBox(height: 16),
            _buildKeyMetrics(monthlyAsync, categoryAsync, dailyAsync),
            const SizedBox(height: 24),
            _buildSectionTitle('Monthly Trend (Last 12 Months)'),
            const SizedBox(height: 8),
            _buildMonthlyChart(monthlyAsync),
            const SizedBox(height: 24),
            _buildSectionTitle('Sales by Category'),
            const SizedBox(height: 8),
            _buildCategoryChart(categoryAsync),
            const SizedBox(height: 24),
            _buildSectionTitle('Daily Sales Trend (Last 30 Days)'),
            const SizedBox(height: 8),
            _buildDailyChart(dailyAsync),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, size: 20, color: Color(0xFF667eea)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      final range = DateTimeRange(start: _startDate, end: _endDate);
      ref.invalidate(monthlySalesSummaryProvider(range));
      ref.invalidate(categorySalesProvider(range));
      ref.invalidate(dailySalesTrendProvider(range));
    }
  }

  Widget _buildKeyMetrics(
    AsyncValue monthlyAsync,
    AsyncValue categoryAsync,
    AsyncValue dailyAsync,
  ) {
    return monthlyAsync.when(
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error loading metrics: $e'),
        ),
      ),
      data: (monthlyData) {
        double totalSales = 0;
        int totalOrders = 0;
        String topCategory = '-';

        for (final row in monthlyData) {
          totalSales += (row['total_sales'] as num?)?.toDouble() ?? 0;
        }

        categoryAsync.whenData((catData) {
          if (catData.isNotEmpty) {
            topCategory = catData.first['category'] as String? ?? '-';
          }
        });

        dailyAsync.whenData((dailyData) {
          for (final row in dailyData) {
            totalOrders += (row['order_count'] as num?)?.toInt() ?? 0;
          }
        });

        final avgOrderValue = totalOrders > 0 ? totalSales / totalOrders : 0.0;

        return Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Total Revenue',
                value: 'Rs${totalSales.toStringAsFixed(0)}',
                color: const Color(0xFF11998e),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Total Orders',
                value: '$totalOrders',
                color: const Color(0xFF667eea),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Avg Order',
                value: 'Rs${avgOrderValue.toStringAsFixed(0)}',
                color: const Color(0xFF8E2DE2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricCard(
                title: 'Top Category',
                value: topCategory,
                color: const Color(0xFFeb3349),
                isText: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthlyChart(AsyncValue<List<Map<String, dynamic>>> asyncData) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncData.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              SizedBox(height: 200, child: Center(child: Text('Error: $e'))),
          data: (data) {
            if (data.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('No data available')),
              );
            }

            final salesSpots = <BarChartGroupData>[];
            final expenseSpots = <BarChartGroupData>[];
            final profitSpots = <BarChartGroupData>[];

            for (int i = 0; i < data.length; i++) {
              final sales = (data[i]['total_sales'] as num?)?.toDouble() ?? 0;
              final expenses =
                  (data[i]['total_expenses'] as num?)?.toDouble() ?? 0;
              final profit = (data[i]['profit'] as num?)?.toDouble() ?? 0;

              salesSpots.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: sales,
                      color: const Color(0xFF11998e),
                      width: 12,
                    ),
                  ],
                ),
              );
              expenseSpots.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: expenses,
                      color: const Color(0xFFeb3349),
                      width: 12,
                    ),
                  ],
                ),
              );
              profitSpots.add(
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: profit,
                      color: const Color(0xFF667eea),
                      width: 12,
                    ),
                  ],
                ),
              );
            }

            final maxY = data.fold<double>(0, (max, row) {
              final s = (row['total_sales'] as num?)?.toDouble() ?? 0;
              final e = (row['total_expenses'] as num?)?.toDouble() ?? 0;
              return s > max ? s : (e > max ? e : max);
            });

            return Column(
              children: [
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY * 1.2,
                      barGroups: _mergeBarGroups(
                        salesSpots,
                        expenseSpots,
                        profitSpots,
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < data.length) {
                                final month =
                                    data[idx]['month'] as String? ?? '';
                                final parts = month.split(' ');
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    parts.isNotEmpty ? parts[0] : '',
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              if (value >= 1000) {
                                return Text(
                                  'Rs${(value / 1000).toStringAsFixed(0)}k',
                                  style: const TextStyle(fontSize: 10),
                                );
                              }
                              return Text(
                                'Rs${value.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withValues(alpha: 0.15),
                          strokeWidth: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LegendItem(color: const Color(0xFF11998e), label: 'Sales'),
                    const SizedBox(width: 16),
                    _LegendItem(
                      color: const Color(0xFFeb3349),
                      label: 'Expenses',
                    ),
                    const SizedBox(width: 16),
                    _LegendItem(
                      color: const Color(0xFF667eea),
                      label: 'Profit',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<BarChartGroupData> _mergeBarGroups(
    List<BarChartGroupData> sales,
    List<BarChartGroupData> expenses,
    List<BarChartGroupData> profit,
  ) {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < sales.length; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            if (i < sales.length) sales[i].barRods.first,
            if (i < expenses.length) expenses[i].barRods.first,
            if (i < profit.length) profit[i].barRods.first,
          ],
        ),
      );
    }
    return groups;
  }

  Widget _buildCategoryChart(AsyncValue<List<Map<String, dynamic>>> asyncData) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncData.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              SizedBox(height: 200, child: Center(child: Text('Error: $e'))),
          data: (data) {
            if (data.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('No category data available')),
              );
            }

            final colors = [
              const Color(0xFF667eea),
              const Color(0xFF11998e),
              const Color(0xFFeb3349),
              const Color(0xFF8E2DE2),
              const Color(0xFFFF9800),
              const Color(0xFF2196F3),
              const Color(0xFF4CAF50),
              const Color(0xFFE91E63),
              const Color(0xFF795548),
              const Color(0xFF607D8B),
            ];

            final totalRevenue = data.fold<double>(
              0,
              (sum, row) =>
                  sum + ((row['total_revenue'] as num?)?.toDouble() ?? 0),
            );

            return Column(
              children: [
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: data.asMap().entries.map((entry) {
                        final revenue =
                            (entry.value['total_revenue'] as num?)
                                ?.toDouble() ??
                            0;
                        final pct = totalRevenue > 0
                            ? (revenue / totalRevenue) * 100
                            : 0;
                        return PieChartSectionData(
                          value: revenue,
                          title: '${pct.toStringAsFixed(0)}%',
                          color: colors[entry.key % colors.length],
                          radius: 60,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: data.asMap().entries.map((entry) {
                    final category =
                        entry.value['category'] as String? ?? 'Unknown';
                    final revenue =
                        (entry.value['total_revenue'] as num?)?.toDouble() ?? 0;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colors[entry.key % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$category (Rs${revenue.toStringAsFixed(0)})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDailyChart(AsyncValue<List<Map<String, dynamic>>> asyncData) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncData.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) =>
              SizedBox(height: 200, child: Center(child: Text('Error: $e'))),
          data: (data) {
            if (data.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('No daily data available')),
              );
            }

            final spots = <FlSpot>[];
            final labels = <int, String>{};
            for (int i = 0; i < data.length; i++) {
              final sales = (data[i]['total_sales'] as num?)?.toDouble() ?? 0;
              spots.add(FlSpot(i.toDouble(), sales));
              if (i % 5 == 0 || i == data.length - 1) {
                final day = data[i]['day'] as String? ?? '';
                labels[i] = day.length >= 10 ? day.substring(5, 10) : day;
              }
            }

            final maxY = spots.fold<double>(
              0,
              (max, spot) => spot.y > max ? spot.y : max,
            );

            return Column(
              children: [
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      maxY: maxY * 1.2,
                      minY: 0,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: const Color(0xFF667eea),
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: const Color(
                              0xFF667eea,
                            ).withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (labels.containsKey(idx)) {
                                return SideTitleWidget(
                                  meta: meta,
                                  child: Text(
                                    labels[idx]!,
                                    style: const TextStyle(fontSize: 9),
                                  ),
                                );
                              }
                              return const SizedBox();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              if (value >= 1000) {
                                return Text(
                                  'Rs${(value / 1000).toStringAsFixed(0)}k',
                                  style: const TextStyle(fontSize: 10),
                                );
                              }
                              return Text(
                                'Rs${value.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.withValues(alpha: 0.15),
                          strokeWidth: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final bool isText;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
    this.isText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isText ? 11 : 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
