import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../models/account.dart';
import '../../services/account_service.dart';
import '../../utils/app_timezone.dart';
import '../../widgets/accounts/account_widgets.dart';
import '../../widgets/accounts/account_sheets.dart';
import '../../widgets/accounts/account_sections.dart';
import '../../widgets/empty_state.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  DateTime? _filterStart;
  DateTime? _filterEnd;
  String _searchQuery = '';
  String _selectedPeriod = 'today';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setPeriod(String period) {
    final now = AppTimezone.nowIst();
    setState(() {
      _selectedPeriod = period;
      switch (period) {
        case 'today':
          _filterStart = AppTimezone.todayStartIst();
          _filterEnd = AppTimezone.todayEndIst();
          break;
        case 'yesterday':
          _filterStart = AppTimezone.yesterdayStartIst();
          _filterEnd = AppTimezone.yesterdayEndIst();
          break;
        case 'week':
          _filterStart = now.subtract(const Duration(days: 6));
          _filterStart = DateTime(_filterStart!.year, _filterStart!.month, _filterStart!.day);
          _filterEnd = AppTimezone.todayEndIst();
          break;
        case 'month':
          _filterStart = AppTimezone.monthStartIst();
          _filterEnd = AppTimezone.monthEndIst();
          break;
        case 'all':
          _filterStart = null;
          _filterEnd = null;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final monthlyAsync = ref.watch(monthlySummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () => _showExportOptions(context),
            tooltip: 'Export',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(accountsProvider);
              ref.invalidate(todayTransactionsProvider);
              ref.invalidate(monthlySummaryProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(todayTransactionsProvider);
          ref.invalidate(monthlySummaryProvider);
        },
        child: accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (accounts) {
            if (accounts.isEmpty) {
              return const EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No Accounts',
                subtitle: 'Set up accounts to track cash flow',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: accounts.map((account) {
                    final isCash = account.accountType == 'cash';
                    return Expanded(
                      child: BalanceCard(
                        title: account.name,
                        balance: account.balance,
                        icon: isCash ? Icons.money : Icons.account_balance,
                        gradient: isCash
                            ? const LinearGradient(colors: [Color(0xFF11998e), Color(0xFF38ef7d)])
                            : const LinearGradient(colors: [Color(0xFF667eea), Color(0xFF764ba2)]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Stock Value Cards
                _buildStockValueCards(context, ref),
                const SizedBox(height: 16),

                monthlyAsync.when(
                  loading: () => const SizedBox(),
                  error: (e, _) => const SizedBox(),
                  data: (summary) => MonthlySummaryCard(summary: summary),
                ),
                const SizedBox(height: 16),

                const TodaySummaryInline(),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTransferSheet(context, accounts),
                    icon: const Icon(Icons.swap_horiz, size: 20),
                    label: const Text('Transfer Between Accounts'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF667eea)),
                      foregroundColor: const Color(0xFF667eea),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                CategoryBreakdown(filterStart: _filterStart, filterEnd: _filterEnd),
                const SizedBox(height: 16),

                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search transactions...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 12),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AccountFilterChip(label: 'Today', selected: _selectedPeriod == 'today', onTap: () => _setPeriod('today')),
                      AccountFilterChip(label: 'Yesterday', selected: _selectedPeriod == 'yesterday', onTap: () => _setPeriod('yesterday')),
                      AccountFilterChip(label: 'This Week', selected: _selectedPeriod == 'week', onTap: () => _setPeriod('week')),
                      AccountFilterChip(label: 'This Month', selected: _selectedPeriod == 'month', onTap: () => _setPeriod('month')),
                      AccountFilterChip(label: 'All', selected: _selectedPeriod == 'all', onTap: () => _setPeriod('all')),
                      AccountFilterChip(label: 'Custom', selected: _selectedPeriod == 'custom', onTap: () => _pickCustomDateRange()),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                const Text('Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TransactionsList(
                  filterStart: _filterStart,
                  filterEnd: _filterEnd,
                  searchQuery: _searchQuery,
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddEntry(context),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Add Entry', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildStockValueCards(BuildContext context, WidgetRef ref) {
    final stockValue = ref.watch(stockValueProvider);
    final sellingValue = ref.watch(stockSellingValueProvider);

    return Row(
      children: [
        Expanded(
          child: stockValue.when(
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => const SizedBox(),
            data: (value) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.inventory_2, color: Colors.white.withValues(alpha: 0.8), size: 20),
                  const SizedBox(height: 8),
                  Text('Stock (Cost)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    'Rs${_formatAmount(value)}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: sellingValue.when(
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => const SizedBox(),
            data: (value) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sell, color: Colors.white.withValues(alpha: 0.8), size: 20),
                  const SizedBox(height: 8),
                  Text('Stock (Selling)', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    'Rs${_formatAmount(value)}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatAmount(double value) {
    if (value == 0) return '0';
    final intValue = value.toInt().abs();
    final str = intValue.toString();
    if (str.length <= 3) return str;
    String result = str.substring(str.length - 3);
    int i = str.length - 3;
    while (i > 0) {
      final start = i - 2 < 0 ? 0 : i - 2;
      result = '${str.substring(start, i)},$result';
      i -= 2;
    }
    return result;
  }

  void _showAddEntry(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const AddEntrySheet(),
    );
  }

  void _showTransferSheet(BuildContext context, List<Account> accounts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TransferSheet(accounts: accounts),
    );
  }

  void _pickCustomDateRange() async {
    final now = AppTimezone.nowIst();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _filterStart != null && _filterEnd != null
          ? DateTimeRange(start: _filterStart!, end: _filterEnd!.subtract(const Duration(days: 1)))
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _filterStart = picked.start;
        _filterEnd = picked.end.add(const Duration(days: 1));
      });
    }
  }

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Export Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Export as PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _exportAsPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('Export as CSV'),
              onTap: () {
                Navigator.pop(ctx);
                _exportAsCsv();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAsPdf() async {
    try {
      final service = AccountService();
      final transactions = await service.getTransactions(
        startDate: _filterStart,
        endDate: _filterEnd,
      );

      final pdf = pw.Document();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('ACCOUNT STATEMENT', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'),
          if (_filterStart != null && _filterEnd != null)
            pw.Text('Period: ${DateFormat('dd MMM yyyy').format(_filterStart!)} - ${DateFormat('dd MMM yyyy').format(_filterEnd!.subtract(const Duration(days: 1)))}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 22,
            headers: ['Category', 'Type', 'Description', 'Amount', 'Date'],
            data: transactions.map((t) => [
              CategoryBreakdown.catLabel(t.category),
              t.type == 'in' ? 'IN' : 'OUT',
              t.description ?? '-',
              'Rs${t.amount.toStringAsFixed(0)}',
              DateFormat('dd MMM yyyy, hh:mm a').format(t.createdAt.toLocal()),
            ]).toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Total: Rs${transactions.fold(0.0, (sum, t) => sum + (t.type == 'in' ? t.amount : -t.amount)).toStringAsFixed(0)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ],
      ));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/account_statement.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)], text: 'Account Statement');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportAsCsv() async {
    try {
      final service = AccountService();
      final transactions = await service.getTransactions(
        startDate: _filterStart,
        endDate: _filterEnd,
      );

      final buffer = StringBuffer();
      buffer.writeln('Category,Type,Amount,Description,Date');
      for (final t in transactions) {
        final desc = (t.description ?? '').replaceAll(',', ';');
        buffer.writeln('${t.category},${t.type},${t.amount.toStringAsFixed(0)},$desc,${DateFormat('dd MMM yyyy, hh:mm a').format(t.createdAt.toLocal())}');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/account_statement.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles([XFile(file.path)], text: 'Account Statement');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
