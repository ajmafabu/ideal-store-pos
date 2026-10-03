import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils/logger.dart';

/// Factory reset (#31). The reset itself runs in ONE database transaction
/// (`factory_reset`, admin only): it either clears everything or nothing.
/// The old version deleted table by table from the app and could stop
/// half-way, leaving a broken database.
class FactoryResetService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Re-checks the signed-in admin's password on a separate connection, so
  /// a typo or another account's e-mail never changes the current session.
  Future<bool> verifyAdmin(String email, String password) async {
    final current = _client.auth.currentUser;
    if (current == null || (current.email ?? '').toLowerCase() != email.trim().toLowerCase()) {
      return false;
    }
    final temp = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    try {
      final res = await temp.auth.signInWithPassword(email: email.trim(), password: password);
      if (res.user?.id != current.id) return false;
      final profile = await _client.from('profiles').select('role, active').eq('id', current.id).maybeSingle();
      return profile != null && profile['role'] == 'admin' && profile['active'] != false;
    } catch (e) {
      Logger.warning('verifyAdmin failed: $e');
      return false;
    } finally {
      try {
        await temp.auth.signOut();
      } catch (_) {}
      await temp.dispose();
    }
  }

  /// Deletes every business record (sales, purchases, stock, customers,
  /// suppliers, cash book). Logins, staff and shop settings are kept.
  Future<void> resetAllData() async {
    await _client.rpc('factory_reset', params: {'p_confirm': 'RESET', 'p_scope': 'all'});
    Logger.info('Factory reset done');
  }

  /// Clears purchases, supplier payments and the cash book only; current
  /// stock is kept as opening stock at its cost price.
  Future<void> clearPurchasesAndAccounts() async {
    await _client.rpc('factory_reset', params: {'p_confirm': 'RESET', 'p_scope': 'purchases_accounts'});
    Logger.info('Purchases and accounts cleared');
  }
}
