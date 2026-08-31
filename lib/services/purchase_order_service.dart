import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/purchase_order.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'product_service.dart';

class PurchaseOrderService {
  final SupabaseClient _client;
  final ProductService _productService;

  PurchaseOrderService({SupabaseClient? client, ProductService? productService})
    : _client = client ?? Supabase.instance.client,
      _productService = productService ?? ProductService();

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

  Future<void> receiveOrder(String orderId) async {
    try {
      final po = await getPurchaseOrder(orderId);
      if (po == null) throw Exception('Purchase order not found');

      // Add stock for each item
      for (final item in po.items) {
        if (!item.received) {
          await _productService.addStock(item.productId, item.qty);
        }
      }

      // Mark all items as received
      final updatedItems = po.items
          .map(
            (item) => PurchaseOrderItem(
              productId: item.productId,
              name: item.name,
              qty: item.qty,
              price: item.price,
              received: true,
            ),
          )
          .toList();

      // Update order status
      await _client
          .from('purchase_orders')
          .update({
            'status': 'received',
            'items': updatedItems.map((e) => e.toJson()).toList(),
            'updated_at': AppTimezone.nowUtc().toIso8601String(),
          })
          .eq('id', orderId);

      Logger.info('Purchase order $orderId received, stock updated');
    } catch (e) {
      Logger.error('receiveOrder', e);
      rethrow;
    }
  }

  Future<void> cancelOrder(String orderId) async {
    await updateStatus(orderId, 'cancelled');
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    try {
      await _client.from('purchase_orders').delete().eq('id', orderId);
    } catch (e) {
      Logger.error('deletePurchaseOrder', e);
    }
  }
}
