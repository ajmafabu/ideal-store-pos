import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../utils/app_timezone.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class GSTReportScreen extends ConsumerStatefulWidget {
  const GSTReportScreen({super.key});

  @override
  ConsumerState<GSTReportScreen> createState() => _GSTReportScreenState();
}

class _GSTReportScreenState extends ConsumerState<GSTReportScreen> {
  DateTime _startDate = AppTimezone.monthStartIst();
  DateTime _endDate = AppTimezone.monthEndIst();
  bool _loading = false;
  List<Map<String, dynamic>> _hsnData = [];
  double _totalSales = 0;
  double _totalGST = 0;
  double _totalCGST = 0;
  double _totalSGST = 0;
  double _totalExclGST = 0;
  int _totalItems = 0;
  int _selectedTab = 0;
  Map<String, dynamic>? _gstr3bData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final start = _startDate.toUtc();
      final end = DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toUtc();

      final response = await Supabase.instance.client
          .from('sales')
          .select('items, total_amount, discount, final_amount')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      Map<String, Map<String, dynamic>> hsnMap = {};
      double totalSales = 0;
      double totalGST = 0;
      int totalItems = 0;

      for (final sale in response as List) {
        final items = sale['items'] as List? ?? [];
        totalSales += (sale['final_amount'] as num?)?.toDouble() ?? 0;

        for (final item in items) {
          final gstRate = (item['gst_rate'] as num?)?.toDouble() ?? 0;
          final qty = (item['qty'] as num?)?.toInt() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0;
          final hsnCode = item['hsn_code'] as String? ?? '';
          final name = item['name'] as String? ?? '';
          final total = (item['total'] as num?)?.toDouble() ?? 0;

          final gstAmount = total * gstRate / (100 + gstRate);
          totalGST += gstAmount;
          totalItems += qty;

          final hsnKey = hsnCode.isEmpty ? 'NO-HSN' : hsnCode;
          if (!hsnMap.containsKey(hsnKey)) {
            hsnMap[hsnKey] = {
              'hsn': hsnKey,
              'name': name,
              'rate': gstRate,
              'qty': 0,
              'taxable_value': 0.0,
              'cgst': 0.0,
              'sgst': 0.0,
              'total': 0.0,
            };
          }
          hsnMap[hsnKey]!['qty'] += qty;
          hsnMap[hsnKey]!['taxable_value'] += total - gstAmount;
          hsnMap[hsnKey]!['cgst'] += gstAmount / 2;
          hsnMap[hsnKey]!['sgst'] += gstAmount / 2;
          hsnMap[hsnKey]!['total'] += total;
        }
      }

      setState(() {
        _hsnData = hsnMap.values.toList();
        _totalSales = totalSales;
        _totalGST = totalGST;
        _totalCGST = totalGST / 2;
        _totalSGST = totalGST / 2;
        _totalExclGST = totalSales - totalGST;
        _totalItems = totalItems;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF667eea),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  Future<void> _fetchGstr3b() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc('get_gstr3b_summary', params: {
        'p_start': _startDate.toUtc().toIso8601String(),
        'p_end': DateTime(_endDate.year, _endDate.month, _endDate.day + 1).toUtc().toIso8601String(),
      });
      if (res is List && res.isNotEmpty) {
        setState(() => _gstr3bData = Map<String, dynamic>.from(res.first));
      } else {
        setState(() => _gstr3bData = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading GSTR-3B: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _gstr3bData = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportGSTR1() async {
    setState(() => _loading = true);
    try {
      List<List<dynamic>> rows = [
        ['HSN Code', 'Description', 'GST Rate (%)', 'Quantity', 'Taxable Value', 'CGST', 'SGST', 'Total'],
      ];
      for (final h in _hsnData) {
        rows.add([
          h['hsn'],
          h['name'],
          h['rate'],
          h['qty'],
          (h['taxable_value'] as double).toStringAsFixed(2),
          (h['cgst'] as double).toStringAsFixed(2),
          (h['sgst'] as double).toStringAsFixed(2),
          (h['total'] as double).toStringAsFixed(2),
        ]);
      }
      rows.add(['', '', '', '', '', '', '', '']);
      rows.add(['TOTAL', '', '', _totalItems, _totalExclGST.toStringAsFixed(2), _totalCGST.toStringAsFixed(2), _totalSGST.toStringAsFixed(2), _totalSales.toStringAsFixed(2)]);

      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/GSTR1_${DateFormat('MMM_yyyy').format(_startDate)}.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles([XFile(file.path)], text: 'GSTR-1 Report - ${DateFormat('MMM yyyy').format(_startDate)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('GST Reports'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_selectedTab == 0)
            IconButton(
              onPressed: _loading ? null : _exportGSTR1,
              icon: const Icon(Icons.file_download_rounded),
              tooltip: 'Export GSTR-1 CSV',
            ),
        ],
      ),
      body: _loading && _hsnData.isEmpty && _gstr3bData == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                if (_selectedTab == 0) {
                  await _loadData();
                } else {
                  await _fetchGstr3b();
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date Range Picker
                    GestureDetector(
                      onTap: _pickDateRange,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Text(
                              '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            Icon(Icons.chevron_right, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tab Selector
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0 ? const Color(0xFF667eea) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text('GSTR-1',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _selectedTab == 0 ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _selectedTab = 1);
                                if (_gstr3bData == null) _fetchGstr3b();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1 ? const Color(0xFF667eea) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text('GSTR-3B',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _selectedTab == 1 ? Colors.white : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_selectedTab == 0) ...[
                      // Summary Cards
                      Row(
                        children: [
                          _summaryCard('Total Sales', 'Rs${_totalSales.toStringAsFixed(0)}', const Color(0xFF667eea)),
                          const SizedBox(width: 8),
                          _summaryCard('Total GST', 'Rs${_totalGST.toStringAsFixed(0)}', const Color(0xFF8E2DE2)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _summaryCard('CGST', 'Rs${_totalCGST.toStringAsFixed(0)}', const Color(0xFF11998e)),
                          const SizedBox(width: 8),
                          _summaryCard('SGST', 'Rs${_totalSGST.toStringAsFixed(0)}', const Color(0xFFf44336)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // HSN Summary
                      const Text('HSN-wise Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                      if (_hsnData.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Text('No GST sales in this period', style: TextStyle(color: Colors.grey))),
                        )
                      else
                        ..._hsnData.map((h) => _hsnCard(h)),

                      const SizedBox(height: 16),

                      // Export Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _exportGSTR1,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Export GSTR-1 (CSV)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667eea),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],

                    if (_selectedTab == 1) ...[
                      // GSTR-3B Summary
                      _buildGstr3bSection(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGstr3bSection() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_gstr3bData == null) {
      return Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('Tap refresh to load GSTR-3B data', style: TextStyle(color: Colors.grey))),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _fetchGstr3b,
              icon: const Icon(Icons.refresh),
              label: const Text('Load GSTR-3B Summary'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667eea),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      );
    }

    final data = _gstr3bData!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('GSTR-3B Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // Outward Supplies
        _gstr3bCard(
          title: '3.1 - Outward Supplies',
          rows: [
            _Gstr3bRow('Taxable Value', (data['outward_taxable'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('IGST', (data['outward_igst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('CGST', (data['outward_cgst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('SGST', (data['outward_sgst'] as num?)?.toDouble() ?? 0),
          ],
        ),
        const SizedBox(height: 8),

        // Inward Supplies (Reverse Charge)
        _gstr3bCard(
          title: '3.2 - Inward Supplies (Reverse Charge)',
          rows: [
            _Gstr3bRow('Taxable Value', (data['inward_taxable'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('IGST', (data['inward_igst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('CGST', (data['inward_cgst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('SGST', (data['inward_sgst'] as num?)?.toDouble() ?? 0),
          ],
        ),
        const SizedBox(height: 8),

        // Tax Payable
        _gstr3bCard(
          title: '6.1 - Tax Payable',
          rows: [
            _Gstr3bRow('Total IGST', (data['total_igst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('Total CGST', (data['total_cgst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('Total SGST', (data['total_sgst'] as num?)?.toDouble() ?? 0),
            _Gstr3bRow('Total Tax Payable', (data['total_tax_payable'] as num?)?.toDouble() ?? 0, bold: true),
          ],
        ),
      ],
    );
  }

  Widget _gstr3bCard({required String title, required List<_Gstr3bRow> rows}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Divider(),
          ...rows.map((row) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(row.label, style: TextStyle(
                  fontSize: 13,
                  fontWeight: row.bold ? FontWeight.bold : FontWeight.normal,
                )),
                Text('Rs${row.value.toStringAsFixed(0)}', style: TextStyle(
                  fontSize: 13,
                  fontWeight: row.bold ? FontWeight.bold : FontWeight.normal,
                  color: row.bold ? const Color(0xFF667eea) : null,
                )),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)]),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _hsnCard(Map<String, dynamic> h) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF667eea).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(h['hsn'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF667eea))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(h['name'], style: const TextStyle(fontWeight: FontWeight.w500))),
              Text('${h['rate'].toStringAsFixed(0)}%', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('Qty', '${h['qty']}'),
              _miniStat('Taxable', 'Rs${(h['taxable_value'] as double).toStringAsFixed(0)}'),
              _miniStat('CGST', 'Rs${(h['cgst'] as double).toStringAsFixed(0)}'),
              _miniStat('SGST', 'Rs${(h['sgst'] as double).toStringAsFixed(0)}'),
              _miniStat('Total', 'Rs${(h['total'] as double).toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Gstr3bRow {
  final String label;
  final double value;
  final bool bold;

  const _Gstr3bRow(this.label, this.value, {this.bold = false});
}
