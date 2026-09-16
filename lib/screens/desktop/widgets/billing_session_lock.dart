import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/providers.dart';
import '../../../utils/pin_auth.dart';

class BillingSessionLock extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;
  final VoidCallback onCancel;

  const BillingSessionLock({
    super.key,
    required this.onUnlocked,
    required this.onCancel,
  });

  @override
  ConsumerState<BillingSessionLock> createState() => _BillingSessionLockState();
}

class _BillingSessionLockState extends ConsumerState<BillingSessionLock> {
  final _pinController = TextEditingController();
  bool _obscurePin = true;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _verifyPin() {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;

    final profile = ref.read(profileProvider).value;
    if (profile == null) {
      setState(() => _errorText = 'Profile not loaded');
      return;
    }

    final storedHash = profile.pin;
    if (storedHash != null && PinAuth.verifyPin(pin, storedHash)) {
      widget.onUnlocked();
    } else if (storedHash == null) {
      setState(() => _errorText = 'No PIN set. Contact admin.');
    } else {
      setState(() => _errorText = 'Incorrect PIN');
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.orange),
          SizedBox(width: 8),
          Text('Session Locked'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter PIN to unlock'),
          const SizedBox(height: 12),
          TextField(
            controller: _pinController,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'PIN',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
              errorText: _errorText,
              suffixIcon: IconButton(
                icon: Icon(_obscurePin ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
            ),
            onSubmitted: (_) => _verifyPin(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _verifyPin,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
