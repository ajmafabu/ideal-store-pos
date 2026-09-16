import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/purchase.dart';
import 'services.dart';

// ============================================
// PURCHASES
// ============================================

final purchasesProvider = FutureProvider<List<Purchase>>((ref) async {
  final service = ref.watch(purchaseServiceProvider);
  return service.getPurchases(limit: 500);
});
