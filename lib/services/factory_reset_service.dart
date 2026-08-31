import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class FactoryResetService {
  final _client = Supabase.instance.client;

  Future<bool> verifyAdmin(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) return false;

      // Check if user is admin
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null || profile['role'] != 'admin') {
        await _client.auth.signOut();
        return false;
      }

      return true;
    } catch (e) {
      Logger.error('verifyAdmin', e);
      return false;
    }
  }

  Future<void> resetAllData() async {
    Logger.info('Factory reset: deleting all data...');

    final currentUser = _client.auth.currentUser;

    // Delete in order to respect foreign keys
    final tables = [
      'account_transactions',
      'payments',
      'supplier_payments',
      'product_returns',
      'damaged_products',
      'purchase_orders',
      'inventory_batches',
      'expenses',
      'sales',
      'purchases',
      'customers',
      'suppliers',
      'products',
      'accounts',
    ];

    for (final table in tables) {
      try {
        await _client.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
        Logger.info('Factory reset: cleared $table');
      } catch (e) {
        Logger.warning('Factory reset: failed to clear $table: $e');
      }
    }

    // Delete all profiles EXCEPT the current admin
    try {
      if (currentUser != null) {
        await _client.from('profiles').delete().neq('id', currentUser.id);
        Logger.info('Factory reset: cleared profiles (kept admin)');
      } else {
        await _client.from('profiles').delete().neq('id', '00000000-0000-0000-0000-000000000000');
        Logger.info('Factory reset: cleared all profiles');
      }
    } catch (e) {
      Logger.warning('Factory reset: failed to clear profiles: $e');
    }

    Logger.info('Factory reset: all data cleared');
  }

  /// Clear only purchases and accounts (keep products and sales)
  Future<void> clearPurchasesAndAccounts() async {
    Logger.info('Clearing purchases and accounts...');

    final tables = [
      'account_transactions',
      'supplier_payments',
      'inventory_batches',
      'purchases',
      'accounts',
    ];

    for (final table in tables) {
      try {
        await _client.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
        Logger.info('Cleared $table');
      } catch (e) {
        Logger.warning('Failed to clear $table: $e');
      }
    }

    // Recreate default accounts
    try {
      await _client.from('accounts').insert([
        {'name': 'Cash in Hand', 'account_type': 'cash', 'balance': 0},
        {'name': 'Bank Account', 'account_type': 'bank', 'balance': 0},
      ]);
      Logger.info('Created default accounts');
    } catch (e) {
      Logger.warning('Failed to create default accounts: $e');
    }

    Logger.info('Purchases and accounts cleared');
  }
}
