import '../utils/app_timezone.dart';

class ProductVariant {
  final String id;
  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final double price;
  final double purchasePrice;
  final int stock;
  final int minStock;
  final Map<String, dynamic> attributes; // {"size": "500g", "color": "Red"}
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? tamilName;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
    required this.price,
    required this.purchasePrice,
    this.stock = 0,
    this.minStock = 0,
    this.attributes = const {},
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.tamilName,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      minStock: (json['min_stock'] as num?)?.toInt() ?? 0,
      attributes: (json['attributes'] as Map?)?.cast<String, dynamic>() ?? {},
      isActive: json['is_active'] as bool? ?? true,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      tamilName: json['tamil_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'name': name,
      'sku': sku,
      'barcode': barcode,
      'price': price,
      'purchase_price': purchasePrice,
      'stock': stock,
      'min_stock': minStock,
      'attributes': attributes,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tamil_name': tamilName,
    };
  }

  ProductVariant copyWith({
    String? id,
    String? productId,
    String? name,
    String? sku,
    String? barcode,
    double? price,
    double? purchasePrice,
    int? stock,
    int? minStock,
    Map<String, dynamic>? attributes,
    bool? isActive,
    String? tamilName,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      attributes: attributes ?? this.attributes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      tamilName: tamilName ?? this.tamilName,
    );
  }

  // Helper to get display string like "500g Red" from attributes
  String get displayName {
    if (attributes.isEmpty) return name;
    return attributes.values.join(' ');
  }

  // Check if variant is low stock
  bool get isLowStock => stock <= minStock && stock > 0;
  bool get isOutOfStock => stock <= 0;
}

class Product {
  final String id;
  final String name;
  final String? barcode;
  final String? category;
  final double purchasePrice;
  final double sellingPrice;
  final int stock;
  final String unit;
  final int lowStockAlert;
  final String? shopId;
  final double gstRate;
  final String? hsnCode;
  final DateTime? expiryDate;
  final String? batchNumber;
  final bool hasVariants;
  final List<ProductVariant> variants;
  final String? tamilName;
  final String? sfw;
  final String unitType;
  final int piecesPerUnit;
  final double? sellingPrice2;
  final String? sellingPrice2Label;

  Product({
    required this.id,
    required this.name,
    this.barcode,
    this.category,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
    this.stock = 0,
    this.unit = 'pcs',
    this.lowStockAlert = 10,
    this.shopId,
    this.gstRate = 0,
    this.hsnCode,
    this.expiryDate,
    this.batchNumber,
    this.hasVariants = false,
    this.variants = const [],
    this.tamilName,
    this.sfw,
    this.unitType = 'pieces',
    this.piecesPerUnit = 1,
    this.sellingPrice2,
    this.sellingPrice2Label,
  });

  bool get isLowStock => stock > 0 && stock <= lowStockAlert;
  bool get hasDualRates => sellingPrice2 != null && sellingPrice2! > 0;

  // Total stock across all variants (for display)
  int get totalStock {
    if (!hasVariants || variants.isEmpty) return stock;
    return variants.fold<int>(0, (sum, v) => sum + v.stock);
  }

  // Lowest price among variants
  double get minVariantPrice {
    if (!hasVariants || variants.isEmpty) return sellingPrice;
    final activeVariants = variants.where((v) => v.isActive).toList();
    if (activeVariants.isEmpty) return sellingPrice;
    return activeVariants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
  }

  // Highest price among variants
  double get maxVariantPrice {
    if (!hasVariants || variants.isEmpty) return sellingPrice;
    final activeVariants = variants.where((v) => v.isActive).toList();
    if (activeVariants.isEmpty) return sellingPrice;
    return activeVariants.map((v) => v.price).reduce((a, b) => a > b ? a : b);
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(AppTimezone.nowIst());
  }

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final now = AppTimezone.nowIst();
    final diff = expiryDate!.difference(now).inDays;
    return diff >= 0 && diff <= 30;
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(AppTimezone.nowIst()).inDays;
  }

  double priceForTier(String tier) {
    switch (tier) {
      case 'wholesale':
        return double.parse((sellingPrice * 0.99).toStringAsFixed(2));
      case 'bulk':
        return double.parse((sellingPrice * 0.98).toStringAsFixed(2));
      default:
        return sellingPrice;
    }
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    List<ProductVariant> variantsList = [];
    if (json['variants'] is List) {
      variantsList = (json['variants'] as List)
          .map((v) => ProductVariant.fromJson(v))
          .toList();
    }

    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      barcode: json['barcode'] as String?,
      category: json['category'] as String?,
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      unit: json['unit'] as String? ?? 'pcs',
      lowStockAlert: (json['low_stock_alert'] as num?)?.toInt() ?? 10,
      shopId: json['shop_id'] as String?,
      gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
      hsnCode: json['hsn_code'] as String?,
      expiryDate: json['expiry_date'] != null
          ? DateTime.tryParse(json['expiry_date'] as String)
          : null,
      batchNumber: json['batch_number'] as String?,
      hasVariants: json['has_variants'] as bool? ?? false,
      variants: variantsList,
      tamilName: json['tamil_name'] as String?,
      sfw: json['sfw'] as String?,
      unitType: json['unit_type'] as String? ?? 'pieces',
      piecesPerUnit: (json['pieces_per_unit'] as num?)?.toInt() ?? 1,
      sellingPrice2: (json['selling_price_2'] as num?)?.toDouble(),
      sellingPrice2Label: json['selling_price_2_label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'barcode': barcode,
      'category': category,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'stock': stock,
      'unit': unit,
      'low_stock_alert': lowStockAlert,
      'shop_id': shopId,
      'gst_rate': gstRate,
      'hsn_code': hsnCode,
      'expiry_date': expiryDate?.toIso8601String().split('T').first,
      'batch_number': batchNumber,
      'has_variants': hasVariants,
      'tamil_name': tamilName,
      'sfw': sfw,
      'unit_type': unitType,
      'pieces_per_unit': piecesPerUnit,
      'selling_price_2': sellingPrice2,
      'selling_price_2_label': sellingPrice2Label,
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'name': name,
      'barcode': barcode,
      'category': category,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'stock': stock,
      'unit': unit,
      'low_stock_alert': lowStockAlert,
      'shop_id': shopId,
      'gst_rate': gstRate,
      'hsn_code': hsnCode,
      'expiry_date': expiryDate?.toIso8601String().split('T').first,
      'batch_number': batchNumber,
      'has_variants': hasVariants,
      'tamil_name': tamilName,
      'sfw': sfw,
      'unit_type': unitType,
      'pieces_per_unit': piecesPerUnit,
      'selling_price_2': sellingPrice2,
      'selling_price_2_label': sellingPrice2Label,
    };
  }

  Product copyWith({
    String? id,
    String? name,
    String? barcode,
    String? category,
    double? purchasePrice,
    double? sellingPrice,
    int? stock,
    String? unit,
    int? lowStockAlert,
    String? shopId,
    double? gstRate,
    String? hsnCode,
    DateTime? expiryDate,
    String? batchNumber,
    bool? hasVariants,
    List<ProductVariant>? variants,
    String? tamilName,
    String? sfw,
    String? unitType,
    int? piecesPerUnit,
    double? sellingPrice2,
    String? sellingPrice2Label,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      lowStockAlert: lowStockAlert ?? this.lowStockAlert,
      shopId: shopId ?? this.shopId,
      gstRate: gstRate ?? this.gstRate,
      hsnCode: hsnCode ?? this.hsnCode,
      expiryDate: expiryDate ?? this.expiryDate,
      batchNumber: batchNumber ?? this.batchNumber,
      hasVariants: hasVariants ?? this.hasVariants,
      variants: variants ?? this.variants,
      tamilName: tamilName ?? this.tamilName,
      sfw: sfw ?? this.sfw,
      unitType: unitType ?? this.unitType,
      piecesPerUnit: piecesPerUnit ?? this.piecesPerUnit,
      sellingPrice2: sellingPrice2 ?? this.sellingPrice2,
      sellingPrice2Label: sellingPrice2Label ?? this.sellingPrice2Label,
    );
  }
}
