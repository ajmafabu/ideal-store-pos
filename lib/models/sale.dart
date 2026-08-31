class CartItem {
  final String productId;
  final String name;
  final double price;
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
  });

  double get discountAmount => (price * qty) * (discount / 100);
  double get total => (price * qty) - discountAmount;
  double get profit => (price - purchasePrice) * qty;
  double get gstAmount => total * gstRate / (100 + gstRate);
  double get taxableAmount => total - gstAmount;
  double get priceExcludingGst => total - gstAmount;
  double get cgst => gstAmount / 2;
  double get sgst => gstAmount / 2;
  int get totalPieces => unitType == 'pieces' ? qty : qty * piecesPerUnit;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'price': price,
    'qty': qty,
    'unit': unit,
    'total': total,
    'purchase_price': purchasePrice,
    'gst_rate': gstRate,
    'hsn_code': hsnCode,
    'tamil_name': tamilName,
    'discount': discount,
    'discount_amount': discountAmount,
    'unit_type': unitType,
    'pieces_per_unit': piecesPerUnit,
    'tier': tier,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    productId: json['product_id'] as String,
    name: json['name'] as String,
    price: (json['price'] as num).toDouble(),
    qty: (json['qty'] as num).toInt(),
    unit: json['unit'] as String? ?? 'pcs',
    purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
    gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
    hsnCode: json['hsn_code'] as String?,
    tamilName: json['tamil_name'] as String?,
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    unitType: json['unit_type'] as String? ?? 'pieces',
    piecesPerUnit: (json['pieces_per_unit'] as num?)?.toInt() ?? 1,
    tier: json['tier'] as String? ?? 'normal',
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
  });

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
    );
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final itemsList =
        (json['items'] as List?)
            ?.map((e) => CartItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return Sale(
      id: json['id'] as String,
      items: itemsList,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      totalDiscount: (json['total_discount'] as num?)?.toDouble() ?? 0,
      finalAmount: (json['final_amount'] as num?)?.toDouble() ?? 0,
      roundOff: (json['round_off'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      createdBy: json['created_by'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      customerId: json['customer_id'] as String?,
      isCredit: json['is_credit'] as bool? ?? false,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      dueAmount: (json['due_amount'] as num?)?.toDouble() ?? 0,
      cashAmount: (json['cash_amount'] as num?)?.toDouble() ?? 0,
      digitalAmount: (json['digital_amount'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'])
          : null,
      extraCharges: (json['extra_charges'] as num?)?.toDouble() ?? 0,
      igstAmount: (json['igst_amount'] as num?)?.toDouble() ?? 0,
      cgstAmount: (json['cgst_amount'] as num?)?.toDouble() ?? 0,
      sgstAmount: (json['sgst_amount'] as num?)?.toDouble() ?? 0,
      taxExempt: json['tax_exempt'] as bool? ?? false,
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
    'created_at': createdAt.toIso8601String(),
    'customer_id': customerId,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'cash_amount': cashAmount,
    'digital_amount': digitalAmount,
    'due_date': dueDate?.toIso8601String(),
    'extra_charges': extraCharges,
    'igst_amount': igstAmount,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'tax_exempt': taxExempt,
  };

  Map<String, dynamic> toInsertJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'discount': discount,
    'total_discount': totalDiscount,
    'final_amount': finalAmount,
    'round_off': roundOff,
    'payment_method': paymentMethod,
    'created_by': createdBy.isNotEmpty ? createdBy : null,
    'customer_id': (customerId != null && customerId!.isNotEmpty) ? customerId : null,
    'is_credit': isCredit,
    'amount_paid': amountPaid,
    'due_amount': dueAmount,
    'cash_amount': cashAmount,
    'digital_amount': digitalAmount,
    'due_date': dueDate?.toIso8601String(),
    'extra_charges': extraCharges,
    'igst_amount': igstAmount,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'tax_exempt': taxExempt,
  };
}
