import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BalanceSheetScreen extends StatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  bool _loading = true;
  Map<String, dynamic>? _data;
  String? _error;

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
      final res = await Supabase.instance.client.rpc('get_balance_sheet');
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
        title: const Text('Balance Sheet'),
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
                        // Balance check indicator
                        _buildBalanceCheck(),
                        const SizedBox(height: 16),
                        
                        // Assets section
                        _buildSection(
                          title: 'ASSETS',
                          icon: Icons.account_balance_wallet,
                          color: Colors.green,
                          items: [
                            _buildItem('Cash in Hand', _data!['cash_in_hand'] ?? 0),
                            _buildItem('Bank Balance', _data!['bank_balance'] ?? 0),
                            _buildItem('Inventory Value', _data!['inventory_value'] ?? 0),
                            _buildItem('Accounts Receivable', _data!['total_receivables'] ?? 0),
                          ],
                          total: _data!['total_assets'] ?? 0,
                          totalLabel: 'Total Assets',
                        ),
                        const SizedBox(height: 24),
                        
                        // Liabilities section
                        _buildSection(
                          title: 'LIABILITIES',
                          icon: Icons.credit_card,
                          color: Colors.red,
                          items: [
                            _buildItem('Accounts Payable', _data!['total_payables'] ?? 0),
                            _buildItem('Credit Purchase Dues', _data!['credit_purchase_dues'] ?? 0),
                          ],
                          total: _data!['total_liabilities'] ?? 0,
                          totalLabel: 'Total Liabilities',
                        ),
                        const SizedBox(height: 24),
                        
                        // Equity section
                        _buildSection(
                          title: 'EQUITY',
                          icon: Icons.account_balance,
                          color: Colors.blue,
                          items: [
                            _buildItem("Owner's Capital", _data!['owner_capital'] ?? 0),
                            _buildItem('Retained Earnings', _data!['retained_earnings'] ?? 0),
                          ],
                          total: _data!['total_equity'] ?? 0,
                          totalLabel: 'Total Equity',
                        ),
                        const SizedBox(height: 24),
                        
                        // Accounting equation
                        _buildAccountingEquation(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildBalanceCheck() {
    final isBalanced = _data?['balance_check'] ?? false;
    return Card(
      color: isBalanced ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isBalanced ? Icons.check_circle : Icons.warning,
              color: isBalanced ? Colors.green : Colors.red,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isBalanced ? 'Balance Sheet is Balanced' : 'Balance Sheet is NOT Balanced',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isBalanced ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Assets = Liabilities + Equity',
                    style: TextStyle(
                      fontSize: 12,
                      color: isBalanced ? Colors.green.shade600 : Colors.red.shade600,
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

  Widget _buildAccountingEquation() {
    final assets = (_data?['total_assets'] as num?)?.toDouble() ?? 0;
    final liabilities = (_data?['total_liabilities'] as num?)?.toDouble() ?? 0;
    final equity = (_data?['total_equity'] as num?)?.toDouble() ?? 0;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accounting Equation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildEquationItem('Assets', assets, Colors.green),
                const Text('=', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                _buildEquationItem('Liabilities', liabilities, Colors.red),
                const Text('+', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                _buildEquationItem('Equity', equity, Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEquationItem(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          _fmt(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
