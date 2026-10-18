import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sale.dart';

// ============================================
// GLOBAL CART STATE
// Persists across tab switches until sale is completed
// ============================================

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  /// Adds a line, or more of the same line. Same product at another price
  /// or rate (the box rate, an edited price) is its own line: merging put
  /// it on the first line's price (17 Oct 2026).
  void addItem(CartItem item) {
    final existing = state.indexWhere(
      (c) =>
          c.productId == item.productId &&
          (c.price - item.price).abs() < 0.005 &&
          (c.rateLabel ?? '') == (item.rateLabel ?? '') &&
          c.stockFactor == item.stockFactor &&
          c.discount == item.discount,
    );
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

  /// Puts a removed line back where it was (Undo).
  void insertItem(int index, CartItem item) {
    state = List.from(state)..insert(index.clamp(0, state.length), item);
  }

  /// Puts an edited line in place of the old one.
  void replaceItem(int index, CartItem item) {
    state = List.from(state)..[index] = item;
  }

  /// Sets a line's quantity (0 or less removes it).
  void setQty(int index, double qty) {
    if (qty <= 0) {
      removeItem(index);
      return;
    }
    state[index].qty = qty;
    state = List.from(state);
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
