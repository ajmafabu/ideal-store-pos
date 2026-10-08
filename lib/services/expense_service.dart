import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense.dart';
import '../models/sale.dart' show isUuid, newDocumentId;
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import '../utils/payment_methods.dart';
import 'account_service.dart';
import 'audit_service.dart';
import 'offline_service.dart';

class ExpenseService {
  final SupabaseClient _client;
  final OfflineService _offlineService;

  ExpenseService({
    SupabaseClient? client,
    AccountService? accountService,
    OfflineService? offlineService,
  }) : _client = client ?? Supabase.instance.client,
       _offlineService = offlineService ?? OfflineService();

  /// Saves an expense. The database posts it to cash or bank according to
  /// its payment method (#10, #12); a server rejection is thrown, only a
  /// network failure queues it (with a stable id).
  Future<Expense?> createExpense(
    Expense expense, {
    String? paymentMethod,
  }) async {
    final id = isUuid(expense.id) ? expense.id : newDocumentId();
    final data = Expense(
      id: id,
      category: expense.category,
      description: expense.description,
      amount: expense.amount,
      createdBy: expense.createdBy,
      createdAt: expense.createdAt,
      paymentMethod: PaymentMethods.normalize(paymentMethod ?? expense.paymentMethod),
    ).toInsertJson();
    try {
      final response = await _client.from('expenses').insert(data).select().single();
      final createdExpense = Expense.fromJson(response);
      AuditService().log(
        action: 'create',
        entityType: 'expense',
        entityId: createdExpense.id,
        newData: data,
        description: 'Expense Rs.${expense.amount} (${expense.category})',
      );
      return createdExpense;
    } catch (e) {
      Logger.error('createExpense', e);
      if (!isNetworkError(e)) rethrow;
      await _offlineService.queuePendingWrite({
        'table': 'expenses',
        'operation': 'insert',
        'data': data,
      });
      return Expense.fromJson({...data, 'id': id});
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
    double total = 0;
    var offset = 0;
    try {
      while (true) {
        final page = await _client.from('expenses').select('amount').order('id').range(offset, offset + 999);
        for (final e in page as List) {
          total += (e['amount'] as num?)?.toDouble() ?? 0;
        }
        if ((page as List).length < 1000) break;
        offset += 1000;
      }
    } catch (e) {
      Logger.warning('getTotalExpenses: $e');
    }
    return total;
  }

  /// Deletes an expense; the database reverses its cash-book entry from the
  /// account it was paid from. Errors are thrown so the screen can say so.
  Future<void> deleteExpense(String id) async {
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
  }
}
