import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/damaged_product.dart';
import '../utils/app_timezone.dart';
import '../utils/logger.dart';
import 'offline_service.dart';

class DamagedService {
  final SupabaseClient _client = Supabase.instance.client;
  final OfflineService _offlineService;

  DamagedService({OfflineService? offlineService})
    : _offlineService = offlineService ?? OfflineService();

  Future<DamagedProduct> createDamaged(DamagedProduct damaged) async {
    try {
      final user = _client.auth.currentUser;

      // Validate stock before decrementing
      if (damaged.productId != null) {
        try {
          final product = await _client
              .from('products')
              .select('stock')
              .eq('id', damaged.productId!)
              .maybeSingle();
          if (product != null) {
            final currentStock = (product['stock'] as num?)?.toInt() ?? 0;
            if (damaged.quantity > currentStock) {
              throw Exception(
                'Insufficient stock: available $currentStock, damaged ${damaged.quantity}',
              );
            }
          }
        } catch (e) {
          if (e.toString().contains('Insufficient stock')) rethrow;
        }
      }

      final response = await _client
          .from('damaged_products')
          .insert(damaged.toInsertJson()..['created_by'] = user?.id)
          .select()
          .single();

      final created = DamagedProduct.fromJson(response);

      // Decrease stock (damaged items removed from inventory)
      if (created.productId != null) {
        try {
          await _client.rpc(
            'decrement_stock',
            params: {
              'p_product_id': created.productId,
              'p_qty': created.quantity,
            },
          );
        } catch (e) {
          Logger.warning('Failed to decrement stock for damaged: $e');
        }
      }

      return created;
    } catch (e) {
      Logger.error('createDamaged', e);
      // Queue for offline
      await _offlineService.queuePendingWrite({
        'table': 'damaged_products',
        'operation': 'insert',
        'data': damaged.toInsertJson(),
      });
      // Queue stock deduction for damaged product
      if (damaged.productId != null &&
          damaged.productId!.isNotEmpty &&
          damaged.quantity > 0) {
        await _offlineService.queuePendingWrite({
          'table': 'products',
          'operation': 'stock_deduct',
          'data': {'product_id': damaged.productId, 'qty': damaged.quantity},
        });
      }
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
        Logger.warning('Failed to load damaged products from offline cache: $e');
      }
      return [];
    }
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
