import 'package:uuid/uuid.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool isUuid(String? s) => s != null && _uuidPattern.hasMatch(s);

/// A fresh id for a document created on this device. The same id is used
/// online and offline, so a sale saved twice (timeout + offline retry) is
/// recognised by the database as one sale (#5).
String newDocumentId() => const Uuid().v4();

double _d(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _i(dynamic v, [int fallback = 0]) {
  if (v is num) return v.round();
  if (v is String) return (double.tryParse(v) ?? fallback).round();
  return fallback;
}

class CartItem {
  final String productId;
  final String name;
  final double price;
  /// Decimal for loose goods sold by weight (1.5 kg).
  double qty;
  final String unit;
  final double purchasePrice;
  final double gstRate;
  final String? hsnCode;
  final String? tamilName;
  double discount;
  final String unitType;
  final int piecesPerUnit;
  final String tier;
  final String? rateLabel;

  /// Stock units consumed by one unit of this line, e.g. 12 when a box of 12
  /// of a "pieces" product is sold. Sent to the database, which deducts
  /// qty × stockFactor (#22).
  final double stockFactor;

  /// True FIFO cost of the line, set by the database on save.
  final double? costTotal;

  CartItem({
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
    this.rateLabel,
    double? stockFactor,
    this.costTotal,
  }) : stockFactor = stockFactor ?? (unitType == 'pieces' ? 1.0 : piecesPerUnit.toDouble());

  /// Stock factor for a line in [lineUnitType] of a product whose stock is
  /// kept in [productUnitType] (pieces_per_unit of each).
  static double stockFactorFor({
    required String lineUnitType,
    required int linePiecesPerUnit,
    required String productUnitType,
    required int productPiecesPerUnit,
  }) {
    final lineFactor = lineUnitType == 'pieces' ? 1 : (linePiecesPerUnit < 1 ? 1 : linePiecesPerUnit);
    final productFactor =
        productUnitType == 'pieces' ? 1 : (productPiecesPerUnit < 1 ? 1 : productPiecesPerUnit);
    return lineFactor / productFactor;
  }

  double get discountAmount => (price * qty) * (discount / 100);
  double get total => (price * qty) - discountAmount;

  /// Line profit after the line discount (bill-level discount is applied in
  /// sale totals). Uses the database FIFO cost when known.
  double get profit => total - (costTotal ?? purchasePrice * qty);
  double get gstAmount => total * gstRate / (100 + gstRate);
  double get taxableAmount => total - gstAmount;
  double get priceExcludingGst => total - gstAmount;
  double get cgst => gstAmount / 2;
  double get sgst => gstAmount / 2;
  double get totalPieces => qty * stockFactor;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'price': price,
    'qty': qty,
    'unit': unit,
    'total': double.parse(total.toStringAsFixed(2)),
    'purchase_price': purchasePrice,
    'gst_rate': gstRate,
    'hsn_code': hsnCode,
    'tamil_name': tamilName,
    'discount': discount,
    'discount_amount': double.parse(discountAmount.toStringAsFixed(2)),
    'unit_type': unitType,
    'pieces_per_unit': piecesPerUnit,
    'stock_factor': stockFactor,
    'tier': tier,
    'rate_label': rateLabel,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final unitType = json['unit_type'] as String? ?? 'pieces';
    final ppu = _i(json['pieces_per_unit'], 1);
    return CartItem(
      productId: json['product_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Item',
      price: _d(json['price']),
      qty: _d(json['qty']),
      unit: json['unit'] as String? ?? 'pcs',
      purchasePrice: _d(json['purchase_price']),
      gstRate: _d(json['gst_rate']),
      hsnCode: json['hsn_code'] as String?,
      tamilName: json['tamil_name'] as String?,
      discount: _d(json['discount']),
      unitType: unitType,
      piecesPerUnit: ppu,
      tier: json['tier'] as String? ?? 'normal',
      rateLabel: json['rate_label'] as String?,
      stockFactor: json['stock_factor'] != null ? _d(json['stock_factor'], 1) : null,
      costTotal: json['cost_total'] != null ? _d(json['cost_total']) : null,
    );
  }

  CartItem copyWith({double? price, double? qty, double? discount, double? purchasePrice}) => CartItem(
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
    tier: tier,
    rateLabel: rateLabel,
    stockFactor: stockFactor,
  );
}

class Sale {
  final String id;
  final List<CartItem> items;
  final double totalAmount;
  final double discount;
  final double totalDiscount;
  final double finalAmount;
  final double roundOff;
  final String paymentMethod;
  final String createdBy;
  final DateTime createdAt;
  final String? customerId;
  final bool isCredit;
  final double amountPaid;
  final double dueAmount;
  final double cashAmount;
  final double digitalAmount;
  final String? customerName;
  final DateTime? dueDate;
  final double extraCharges;
  final double igstAmount;
  final double cgstAmount;
  final double sgstAmount;
  final bool taxExempt;

  /// Sequential printable number assigned by the database (#19).
  final int? invoiceNo;
  final double? taxableAmount;

  Sale({
    required this.id,
    required this.items,
    required this.totalAmount,
    this.discount = 0,
    this.totalDiscount = 0,
    required this.finalAmount,
    this.roundOff = 0,
    this.paymentMethod = 'cash',
    required this.createdBy,
    required this.createdAt,
    this.customerId,
    this.isCredit = false,
    this.amountPaid = 0,
    this.dueAmount = 0,
    this.cashAmount = 0,
    this.digitalAmount = 0,
    this.customerName,
    this.dueDate,
    this.extraCharges = 0,
    this.igstAmount = 0,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.taxExempt = false,
    this.invoiceNo,
    this.taxableAmount,
  });

  double get taxTotal => cgstAmount + sgstAmount + igstAmount;

  /// What to print as the invoice number: the database number when synced,
  /// otherwise a short form of the id (offline bills).
  String get invoiceLabel =>
      invoiceNo != null ? invoiceNo.toString() : (id.length >= 8 ? id.substring(0, 8).toUpperCase() : id);

  Sale copyWith({String? customerName, DateTime? dueDate}) {
    return Sale(
      id: id,
      items: items,
      totalAmount: totalAmount,
      discount: discount,
      totalDiscount: totalDiscount,
      finalAmount: finalAmount,
      roundOff: roundOff,
      paymentMethod: paymentMethod,
      createdBy: createdBy,
      createdAt: createdAt,
      customerId: customerId,
      isCredit: isCredit,
      amountPaid: amountPaid,
      dueAmount: dueAmount,
      cashAmount: cashAmount,
      digitalAmount: digitalAmount,
      customerName: customerName ?? this.customerName,
      dueDate: dueDate ?? this.dueDate,
      extraCharges: extraCharges,
      igstAmount: igstAmount,
      cgstAmount: cgstAmount,
      sgstAmount: sgstAmount,
      taxExempt: taxExempt,
      invoiceNo: invoiceNo,
      taxableAmount: taxableAmount,
    );
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final itemsList = <CartItem>[];
    for (final e in (json['items'] as List?) ?? const []) {
      if (e is Map) {
        try {
          itemsList.add(CartItem.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          // one malformed line must not hide the whole sale
        }
      }
    }

    return Sale(
      id: json['id'].toString(),
      items: itemsList,
      totalAmount: _d(json['total_amount']),
      discount: _d(json['discount']),
      totalDiscount: _d(json['total_discount']),
      finalAmount: _d(json['final_amount']),
      roundOff: _d(json['round_off']),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      createdBy: json['created_by'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      customerId: json['customer_id'] as String?,
      isCredit: json['is_credit'] as bool? ?? false,
      amountPaid: _d(json['amount_paid']),
      dueAmount: _d(json['due_amount']),
      cashAmount: _d(json['cash_amount']),
      digitalAmount: _d(json['digital_amount']),
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
      extraCharges: _d(json['extra_charges']),
      igstAmount: _d(json['igst_amount']),
      cgstAmount: _d(json['cgst_amount']),
      sgstAmount: _d(json['sgst_amount']),
      taxExempt: json['tax_exempt'] as bool? ?? false,
      invoiceNo: json['invoice_no'] != null ? _i(json['invoice_no']) : null,
      taxableAmount: json['taxable_amount'] != null ? _d(json['taxable_amount']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'discount': discount,
    'total_discount': totalDiscount,
    'final_amount': finalAmount,
    'round_off': roundOff,
    'payment_method': paymentMethod,
    'created_by': createdBy,
    'created_at': createdAt.toUtc().toIso8601String(),
    'customer_id': customerId,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'cash_amount': cashAmount,
    'digital_amount': digitalAmount,
    'due_date': dueDate?.toIso8601String().split('T').first,
    'extra_charges': extraCharges,
    'igst_amount': igstAmount,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'tax_exempt': taxExempt,
    if (invoiceNo != null) 'invoice_no': invoiceNo,
  };

  /// Insert payload. Includes the client id (idempotent retries) and the
  /// real sale time (offline sales keep their date). GST split, due amount
  /// and stock are decided by the database.
  Map<String, dynamic> toInsertJson() => {
    if (isUuid(id)) 'id': id,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'discount': discount,
    'total_discount': totalDiscount,
    'final_amount': finalAmount < 0 ? 0 : finalAmount,
    'round_off': roundOff,
    'payment_method': paymentMethod,
    'created_by': createdBy.isNotEmpty ? createdBy : null,
    'customer_id': (customerId != null && customerId!.isNotEmpty) ? customerId : null,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'cash_amount': cashAmount,
    'digital_amount': digitalAmount,
    'due_date': dueDate?.toIso8601String().split('T').first,
    'extra_charges': extraCharges,
    'tax_exempt': taxExempt,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
