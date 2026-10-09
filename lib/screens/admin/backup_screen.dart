import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../services/backup_service.dart';
import '../../utils/app_timezone.dart';
import '../../utils/error_messages.dart';

/// Backup & Restore (#31): there was no way to restore before.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _service = BackupService();
  bool _busy = false;
  String? _busyText;
  List<File> _local = [];
  List<String> _cloud = [];
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final local = await _service.localBackups();
      List<String> cloud = [];
      List<Map<String, dynamic>> history = [];
      try {
        cloud = await _service.cloudBackups();
      } catch (_) {}
      try {
        history = await _service.getBackupHistory();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _local = local;
          _cloud = cloud;
          _history = history;
        });
      }
    } catch (e) {
      _snack('Could not list backups: ${ErrorMessages.parse(e)}', error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  Future<void> _run(String text, Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await job();
    } catch (e) {
      _snack(ErrorMessages.parse(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  Future<void> _backup() => _run('Making backup…', () async {
        final r = await _service.performBackup(
          onProgress: (step, of, what) {
            if (mounted) setState(() => _busyText = 'Making backup… $step of $of: $what');
          },
        );
        if (!r.success) throw Exception(r.error ?? 'Backup failed');
        await _refresh();
        if (!mounted) return;
        // a clear "done", not a message that is easy to miss (QA #3)
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              r.cloudPath != null ? Icons.check_circle : Icons.warning_amber,
              color: r.cloudPath != null ? Colors.green : Colors.orange,
              size: 40,
            ),
            title: Text(r.cloudPath != null ? 'Backup done' : 'Backup saved on this phone only'),
            content: Text(r.cloudPath != null
                ? 'Saved on this device and in the cloud (${r.fileSizeMB}).'
                : 'Saved on this device (${r.fileSizeMB}). The cloud upload failed — try again when the internet is better.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      });

  /// Restore needs the word RESTORE typed in, because it replaces everything.
  Future<bool> _confirmRestore(String what) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(what, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text(
                'ALL current sales, purchases, stock, customers and cash-book entries will be '
                'replaced by the backup. Make a fresh backup first if you may need today\'s data.\n\n'
                'Type RESTORE to continue.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'RESTORE'),
                onChanged: (_) => setD(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: ctrl.text.trim() == 'RESTORE' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _afterRestore(Map<String, dynamic> counts) async {
    ref.invalidate(productsProvider);
    ref.invalidate(salesHistoryProvider);
    ref.invalidate(accountsProvider);
    ref.invalidate(dashboardSummaryProvider);
    final total = counts.values.fold<num>(0, (s, v) => s + (v is num ? v : 0));
    _snack('Restored $total records');
    await _refresh();
  }

  Future<void> _restoreLocal(File f) async {
    if (!await _confirmRestore(f.path.split(Platform.pathSeparator).last)) return;
    await _run('Restoring…', () async => _afterRestore(await _service.restoreFromLocal(f)));
  }

  Future<void> _restoreCloud(String name) async {
    if (!await _confirmRestore(name)) return;
    await _run('Restoring…', () async => _afterRestore(await _service.restoreFromCloud(name)));
  }

  String _when(String? iso) {
    final t = DateTime.tryParse(iso ?? '');
    return t == null ? '' : DateFormat('dd MMM yyyy, hh:mm a').format(AppTimezone.toIst(t));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
        actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.backup_rounded, color: Colors.blue, size: 32),
                  title: const Text('Make a backup now'),
                  subtitle: const Text('All business data → this device + cloud. Logins and PINs are not included.'),
                  trailing: FilledButton(onPressed: _busy ? null : _backup, child: const Text('Back up')),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.green),
                  title: const Text('Share latest backup file'),
                  subtitle: const Text('Keep a copy on a pen drive, e-mail or Drive'),
                  onTap: _busy ? null : () => _run('Sharing…', _service.shareLatestBackup),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.table_view_rounded, color: Colors.teal),
                  title: const Text('Export all sales (CSV)'),
                  subtitle: const Text('For your accountant'),
                  onTap: _busy ? null : () => _run('Exporting…', _service.shareSalesCsv),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Restore from this device', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (_local.isEmpty)
                const Padding(padding: EdgeInsets.all(8), child: Text('No backups on this device yet.')),
              for (final f in _local.take(10))
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(f.path.split(Platform.pathSeparator).last),
                  subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
                  trailing: TextButton(onPressed: _busy ? null : () => _restoreLocal(f), child: const Text('Restore')),
                ),
              const SizedBox(height: 16),
              const Text('Restore from cloud', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (_cloud.isEmpty)
                const Padding(padding: EdgeInsets.all(8), child: Text('No cloud backups found.')),
              for (final n in _cloud.take(10))
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(n),
                  trailing: TextButton(onPressed: _busy ? null : () => _restoreCloud(n), child: const Text('Restore')),
                ),
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Backup history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                for (final h in _history.take(10))
                  ListTile(
                    dense: true,
                    leading: Icon(
                      h['status'] == 'completed' ? Icons.check_circle : Icons.error_outline,
                      color: h['status'] == 'completed' ? Colors.green : Colors.red,
                    ),
                    title: Text(_when(h['started_at']?.toString())),
                    subtitle: Text(h['status'] == 'completed'
                        ? '${h['file_path'] ?? ''}'
                        : 'Failed: ${h['error_message'] ?? ''}'),
                  ),
              ],
            ],
          ),
          if (_busy)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(width: 16),
                        Text(_busyText ?? 'Working…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
