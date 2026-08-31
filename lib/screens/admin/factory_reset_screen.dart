import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/logger.dart';
import '../../config/app_colors.dart';
import '../../config/providers.dart';
import '../../services/factory_reset_service.dart';

class FactoryResetScreen extends ConsumerStatefulWidget {
  const FactoryResetScreen({super.key});

  @override
  ConsumerState<FactoryResetScreen> createState() => _FactoryResetScreenState();
}

class _FactoryResetScreenState extends ConsumerState<FactoryResetScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canReset => _confirmController.text == 'RESET' && !_loading;

  Future<void> _performReset() async {
    if (!_canReset) return;

    setState(() => _loading = true);

    try {
      final service = FactoryResetService();

      // Verify admin credentials
      final verified = await service.verifyAdmin(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!verified) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid admin credentials or not an admin account'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _loading = false);
        return;
      }

      // Show final confirmation
      if (mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Final Confirmation'),
            content: const Text(
              'This will permanently delete ALL products, sales, purchases, expenses, '
              'customers, suppliers, accounts, and staff data.\n\n'
              'This action CANNOT be undone!',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete Everything'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          setState(() => _loading = false);
          return;
        }
      }

      // Perform reset
      await service.resetAllData();

      // Re-create default accounts
      try {
        await Supabase.instance.client.from('accounts').insert([
          {'name': 'Cash in Hand', 'account_type': 'cash', 'balance': 0},
          {'name': 'Bank Account', 'account_type': 'bank', 'balance': 0},
        ]);
      } catch (e) {
        Logger.warning('Failed to re-create default accounts during factory reset: $e');
      }

      // Sign out
      await Supabase.instance.client.auth.signOut();

      // Clear biometric credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometric_enabled');
      await prefs.remove('biometric_email');
      await prefs.remove('biometric_pin');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factory reset complete. All data cleared.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearPurchasesAndAccounts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Purchases & Accounts?'),
        content: const Text('This will delete all purchases, account transactions, and reset account balances to zero.\n\nProducts, sales, and customers will NOT be affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      final service = FactoryResetService();
      await service.clearPurchasesAndAccounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchases & Accounts cleared. Balances reset to zero.'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh accounts
        ref.invalidate(accountsProvider);
        ref.invalidate(purchasesProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Factory Reset'),
        foregroundColor: Colors.red,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Danger Zone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'This will permanently delete ALL data from the app:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...[
                  'Products & Stock',
                  'Sales & Purchase History',
                  'Expenses',
                  'Customers & Suppliers',
                  'Accounts & Transactions',
                  'Staff Profiles',
                ].map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.close, color: Colors.red, size: 14),
                          const SizedBox(width: 6),
                          Text(item, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                const Text(
                  'You will be signed out after reset.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Admin email
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Admin Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
          ),
          const SizedBox(height: 12),

          // Admin password
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Admin Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Type RESET confirmation
          TextField(
            controller: _confirmController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Type RESET to confirm',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.keyboard),
              hintText: 'RESET',
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'Type exactly "RESET" (uppercase) to enable the button',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Reset button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _canReset ? _performReset : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever),
              label: Text(
                _loading ? 'Resetting...' : 'Factory Reset',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Cancel button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _loading ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(height: 32),

          // Clear Purchases & Accounts (lighter option)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.orange, size: 24),
                    const SizedBox(width: 8),
                    const Text(
                      'Clear Purchases & Accounts',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Reset purchases, account transactions, and account balances to zero. Products, sales, and customers will be kept.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                ...[
                  'All purchase records',
                  'All account transactions',
                  'Account balances reset to 0',
                  'Products & stock KEPT',
                  'Sales history KEPT',
                ].map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            item.contains('KEPT') ? Icons.check : Icons.close,
                            color: item.contains('KEPT') ? Colors.green : Colors.orange,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(item, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _clearPurchasesAndAccounts,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.cleaning_services, size: 18),
                    label: const Text('Clear Purchases & Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
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
