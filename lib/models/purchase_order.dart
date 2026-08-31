class PurchaseOrderItem {
  final String productId;
  final String name;
  final int qty;
  final double price;
  final bool received;

  PurchaseOrderItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.price,
    this.received = false,
  });

  double get total => qty * price;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderItem(
      productId: json['product_id'] as String,
      name: json['name'] as String? ?? '',
      qty: (json['qty'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      received: json['received'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'qty': qty,
    'price': price,
    'received': received,
  };
}

class PurchaseOrder {
  final String id;
  final String? supplierId;
  final String? supplierName;
  final List<PurchaseOrderItem> items;
  final double totalAmount;
  final String status;
  final String? notes;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  PurchaseOrder({
    required this.id,
    this.supplierId,
    this.supplierName,
    required this.items,
    required this.totalAmount,
    this.status = 'pending',
    this.notes,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List?)
        ?.map((e) => PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return PurchaseOrder(
      id: json['id'] as String,
      supplierId: json['supplier_id'] as String?,
      supplierName: json['supplier_name'] as String?,
      items: itemsList,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      notes: json['notes'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'supplier_id': supplierId,
    'supplier_name': supplierName,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'status': status,
    'notes': notes,
    'created_by': createdBy,
  };

  Map<String, dynamic> toInsertJson() => {
    'supplier_id': supplierId,
    'supplier_name': supplierName,
    'items': items.map((e) => e.toJson()).toList(),
    'total_amount': totalAmount,
    'status': status,
    'notes': notes,
    'created_by': createdBy,
  };
}
