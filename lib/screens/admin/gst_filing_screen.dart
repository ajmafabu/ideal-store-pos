import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/gst_export_service.dart';

class GstFilingScreen extends StatefulWidget {
  const GstFilingScreen({super.key});

  @override
  State<GstFilingScreen> createState() => _GstFilingScreenState();
}

class _GstFilingScreenState extends State<GstFilingScreen> {
  final _gstService = GstExportService();
  bool _loading = false;
  DateTime _selectedMonth = DateTime.now();

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: now,
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
      setState(() => _selectedMonth = DateTime(picked.year, picked.month));
    }
  }

  Future<void> _exportGstr1B2B() async {
    setState(() => _loading = true);
    try {
      final file = await _gstService.exportGstr1B2B(
        month: _selectedMonth.month,
        year: _selectedMonth.year,
      );
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GSTR-1 B2B saved: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => _gstService.shareGstr1(
                month: _selectedMonth.month,
                year: _selectedMonth.year,
              ),
            ),
          ),
        );
      }
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

  Future<void> _exportGstr1B2C() async {
    setState(() => _loading = true);
    try {
      final file = await _gstService.exportGstr1B2C(
        month: _selectedMonth.month,
        year: _selectedMonth.year,
      );
      if (file != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GSTR-1 B2C saved: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => _gstService.shareGstr1(
                month: _selectedMonth.month,
                year: _selectedMonth.year,
              ),
            ),
          ),
        );
      }
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

  Future<void> _shareAll() async {
    setState(() => _loading = true);
    try {
      await _gstService.shareGstr1(
        month: _selectedMonth.month,
        year: _selectedMonth.year,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Filing Export'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Month Selector
                GestureDetector(
                  onTap: _pickMonth,
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
                          monthLabel,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text('GSTR-1 Export', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF667eea).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.business_rounded, color: Color(0xFF667eea)),
                    ),
                    title: const Text('B2B Sales (Business to Business)'),
                    subtitle: const Text('Sales to GST-registered customers'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exportGstr1B2B,
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11998e).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person_rounded, color: Color(0xFF11998e)),
                    ),
                    title: const Text('B2C Sales (Business to Consumer)'),
                    subtitle: const Text('Rate-wise summary of consumer sales'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exportGstr1B2C,
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _shareAll,
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share All GSTR-1 Files'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667eea),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'B2B exports include invoices for GST-registered customers. B2C exports provide rate-wise summaries for consumer sales.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
