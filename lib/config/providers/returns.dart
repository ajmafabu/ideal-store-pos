import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/purchase_order.dart';
import 'services.dart';

// ============================================
// RETURNS & DAMAGED
// ============================================

final returnsProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(returnServiceProvider).getReturns(limit: 100);
});

final damagedProvider = FutureProvider<List<dynamic>>((ref) async {
  return ref.watch(damagedServiceProvider).getDamaged(limit: 100);
});

// ============================================
// PURCHASE ORDERS
// ============================================

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  return ref.watch(purchaseOrderServiceProvider).getPurchaseOrders(limit: 100);
});
