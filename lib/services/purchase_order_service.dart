import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase_order.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import '../utils/payment_methods.dart';
import 'product_service.dart';

class PurchaseOrderService {
  final SupabaseClient _client;

  // productService kept for call-site compatibility
  PurchaseOrderService({SupabaseClient? client, ProductService? productService})
    : _client = client ?? Supabase.instance.client;

  Future<PurchaseOrder> createPurchaseOrder(PurchaseOrder po) async {
    final user = _client.auth.currentUser;
    final insertData = po.toInsertJson()..['created_by'] = user?.id;

    final response = await _client
        .from('purchase_orders')
        .insert(insertData)
        .select()
        .single();

    return PurchaseOrder.fromJson(response);
  }

  Future<List<PurchaseOrder>> getPurchaseOrders({
    int limit = 100,
    String? status,
  }) async {
    try {
      var builder = _client.from('purchase_orders').select();

      if (status != null) {
        builder = builder.eq('status', status);
      }

      final response = await builder
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).map((e) => PurchaseOrder.fromJson(e)).toList();
    } catch (e) {
      Logger.error('getPurchaseOrders', e);
      return [];
    }
  }

  Future<PurchaseOrder?> getPurchaseOrder(String id) async {
    try {
      final response = await _client
          .from('purchase_orders')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return PurchaseOrder.fromJson(response);
    } catch (e) {
      Logger.error('getPurchaseOrder', e);
      return null;
    }
  }

  Future<void> updatePurchaseOrder(PurchaseOrder po) async {
    try {
      await _client
          .from('purchase_orders')
          .update({
            'supplier_id': po.supplierId,
            'supplier_name': po.supplierName,
            'items': po.items.map((e) => e.toJson()).toList(),
            'total_amount': po.totalAmount,
            'status': po.status,
            'notes': po.notes,
            'updated_at': AppTimezone.nowUtc().toIso8601String(),
          })
          .eq('id', po.id);
    } catch (e) {
      Logger.error('updatePurchaseOrder', e);
    }
  }

  Future<void> updateStatus(String orderId, String status) async {
    try {
      await _client
          .from('purchase_orders')
          .update({
            'status': status,
            'updated_at': AppTimezone.nowUtc().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (e) {
      Logger.error('updateStatus', e);
    }
  }

  /// Receives an order as a real purchase in one database transaction:
  /// stock, costed batches, cost price, supplier dues and (if paid now) the
  /// cash/bank payment — and marks the order received only if all of that
  /// succeeded (#21). [paymentMethod] 'credit' means pay the supplier later.
  /// [items]: what actually arrived (qty / price changed, 0 = not received).
  /// Null receives the order exactly as ordered.
  Future<void> receiveOrder(
    String orderId, {
    String paymentMethod = 'credit',
    List<PurchaseOrderItem>? items,
  }) async {
    final method = PaymentMethods.normalize(paymentMethod);
    final isCredit = method == PaymentMethods.credit;
    double paid = 0;
    if (!isCredit) {
      var lines = items;
      if (lines == null) {
        final po = await getPurchaseOrder(orderId);
        if (po == null) throw Exception('Purchase order not found');
        lines = po.items;
      }
      paid = lines.fold<double>(0, (sum, i) => sum + i.price * i.qty);
    }
    await _client.rpc('receive_purchase_order', params: {
      'p_order_id': orderId,
      'p_is_credit': isCredit,
      'p_amount_paid': paid,
      'p_payment_method': isCredit ? PaymentMethods.cash : method,
      if (items != null) 'p_items': items.map((i) => i.toJson()).toList(),
    });
    ProductService.invalidateCache();
    Logger.info('Purchase order $orderId received as a purchase');
  }

  Future<void> cancelOrder(String orderId) async {
    await updateStatus(orderId, 'cancelled');
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    try {
      await _client.from('purchase_orders').delete().eq('id', orderId);
    } catch (e) {
      Logger.error('deletePurchaseOrder', e);
      rethrow; // a silent failure looked like a delete
    }
  }
}
