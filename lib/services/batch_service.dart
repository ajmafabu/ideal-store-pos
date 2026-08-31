import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_batch.dart';
import '../utils/logger.dart';

class BatchService {
  final SupabaseClient _client;

  BatchService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  /// Get all batches for a product
  Future<List<InventoryBatch>> getProductBatches(String productId) async {
    try {
      final response = await _client
          .from('inventory_batches')
          .select()
          .eq('product_id', productId)
          .gt('remaining', 0)
          .order('created_at', ascending: true);

      return (response as List).map((e) => InventoryBatch.fromJson(e)).toList();
    } catch (e) {
      Logger.error('getProductBatches', e);
      return [];
    }
  }

  /// Get expiring batches within X days
  Future<List<Map<String, dynamic>>> getExpiringBatches({int days = 30}) async {
    try {
      final response = await _client.rpc(
        'get_expiring_batches',
        params: {'p_days': days},
      );

      if (response is List) {
        return response
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    } catch (e) {
      Logger.error('getExpiringBatches', e);
      return [];
    }
  }

  /// Deduct stock from specific batch
  Future<void> deductBatchStock(String batchId, int qty) async {
    try {
      await _client.rpc(
        'deduct_stock_fifo',
        params: {'p_product_id': batchId, 'p_qty': qty},
      );
    } catch (e) {
      Logger.error('deductBatchStock', e);
    }
  }
}
