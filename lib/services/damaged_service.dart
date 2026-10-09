import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/damaged_product.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'offline_service.dart';
import 'product_service.dart';

class DamagedService {
  final SupabaseClient _client = Supabase.instance.client;
  final OfflineService _offlineService;

  DamagedService({OfflineService? offlineService})
    : _offlineService = offlineService ?? OfflineService();

  /// Writes off damaged stock atomically (stock check under lock, FIFO
  /// batches, cost of the loss). A rejection such as "Insufficient stock" is
  /// shown to the user; only a network failure is queued, as an operation
  /// that is replayed through the same RPC (#6).
  Future<DamagedProduct> createDamaged(DamagedProduct damaged) async {
    final id = const Uuid().v4();
    try {
      final response = await _client
          .rpc(
            'create_damaged_atomic',
            params: {
              'p_id': id,
              'p_product_id': damaged.productId,
              'p_product_name': damaged.productName,
              'p_quantity': damaged.quantity,
              'p_unit_price': damaged.unitPrice,
              'p_reason': damaged.reason,
              'p_created_by': _client.auth.currentUser?.id,
            },
          )
          .select()
          .single();
      ProductService.invalidateCache();
      return DamagedProduct.fromJson(response);
    } catch (e) {
      Logger.error('createDamaged', e);
      if (!isNetworkError(e)) rethrow;
      await _offlineService.addPendingOperation({
        'type': 'damaged',
        'data': {
          'id': id,
          'product_id': damaged.productId,
          'product_name': damaged.productName,
          'quantity': damaged.quantity,
          'reason': damaged.reason,
        },
      });
      return damaged;
    }
  }

  Future<List<DamagedProduct>> getDamaged({int limit = 100}) async {
    try {
      final response = await _client
          .from('damaged_products')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      final list = (response as List)
          .map((e) => DamagedProduct.fromJson(e))
          .toList();

      // Cache for offline
      try {
        await _offlineService.cacheDamaged(
          (response as List).cast<Map<String, dynamic>>(),
        );
      } catch (e) {
        Logger.warning('Failed to cache damaged products for offline: $e');
      }

      return list;
    } catch (e) {
      Logger.error('getDamaged', e);
      // Offline fallback
      try {
        final cached = _offlineService.getCachedDamaged();
        if (cached.isNotEmpty) {
          return cached.map((e) => DamagedProduct.fromJson(e)).toList();
        }
      } catch (e) {
        Logger.warning(
          'Failed to load damaged products from offline cache: $e',
        );
      }
      return [];
    }
  }

  /// Deletes a wrong entry; the database puts its stock back (QA #86).
  Future<void> deleteDamaged(String id) async {
    await _client.rpc('delete_damaged_atomic', params: {'p_id': id});
    ProductService.invalidateCache();
  }

  Future<int> getTodayDamagedCount() async {
    try {
      final start = AppTimezone.todayStartUtc();
      final end = AppTimezone.todayEndUtc();

      final response = await _client
          .from('damaged_products')
          .select('quantity')
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());

      int total = 0;
      for (final e in response as List) {
        total += (e['quantity'] as num?)?.toInt() ?? 0;
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}
