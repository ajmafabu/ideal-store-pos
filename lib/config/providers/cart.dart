import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sale.dart';

// ============================================
// GLOBAL CART STATE
// Persists across tab switches until sale is completed
// ============================================

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  void addItem(CartItem item) {
    final existing = state.indexWhere((c) => c.productId == item.productId);
    if (existing >= 0) {
      state[existing].qty += item.qty;
      state = List.from(state);
    } else {
      state = [...state, item];
    }
  }

  void removeItem(int index) {
    state = List.from(state)..removeAt(index);
  }

  void updateQty(int index, int delta) {
    final item = state[index];
    final newQty = item.qty + delta;
    if (newQty <= 0) {
      state = List.from(state)..removeAt(index);
    } else {
      item.qty = newQty;
      state = List.from(state);
    }
  }

  void updateDiscount(int index, double discount) {
    state[index].discount = discount;
    state = List.from(state);
  }

  void updateItemPrice(int index, double newPrice) {
    final item = state[index];
    state[index] = CartItem(
      productId: item.productId,
      name: item.name,
      price: newPrice,
      qty: item.qty,
      unit: item.unit,
      purchasePrice: item.purchasePrice,
      gstRate: item.gstRate,
      hsnCode: item.hsnCode,
      tamilName: item.tamilName,
      discount: item.discount,
      unitType: item.unitType,
      piecesPerUnit: item.piecesPerUnit,
      tier: item.tier,
      rateLabel: item.rateLabel,
    );
    state = List.from(state);
  }

  void clear() {
    state = [];
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
