import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

/// Full backup and restore (#31).
///
/// A backup is one JSON file `{format, version, created_at, tables: {...}}`
/// with every business table read page by page (no 1000-row cut-off). It is
/// saved on this device and uploaded to the private "backups" storage
/// bucket. Login data (profiles with PIN hashes) is never included.
/// Restore sends the file to the `restore_backup` database function, which
/// replaces all business data in ONE transaction: it either fully succeeds
/// or changes nothing.
class BackupService {
  final SupabaseClient _client;

  BackupService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  static const format = 'ideal-pos-backup';
  static const version = 2;
  static const _bucket = 'backups';

  /// Same order as `backup_table_list()` in the database (parents first).
  static const tables = [
    'shop_settings', 'app_config', 'customers', 'suppliers', 'products', 'product_variants',
    'accounts', 'sales', 'purchase_orders', 'purchases', 'inventory_batches', 'payments',
    'supplier_payments', 'expenses', 'account_transactions', 'legacy_postings', 'product_returns',
    'damaged_products', 'stock_reconciliation', 'payment_reminders', 'transaction_edits',
  ];

  Future<List<Map<String, dynamic>>> _readAll(String table) async {
    final rows = <Map<String, dynamic>>[];
    const page = 1000;
    var from = 0;
    while (true) {
      final res = await _client.from(table).select().range(from, from + page - 1);
      final list = (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      rows.addAll(list);
      if (list.length < page) break;
      from += page;
    }
    return rows;
  }

  /// Reads every business table. A table that cannot be read stops the
  /// backup (a silent gap would make the backup useless for restore).
  Future<Map<String, dynamic>> exportData() async {
    final data = <String, dynamic>{};
    for (final t in tables) {
      data[t] = await _readAll(t);
      Logger.info('Backup: $t ${(data[t] as List).length} rows');
    }
    return {
      'format': format,
      'version': version,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
    };
  }

  Future<Directory> _localDir() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/ideal_pos_backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Makes a backup: local file + cloud copy + history record.
  Future<BackupResult> performBackup({String type = 'manual'}) async {
    final watch = Stopwatch()..start();
    String? backupId;
    try {
      backupId = (await _client.rpc('create_backup_record', params: {'p_backup_type': type}))?.toString();
      final data = await exportData();
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      final checksum = sha256.convert(bytes).toString();
      final name = 'backup_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json';

      final file = File('${(await _localDir()).path}/$name');
      await file.writeAsBytes(bytes);

      String? cloudPath;
      try {
        await _client.storage.from(_bucket).uploadBinary(
              name,
              bytes,
              fileOptions: const FileOptions(contentType: 'application/json', upsert: true),
            );
        cloudPath = '$_bucket/$name';
      } catch (e) {
        Logger.warning('Cloud upload failed, backup kept on this device only: $e');
      }

      if (backupId != null) {
        await _client.rpc('complete_backup', params: {
          'p_backup_id': backupId,
          'p_file_path': cloudPath ?? file.path,
          'p_file_size_bytes': bytes.length,
          'p_checksum': checksum,
        });
      }
      watch.stop();
      return BackupResult(
        success: true,
        backupId: backupId,
        filePath: file.path,
        cloudPath: cloudPath,
        fileSizeBytes: bytes.length,
        checksum: checksum,
        duration: watch.elapsed,
        tablesBackedUp: tables.length,
      );
    } catch (e) {
      watch.stop();
      Logger.error('Backup failed', e);
      if (backupId != null) {
        try {
          await _client.rpc('fail_backup', params: {'p_backup_id': backupId, 'p_error_message': e.toString()});
        } catch (_) {}
      }
      return BackupResult(success: false, error: e.toString(), duration: watch.elapsed);
    }
  }

  /// Backups saved on this device, newest first.
  Future<List<File>> localBackups() async {
    final dir = await _localDir();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Backups in the cloud bucket, newest first (file names).
  Future<List<String>> cloudBackups() async {
    final items = await _client.storage.from(_bucket).list();
    final names = items.map((o) => o.name).where((n) => n.endsWith('.json')).toList()
      ..sort((a, b) => b.compareTo(a));
    return names;
  }

  Future<void> shareLatestBackup() async {
    final files = await localBackups();
    if (files.isEmpty) throw Exception('No backup on this device yet. Make a backup first.');
    await Share.shareXFiles([XFile(files.first.path)], text: 'Ideal Store POS Backup');
  }

  Map<String, dynamic> _parse(List<int> bytes) {
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map || data['format'] != format || data['tables'] is! Map) {
      throw Exception('This file is not an Ideal Store POS backup (version 2 or later).');
    }
    return Map<String, dynamic>.from(data);
  }

  /// Replaces ALL business data with the backup, in one database
  /// transaction. Returns rows restored per table.
  Future<Map<String, dynamic>> restore(List<int> bytes) async {
    final data = _parse(bytes);
    final res = await _client.rpc('restore_backup', params: {'p_data': data, 'p_confirm': 'RESTORE'});
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<Map<String, dynamic>> restoreFromLocal(File file) async => restore(await file.readAsBytes());

  Future<Map<String, dynamic>> restoreFromCloud(String name) async =>
      restore(await _client.storage.from(_bucket).download(name));

  Future<List<Map<String, dynamic>>> getBackupHistory({int limit = 20}) async {
    final res = await _client.rpc('get_backup_history', params: {'p_limit': limit});
    return (res as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Every sale as CSV (for an accountant).
  Future<File> exportSalesCsv() async {
    final sales = await _readAll('sales');
    sales.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final csv = StringBuffer('Invoice No,Date,Items,Total,Final Amount,Payment,Customer ID,Credit,Due\n');
    for (final s in sales) {
      final items = (s['items'] as List?)
              ?.map((i) => '${(i as Map)['name'] ?? ''}(${i['qty'] ?? 0})')
              .join('; ') ??
          '';
      csv.writeln([
        s['invoice_no'] ?? '',
        s['created_at'] ?? '',
        '"${items.replaceAll('"', '""')}"',
        s['total_amount'] ?? 0,
        s['final_amount'] ?? 0,
        s['payment_method'] ?? '',
        s['customer_id'] ?? '',
        s['is_credit'] ?? false,
        s['due_amount'] ?? 0,
      ].join(','));
    }
    final file = File('${(await _localDir()).path}/sales_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv.toString());
    return file;
  }

  Future<void> shareSalesCsv() async {
    final file = await exportSalesCsv();
    await Share.shareXFiles([XFile(file.path)], text: 'Sales Export - Ideal Store POS');
  }
}

class BackupResult {
  final bool success;
  final String? backupId;
  final String? filePath;
  final String? cloudPath;
  final int? fileSizeBytes;
  final String? checksum;
  final Duration? duration;
  final int? tablesBackedUp;
  final String? error;

  const BackupResult({
    required this.success,
    this.backupId,
    this.filePath,
    this.cloudPath,
    this.fileSizeBytes,
    this.checksum,
    this.duration,
    this.tablesBackedUp,
    this.error,
  });

  String get fileSizeMB {
    if (fileSizeBytes == null) return 'N/A';
    return '${(fileSizeBytes! / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
