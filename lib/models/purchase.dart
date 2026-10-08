import 'sale.dart' show isUuid;

class PurchaseItem {
  final String productId;
  final String name;
  final double price;
  /// Decimal for loose goods bought by weight (25.5 kg).
  double qty;
  final String unit;
  final double gstRate;
  final String? hsnCode;
  final String? batchNumber;
  final String? tamilName;
  final DateTime? expiryDate;

  /// Stock units per purchased unit (e.g. 12 when buying a box of 12 of a
  /// product counted in pieces). The database adds qty × stockFactor (#22).
  final double stockFactor;

  PurchaseItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.qty,
    required this.unit,
    this.gstRate = 0,
    this.hsnCode,
    this.batchNumber,
    this.tamilName,
    this.expiryDate,
    this.stockFactor = 1,
  });

  static const _keep = Object();

  /// Copy that keeps every field not given (batch, expiry, Tamil name, stock
  /// factor). Pass `batchNumber: null` / `expiryDate: null` to clear them.
  PurchaseItem copyWith({
    double? price,
    double? qty,
    Object? batchNumber = _keep,
    Object? expiryDate = _keep,
  }) => PurchaseItem(
    productId: productId,
    name: name,
    price: price ?? this.price,
    qty: qty ?? this.qty,
    unit: unit,
    gstRate: gstRate,
    hsnCode: hsnCode,
    batchNumber: identical(batchNumber, _keep) ? this.batchNumber : batchNumber as String?,
    tamilName: tamilName,
    expiryDate: identical(expiryDate, _keep) ? this.expiryDate : expiryDate as DateTime?,
    stockFactor: stockFactor,
  );

  double get total => price * qty;
  double get gstAmount => total * gstRate / (100 + gstRate);
  double get priceExcludingGst => total - gstAmount;
  double get cgst => gstAmount / 2;
  double get sgst => gstAmount / 2;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'price': price,
    'qty': qty,
    'unit': unit,
    'total': total,
    'gst_rate': gstRate,
    'hsn_code': hsnCode,
    'batch_number': batchNumber,
    'tamil_name': tamilName,
    'expiry_date': expiryDate?.toIso8601String().split('T').first,
    if (stockFactor != 1) 'stock_factor': stockFactor,
  };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    productId: json['product_id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    qty: (json['qty'] as num).toDouble(),
    unit: json['unit'] as String? ?? 'pcs',
    gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
    hsnCode: json['hsn_code'] as String?,
    batchNumber: json['batch_number'] as String?,
    tamilName: json['tamil_name'] as String?,
    expiryDate: json['expiry_date'] != null
        ? DateTime.tryParse(json['expiry_date'].toString())
        : null,
    stockFactor: (json['stock_factor'] as num?)?.toDouble() ?? 1,
  );
}

class Purchase {
  final String id;
  final String? supplierName;
  final List<PurchaseItem> items;
  final double totalAmount;
  final double roundOff;
  final String createdBy;
  final DateTime createdAt;
  final String? supplierId;
  final bool isCredit;
  final double amountPaid;
  final double dueAmount;
  final String paymentMethod;
  final DateTime? dueDate;

  Purchase({
    required this.id,
    this.supplierName,
    required this.items,
    required this.totalAmount,
    this.roundOff = 0,
    required this.createdBy,
    required this.createdAt,
    this.supplierId,
    this.isCredit = false,
    this.amountPaid = 0,
    this.dueAmount = 0,
    this.paymentMethod = 'cash',
    this.dueDate,
  });

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?)
        ?.map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return Purchase(
      id: json['id'] as String,
      supplierName: json['supplier_name'] as String?,
      items: itemsList,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      roundOff: (json['round_off'] as num?)?.toDouble() ?? 0,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      supplierId: json['supplier_id'] as String?,
      isCredit: json['is_credit'] as bool? ?? false,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
    );
  }

  /// Insert payload. One insert is the whole purchase: the database adds the
  /// stock, creates costed batches, updates the cost price, the supplier's
  /// dues and the cash/bank outflow (#11). The client id keeps offline
  /// retries idempotent and payment_method is finally stored (#12).
  Map<String, dynamic> toInsertJson() => {
    if (isUuid(id)) 'id': id,
    'payment_method': paymentMethod,
    'created_at': createdAt.toUtc().toIso8601String(),
    'supplier_name': supplierName,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'round_off': roundOff,
    'created_by': createdBy.isNotEmpty ? createdBy : null,
    'supplier_id': supplierId,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'due_date': dueDate?.toIso8601String().split('T').first,
  };
}
