class InventoryBatch {
  final String id;
  final String productId;
  final String? purchaseId;
  final String? batchNumber;
  final DateTime? expiryDate;
  final int quantity;
  final int remaining;
  final double purchasePrice;
  final DateTime createdAt;

  InventoryBatch({
    required this.id,
    required this.productId,
    this.purchaseId,
    this.batchNumber,
    this.expiryDate,
    required this.quantity,
    required this.remaining,
    required this.purchasePrice,
    required this.createdAt,
  });

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff >= 0 && diff <= 30;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  factory InventoryBatch.fromJson(Map<String, dynamic> json) {
    return InventoryBatch(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      purchaseId: json['purchase_id'] as String?,
      batchNumber: json['batch_number'] as String?,
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'] as String)
          : null,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      remaining: (json['remaining'] as num?)?.toInt() ?? 0,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'purchase_id': purchaseId,
    'batch_number': batchNumber,
    'expiry_date': expiryDate?.toIso8601String().split('T').first,
    'quantity': quantity,
    'remaining': remaining,
    'purchase_price': purchasePrice,
  };

  Map<String, dynamic> toInsertJson() => {
    'product_id': productId,
    'purchase_id': purchaseId,
    'batch_number': batchNumber,
    'expiry_date': expiryDate?.toIso8601String().split('T').first,
    'quantity': quantity,
    'remaining': remaining,
    'purchase_price': purchasePrice,
  };
}
