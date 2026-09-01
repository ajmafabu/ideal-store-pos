class ProductReturn {
  final String id;
  final String? saleId;
  final String? productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double refundAmount;
  final String? reason;
  final String? createdBy;
  final DateTime createdAt;
  final String? originalSaleId;
  final double returnAmount;

  ProductReturn({
    required this.id,
    this.saleId,
    this.productId,
    required this.productName,
    required this.quantity,
    this.unitPrice = 0,
    this.refundAmount = 0,
    this.reason,
    this.createdBy,
    required this.createdAt,
    this.originalSaleId,
    this.returnAmount = 0,
  });

  factory ProductReturn.fromJson(Map<String, dynamic> json) {
    return ProductReturn(
      id: json['id'] as String,
      saleId: json['sale_id'] as String?,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      originalSaleId: json['original_sale_id'] as String?,
      returnAmount: (json['return_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'refund_amount': refundAmount,
      'reason': reason,
      'created_by': createdBy,
      'original_sale_id': originalSaleId,
      'return_amount': returnAmount,
    };
  }
}
