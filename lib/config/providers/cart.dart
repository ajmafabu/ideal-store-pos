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

  void updateQty(int index, double delta) {
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
    // copyWith keeps unit, tier and stock factor
    state[index] = state[index].copyWith(price: newPrice);
    state = List.from(state);
  }

  void clear() {
    state = [];
  }

  /// Puts a held bill's lines back exactly as they were (addItem would merge
  /// lines of the same product).
  void replaceAll(List<CartItem> items) {
    state = List.of(items);
  }
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);
