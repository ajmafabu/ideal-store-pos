class DamagedProduct {
  final String id;
  final String? productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String? reason;
  final String? createdBy;
  final DateTime createdAt;

  DamagedProduct({
    required this.id,
    this.productId,
    required this.productName,
    required this.quantity,
    this.unitPrice = 0,
    this.reason,
    this.createdBy,
    required this.createdAt,
  });

  factory DamagedProduct.fromJson(Map<String, dynamic> json) {
    return DamagedProduct(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'reason': reason,
      'created_by': createdBy,
    };
  }
}
