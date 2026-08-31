import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../utils/app_timezone.dart';
import '../../services/return_service.dart';
import '../../services/damaged_service.dart';
import '../../services/customer_service.dart';
import '../../config/providers.dart';

class ReportData {
  final double totalSales;
  final double totalPurchases;
  final double totalExpenses;
  final double netProfit;
  final List<Map<String, dynamic>> salesByDay;
  final List<Map<String, dynamic>> topProducts;
  final Map<String, double> salesByCategory;
  final Map<String, double> expensesByCategory;
  final Map<String, double> paymentBreakdown;
  final double prevMonthSales;
  final double prevMonthExpenses;
  final double prevMonthProfit;

  double get profitMargin =>
      totalSales > 0 ? (netProfit / totalSales * 100) : 0;
  double get grossProfit => totalSales - totalPurchases;
  double get grossMargin =>
      totalSales > 0 ? (grossProfit / totalSales * 100) : 0;

  ReportData({
    required this.totalSales,
    required this.totalPurchases,
    required this.totalExpenses,
    required this.netProfit,
    required this.salesByDay,
    required this.topProducts,
    required this.salesByCategory,
    required this.expensesByCategory,
    required this.paymentBreakdown,
    this.prevMonthSales = 0,
    this.prevMonthExpenses = 0,
    this.prevMonthProfit = 0,
  });
}

class DateRange {
  final DateTime start;
  final DateTime end;
  final String label;
  const DateRange(this.start, this.end, {this.label = 'Custom'});
}

class DateRangeNotifier extends Notifier<DateRange> {
  @override
  DateRange build() {
    final now = AppTimezone.nowIst();
    return DateRange(
      DateTime(now.year, now.month, 1),
      now,
      label: 'This Month',
    );
  }

  void update(DateTime start, DateTime end, {String label = 'Custom'}) {
    state = DateRange(start, end, label: label);
  }

  void setToday() {
    final now = AppTimezone.nowIst();
    state = DateRange(
      DateTime(now.year, now.month, now.day),
      now,
      label: 'Today',
    );
  }

  void setThisWeek() {
    final now = AppTimezone.nowIst();
    final start = now.subtract(Duration(days: now.weekday - 1));
    state = DateRange(
      DateTime(start.year, start.month, start.day),
      now,
      label: 'This Week',
    );
  }

  void setThisMonth() {
    final now = AppTimezone.nowIst();
    state = DateRange(
      DateTime(now.year, now.month, 1),
      now,
      label: 'This Month',
    );
  }

  void setLastMonth() {
    final now = AppTimezone.nowIst();
    final start = DateTime(now.year, now.month - 1, 1);
    final end = DateTime(now.year, now.month, 0);
    state = DateRange(start, end, label: 'Last Month');
  }
}

final dateRangeProvider = NotifierProvider<DateRangeNotifier, DateRange>(
  DateRangeNotifier.new,
);

final reportDataProvider = FutureProvider<ReportData>((ref) async {
  final range = ref.watch(dateRangeProvider);
  final client = Supabase.instance.client;
  final endExclusive = range.end.add(const Duration(days: 1));

  // Current period data
  final salesResponse = await client
      .from('sales')
      .select()
      .gte('created_at', range.start.toUtc().toIso8601String())
      .lt('created_at', endExclusive.toUtc().toIso8601String());

  double totalSales = 0;
  double totalPurchaseCost = 0;
  Map<String, double> productSales = {};
  Map<String, double> dailySales = {};
  Map<String, double> categorySales = {};
  Map<String, double> paymentBreakdown = {'cash': 0, 'digital': 0};

  for (final sale in salesResponse as List) {
    final amount = (sale['final_amount'] as num?)?.toDouble() ?? 0;
    totalSales += amount;

    final payment = sale['payment_method'] as String? ?? 'cash';
    paymentBreakdown[payment] = (paymentBreakdown[payment] ?? 0) + amount;

    final createdAt = sale['created_at'] as String?;
    if (createdAt != null) {
      final date = DateFormat(
        'dd MMM',
      ).format(DateTime.parse(createdAt).toLocal());
      dailySales[date] = (dailySales[date] ?? 0) + amount;
    }

    final items = sale['items'] as List? ?? [];
    for (final item in items) {
      final name = item['name'] as String? ?? 'Unknown';
      final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
      final purchasePrice = (item['purchase_price'] as num?)?.toDouble() ?? 0;
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      totalPurchaseCost += purchasePrice * qty;
      productSales[name] = (productSales[name] ?? 0) + itemTotal;
    }
  }

  // Get category data from products
  final productsRes = await client
      .from('products')
      .select('id, name, category');
  Map<String, String> productCategory = {};
  for (final p in productsRes as List) {
    productCategory[p['id'] as String] = p['category'] as String? ?? 'Other';
  }

  for (final sale in salesResponse as List) {
    final items = sale['items'] as List? ?? [];
    for (final item in items) {
      final productId = item['product_id'] as String?;
      final cat = productCategory[productId] ?? 'Other';
      final itemTotal = (item['total'] as num?)?.toDouble() ?? 0;
      categorySales[cat] = (categorySales[cat] ?? 0) + itemTotal;
    }
  }

  // Purchases - calculated from sale items (selling price - purchase price)
  double totalPurchases = totalPurchaseCost;

  // Expenses
  final expensesResponse = await client
      .from('expenses')
      .select('amount, category')
      .gte('created_at', range.start.toUtc().toIso8601String())
      .lt('created_at', endExclusive.toUtc().toIso8601String());

  double totalExpenses = 0;
  Map<String, double> expensesByCategory = {};
  for (final e in expensesResponse as List) {
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    totalExpenses += amount;
    final cat = e['category'] as String? ?? 'Other';
    expensesByCategory[cat] = (expensesByCategory[cat] ?? 0) + amount;
  }

  // Previous month comparison
  final prevStart = DateTime(range.start.year, range.start.month - 1, 1);
  final prevEnd = DateTime(range.start.year, range.start.month, 0);
  final prevEndExcl = prevEnd.add(const Duration(days: 1));

  final prevSales = await client
      .from('sales')
      .select('final_amount, items')
      .gte('created_at', prevStart.toUtc().toIso8601String())
      .lt('created_at', prevEndExcl.toUtc().toIso8601String());

  double prevMonthSales = 0;
  double prevMonthPurchases = 0;
  for (final s in prevSales as List) {
    prevMonthSales += (s['final_amount'] as num?)?.toDouble() ?? 0;
    final items = s['items'] as List? ?? [];
    for (final item in items) {
      final purchasePrice = (item['purchase_price'] as num?)?.toDouble() ?? 0;
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      prevMonthPurchases += purchasePrice * qty;
    }
  }

  final prevExpenses = await client
      .from('expenses')
      .select('amount')
      .gte('created_at', prevStart.toUtc().toIso8601String())
      .lt('created_at', prevEndExcl.toUtc().toIso8601String());

  double prevMonthExpenses = 0;
  for (final e in prevExpenses as List) {
    prevMonthExpenses += (e['amount'] as num?)?.toDouble() ?? 0;
  }

  double netProfit = totalSales - totalPurchases - totalExpenses;
  double prevMonthProfit =
      prevMonthSales - prevMonthPurchases - prevMonthExpenses;

  var topProducts =
      productSales.entries
          .map((e) => {'name': e.key, 'total': e.value})
          .toList()
        ..sort(
          (a, b) => (b['total'] as double).compareTo(a['total'] as double),
        );

  var salesByDay = dailySales.entries
      .map((e) => {'date': e.key, 'total': e.value})
      .toList();

  return ReportData(
    totalSales: totalSales,
    totalPurchases: totalPurchases,
    totalExpenses: totalExpenses,
    netProfit: netProfit,
    salesByDay: salesByDay,
    topProducts: topProducts.take(5).toList(),
    salesByCategory: categorySales,
    expensesByCategory: expensesByCategory,
    paymentBreakdown: paymentBreakdown,
    prevMonthSales: prevMonthSales,
    prevMonthExpenses: prevMonthExpenses,
    prevMonthProfit: prevMonthProfit,
  );
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(reportDataProvider);
    final range = ref.watch(dateRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(reportDataProvider),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _exportReport(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportDataProvider),
        child: reportAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (report) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick period selector
                _PeriodSelector(range: range, ref: ref),
                const SizedBox(height: 12),

                // Month comparison
                _MonthComparison(report: report),
                const SizedBox(height: 12),

                // Profit summary - P&L breakdown
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profit & Loss Statement',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        _ReportRow(
                          'Sales Revenue',
                          'Rs${report.totalSales.toStringAsFixed(0)}',
                          Colors.green,
                        ),
                        _ReportRow(
                          'Less: COGS (Purchases)',
                          '-Rs${report.totalPurchases.toStringAsFixed(0)}',
                          Colors.orange,
                        ),
                        const Divider(height: 4),
                        _ReportRow(
                          'Gross Profit',
                          'Rs${report.grossProfit.toStringAsFixed(0)} (${report.grossMargin.toStringAsFixed(1)}%)',
                          report.grossProfit >= 0 ? Colors.green : Colors.red,
                          bold: true,
                        ),
                        const SizedBox(height: 8),
                        _ReportRow(
                          'Less: Expenses (Total)',
                          '-Rs${report.totalExpenses.toStringAsFixed(0)}',
                          Colors.red,
                        ),
                        const Divider(height: 4),
                        _ReportRow(
                          'Net Profit',
                          'Rs${report.netProfit.toStringAsFixed(0)} (${report.profitMargin.toStringAsFixed(1)}%)',
                          report.netProfit >= 0 ? Colors.green : Colors.red,
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Balance Sheet
                _BalanceSheetSection(ref: ref),

                const SizedBox(height: 12),

                // Trial Balance
                _TrialBalanceSection(),

                const SizedBox(height: 12),

                // Returns & Damaged summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Returns & Damaged',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        FutureBuilder<double>(
                          future: _getTodayReturns(),
                          builder: (ctx, snap) => _ReportRow(
                            'Today\'s Returns',
                            'Rs${(snap.data ?? 0).toStringAsFixed(0)}',
                            Colors.orange,
                          ),
                        ),
                        FutureBuilder<int>(
                          future: _getTodayDamaged(),
                          builder: (ctx, snap) => _ReportRow(
                            'Today\'s Damaged',
                            '${snap.data ?? 0} items',
                            Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Aging Analysis
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Aging Analysis (Receivables)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getAgingData(),
                          builder: (ctx, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final data = snap.data ?? [];
                            if (data.isEmpty) {
                              return const Text(
                                'No receivables data available',
                                style: TextStyle(color: Colors.grey),
                              );
                            }
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 16,
                                headingTextStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                dataTextStyle: const TextStyle(fontSize: 12),
                                columns: const [
                                  DataColumn(label: Text('Customer')),
                                  DataColumn(
                                    label: Text('Total Due'),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text('Current'),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text('30 days'),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text('60 days'),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text('90 days'),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: Text('90+ days'),
                                    numeric: true,
                                  ),
                                ],
                                rows: data.map((row) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(row['customer_name'] ?? 'Unknown'),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['total_due'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['current'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['days_30'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['days_60'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['days_90'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          'Rs${((row['days_90_plus'] as num?) ?? 0).toStringAsFixed(0)}',
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Payment breakdown
                if (report.paymentBreakdown.values.any((v) => v > 0)) ...[
                  const Text(
                    'Payment Method',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _PaymentPieChart(data: report.paymentBreakdown),
                  const SizedBox(height: 12),
                ],

                // Sales by category
                if (report.salesByCategory.isNotEmpty) ...[
                  const Text(
                    'Sales by Category',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _CategoryPieChart(
                    data: report.salesByCategory,
                    colors: Colors.primaries,
                  ),
                  const SizedBox(height: 12),
                ],

                // Expense by category
                if (report.expensesByCategory.isNotEmpty) ...[
                  const Text(
                    'Expenses by Category',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _CategoryPieChart(
                    data: report.expensesByCategory,
                    colors: [
                      Colors.red,
                      Colors.orange,
                      Colors.amber,
                      Colors.brown,
                      Colors.pink,
                      Colors.teal,
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                // Sales by day chart
                if (report.salesByDay.isNotEmpty) ...[
                  const Text(
                    'Sales Trend',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY:
                                report.salesByDay
                                    .map((e) => e['total'] as double)
                                    .reduce((a, b) => a > b ? a : b) *
                                1.2,
                            barGroups: report.salesByDay.asMap().entries.map((
                              entry,
                            ) {
                              return BarChartGroupData(
                                x: entry.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: entry.value['total'] as double,
                                    color: Colors.indigo,
                                    width: 16,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                            titlesData: FlTitlesData(
                              show: true,
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final idx = value.toInt();
                                    if (idx < report.salesByDay.length) {
                                      return Text(
                                        report.salesByDay[idx]['date']
                                            as String,
                                        style: const TextStyle(fontSize: 9),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Top products
                if (report.topProducts.isNotEmpty) ...[
                  const Text(
                    'Top Products',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...report.topProducts.asMap().entries.map((entry) {
                    final i = entry.key + 1;
                    final p = entry.value;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: i <= 3
                              ? Colors.green.shade100
                              : Colors.grey.shade100,
                          child: Text(
                            '$i',
                            style: TextStyle(
                              color: i <= 3 ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(p['name'] as String),
                        trailing: Text(
                          'Rs${(p['total'] as double).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportReport(BuildContext context, WidgetRef ref) async {
    final report = ref.read(reportDataProvider).value;
    if (report == null) return;

    final range = ref.read(dateRangeProvider);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'IDEAL STORE',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Header(
            level: 1,
            child: pw.Text(
              'Business Report',
              style: pw.TextStyle(fontSize: 18),
            ),
          ),
          pw.Text(
            'Period: ${DateFormat('dd MMM yyyy').format(range.start)} to ${DateFormat('dd MMM yyyy').format(range.end)}',
          ),
          pw.SizedBox(height: 10),
          pw.Divider(),

          // Profit Summary - P&L
          pw.Header(
            level: 2,
            child: pw.Text(
              'Profit & Loss Statement',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          _pdfRow('Sales Revenue', 'Rs${report.totalSales.toStringAsFixed(2)}'),
          _pdfRow(
            'Less: COGS (Purchases)',
            '-Rs${report.totalPurchases.toStringAsFixed(2)}',
          ),
          pw.Divider(),
          _pdfRow(
            'Gross Profit',
            'Rs${(report.totalSales - report.totalPurchases).toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 4),
          _pdfRow(
            'Less: Expenses (Total)',
            '-Rs${report.totalExpenses.toStringAsFixed(2)}',
          ),
          pw.Divider(),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Net Profit',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                pw.Text(
                  'Rs${report.netProfit.toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Payment Breakdown
          if (report.paymentBreakdown.values.any((v) => v > 0)) ...[
            pw.Header(
              level: 2,
              child: pw.Text(
                'Payment Breakdown',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            ...report.paymentBreakdown.entries
                .where((e) => e.value > 0)
                .map(
                  (e) => _pdfRow(
                    e.key.toUpperCase(),
                    'Rs${e.value.toStringAsFixed(2)}',
                  ),
                ),
            pw.SizedBox(height: 16),
          ],

          // Sales by Category
          if (report.salesByCategory.isNotEmpty) ...[
            pw.Header(
              level: 2,
              child: pw.Text(
                'Sales by Category',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            ...report.salesByCategory.entries.map(
              (e) => _pdfRow(e.key, 'Rs${e.value.toStringAsFixed(2)}'),
            ),
            pw.SizedBox(height: 16),
          ],

          // Expense by Category
          if (report.expensesByCategory.isNotEmpty) ...[
            pw.Header(
              level: 2,
              child: pw.Text(
                'Expenses by Category',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            ...report.expensesByCategory.entries.map(
              (e) => _pdfRow(e.key, 'Rs${e.value.toStringAsFixed(2)}'),
            ),
            pw.SizedBox(height: 16),
          ],

          // Top Products
          if (report.topProducts.isNotEmpty) ...[
            pw.Header(
              level: 2,
              child: pw.Text(
                'Top Products',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            ...report.topProducts.asMap().entries.map((entry) {
              final i = entry.key + 1;
              final p = entry.value;
              return _pdfRow(
                '#$i ${p['name']}',
                'Rs${(p['total'] as double).toStringAsFixed(2)}',
              );
            }),
            pw.SizedBox(height: 16),
          ],

          // Sales by Day
          if (report.salesByDay.isNotEmpty) ...[
            pw.Header(
              level: 2,
              child: pw.Text(
                'Daily Sales',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            ...report.salesByDay.map(
              (e) => _pdfRow(
                e['date'] as String,
                'Rs${(e['total'] as double).toStringAsFixed(2)}',
              ),
            ),
          ],

          pw.SizedBox(height: 30),
          pw.Divider(),
          pw.Center(
            child: pw.Text(
              'Generated on ${DateFormat('dd MMM yyyy, hh:mm a').format(AppTimezone.nowIst())}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'IdealStore_Report.pdf',
    );
  }

  pw.Widget _pdfRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 12)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  final DateRange range;
  final WidgetRef ref;

  const _PeriodSelector({required this.range, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _PeriodChip(
              label: 'Today',
              isSelected: range.label == 'Today',
              onTap: () => ref.read(dateRangeProvider.notifier).setToday(),
            ),
            _PeriodChip(
              label: 'Week',
              isSelected: range.label == 'This Week',
              onTap: () => ref.read(dateRangeProvider.notifier).setThisWeek(),
            ),
            _PeriodChip(
              label: 'Month',
              isSelected: range.label == 'This Month',
              onTap: () => ref.read(dateRangeProvider.notifier).setThisMonth(),
            ),
            _PeriodChip(
              label: 'Last Month',
              isSelected: range.label == 'Last Month',
              onTap: () => ref.read(dateRangeProvider.notifier).setLastMonth(),
            ),
            IconButton(
              icon: const Icon(Icons.calendar_today, size: 20),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: DateTimeRange(
                    start: range.start,
                    end: range.end,
                  ),
                );
                if (picked != null) {
                  ref
                      .read(dateRangeProvider.notifier)
                      .update(picked.start, picked.end);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _MonthComparison extends StatelessWidget {
  final ReportData report;

  const _MonthComparison({required this.report});

  @override
  Widget build(BuildContext context) {
    if (report.prevMonthSales == 0) return const SizedBox();

    final salesChange = report.totalSales - report.prevMonthSales;
    final profitChange = report.netProfit - report.prevMonthProfit;
    final salesUp = salesChange >= 0;
    final profitUp = profitChange >= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'vs Last Month',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ComparisonTile(
                    label: 'Sales',
                    current: report.totalSales,
                    previous: report.prevMonthSales,
                    isUp: salesUp,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ComparisonTile(
                    label: 'Profit',
                    current: report.netProfit,
                    previous: report.prevMonthProfit,
                    isUp: profitUp,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonTile extends StatelessWidget {
  final String label;
  final double current;
  final double previous;
  final bool isUp;

  const _ComparisonTile({
    required this.label,
    required this.current,
    required this.previous,
    required this.isUp,
  });

  @override
  Widget build(BuildContext context) {
    final change = previous > 0
        ? ((current - previous) / previous * 100).abs()
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUp ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUp ? Icons.trending_up : Icons.trending_down,
                size: 16,
                color: isUp ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                '${change.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isUp ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentPieChart extends StatelessWidget {
  final Map<String, double> data;

  const _PaymentPieChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const SizedBox();

    final colors = {'cash': Colors.green, 'digital': Colors.blue};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              height: 120,
              width: 120,
              child: PieChart(
                PieChartData(
                  sections: data.entries.where((e) => e.value > 0).map((e) {
                    final pct = (e.value / total * 100);
                    return PieChartSectionData(
                      value: e.value,
                      title: '${pct.toStringAsFixed(0)}%',
                      color: colors[e.key] ?? Colors.grey,
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.entries.where((e) => e.value > 0).map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        color: colors[e.key] ?? Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${e.key.toUpperCase()}: Rs${e.value.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPieChart extends StatelessWidget {
  final Map<String, double> data;
  final List<Color> colors;

  const _CategoryPieChart({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const SizedBox();

    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              height: 140,
              child: PieChart(
                PieChartData(
                  sections: top5.asMap().entries.map((entry) {
                    final pct = entry.value.value / total * 100;
                    return PieChartSectionData(
                      value: entry.value.value,
                      title: '${pct.toStringAsFixed(0)}%',
                      color: colors[entry.key % colors.length],
                      radius: 55,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: top5.asMap().entries.map((entry) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      color: colors[entry.key % colors.length],
                    ),
                    const SizedBox(width: 4),
                    Text(entry.value.key, style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

Future<double> _getTodayReturns() async {
  return ReturnService().getTodayReturnsTotal();
}

Future<int> _getTodayDamaged() async {
  return DamagedService().getTodayDamagedCount();
}

Future<List<Map<String, dynamic>>> _getAgingData() async {
  return CustomerService().getReceivablesAging();
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;

  const _ReportRow(this.label, this.value, this.color, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 15 : 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 15 : 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceSheetSection extends ConsumerWidget {
  final WidgetRef ref;
  const _BalanceSheetSection({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final stockValueAsync = ref.watch(stockValueProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Balance Sheet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            accountsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error loading accounts: $e'),
              data: (accounts) {
                double cashBalance = 0;
                double bankBalance = 0;
                for (final a in accounts) {
                  if (a.accountType == 'cash') cashBalance = a.balance;
                  if (a.accountType == 'bank') bankBalance = a.balance;
                }
                return stockValueAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (stockValue) {
                    return FutureBuilder<double>(
                      future: CustomerService().getTotalDebt(),
                      builder: (ctx, snap) {
                        final receivables = snap.data ?? 0;
                        final totalAssets =
                            cashBalance +
                            bankBalance +
                            stockValue +
                            receivables;
                        const liabilities = 0.0;
                        final equity = totalAssets - liabilities;
                        return Column(
                          children: [
                            _ReportRow(
                              'Cash in Hand',
                              'Rs${cashBalance.toStringAsFixed(0)}',
                              Colors.green,
                            ),
                            _ReportRow(
                              'Bank Balance',
                              'Rs${bankBalance.toStringAsFixed(0)}',
                              Colors.blue,
                            ),
                            _ReportRow(
                              'Stock Value',
                              'Rs${stockValue.toStringAsFixed(0)}',
                              Colors.purple,
                            ),
                            _ReportRow(
                              'Accounts Receivable (Dues)',
                              'Rs${receivables.toStringAsFixed(0)}',
                              Colors.orange,
                            ),
                            const Divider(),
                            _ReportRow(
                              'Total Assets',
                              'Rs${totalAssets.toStringAsFixed(0)}',
                              Colors.green,
                              bold: true,
                            ),
                            _ReportRow(
                              'Total Liabilities',
                              'Rs${liabilities.toStringAsFixed(0)}',
                              Colors.red,
                            ),
                            _ReportRow(
                              'Equity (Assets - Liabilities)',
                              'Rs${equity.toStringAsFixed(0)}',
                              Colors.indigo,
                              bold: true,
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrialBalanceSection extends ConsumerWidget {
  const _TrialBalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trial Balance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchTrialBalance(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data ?? [];
                if (data.isEmpty) {
                  return const Text(
                    'No trial balance data available',
                    style: TextStyle(color: Colors.grey),
                  );
                }
                double totalDebit = 0;
                double totalCredit = 0;
                for (final row in data) {
                  totalDebit += (row['debit'] as num?)?.toDouble() ?? 0;
                  totalCredit += (row['credit'] as num?)?.toDouble() ?? 0;
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 24,
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    dataTextStyle: const TextStyle(fontSize: 12),
                    columns: const [
                      DataColumn(label: Text('Account')),
                      DataColumn(label: Text('Debit'), numeric: true),
                      DataColumn(label: Text('Credit'), numeric: true),
                    ],
                    rows: [
                      ...data.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                row['account_name'] ?? row['name'] ?? 'Unknown',
                              ),
                            ),
                            DataCell(
                              Text(
                                'Rs${((row['debit'] as num?) ?? 0).toStringAsFixed(0)}',
                              ),
                            ),
                            DataCell(
                              Text(
                                'Rs${((row['credit'] as num?) ?? 0).toStringAsFixed(0)}',
                              ),
                            ),
                          ],
                        );
                      }),
                      DataRow(
                        cells: [
                          const DataCell(
                            Text(
                              'TOTAL',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataCell(
                            Text(
                              'Rs${totalDebit.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              'Rs${totalCredit.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchTrialBalance() async {
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc('get_trial_balance');
      if (res is List) {
        return res
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
