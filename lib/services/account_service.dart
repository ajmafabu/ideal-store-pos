import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/account.dart';
import '../utils/logger.dart';
import '../utils/app_timezone.dart';
import '../utils/network_errors.dart';
import 'offline_service.dart';
import '../utils/search_term.dart';

/// Cash book access.
///
/// Since app 1.1.0 sales, purchases, expenses, payments and refunds post
/// themselves to the cash book inside the database (triggers), so this
/// service only handles manual entries, transfers and reading. Balances are
/// kept equal to the journal by a database trigger (#10, #20).
class AccountService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  /// Page size for exports; PostgREST caps a single response at 1,000 rows.
  static const _pageSize = 1000;

  AccountService({SupabaseClient? client, OfflineService? offlineService})
    : _client = client ?? Supabase.instance.client,
      _offlineService = offlineService ?? OfflineService();

  Future<List<Account>> getAccounts() async {
    try {
      final res = await _client.from('accounts').select().order('created_at');
      final list = (res as List).map((a) => Account.fromJson(a)).toList();
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
    final accounts = await getAccounts();
    for (final a in accounts) {
      if (a.accountType == type) return a;
    }
    return null;
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
    if (accounts.isEmpty && !(await _offlineService.isOnline())) return;
    final hasCash = accounts.any((a) => a.accountType == 'cash');
    final hasBank = accounts.any((a) => a.accountType == 'bank');
    try {
      if (!hasCash) await createAccount('Cash in Hand', 'cash');
      if (!hasBank) await createAccount('Bank Account', 'bank');
    } catch (e) {
      Logger.warning('ensureAccountsExist: $e');
    }
  }

  /// Merges duplicate cash/bank accounts in one database transaction:
  /// signed balances and the full journal history are kept (#20).
  Future<int> mergeDuplicateAccounts() async {
    try {
      final res = await _client.rpc('merge_duplicate_accounts');
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      Logger.warning('mergeDuplicateAccounts: $e');
      return 0;
    }
  }

  DateTime _toUtc(DateTime d) => d.isUtc ? d : d.subtract(AppTimezone.localOffset);

  /// One page of journal rows (newest first) — for the on-screen list.
  Future<List<AccountTransaction>> getTransactions({
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      var query = _client.from('account_transactions').select();
      if (accountId != null) query = query.eq('account_id', accountId);
      if (startDate != null) query = query.gte('created_at', _toUtc(startDate).toIso8601String());
      if (endDate != null) query = query.lt('created_at', _toUtc(endDate).toIso8601String());
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchTerm(searchQuery);
        if (q.isNotEmpty) {
          query = query.or('description.ilike.%$q%,category.ilike.%$q%');
        }
      }
      final res = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return (res as List).map((t) => AccountTransaction.fromJson(t)).toList();
    } catch (e) {
      Logger.error('getTransactions', e);
      return [];
    }
  }

  /// Every journal row in the period, fetched page by page — for PDF/CSV
  /// exports, which used to stop silently at 100 rows (#20).
  Future<List<AccountTransaction>> getAllTransactions({
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final all = <AccountTransaction>[];
    var offset = 0;
    while (true) {
      final page = await getTransactions(
        accountId: accountId,
        startDate: startDate,
        endDate: endDate,
        limit: _pageSize,
        offset: offset,
      );
      all.addAll(page);
      if (page.length < _pageSize) break;
      offset += _pageSize;
    }
    return all;
  }

  Future<List<AccountTransaction>> getTodayTransactions() =>
      getTransactions(startDate: AppTimezone.todayStartUtc(), endDate: AppTimezone.todayEndUtc());

  Future<List<AccountTransaction>> getMonthTransactions() =>
      getTransactions(startDate: AppTimezone.monthStartUtc(), endDate: AppTimezone.monthEndUtc());

  /// Totals computed by the database: no row cap, transfers between your
  /// own accounts reported separately instead of inflating in/out (#20).
  Future<AccountSummary> getSummary({
    DateTime? startDate,
    DateTime? endDate,
    String? accountId,
  }) async {
    try {
      final res = await _client.rpc('get_account_summary', params: {
        'p_start': startDate == null ? null : _toUtc(startDate).toIso8601String(),
        'p_end': endDate == null ? null : _toUtc(endDate).toIso8601String(),
        'p_account_id': accountId,
      });
      final row = (res is List && res.isNotEmpty) ? res.first : res;
      if (row is Map<String, dynamic>) return AccountSummary.fromJson(row);
    } catch (e) {
      Logger.error('getSummary', e);
    }
    return const AccountSummary();
  }

  Future<Map<String, double>> getMonthlySummary() async =>
      (await getSummary(startDate: AppTimezone.monthStartUtc(), endDate: AppTimezone.monthEndUtc())).toLegacyMap();

  Future<Map<String, double>> getTodaySummary() async =>
      (await getSummary(startDate: AppTimezone.todayStartUtc(), endDate: AppTimezone.todayEndUtc())).toLegacyMap();

  /// Manual cash-book entry (opening balance, owner's drawings, other income
  /// or expense). Business documents post themselves — never call this for a
  /// sale/purchase/expense/payment.
  Future<void> addTransaction({
    required String accountId,
    required String type,
    required double amount,
    required String category,
    String? description,
  }) async {
    try {
      await _client.rpc(
        'add_account_transaction',
        params: {
          'p_account_id': accountId,
          'p_type': type,
          'p_amount': amount,
          'p_category': category,
          'p_description': description,
          'p_created_by': _client.auth.currentUser?.id,
          'p_source': 'manual',
        },
      );
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      Logger.warning('addTransaction offline, queuing: $e');
      // queued as a plain insert: the database's balance trigger applies it
      await _offlineService.queuePendingWrite({
        'table': 'account_transactions',
        'operation': 'insert',
        'data': {
          'id': const Uuid().v4(),
          'account_id': accountId,
          'type': type,
          'amount': amount,
          'category': category,
          'description': description,
          'source': 'manual',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      });
    }
  }

  /// Atomic transfer between two of your own accounts (one database call).
  Future<void> transferBetweenAccounts({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    String? description,
  }) async {
    if (fromAccountId == toAccountId) {
      throw Exception('Choose two different accounts');
    }
    await _client.rpc(
      'transfer_between_accounts',
      params: {
        'p_from_account_id': fromAccountId,
        'p_to_account_id': toAccountId,
        'p_amount': amount,
        'p_description': description ?? 'Transfer',
        'p_created_by': _client.auth.currentUser?.id,
      },
    );
  }

  /// Per-account check that balance = journal (difference = opening balance
  /// or historical drift from older app versions).
  Future<List<Map<String, dynamic>>> getReconciliation() async {
    try {
      final res = await _client.rpc('get_account_reconciliation');
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      Logger.error('getReconciliation', e);
      return [];
    }
  }

  Map<String, double> getCategoryBreakdown(
    List<AccountTransaction> transactions,
  ) {
    final breakdown = <String, double>{};
    for (final t in transactions) {
      if (t.isTransfer) continue;
      final key = '${t.category}_${t.type}';
      breakdown[key] = (breakdown[key] ?? 0) + t.amount;
    }
    return breakdown;
  }
}
