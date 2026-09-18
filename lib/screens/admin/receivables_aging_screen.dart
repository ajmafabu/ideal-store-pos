import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReceivablesAgingScreen extends StatefulWidget {
  const ReceivablesAgingScreen({super.key});

  @override
  State<ReceivablesAgingScreen> createState() => _ReceivablesAgingScreenState();
}

class _ReceivablesAgingScreenState extends State<ReceivablesAgingScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _data = [];
  String? _error;
  int _selectedBucket = -1; // -1 = all, 0-3 = specific bucket

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
      final res = await Supabase.instance.client.rpc('get_receivables_aging');
      if (res != null) {
        setState(() {
          _data = (res as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _data = [];
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

  double _getTotalDue() {
    return _data.fold(0.0, (sum, row) => sum + ((row['total_due'] as num?)?.toDouble() ?? 0));
  }

  double _getBucketTotal(int bucket) {
    final keys = ['current_amount', 'days_1_30', 'days_31_60', 'days_61_90', 'days_90_plus'];
    if (bucket < 0 || bucket >= keys.length) return _getTotalDue();
    return _data.fold(0.0, (sum, row) => sum + ((row[keys[bucket]] as num?)?.toDouble() ?? 0));
  }

  List<Map<String, dynamic>> _getFilteredData() {
    if (_selectedBucket < 0) return _data;
    final keys = ['current_amount', 'days_1_30', 'days_31_60', 'days_61_90', 'days_90_plus'];
    final key = keys[_selectedBucket];
    return _data.where((row) => ((row[key] as num?)?.toDouble() ?? 0) > 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receivables Aging'),
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
                        // Total outstanding
                        _buildTotalCard(),
                        const SizedBox(height: 16),
                        
                        // Aging buckets
                        _buildAgingBuckets(),
                        const SizedBox(height: 16),
                        
                        // Customer list
                        _buildCustomerList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTotalCard() {
    final total = _getTotalDue();
    return Card(
      color: total > 0 ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              total > 0 ? Icons.warning : Icons.check_circle,
              color: total > 0 ? Colors.orange : Colors.green,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Outstanding',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  Text(
                    _fmt(total),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: total > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${_data.length} customers',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgingBuckets() {
    final buckets = [
      {'label': 'Current', 'days': '0 days', 'color': Colors.green},
      {'label': '1-30 Days', 'days': '1-30 days', 'color': Colors.yellow.shade700},
      {'label': '31-60 Days', 'days': '31-60 days', 'color': Colors.orange},
      {'label': '61-90 Days', 'days': '61-90 days', 'color': Colors.deepOrange},
      {'label': '90+ Days', 'days': '90+ days', 'color': Colors.red},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Aging Buckets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: buckets.length,
                itemBuilder: (context, index) {
                  final bucket = buckets[index];
                  final amount = _getBucketTotal(index);
                  final isSelected = _selectedBucket == index;
                  
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedBucket = isSelected ? -1 : index;
                      });
                    },
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (bucket['color'] as Color).withOpacity(0.2)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? (bucket['color'] as Color)
                              : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bucket['label'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: bucket['color'] as Color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bucket['days'] as String,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _fmt(amount),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: amount > 0 ? Colors.black : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerList() {
    final filteredData = _getFilteredData();
    
    if (filteredData.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 48, color: Colors.green.shade300),
                const SizedBox(height: 16),
                Text(
                  _selectedBucket < 0
                      ? 'No outstanding receivables'
                      : 'No customers in this bucket',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Customers (${filteredData.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_selectedBucket >= 0)
                  TextButton(
                    onPressed: () => setState(() => _selectedBucket = -1),
                    child: const Text('Show All'),
                  ),
              ],
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredData.length,
              itemBuilder: (context, index) {
                final row = filteredData[index];
                final name = row['customer_name']?.toString() ?? 'Unknown';
                final phone = row['phone']?.toString() ?? '';
                final totalDue = (row['total_due'] as num?)?.toDouble() ?? 0;
                final saleCount = (row['sale_count'] as num?)?.toInt() ?? 0;
                final oldestDate = row['oldest_sale_date'] as String?;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    phone.isNotEmpty ? phone : '$saleCount credit sales',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmt(totalDue),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      if (oldestDate != null)
                        Text(
                          'Since ${DateFormat('dd MMM yyyy').format(DateTime.parse(oldestDate))}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
}
