import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sale.dart';

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

  /// Bill-level GST included in the line totals (before the bill discount).
  double get gstTotal => items.fold(0.0, (sum, item) => sum + item.gstAmount);
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

  /// Stock units consumed by one unit of this line (e.g. 12 for a box of 12
  /// of a product whose stock is counted in pieces). The database deducts
  /// qty × stockFactor (#22).
  final double stockFactor;

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
    double? stockFactor,
  }) : basePrice = basePrice ?? price,
       stockFactor = stockFactor ?? (unitType == 'pieces' ? 1.0 : piecesPerUnit.toDouble());

  double get discountAmount => (price * qty) * (discount / 100);
  double get total => (price * qty) - discountAmount;

  /// Profit after the line discount (purchasePrice is per line unit).
  double get profit => total - purchasePrice * qty;
  double get totalPieces => qty * stockFactor;

  DesktopCartItem copyWith({
    double? price,
    int? qty,
    double? purchasePrice,
    double? discount,
    String? rateLabel,
    String? tier,
  }) => DesktopCartItem(
    productId: productId,
    name: name,
    price: price ?? this.price,
    qty: qty ?? this.qty,
    unit: unit,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    gstRate: gstRate,
    hsnCode: hsnCode,
    tamilName: tamilName,
    discount: discount ?? this.discount,
    unitType: unitType,
    piecesPerUnit: piecesPerUnit,
    tier: tier ?? this.tier,
    basePrice: basePrice,
    rateLabel: rateLabel ?? this.rateLabel,
    stockFactor: stockFactor,
  );

  /// The line as stored on the sale.
  CartItem toCartItem({String? tier}) => CartItem(
    productId: productId,
    name: name,
    price: price,
    qty: qty,
    unit: unit,
    purchasePrice: purchasePrice,
    gstRate: gstRate,
    hsnCode: hsnCode,
    tamilName: tamilName,
    discount: discount,
    unitType: unitType,
    piecesPerUnit: piecesPerUnit,
    tier: tier ?? this.tier,
    rateLabel: rateLabel,
    stockFactor: stockFactor,
  );

  /// Rebuild a cart line from a saved sale line (edit sale).
  factory DesktopCartItem.fromCartItem(CartItem item) => DesktopCartItem(
    productId: item.productId,
    name: item.name,
    price: item.price,
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
    stockFactor: item.stockFactor,
  );

  /// Held-bill storage keeps every field, so a restored bill sells the same
  /// units at the same rate.
  Map<String, dynamic> toHeldJson() => {
    'product_id': productId,
    'name': name,
    'price': price,
    'qty': qty,
    'unit': unit,
    'purchase_price': purchasePrice,
    'gst_rate': gstRate,
    'hsn_code': hsnCode,
    'tamil_name': tamilName,
    'discount': discount,
    'unit_type': unitType,
    'pieces_per_unit': piecesPerUnit,
    'tier': tier,
    'base_price': basePrice,
    'rate_label': rateLabel,
    'stock_factor': stockFactor,
  };

  factory DesktopCartItem.fromHeldJson(Map<String, dynamic> m) => DesktopCartItem(
    productId: m['product_id'] as String,
    name: m['name'] as String,
    price: (m['price'] as num).toDouble(),
    qty: (m['qty'] as num).toInt(),
    unit: m['unit'] as String? ?? 'pcs',
    purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
    gstRate: (m['gst_rate'] as num?)?.toDouble() ?? 0,
    hsnCode: m['hsn_code'] as String?,
    tamilName: m['tamil_name'] as String?,
    discount: (m['discount'] as num?)?.toDouble() ?? 0,
    unitType: m['unit_type'] as String? ?? 'pieces',
    piecesPerUnit: (m['pieces_per_unit'] as num?)?.toInt() ?? 1,
    tier: m['tier'] as String? ?? 'normal',
    basePrice: (m['base_price'] as num?)?.toDouble(),
    rateLabel: m['rate_label'] as String?,
    stockFactor: (m['stock_factor'] as num?)?.toDouble(),
  );
  
  // GST getters (consistent with CartItem in sale.dart)
  double get gstAmount => total * gstRate / (100 + gstRate);
  double get taxableAmount => total - gstAmount;
  double get cgst => gstAmount / 2;
  double get sgst => gstAmount / 2;
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
      (c) => c.productId == item.productId && c.unitType == item.unitType && c.stockFactor == item.stockFactor,
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
  int _heldBillVersion = 0;
  int get heldBillVersion => _heldBillVersion;

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
    _heldBillVersion++;
    clearSession(_activeSessionIndex);
    _editingSale = null;
    state = List.from(state);
    return true;
  }

  bool restoreHeldBill(int index) {
    if (index < 0 || index >= heldBills.length) return false;
    final bill = heldBills.removeAt(index);
    _heldBillVersion++;
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
