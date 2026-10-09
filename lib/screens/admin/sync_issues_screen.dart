import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/providers.dart';
import '../../utils/app_timezone.dart';

/// Items saved offline that the server refused 5 times (#6). They used to be
/// deleted silently; now they wait here until someone retries or discards
/// them.
class SyncIssuesScreen extends ConsumerStatefulWidget {
  const SyncIssuesScreen({super.key});

  @override
  ConsumerState<SyncIssuesScreen> createState() => _SyncIssuesScreenState();
}

class _SyncIssuesScreenState extends ConsumerState<SyncIssuesScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _items = ref.read(offlineServiceProvider).getDeadLetters());
  }

  String _title(Map<String, dynamic> d) {
    final kind = d['kind']?.toString() ?? '';
    final item = Map<String, dynamic>.from((d['item'] as Map?) ?? const {});
    switch (kind) {
      case 'sale':
        final amount = (item['final_amount'] as num?)?.toDouble() ?? 0;
        return 'Sale of Rs${amount.toStringAsFixed(0)}';
      case 'op':
        final type = item['type']?.toString() ?? 'change';
        const names = {'edit': 'Sale edit', 'delete': 'Sale delete', 'return': 'Return', 'damaged': 'Damaged stock'};
        return names[type] ?? 'Change ($type)';
      default:
        final table = item['table']?.toString() ?? 'record';
        final op = item['operation']?.toString() ?? '';
        return '${op.isEmpty ? '' : '$op · '}${table.replaceAll('_', ' ')}';
    }
  }

  Future<void> _retry(Map<String, dynamic> d) async {
    final service = ref.read(offlineServiceProvider);
    await service.retryDeadLetter(d['key'].toString());
    await service.forceSync();
    _load();
    if (mounted) {
      final stillFailing = service.getDeadLetters().any((x) => x['key'] == d['key']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(stillFailing ? 'Still failing — see the reason' : 'Sent to the server again')),
      );
    }
  }

  Future<void> _discard(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this item?'),
        content: Text('"${_title(d)}" will NOT be saved. Enter it again by hand if it is still needed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Color(0xFFC62828)),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(offlineServiceProvider).discardDeadLetter(d['key'].toString());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync problems')),
      body: _items.isEmpty
          ? const Center(child: Text('Nothing waiting — everything saved offline has synced.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = _items[i];
                final when = DateTime.tryParse(d['failed_at']?.toString() ?? '');
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(d), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        if (when != null)
                          Text(
                            'Failed ${DateFormat('dd MMM, hh:mm a').format(AppTimezone.toIst(when))}',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                        const SizedBox(height: 6),
                        Text('Reason: ${d['error'] ?? 'unknown'}', style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(onPressed: () => _discard(d), child: const Text('Discard')),
                            const SizedBox(width: 8),
                            FilledButton(onPressed: () => _retry(d), child: const Text('Try again')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
