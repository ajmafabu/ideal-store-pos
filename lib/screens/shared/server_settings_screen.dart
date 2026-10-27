import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../services/offline_service.dart';
import '../../utils/logger.dart';

/// Which server this device uses (27 Oct 2026). Normally the built-in
/// Supabase project. If that project is ever gone, the admin restores the
/// latest backup into a new server and points each device (PC and phone)
/// here at it: the shop is back the same day, no new app version needed.
/// Bills waiting on this device are sent to the new server.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final problem = await SupabaseConfig.testConnection(_url.text, _key.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = problem == null;
      _result = problem ?? 'Connected. This server answers with this key.';
    });
  }

  /// Typed confirmation: nobody changes the server by a stray tap.
  Future<bool> _confirm(String title, String body) async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 12),
              TextField(
                controller: typed,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Type SERVER to confirm', border: OutlineInputBorder()),
                onChanged: (_) => setDialog(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: typed.text.trim().toUpperCase() == 'SERVER' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    return ok == true;
  }

  Future<void> _signOutAndTellRestart(String what) async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (e) {
      Logger.warning('Local sign-out after server change: $e');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restart_alt, size: 40),
        title: const Text('Close and open the app again'),
        content: Text('$what\n\nThen sign in again.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _save() async {
    final problem = await SupabaseConfig.testConnection(_url.text, _key.text);
    if (problem != null) {
      setState(() {
        _ok = false;
        _result = problem;
      });
      return;
    }
    final waiting = OfflineService().pendingCount;
    final yes = await _confirm(
      'Use this server?',
      'This device will use ${_url.text.trim()}.\n\n'
          '${waiting > 0 ? '$waiting bill(s) waiting on this device will be sent to the new server.\n\n' : ''}'
          'Do the same on every PC and phone of the shop.',
    );
    if (!yes) return;
    await SupabaseConfig.saveOverride(_url.text, _key.text);
    await _signOutAndTellRestart('This device now uses the new server.');
  }

  Future<void> _useBuiltIn() async {
    final yes = await _confirm(
      'Go back to the normal server?',
      'This device will use ${SupabaseConfig.supabaseUrl} again.',
    );
    if (!yes) return;
    await SupabaseConfig.clearOverride();
    await _signOutAndTellRestart('This device uses the normal server again.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Server settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: SupabaseConfig.usingOtherServer ? const Color(0xFFFFF4DE) : const Color(0xFFE3F5EA),
            child: ListTile(
              leading: Icon(SupabaseConfig.usingOtherServer ? Icons.swap_horiz : Icons.cloud_done_outlined),
              title: Text(SupabaseConfig.usingOtherServer ? 'Using another server' : 'Using the normal server'),
              subtitle: Text(SupabaseConfig.url),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Change this only when moving the shop to a new server (for example if Supabase is gone and the '
            'backup was restored elsewhere). Everyday server problems need nothing here: bills are kept on '
            'the device and sent when the server is back.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'New server address',
              hintText: 'https://xxxxxxxx.supabase.co',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Public key (anon / publishable)',
              hintText: 'eyJ… or sb_publishable_…   — never the secret key',
              border: OutlineInputBorder(),
            ),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_result!, style: TextStyle(color: _ok ? Colors.green.shade800 : scheme.error)),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check),
                label: const Text('Test connection'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Use this server'),
              ),
              if (SupabaseConfig.usingOtherServer)
                TextButton(onPressed: _busy ? null : _useBuiltIn, child: const Text('Back to the normal server')),
            ],
          ),
        ],
      ),
    );
  }
}
