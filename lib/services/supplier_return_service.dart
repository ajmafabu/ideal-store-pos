import 'package:supabase_flutter/supabase_flutter.dart';

import 'product_service.dart';

/// One line going back to the supplier, in the product's stock units.
class SupplierReturnLine {
  SupplierReturnLine({required this.productId, required this.name, required this.qty, required this.price});
  final String productId;
  final String name;
  final double qty;

  /// Value per unit (what the supplier gives back for it).
  final double price;

  double get total => qty * price;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'name': name,
    'qty': qty,
    'price': price,
    'stock_factor': 1,
  };
}

/// A return to a supplier, as saved (supplier_returns).
class SupplierReturn {
  SupplierReturn({
    required this.id,
    required this.supplierName,
    required this.items,
    required this.total,
    required this.credit,
    required this.refund,
    required this.refundMethod,
    required this.at,
    this.reason,
  });

  final String id;
  final String supplierName;
  final List<Map<String, dynamic>> items;
  final double total;

  /// Taken off what the shop owes the supplier.
  final double credit;

  /// Money received back.
  final double refund;
  final String refundMethod;
  final DateTime at;
  final String? reason;

  factory SupplierReturn.fromJson(Map<String, dynamic> j) => SupplierReturn(
    id: j['id'].toString(),
    supplierName: (j['supplier_name'] ?? 'Supplier').toString(),
    items: [for (final i in (j['items'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)],
    total: (j['total_amount'] as num?)?.toDouble() ?? 0,
    credit: (j['credit_amount'] as num?)?.toDouble() ?? 0,
    refund: (j['refund_amount'] as num?)?.toDouble() ?? 0,
    refundMethod: (j['refund_method'] ?? 'cash').toString(),
    at: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    reason: j['reason']?.toString(),
  );
}

/// Goods sent back to the supplier (23 Oct 2026). The database takes the
/// stock out at its FIFO cost, takes the value off what the shop owes the
/// supplier (oldest bill first) and posts any money received back.
class SupplierReturnService {
  SupplierReturnService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  /// [id] comes from newDocumentId(): a retried save is recognised.
  Future<SupplierReturn> create({
    required String id,
    String? supplierId,
    required String supplierName,
    required List<SupplierReturnLine> lines,
    required String refundMethod,
    String? reason,
  }) async {
    final rows = await _client.rpc(
      'create_supplier_return',
      params: {
        'p_id': id,
        'p_supplier_id': supplierId,
        'p_supplier_name': supplierName,
        'p_items': [for (final l in lines) l.toJson()],
        'p_refund_method': refundMethod,
        'p_reason': reason,
      },
    );
    ProductService.invalidateCache();
    final list = rows as List;
    return SupplierReturn.fromJson(Map<String, dynamic>.from(list.first as Map));
  }

  Future<List<SupplierReturn>> recent({int limit = 100}) async {
    final rows = await _client.from('supplier_returns').select().order('created_at', ascending: false).limit(limit);
    return [for (final r in rows as List) SupplierReturn.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// Entered by mistake: the stock, the dues and the money go back.
  Future<void> delete(String id) async {
    await _client.rpc('delete_supplier_return', params: {'p_id': id});
    ProductService.invalidateCache();
  }
}
