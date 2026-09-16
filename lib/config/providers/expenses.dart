import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/expense.dart';
import 'services.dart';

// ============================================
// EXPENSES
// ============================================

final expensesProvider = FutureProvider<List<Expense>>((ref) async {
  final service = ref.watch(expenseServiceProvider);
  return service.getExpenses(limit: 100);
});
