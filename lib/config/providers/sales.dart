import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sale.dart';
import 'services.dart';

// ============================================
// SALES
// ============================================

final salesHistoryProvider = FutureProvider<List<Sale>>((ref) async {
  final service = ref.watch(saleServiceProvider);
  return service.getSalesHistory(limit: 500);
});
