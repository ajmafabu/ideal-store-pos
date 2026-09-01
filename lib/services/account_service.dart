import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/account.dart';
import '../utils/logger.dart';
import '../utils/app_timezone.dart';
import 'offline_service.dart';

class AccountService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  AccountService({SupabaseClient? client, OfflineService? offlineService})
    : _client = client ?? Supabase.instance.client,
      _offlineService = offlineService ?? OfflineService();

  Future<List<Account>> getAccounts() async {
    try {
      final res = await _client.from('accounts').select().order('created_at');
      final list = (res as List).map((a) => Account.fromJson(a)).toList();
      // Cache for offline
      try {
        await _offlineService.cacheAccounts(
          (res as List).cast<Map<String, dynamic>>(),
        );
      } catch (e) {
        Logger.warning('Failed to cache accounts for offline: $e');
      }
      return list;
    } catch (e) {
      Logger.error('getAccounts', e);
      // Offline fallback
      try {
        final cached = _offlineService.getCachedAccounts();
        if (cached.isNotEmpty) {
          return cached.map((a) => Account.fromJson(a)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to load accounts from offline cache: $e');
      }
      return [];
    }
  }

  Future<Account?> getAccountByType(String type) async {
    try {
      final res = await _client
          .from('accounts')
          .select()
          .eq('account_type', type)
          .maybeSingle();
      if (res == null) return null;
      return Account.fromJson(res);
    } catch (e) {
      Logger.error('getAccountByType', e);
      return null;
    }
  }

  Future<Account> createAccount(
    String name,
    String type, {
    double initialBalance = 0,
  }) async {
    final user = _client.auth.currentUser;
    final res = await _client
        .from('accounts')
        .insert({
          'name': name,
          'account_type': type,
          'balance': initialBalance,
          'created_by': user?.id,
        })
        .select()
        .single();
    return Account.fromJson(res);
  }

  Future<void> ensureAccountsExist() async {
    final accounts = await getAccounts();
    if (accounts.isEmpty) {
      await createAccount('Cash in Hand', 'cash');
      await createAccount('Bank Account', 'bank');
    }
  }

  Future<List<AccountTransaction>> getTransactions({
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 100,
  }) async {
    try {
      var query = _client.from('account_transactions').select();

      if (accountId != null) {
        query = query.eq('account_id', accountId);
      }
      if (startDate != null) {
        final utcStart = startDate.isUtc
            ? startDate
            : startDate.subtract(AppTimezone.localOffset);
        query = query.gte('created_at', utcStart.toIso8601String());
      }
      if (endDate != null) {
        final utcEnd = endDate.isUtc
            ? endDate
            : endDate.subtract(AppTimezone.localOffset);
        query = query.lt('created_at', utcEnd.toIso8601String());
      }

      final res = await query
          .order('created_at', ascending: false)
          .limit(limit);
      var transactions = (res as List)
          .map((t) => AccountTransaction.fromJson(t))
          .toList();

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase();
        transactions = transactions
            .where(
              (t) =>
                  (t.description?.toLowerCase().contains(q) ?? false) ||
                  t.category.toLowerCase().contains(q),
            )
            .toList();
      }

      return transactions;
    } catch (e) {
      Logger.error('getTransactions', e);
      return [];
    }
  }

  Future<List<AccountTransaction>> getTodayTransactions() async {
    final start = AppTimezone.todayStartUtc();
    final end = AppTimezone.todayEndUtc();
    return getTransactions(startDate: start, endDate: end);
  }

  Future<List<AccountTransaction>> getMonthTransactions() async {
    final start = AppTimezone.monthStartUtc();
    final end = AppTimezone.monthEndUtc();
    return getTransactions(startDate: start, endDate: end);
  }

  Future<Map<String, double>> getMonthlySummary() async {
    final transactions = await getMonthTransactions();
    double totalIn = 0, totalOut = 0;
    for (final t in transactions) {
      if (t.type == 'in') {
        totalIn += t.amount;
      } else {
        totalOut += t.amount;
      }
    }
    return {
      'total_in': totalIn,
      'total_out': totalOut,
      'net': totalIn - totalOut,
    };
  }

  Future<void> addTransaction({
    required String accountId,
    required String type,
    required double amount,
    required String category,
    String? description,
  }) async {
    try {
      final user = _client.auth.currentUser;
      await _client.rpc(
        'add_account_transaction',
        params: {
          'p_account_id': accountId,
          'p_type': type,
          'p_amount': amount,
          'p_category': category,
          'p_description': description,
          'p_created_by': user?.id,
        },
      );
    } catch (e) {
      Logger.warning('addTransaction failed, queuing offline: $e');
      await _offlineService.queuePendingWrite({
        'table': 'account_transactions',
        'operation': 'insert',
        'data': {
          'account_id': accountId,
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
        },
      });
    }
  }

  Future<void> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? description,
  }) async {
    // Money out from source
    await addTransaction(
      accountId: fromAccountId,
      type: 'out',
      amount: amount,
      category: 'transfer',
      description: description ?? 'Transfer out',
    );

    // Money in to destination (with rollback on failure)
    try {
      await addTransaction(
        accountId: toAccountId,
        type: 'in',
        amount: amount,
        category: 'transfer',
        description: description ?? 'Transfer in',
      );
    } catch (e) {
      // Rollback: reverse the first transaction
      await addTransaction(
        accountId: fromAccountId,
        type: 'in',
        amount: amount,
        category: 'transfer',
        description: 'Rollback: failed transfer to account',
      );
      rethrow;
    }
  }

  Future<Map<String, double>> getTodaySummary() async {
    final transactions = await getTodayTransactions();
    double totalIn = 0, totalOut = 0;

    for (final t in transactions) {
      if (t.type == 'in') {
        totalIn += t.amount;
      } else {
        totalOut += t.amount;
      }
    }

    return {
      'total_in': totalIn,
      'total_out': totalOut,
      'net': totalIn - totalOut,
    };
  }

  Map<String, double> getCategoryBreakdown(
    List<AccountTransaction> transactions,
  ) {
    final breakdown = <String, double>{};
    for (final t in transactions) {
      final key = '${t.category}_${t.type}';
      breakdown[key] = (breakdown[key] ?? 0) + t.amount;
    }
    return breakdown;
  }
}
