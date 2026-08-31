import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  /// Export all data as JSON backup
  Future<File?> exportJsonBackup() async {
    try {
      final supabase = Supabase.instance.client;
      final backup = <String, dynamic>{
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0.12',
      };

      // Fetch all tables in parallel
      final results = await Future.wait([
        supabase.from('products').select(),
        supabase.from('sales').select(),
        supabase.from('customers').select(),
        supabase.from('suppliers').select(),
        supabase.from('purchases').select(),
        supabase.from('expenses').select(),
        supabase.from('accounts').select(),
        supabase.from('account_transactions').select(),
      ]);

      backup['products'] = results[0];
      backup['sales'] = results[1];
      backup['customers'] = results[2];
      backup['suppliers'] = results[3];
      backup['purchases'] = results[4];
      backup['expenses'] = results[5];
      backup['accounts'] = results[6];
      backup['account_transactions'] = results[7];

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('${dir.path}/ideal_store_backup_$timestamp.json');
      await file.writeAsString(jsonEncode(backup));
      
      Logger.info('Backup exported: ${file.path}');
      return file;
    } catch (e) {
      Logger.error('Backup export failed', e);
      return null;
    }
  }

  /// Export sales as CSV for accounting
  Future<File?> exportSalesCsv({DateTime? from, DateTime? to}) async {
    try {
      final supabase = Supabase.instance.client;
      var query = supabase.from('sales').select('*, customers(name)');
      
      if (from != null) query = query.gte('created_at', from.toIso8601String());
      if (to != null) query = query.lte('created_at', to.toIso8601String());
      
      final sales = await query.order('created_at', ascending: false);
      
      final rows = <List<String>>[
        ['Date', 'Invoice #', 'Customer', 'Items', 'Subtotal', 'Discount', 'Tax', 'Total', 'Payment', 'Status'],
      ];
      
      for (final sale in sales) {
        final items = sale['items'] as List? ?? [];
        final customerName = (sale['customers'] as Map?)?['name'] ?? 'Walk-in';
        rows.add([
          sale['created_at']?.toString() ?? '',
          sale['invoice_number']?.toString() ?? '',
          customerName,
          items.length.toString(),
          (sale['subtotal'] ?? 0).toString(),
          (sale['discount'] ?? 0).toString(),
          (sale['tax'] ?? 0).toString(),
          (sale['final_amount'] ?? 0).toString(),
          sale['payment_method']?.toString() ?? '',
          sale['is_credit'] == true ? 'Credit' : 'Paid',
        ]);
      }
      
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/sales_export_$timestamp.csv');
      await file.writeAsString(csv);
      
      Logger.info('Sales CSV exported: ${file.path}');
      return file;
    } catch (e) {
      Logger.error('Sales CSV export failed', e);
      return null;
    }
  }

  /// Share backup file
  Future<void> shareBackup() async {
    final file = await exportJsonBackup();
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)], text: 'Ideal Store POS Backup');
    }
  }

  /// Share sales CSV
  Future<void> shareSalesCsv({DateTime? from, DateTime? to}) async {
    final file = await exportSalesCsv(from: from, to: to);
    if (file != null) {
      await Share.shareXFiles([XFile(file.path)], text: 'Sales Export');
    }
  }
}
