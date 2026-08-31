import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense.dart';
import '../utils/logger.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'offline_service.dart';

class ExpenseService {
  final SupabaseClient _client;
  final AccountService _accountService;
  final OfflineService _offlineService;

  ExpenseService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _accountService = accountService ?? AccountService(),
       _offlineService = offlineService ?? OfflineService();

  Future<Expense?> createExpense(
    Expense expense, {
    String paymentMethod = 'cash',
  }) async {
    try {
      final response = await _client
          .from('expenses')
          .insert(expense.toInsertJson())
          .select()
          .single();

      final createdExpense = Expense.fromJson(response);

      // Wire to accounts: expense = Money Out
      try {
        final accounts = await _accountService.getAccounts();
        if (accounts.isEmpty) {
          await _accountService.ensureAccountsExist();
        }
        final refreshed = await _accountService.getAccounts();
        final accountType =
            paymentMethod == 'upi' ||
                paymentMethod == 'digital' ||
                paymentMethod == 'bank'
            ? 'bank'
            : 'cash';
        final account = refreshed.firstWhere(
          (a) => a.accountType == accountType,
          orElse: () => refreshed.first,
        );
        await _accountService.addTransaction(
          accountId: account.id,
          type: 'out',
          amount: expense.amount,
          category: 'expense',
          description: expense.category,
        );
        Logger.info(
          'Account entry: Expense Rs${expense.amount} (${expense.category}) → $accountType',
        );
      } catch (e) {
        Logger.error('Account entry failed for expense', e);
      }

      AuditService().log(
        action: 'create',
        entityType: 'expense',
        entityId: createdExpense.id,
        newData: expense.toInsertJson(),
        description: 'Expense Rs.${expense.amount} (${expense.category})',
      );

      return createdExpense;
    } catch (e) {
      Logger.error('createExpense', e);
      // Queue for offline sync
      await _offlineService.queuePendingWrite({
        'table': 'expenses',
        'operation': 'insert',
        'data': expense.toInsertJson(),
      });
      // Queue account entry (Money Out) for when we come back online
      try {
        final accounts = await _accountService.getAccounts();
        if (accounts.isNotEmpty) {
          final accountType =
              (paymentMethod == 'upi' ||
                  paymentMethod == 'digital' ||
                  paymentMethod == 'bank')
              ? 'bank'
              : 'cash';
          final account = accounts.firstWhere(
            (a) => a.accountType == accountType,
            orElse: () => accounts.first,
          );
          await _accountService.addTransaction(
            accountId: account.id,
            type: 'out',
            amount: expense.amount,
            category: 'expense',
            description: expense.category,
          );
        }
      } catch (accountError) {
        Logger.error(
          'Account entry also failed for offline expense',
          accountError,
        );
      }
      Logger.info('Expense queued for offline sync');
      return expense;
    }
  }

  Future<List<Expense>> getExpenses({int limit = 50}) async {
    final online = await _offlineService.isOnline();
    if (!online) {
      try {
        final cached = _offlineService.getCachedExpenses();
        if (cached.isNotEmpty) {
          return cached.map((e) => Expense.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to read cached expenses (offline): $e');
      }
      return [];
    }

    try {
      final response = await _client
          .from('expenses')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (response as List).map((e) => Expense.fromJson(e)).toList();

      // Cache for offline
      try {
        await _offlineService.cacheExpenses(
          list.map((e) => e.toJson()).toList(),
        );
      } catch (e) {
        Logger.warning('Failed to cache expenses for offline: $e');
      }

      return list;
    } catch (e) {
      // Offline fallback
      try {
        final cached = _offlineService.getCachedExpenses();
        if (cached.isNotEmpty) {
          Logger.info('Loaded ${cached.length} expenses from offline cache');
          return cached.map((e) => Expense.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning('Failed to load expenses from offline cache: $e');
      }
      return [];
    }
  }

  Future<double> getTotalExpenses() async {
    try {
      final response = await _client.from('expenses').select('amount');
      double total = 0;
      for (final e in response as List) {
        total += (e['amount'] as num).toDouble();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      final expenseData = await _client
          .from('expenses')
          .select('amount, category, payment_method')
          .eq('id', id)
          .maybeSingle();

      await _client.from('expenses').delete().eq('id', id);

      AuditService().log(
        action: 'delete',
        entityType: 'expense',
        entityId: id,
        oldData: expenseData,
        description: 'Deleted expense: ${expenseData?['category'] ?? id}',
      );

      if (expenseData != null) {
        try {
          final accounts = await _accountService.getAccounts();
          if (accounts.isNotEmpty) {
            // Determine correct account to reverse to
            final paymentMethod =
                expenseData['payment_method'] as String? ?? 'cash';
            final accountType =
                (paymentMethod == 'upi' ||
                    paymentMethod == 'digital' ||
                    paymentMethod == 'bank')
                ? 'bank'
                : 'cash';
            final account = accounts.firstWhere(
              (a) => a.accountType == accountType,
              orElse: () => accounts.first,
            );
            await _accountService.addTransaction(
              accountId: account.id,
              type: 'in',
              amount: (expenseData['amount'] as num?)?.toDouble() ?? 0,
              category: 'expense_reversal',
              description: 'Reversed: ${expenseData['category'] ?? 'expense'}',
            );
            Logger.info(
              'Account reversal: Expense Rs${expenseData['amount']} → $accountType',
            );
          }
        } catch (e) {
          Logger.error('Failed to reverse account entry for expense', e);
        }
      }
    } catch (e) {
      Logger.error('deleteExpense', e);
    }
  }
}
