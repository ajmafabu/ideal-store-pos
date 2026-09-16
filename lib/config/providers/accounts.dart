import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/account.dart';
import 'services.dart';

// ============================================
// ACCOUNTS
// ============================================

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final service = ref.watch(accountServiceProvider);
  await service.ensureAccountsExist();
  return service.getAccounts();
});

final todayTransactionsProvider = FutureProvider<List<AccountTransaction>>((
  ref,
) async {
  final service = ref.watch(accountServiceProvider);
  return service.getTodayTransactions();
});

final monthlySummaryProvider = FutureProvider<Map<String, double>>((ref) async {
  final service = ref.watch(accountServiceProvider);
  return service.getMonthlySummary();
});

final dateRangeTransactionsProvider =
    FutureProvider.family<
      List<AccountTransaction>,
      ({DateTime start, DateTime end})
    >((ref, dates) async {
      final service = ref.watch(accountServiceProvider);
      return service.getTransactions(
        startDate: dates.start,
        endDate: dates.end,
      );
    });
