import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class BackupService {
  final SupabaseClient _client;

  BackupService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ============================================
  // LEGACY METHODS (for backward compatibility)
  // ============================================

  /// Export all data to JSON and return the file
  Future<File?> exportJsonBackup() async {
    try {
      final data = await exportData();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'backup_$timestamp.json';

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      final jsonStr = JsonEncoder.withIndent('  ').convert(data);
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      Logger.info('JSON backup exported: $filePath');
      return file;
    } catch (e) {
      Logger.error('Failed to export JSON backup: $e');
      return null;
    }
  }

  /// Share the last backup file
  Future<void> shareBackup() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync().whereType<File>().where(
        (f) => f.path.contains('backup_') && f.path.endsWith('.json'),
      ).toList();

      if (files.isEmpty) {
        Logger.warning('No backup files found to share');
        return;
      }

      // Sort by modified time, newest first
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestBackup = files.first;

      await Share.shareXFiles(
        [XFile(latestBackup.path)],
        text: 'Ideal Store POS Backup',
      );
    } catch (e) {
      Logger.error('Failed to share backup: $e');
    }
  }

  /// Export sales data to CSV
  Future<File?> exportSalesCsv() async {
    try {
      final response = await _client
          .from('sales')
          .select('id, items, total_amount, final_amount, payment_method, created_at, customer_id, is_credit')
          .order('created_at', ascending: false);

      if (response.isEmpty) {
        Logger.warning('No sales data to export');
        return null;
      }

      // Build CSV
      final csv = StringBuffer();
      csv.writeln('ID,Items,Total Amount,Final Amount,Payment Method,Created At,Customer ID,Is Credit');

      for (final sale in response) {
        final items = (sale['items'] as List?)
            ?.map((item) => '${item['name'] ?? ''}(${item['qty'] ?? 0})')
            .join('; ') ?? '';
        csv.writeln(
          '${sale['id']},'
          '"${items.replaceAll('"', '""')}",'
          '${sale['total_amount'] ?? 0},'
          '${sale['final_amount'] ?? 0},'
          '${sale['payment_method'] ?? ''},'
          '${sale['created_at'] ?? ''},'
          '${sale['customer_id'] ?? ''},'
          '${sale['is_credit'] ?? false}',
        );
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'sales_export_$timestamp.csv';

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(csv.toString());

      Logger.info('Sales CSV exported: $filePath');
      return file;
    } catch (e) {
      Logger.error('Failed to export sales CSV: $e');
      return null;
    }
  }

  /// Share the last sales CSV export
  Future<void> shareSalesCsv() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync().whereType<File>().where(
        (f) => f.path.contains('sales_export_') && f.path.endsWith('.csv'),
      ).toList();

      if (files.isEmpty) {
        Logger.warning('No CSV files found to share');
        return;
      }

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestCsv = files.first;

      await Share.shareXFiles(
        [XFile(latestCsv.path)],
        text: 'Sales Export - Ideal Store POS',
      );
    } catch (e) {
      Logger.error('Failed to share CSV: $e');
    }
  }

  /// Create a backup record and return the backup ID
  Future<String?> createBackupRecord({String type = 'manual'}) async {
    try {
      final result = await _client.rpc(
        'create_backup_record',
        params: {'p_backup_type': type},
      );
      return result as String?;
    } catch (e) {
      Logger.error('Failed to create backup record: $e');
      return null;
    }
  }

  /// Export all data to JSON files
  Future<Map<String, dynamic>> exportData() async {
    final data = <String, dynamic>{};

    // List of tables to backup
    final tables = [
      'products',
      'product_variants',
      'sales',
      'purchases',
      'expenses',
      'customers',
      'suppliers',
      'accounts',
      'account_transactions',
      'product_returns',
      'damaged_products',
      'purchase_orders',
      'inventory_batches',
      'profiles',
      'app_config',
    ];

    for (final table in tables) {
      try {
        final response = await _client.from(table).select();
        data[table] = response;
        Logger.info('Exported $table: ${response.length} rows');
      } catch (e) {
        Logger.warning('Failed to export $table: $e');
        data[table] = [];
      }
    }

    return data;
  }

  /// Save backup to local file
  Future<String?> saveBackupToFile({
    required Map<String, dynamic> data,
    String? directory,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileName = 'backup_$timestamp.json';

      // Use provided directory or default temp directory
      final dir = directory ?? Directory.systemTemp.path;
      final filePath = '$dir/$fileName';

      // Convert to JSON with pretty printing
      final jsonStr = JsonEncoder.withIndent('  ').convert(data);

      // Write to file
      final file = File(filePath);
      await file.writeAsString(jsonStr);

      // Calculate checksum
      final bytes = await file.readAsBytes();
      final checksum = _calculateChecksum(bytes);

      Logger.info('Backup saved to: $filePath (${bytes.length} bytes)');

      return filePath;
    } catch (e) {
      Logger.error('Failed to save backup file: $e');
      return null;
    }
  }

  /// Complete a backup record
  Future<void> completeBackup({
    required String backupId,
    required String filePath,
    required int fileSizeBytes,
    required String checksum,
  }) async {
    try {
      await _client.rpc(
        'complete_backup',
        params: {
          'p_backup_id': backupId,
          'p_file_path': filePath,
          'p_file_size_bytes': fileSizeBytes,
          'p_checksum': checksum,
        },
      );
      Logger.info('Backup completed: $backupId');
    } catch (e) {
      Logger.error('Failed to complete backup: $e');
    }
  }

  /// Fail a backup record
  Future<void> failBackup({
    required String backupId,
    required String errorMessage,
  }) async {
    try {
      await _client.rpc(
        'fail_backup',
        params: {
          'p_backup_id': backupId,
          'p_error_message': errorMessage,
        },
      );
    } catch (e) {
      Logger.error('Failed to record backup failure: $e');
    }
  }

  /// Get backup history
  Future<List<Map<String, dynamic>>> getBackupHistory({int limit = 20}) async {
    try {
      final result = await _client.rpc(
        'get_backup_history',
        params: {'p_limit': limit},
      );
      if (result is List) {
        return result.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      Logger.error('Failed to get backup history: $e');
      return [];
    }
  }

  /// Get database size estimate
  Future<Map<String, dynamic>> getDatabaseSize() async {
    try {
      final result = await _client.rpc('get_database_size_estimate');
      if (result is Map<String, dynamic>) {
        return result;
      }
      return {};
    } catch (e) {
      Logger.error('Failed to get database size: $e');
      return {};
    }
  }

  /// Get table row counts
  Future<Map<String, dynamic>> getTableRowCounts() async {
    try {
      final result = await _client.rpc('get_table_row_counts');
      if (result is Map<String, dynamic>) {
        return result;
      }
      return {};
    } catch (e) {
      Logger.error('Failed to get table row counts: $e');
      return {};
    }
  }

  /// Full backup workflow: create record, export, save, complete
  Future<BackupResult> performBackup({
    String? directory,
    String type = 'manual',
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Create backup record
      final backupId = await createBackupRecord(type: type);
      if (backupId == null) {
        return BackupResult(
          success: false,
          error: 'Failed to create backup record',
        );
      }

      // 2. Export data
      final data = await exportData();

      // 3. Save to file
      final filePath = await saveBackupToFile(
        data: data,
        directory: directory,
      );
      if (filePath == null) {
        await failBackup(
          backupId: backupId,
          errorMessage: 'Failed to save backup file',
        );
        return BackupResult(
          success: false,
          error: 'Failed to save backup file',
        );
      }

      // 4. Get file info
      final file = File(filePath);
      final fileSize = await file.length();
      final bytes = await file.readAsBytes();
      final checksum = _calculateChecksum(bytes);

      // 5. Complete backup record
      await completeBackup(
        backupId: backupId,
        filePath: filePath,
        fileSizeBytes: fileSize,
        checksum: checksum,
      );

      stopwatch.stop();

      return BackupResult(
        success: true,
        backupId: backupId,
        filePath: filePath,
        fileSizeBytes: fileSize,
        checksum: checksum,
        duration: stopwatch.elapsed,
        tablesBackedUp: data.keys.length,
      );
    } catch (e) {
      stopwatch.stop();
      Logger.error('Backup failed: $e');
      return BackupResult(
        success: false,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Calculate simple checksum (sum of bytes modulo 2^32)
  String _calculateChecksum(List<int> bytes) {
    int sum = 0;
    for (final byte in bytes) {
      sum = (sum + byte) & 0xFFFFFFFF;
    }
    return sum.toRadixString(16).padLeft(8, '0');
  }
}

class BackupResult {
  final bool success;
  final String? backupId;
  final String? filePath;
  final int? fileSizeBytes;
  final String? checksum;
  final Duration? duration;
  final int? tablesBackedUp;
  final String? error;

  const BackupResult({
    required this.success,
    this.backupId,
    this.filePath,
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

  String get durationFormatted {
    if (duration == null) return 'N/A';
    return '${duration!.inSeconds}.${(duration!.inMilliseconds % 1000) ~/ 100}s';
  }

  @override
  String toString() {
    if (success) {
      return 'Backup successful: $filePath ($fileSizeMB, $durationFormatted)';
    }
    return 'Backup failed: $error';
  }
}
