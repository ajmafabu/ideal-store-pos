import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class GstExportService {
  static final GstExportService _instance = GstExportService._internal();
  factory GstExportService() => _instance;
  GstExportService._internal();

  /// Export GSTR-1 B2B (Business to Business) sales
  Future<File?> exportGstr1B2B({required int month, required int year}) async {
    try {
      final supabase = Supabase.instance.client;
      
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0, 23, 59, 59);
      
      final sales = await supabase
          .from('sales')
          .select('*, customers(gst_number, name, phone)')
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String())
          .order('created_at');
      
      // GSTR-1 B2B format
      final rows = <List<String>>[
        ['GSTIN of Supplier', 'Trade/Legal Name', 'Invoice Number', 'Invoice Date', 
         'Invoice Value', 'Place of Supply', 'Reverse Charge', 'Invoice Type',
         'Rate', 'Taxable Value', 'CGST Amount', 'SGST Amount', 'Total Tax'],
      ];
      
      final supplierGstin = ''; // TODO: Get from shop settings
      
      for (final sale in sales) {
        final customer = sale['customers'] as Map<String, dynamic>?;
        final customerGstin = customer?['gst_number'] as String? ?? '';
        final customerName = customer?['name'] as String? ?? 'Walk-in';
        final items = sale['items'] as List? ?? [];
        
        // Only include sales to GST-registered customers (B2B)
        if (customerGstin.isEmpty) continue;
        
        double totalTaxable = 0;
        double totalCgst = 0;
        double totalSgst = 0;
        
        for (final item in items) {
          final qty = (item['quantity'] ?? 1) as num;
          final price = (item['price'] ?? 0) as num;
          final gstRate = (item['gst_rate'] ?? 0) as num;
          final discount = (item['discount'] ?? 0) as num;
          
          final taxable = (price * qty - discount).toDouble();
          final gstAmount = taxable * gstRate / 100;
          
          totalTaxable += taxable;
          totalCgst += gstAmount / 2;
          totalSgst += gstAmount / 2;
        }
        
        final invoiceDate = sale['created_at'] != null
            ? DateTime.parse(sale['created_at'].toString())
            : DateTime.now();
        
        rows.add([
          supplierGstin,
          'Ideal Store',
          sale['invoice_number']?.toString() ?? '',
          '${invoiceDate.day.toString().padLeft(2, '0')}/${invoiceDate.month.toString().padLeft(2, '0')}/${invoiceDate.year}',
          (sale['final_amount'] ?? 0).toStringAsFixed(2),
          '33-Tamil Nadu', // TODO: Get from shop settings
          'N',
          'Regular',
          '18', // Default GST rate
          totalTaxable.toStringAsFixed(2),
          totalCgst.toStringAsFixed(2),
          totalSgst.toStringAsFixed(2),
          (totalCgst + totalSgst).toStringAsFixed(2),
        ]);
      }
      
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gstr1_b2b_${year}_${month.toString().padLeft(2, '0')}.csv');
      await file.writeAsString(csv);
      
      Logger.info('GSTR-1 B2B exported: ${file.path}');
      return file;
    } catch (e) {
      Logger.error('GSTR-1 export failed', e);
      return null;
    }
  }

  /// Export GSTR-1 B2C (Business to Consumer) sales summary
  Future<File?> exportGstr1B2C({required int month, required int year}) async {
    try {
      final supabase = Supabase.instance.client;
      
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0, 23, 59, 59);
      
      final sales = await supabase
          .from('sales')
          .select('items, final_amount, customers(gst_number)')
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String())
          .order('created_at');
      
      // Aggregate by GST rate
      final Map<String, Map<String, double>> rateWise = {};
      
      for (final sale in sales) {
        final customer = sale['customers'] as Map<String, dynamic>?;
        final customerGstin = customer?['gst_number'] as String?;
        
        // Only B2C (no GSTIN)
        if (customerGstin != null && customerGstin.isNotEmpty) continue;
        
        final items = sale['items'] as List? ?? [];
        for (final item in items) {
          final qty = (item['quantity'] ?? 1) as num;
          final price = (item['price'] ?? 0) as num;
          final gstRate = (item['gst_rate'] ?? 0) as num;
          final discount = (item['discount'] ?? 0) as num;
          final rateKey = gstRate.toString();
          
          rateWise.putIfAbsent(rateKey, () => {'taxable': 0, 'cgst': 0, 'sgst': 0});
          final taxable = (price * qty - discount).toDouble();
          rateWise[rateKey]!['taxable'] = rateWise[rateKey]!['taxable']! + taxable;
          rateWise[rateKey]!['cgst'] = rateWise[rateKey]!['cgst']! + (taxable * gstRate / 200);
          rateWise[rateKey]!['sgst'] = rateWise[rateKey]!['sgst']! + (taxable * gstRate / 200);
        }
      }
      
      final rows = <List<String>>[
        ['Place of Supply', 'Rate', 'Taxable Value', 'CGST Amount', 'SGST Amount', 'Total Tax'],
      ];
      
      for (final entry in rateWise.entries) {
        rows.add([
          '33-Tamil Nadu',
          entry.key,
          entry.value['taxable']!.toStringAsFixed(2),
          entry.value['cgst']!.toStringAsFixed(2),
          entry.value['sgst']!.toStringAsFixed(2),
          (entry.value['cgst']! + entry.value['sgst']!).toStringAsFixed(2),
        ]);
      }
      
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gstr1_b2c_${year}_${month.toString().padLeft(2, '0')}.csv');
      await file.writeAsString(csv);
      
      Logger.info('GSTR-1 B2C exported: ${file.path}');
      return file;
    } catch (e) {
      Logger.error('GSTR-1 B2C export failed', e);
      return null;
    }
  }

  /// Share GSTR-1 files
  Future<void> shareGstr1({required int month, required int year}) async {
    final b2b = await exportGstr1B2B(month: month, year: year);
    final b2c = await exportGstr1B2C(month: month, year: year);
    
    final files = <XFile>[];
    if (b2b != null) files.add(XFile(b2b.path));
    if (b2c != null) files.add(XFile(b2c.path));
    
    if (files.isNotEmpty) {
      await Share.shareXFiles(files, text: 'GSTR-1 Export $year-$month');
    }
  }
}
