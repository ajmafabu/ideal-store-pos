import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/sale.dart';

class HeldBill {
  final SaleSession session;
  final DateTime time;
  final Sale? editingSale;

  HeldBill({required this.session, required this.time, this.editingSale});
}

class SaleSession {
  final String id;
  final List<DesktopCartItem> items;
  String? customerId;
  String? customerName;
  double totalDiscount;
  String paymentMethod;
  bool isCredit;
  double amountPaid;
  DateTime createdAt;

  SaleSession({
    required this.id,
    List<DesktopCartItem>? items,
    this.customerId,
    this.customerName,
    this.totalDiscount = 0,
    this.paymentMethod = 'cash',
    this.isCredit = false,
    this.amountPaid = 0,
    DateTime? createdAt,
  }) : items = items ?? [],
       createdAt = createdAt ?? DateTime.now();

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.total);
  double get total => subtotal - totalDiscount;
  int get itemCount => items.length;
  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);
}

class DesktopCartItem {
  final String productId;
  final String name;
  double price;
  int qty;
  final String unit;
  final double purchasePrice;
  final double gstRate;
  final String? hsnCode;
  final String? tamilName;
  double discount;
  final String unitType;
  final int piecesPerUnit;
  final String tier;
  final double basePrice;
  final String? rateLabel;

  DesktopCartItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    required this.unit,
    this.purchasePrice = 0,
    this.gstRate = 0,
    this.hsnCode,
    this.tamilName,
    this.discount = 0,
    this.unitType = 'pieces',
    this.piecesPerUnit = 1,
    this.tier = 'normal',
    double? basePrice,
    this.rateLabel,
  }) : basePrice = basePrice ?? price;

  double get discountAmount => (price * qty) * (discount / 100);
  double get total => (price * qty) - discountAmount;
  double get profit => (price - purchasePrice) * qty;
  int get totalPieces => unitType == 'pieces' ? qty : qty * piecesPerUnit;
}

class DesktopBillingNotifier extends Notifier<List<SaleSession>> {
  int _activeSessionIndex = 0;
  int _sessionCounter = 0;
  Sale? _editingSale;

  @override
  List<SaleSession> build() {
    _sessionCounter++;
    return [SaleSession(id: 'sale_$_sessionCounter')];
  }

  int get activeSessionIndex => _activeSessionIndex;
  SaleSession get activeSession => state[_activeSessionIndex];
  Sale? get editingSale => _editingSale;

  void setEditingSale(Sale? sale) {
    _editingSale = sale;
    state = List.from(state);
  }

  void clearEditingSale() {
    _editingSale = null;
    state = List.from(state);
  }

  void switchSession(int index) {
    if (index >= 0 && index < state.length) {
      _activeSessionIndex = index;
      state = List.from(state);
    }
  }

  void createQuickSale() {
    _sessionCounter++;
    state = [...state, SaleSession(id: 'quick_$_sessionCounter')];
    _activeSessionIndex = state.length - 1;
  }

  void closeSession(int index) {
    if (state.length <= 1) return;
    state = List.from(state)..removeAt(index);
    if (_activeSessionIndex >= state.length) {
      _activeSessionIndex = state.length - 1;
    }
    state = List.from(state);
  }

  void addItem(DesktopCartItem item) {
    final session = state[_activeSessionIndex];
    final existing = session.items.indexWhere(
      (c) => c.productId == item.productId,
    );
    if (existing >= 0) {
      session.items[existing].qty += item.qty;
    } else {
      session.items.add(item);
    }
    state = List.from(state);
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

  void updateItem(int index, DesktopCartItem item) {
    final session = state[_activeSessionIndex];
    if (index >= 0 && index < session.items.length) {
      session.items[index] = item;
      state = List.from(state);
    }
  }

  void removeItem(int index) {
    state[_activeSessionIndex].items.removeAt(index);
    state = List.from(state);
  }

  void insertItem(int index, DesktopCartItem item) {
    final session = state[_activeSessionIndex];
    if (index >= 0 && index <= session.items.length) {
      session.items.insert(index, item);
      state = List.from(state);
    }
  }

  void mergeIntoActive(int sourceIndex) {
    if (sourceIndex == _activeSessionIndex) return;
    final source = state[sourceIndex];
    final target = state[_activeSessionIndex];
    for (final item in source.items) {
      target.items.add(item);
    }
    source.items.clear();
    state = List.from(state);
  }

  void setCustomer(String? id, String? name) {
    state[_activeSessionIndex].customerId = id;
    state[_activeSessionIndex].customerName = name;
    state = List.from(state);
  }

  void clearSession(int index) {
    state[index].items.clear();
    state[index].totalDiscount = 0;
    state[index].customerId = null;
    state[index].customerName = null;
    state[index].paymentMethod = 'cash';
    state[index].isCredit = false;
    state[index].amountPaid = 0;
    state = List.from(state);
  }

  void updateAllItemPrices(String tier, Map<String, double> sellingPrices) {
    final session = state[_activeSessionIndex];
    for (final item in session.items) {
      final base = sellingPrices[item.productId] ?? item.basePrice;
      switch (tier) {
        case 'wholesale':
          item.price = double.parse((base * 0.99).toStringAsFixed(2));
          break;
        case 'bulk':
          item.price = double.parse((base * 0.98).toStringAsFixed(2));
          break;
        default:
          item.price = base;
      }
    }
    state = List.from(state);
  }

  void updateAllItemPricesFromCurrent(String tier) {
    final session = state[_activeSessionIndex];
    for (final item in session.items) {
      switch (tier) {
        case 'wholesale':
          item.price = double.parse((item.basePrice * 0.99).toStringAsFixed(2));
          break;
        case 'bulk':
          item.price = double.parse((item.basePrice * 0.98).toStringAsFixed(2));
          break;
        default:
          item.price = item.basePrice;
      }
    }
    state = List.from(state);
  }

  void resetAfterSale(int sessionIndex) {
    clearSession(sessionIndex);
  }

  final List<HeldBill> heldBills = [];

  bool autoHoldCurrentSession() {
    final session = state[_activeSessionIndex];
    if (session.items.isEmpty) return false;
    heldBills.add(HeldBill(
      session: SaleSession(
        id: session.id,
        items: List<DesktopCartItem>.from(session.items),
        customerId: session.customerId,
        customerName: session.customerName,
        totalDiscount: session.totalDiscount,
        paymentMethod: session.paymentMethod,
        isCredit: session.isCredit,
        amountPaid: session.amountPaid,
      ),
      time: DateTime.now(),
      editingSale: _editingSale,
    ));
    clearSession(_activeSessionIndex);
    _editingSale = null;
    state = List.from(state);
    return true;
  }

  bool restoreHeldBill(int index) {
    if (index < 0 || index >= heldBills.length) return false;
    final bill = heldBills.removeAt(index);
    clearSession(_activeSessionIndex);
    for (final item in bill.session.items) {
      state[_activeSessionIndex].items.add(item);
    }
    state[_activeSessionIndex].customerId = bill.session.customerId;
    state[_activeSessionIndex].customerName = bill.session.customerName;
    state[_activeSessionIndex].totalDiscount = bill.session.totalDiscount;
    state[_activeSessionIndex].paymentMethod = bill.session.paymentMethod;
    state[_activeSessionIndex].isCredit = bill.session.isCredit;
    state[_activeSessionIndex].amountPaid = bill.session.amountPaid;
    _editingSale = bill.editingSale;
    state = List.from(state);
    return true;
  }
}

final desktopBillingProvider =
    NotifierProvider<DesktopBillingNotifier, List<SaleSession>>(
      DesktopBillingNotifier.new,
    );
