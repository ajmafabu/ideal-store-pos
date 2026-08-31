import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/purchase.dart';
import '../models/supplier.dart';

class PurchaseSession {
  final String id;
  final List<PurchaseItem> items;
  Supplier? supplier;
  String paymentMethod;
  bool isCredit;
  double discount;
  double roundOff;
  double extraCharges;

  PurchaseSession({
    required this.id,
    List<PurchaseItem>? items,
    this.supplier,
    this.paymentMethod = 'cash',
    this.isCredit = false,
    this.discount = 0,
    this.roundOff = 0,
    this.extraCharges = 0,
  }) : items = items ?? [];

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.total);
  double get totalBeforeDiscount => subtotal;
  double get totalAfterDiscount => subtotal - discount + extraCharges;
  int get itemCount => items.length;
  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);
}

class DesktopPurchaseNotifier extends Notifier<List<PurchaseSession>> {
  int _activeSessionIndex = 0;

  int get activeSessionIndex => _activeSessionIndex;

  @override
  List<PurchaseSession> build() => [PurchaseSession(id: 'PURCHASE 1')];

  void switchSession(int index) {
    if (index >= 0 && index < state.length) {
      _activeSessionIndex = index;
      state = List.from(state);
    }
  }

  void createQuickPurchase() {
    state = [...state, PurchaseSession(id: 'PURCHASE ${state.length + 1}')];
    _activeSessionIndex = state.length - 1;
    state = List.from(state);
  }

  void closeSession(int index) {
    if (state.length <= 1) return;
    state.removeAt(index);
    if (_activeSessionIndex >= state.length) {
      _activeSessionIndex = state.length - 1;
    }
    state = List.from(state);
  }

  void addItem(PurchaseItem item) {
    final session = state[_activeSessionIndex];
    final existing = session.items.indexWhere(
      (c) => c.productId == item.productId && c.batchNumber == item.batchNumber,
    );
    if (existing >= 0) {
      session.items[existing].qty += item.qty;
    } else {
      session.items.add(item);
    }
    state = List.from(state);
  }

  void updateItem(int index, PurchaseItem item) {
    final session = state[_activeSessionIndex];
    if (index >= 0 && index < session.items.length) {
      session.items[index] = item;
      state = List.from(state);
    }
  }

  void updateItemQty(int index, int qty) {
    final session = state[_activeSessionIndex];
    if (qty <= 0) {
      session.items.removeAt(index);
    } else {
      session.items[index].qty = qty;
    }
    state = List.from(state);
  }

  void removeItem(int index) {
    state[_activeSessionIndex].items.removeAt(index);
    state = List.from(state);
  }

  void setSupplier(Supplier? supplier) {
    state[_activeSessionIndex].supplier = supplier;
    state = List.from(state);
  }

  void setDiscount(double discount) {
    state[_activeSessionIndex].discount = discount;
    state = List.from(state);
  }

  void setPaymentMethod(String method) {
    state[_activeSessionIndex].paymentMethod = method;
    state[_activeSessionIndex].isCredit = method == 'credit';
    state = List.from(state);
  }

  void clearSession(int index) {
    state[index].items.clear();
    state[index].discount = 0;
    state[index].supplier = null;
    state[index].paymentMethod = 'cash';
    state[index].isCredit = false;
    state = List.from(state);
  }

  void resetAfterPurchase() {
    final session = state[_activeSessionIndex];
    session.items.clear();
    session.discount = 0;
    session.supplier = null;
    session.paymentMethod = 'cash';
    session.isCredit = false;
    state = List.from(state);
  }
}

final desktopPurchaseProvider =
    NotifierProvider<DesktopPurchaseNotifier, List<PurchaseSession>>(
      DesktopPurchaseNotifier.new,
    );
