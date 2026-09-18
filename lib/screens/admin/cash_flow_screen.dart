import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_timezone.dart';

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;
  String _selectedPeriod = 'monthly';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = AppTimezone.nowIst();
      DateTime start;
      DateTime end = now;

      switch (_selectedPeriod) {
        case 'daily':
          start = DateTime(now.year, now.month, now.day);
          break;
        case 'weekly':
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          start = DateTime(weekStart.year, weekStart.month, weekStart.day);
          break;
        case 'monthly':
          start = DateTime(now.year, now.month, 1);
          break;
        case 'yearly':
          start = DateTime(now.year, 1, 1);
          break;
        default:
          start = DateTime(now.year, now.month, 1);
      }

      final startUtc = DateTime.utc(start.year, start.month, start.day)
          .subtract(AppTimezone.localOffset);
      final endUtc = DateTime.utc(end.year, end.month, end.day + 1)
          .subtract(AppTimezone.localOffset);

      final res = await Supabase.instance.client.rpc('get_cash_flow', params: {
        'p_start': startUtc.toIso8601String(),
        'p_end': endUtc.toIso8601String(),
      });

      if (res != null && (res as List).isNotEmpty) {
        setState(() {
          _data = res.first as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'No data available';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _fmt(double v) {
    final f = NumberFormat('#,##,##0', 'en_IN');
    return '₹${f.format(v.round())}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow Statement'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Period selector
                        _buildPeriodSelector(),
                        const SizedBox(height: 16),
                        
                        // Net cash flow summary
                        _buildNetCashFlowCard(),
                        const SizedBox(height: 16),
                        
                        // Cash inflows
                        _buildSection(
                          title: 'CASH INFLOWS',
                          icon: Icons.arrow_downward,
                          color: Colors.green,
                          items: [
                            _buildItem('Cash Sales', _data!['cash_sales'] ?? 0),
                            _buildItem('Digital Sales', _data!['digital_sales'] ?? 0),
                            _buildItem('Credit Collections', _data!['cash_received_customers'] ?? 0),
                          ],
                          total: _data!['total_sales_inflow'] ?? 0,
                          totalLabel: 'Total Inflows',
                        ),
                        const SizedBox(height: 16),
                        
                        // Cash outflows
                        _buildSection(
                          title: 'CASH OUTFLOWS',
                          icon: Icons.arrow_upward,
                          color: Colors.red,
                          items: [
                            _buildItem('Purchase Payments', _data!['purchase_payments'] ?? 0),
                            _buildItem('Expense Payments', _data!['expense_payments'] ?? 0),
                          ],
                          total: _data!['total_outflow'] ?? 0,
                          totalLabel: 'Total Outflows',
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildPeriodButton('Daily', 'daily'),
            _buildPeriodButton('Weekly', 'weekly'),
            _buildPeriodButton('Monthly', 'monthly'),
            _buildPeriodButton('Yearly', 'yearly'),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return TextButton(
      onPressed: () {
        setState(() => _selectedPeriod = value);
        _loadData();
      },
      style: TextButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue.shade100 : null,
        foregroundColor: isSelected ? Colors.blue.shade800 : Colors.grey,
      ),
      child: Text(label),
    );
  }

  Widget _buildNetCashFlowCard() {
    final netCashFlow = (_data?['net_cash_flow'] as num?)?.toDouble() ?? 0;
    final isPositive = netCashFlow >= 0;

    return Card(
      color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isPositive ? Icons.trending_up : Icons.trending_down,
              color: isPositive ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Net Cash Flow',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    _fmt(netCashFlow),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> items,
    required double total,
    required String totalLabel,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...items,
            const Divider(),
            _buildItem(totalLabel, total, isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(String label, dynamic value, {bool isBold = false}) {
    final amount = (value as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            _fmt(amount),
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.black : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
