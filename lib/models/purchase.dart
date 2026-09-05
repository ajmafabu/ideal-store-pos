class PurchaseItem {
  final String productId;
  final String name;
  final double price;
  int qty;
  final String unit;
  final double gstRate;
  final String? hsnCode;
  final String? batchNumber;
  final String? tamilName;
  final DateTime? expiryDate;

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
  });

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
  };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    productId: json['product_id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    qty: (json['qty'] as num).toInt(),
    unit: json['unit'] as String? ?? 'pcs',
    gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
    hsnCode: json['hsn_code'] as String?,
    batchNumber: json['batch_number'] as String?,
    tamilName: json['tamil_name'] as String?,
    expiryDate: json['expiry_date'] != null
        ? DateTime.tryParse(json['expiry_date'] as String)
        : null,
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
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date']) : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'supplier_name': supplierName,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'round_off': roundOff,
    'created_by': createdBy.isNotEmpty ? createdBy : null,
    'supplier_id': supplierId,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'due_date': dueDate?.toIso8601String(),
  };
}
