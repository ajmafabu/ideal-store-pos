import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/providers.dart';
import '../models/profile.dart';
import '../utils/error_messages.dart';

/// "My account" from the round profile button on the dashboard: who is
/// signed in, and Set / Change my PIN (for PIN sign-in). The Windows till
/// lock was removed on the owner's request (13 Oct 2026).
void showMyAccountSheet(BuildContext context, WidgetRef ref, Profile profile) {
  final email = ref.read(authServiceProvider).currentUser?.email ?? '';
  final hasPin = profile.pin != null && profile.pin!.isNotEmpty;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(profile.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('$email · ${profile.isAdmin ? 'Admin' : 'Staff'}', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            const SizedBox(height: 4),
            Text(
              hasPin
                  ? 'You can sign in with your PIN.'
                  : 'No PIN set yet. Set one to sign in with a PIN.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.pop(ctx);
                _showChangePin(context, ref, hasPin);
              },
              icon: const Icon(Icons.pin_outlined),
              label: Text(hasPin ? 'Change my PIN' : 'Set my PIN'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

void _showChangePin(BuildContext context, WidgetRef ref, bool hasPin) {
  final current = TextEditingController();
  final newPin = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  var saving = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        Future<void> save() async {
          final p = newPin.text.trim();
          if (!RegExp(r'^\d{4,6}$').hasMatch(p)) {
            setD(() => error = 'The new PIN must be 4 to 6 digits');
            return;
          }
          if (p != confirm.text.trim()) {
            setD(() => error = 'The two new PINs are not the same');
            return;
          }
          setD(() {
            error = null;
            saving = true;
          });
          try {
            await ref.read(authServiceProvider).changeOwnPin(
                  newPin: p,
                  currentPin: hasPin ? current.text.trim() : null,
                  password: hasPin ? null : current.text,
                );
            ref.invalidate(profileProvider);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(hasPin ? 'PIN changed' : 'PIN set'), backgroundColor: Colors.green),
              );
            }
          } catch (e) {
            final msg = e.toString();
            setD(() {
              saving = false;
              error = msg.contains('current PIN') || msg.contains('password is wrong') || msg.contains('4 to 6')
                  ? msg.replaceFirst('Exception: ', '')
                  : ErrorMessages.parse(e);
            });
          }
        }

        InputDecoration deco(String label) =>
            InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: '');

        return AlertDialog(
          title: Text(hasPin ? 'Change my PIN' : 'Set my PIN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: current,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: hasPin ? TextInputType.number : TextInputType.visiblePassword,
                  maxLength: hasPin ? 6 : null,
                  decoration: deco(hasPin ? 'Current PIN' : 'Your account password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: deco('New PIN (4–6 digits)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: deco('New PIN again'),
                  onSubmitted: (_) => saving ? null : save(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Color(0xFFC62828))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

