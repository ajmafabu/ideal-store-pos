import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../models/stock_move.dart';
import '../utils/logger.dart';
import '../utils/network_errors.dart';
import 'audit_service.dart';
import 'offline_service.dart';

class ProductService {
  final SupabaseClient _client = Supabase.instance.client;
  final OfflineService _offlineService;

  ProductService({OfflineService? offlineService})
    : _offlineService = offlineService ?? OfflineService();

  // The product list is kept in memory. After a sale or a purchase only
  // the products changed since the last download are fetched (the database
  // stamps updated_at on every change, stock included); the whole list is
  // fetched once every 10 minutes, so deleted or merged products drop out.
  // Before (18 Oct 2026) every sale re-downloaded all 1,151 products, about
  // 0.7 MB, and the till waited behind it on slow shop internet.
  static List<Product>? _productsCache;
  static DateTime? _fullTime;
  static String? _watermark; // newest updated_at seen (database clock)
  static bool _stale = true;
  static const Duration _fullEvery = Duration(minutes: 10);

  /// Something changed: the next read fetches what changed. [full] forces
  /// the whole list (after a delete).
  static void invalidateCache({bool full = false}) {
    _stale = true;
    if (full) _fullTime = null;
  }

  Future<List<Product>> getAllProducts() async {
    final cache = _productsCache;
    if (cache != null && !_stale) return cache;
    final fullDue = cache == null ||
        _watermark == null ||
        _fullTime == null ||
        DateTime.now().difference(_fullTime!) >= _fullEvery;
    try {
      final List<Product> allProducts;
      if (fullDue) {
        allProducts = await _downloadAll();
        _fullTime = DateTime.now();
        Logger.info('Loaded ${allProducts.length} products from database');
      } else {
        allProducts = await _downloadChanges(cache);
      }
      _productsCache = allProducts;
      _stale = false;
      await _cacheOffline(allProducts);
      return allProducts;
    } catch (e, stackTrace) {
      Logger.error('Failed to get products', e, stackTrace);
      // Try to load from offline cache
      if (_productsCache == null) {
        try {
          final cached = _offlineService.getCachedProducts();
          if (cached.isNotEmpty) {
            Logger.info('Loaded ${cached.length} products from offline cache');
            return cached.map((e) => Product.fromJson(e)).toList();
          }
        } catch (e) {
          Logger.warning('Failed to load from offline cache: $e');
        }
      }
      return _productsCache ?? [];
    }
  }

  /// Every product (1000 a request).
  Future<List<Product>> _downloadAll() async {
    final all = <Product>[];
    String? newest;
    var offset = 0;
    const batchSize = 1000;
    while (true) {
      final response = await _client
          .from('products')
          .select('*, variants:product_variants(*)')
          .order('name', ascending: true)
          .range(offset, offset + batchSize - 1)
          .timeout(const Duration(seconds: 30));
      final rows = response as List;
      newest = _newest(rows, newest);
      all.addAll(_parse(rows));
      if (rows.length < batchSize) break;
      offset += batchSize;
    }
    _watermark = newest;
    return all;
  }

  /// Only the products changed since the last download, merged in.
  Future<List<Product>> _downloadChanges(List<Product> current) async {
    final response = await _client
        .from('products')
        .select('*, variants:product_variants(*)')
        .gte('updated_at', _watermark!)
        .order('updated_at', ascending: true)
        .limit(1000)
        .timeout(const Duration(seconds: 15));
    final rows = response as List;
    if (rows.length >= 1000) return _downloadAll(); // a big change: take everything
    _watermark = _newest(rows, _watermark);
    final changed = {for (final p in _parse(rows)) p.id: p};
    if (changed.isEmpty) return current;
    final merged = [
      for (final p in current) changed.remove(p.id) ?? p,
      ...changed.values, // new products
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    Logger.info('Updated ${rows.length} changed products');
    return merged;
  }

  static String? _newest(List rows, String? start) {
    var newest = start;
    for (final r in rows) {
      final t = (r as Map)['updated_at']?.toString();
      if (t != null && (newest == null || t.compareTo(newest) > 0)) newest = t;
    }
    return newest;
  }

  static List<Product> _parse(List rows) => rows
      .map((e) {
        try {
          return Product.fromJson(e);
        } catch (err) {
          Logger.warning('Failed to parse product ${e is Map ? e['id'] : 'unknown'}: $err');
          return null;
        }
      })
      .whereType<Product>()
      .toList();

  Future<void> _cacheOffline(List<Product> allProducts) async {
    try {
      await _offlineService.cacheProducts(
        allProducts
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'tamil_name': p.tamilName,
                'selling_price': p.sellingPrice,
                'purchase_price': p.purchasePrice,
                'stock': p.stock,
                'barcode': p.barcode,
                'category': p.category,
                'unit': p.unit,
                'sfw': p.sfw,
                'gst_rate': p.gstRate,
                'hsn_code': p.hsnCode,
                'low_stock_alert': p.lowStockAlert,
                'expiry_date': p.expiryDate?.toIso8601String(),
                'unit_type': p.unitType,
                'pieces_per_unit': p.piecesPerUnit,
                'hidden_at': p.hiddenAt?.toIso8601String(),
                'variants': p.variants
                    .map(
                      (v) => {
                        'id': v.id,
                        'product_id': v.productId,
                        'name': v.name,
                        'price': v.price,
                        'purchase_price': v.purchasePrice,
                        'stock': v.stock,
                        'barcode': v.barcode,
                        'sku': v.sku,
                        'min_stock': v.minStock,
                        'is_active': v.isActive,
                        'attributes': v.attributes,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
      );
    } catch (e) {
      Logger.warning('Failed to cache products: $e');
    }
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    try {
      final response = await _client
          .from('products')
          .select('*, variants:product_variants(*)')
          .eq('barcode', barcode)
          .maybeSingle();

      if (response == null) return null;
      return Product.fromJson(response);
    } catch (e, stackTrace) {
      Logger.error('Failed to get product by barcode', e, stackTrace);
      return null;
    }
  }

  Future<Product?> getProductById(String id) async {
    try {
      final response = await _client
          .from('products')
          .select('*, variants:product_variants(*)')
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Product.fromJson(response);
    } catch (e, stackTrace) {
      Logger.error('Failed to get product by id', e, stackTrace);
      return null;
    }
  }

  Future<Product?> createProduct(Product product) async {
    try {
      final insertData = product.toInsertJson();
      final hasVariants = product.hasVariants;
      final variants = product.variants;

      // First create the product
      final response = await _client
          .from('products')
          .insert(insertData)
          .select()
          .single();

      final createdProduct = Product.fromJson(response);

      // Then create variants if any
      if (hasVariants && variants.isNotEmpty) {
        final variantData = variants
            .map(
              (v) => {
                'product_id': createdProduct.id,
                'name': v.name,
                'sku': v.sku,
                'barcode': v.barcode,
                'price': v.price,
                'purchase_price': v.purchasePrice,
                'stock': v.stock,
                'min_stock': v.minStock,
                'attributes': v.attributes,
                'is_active': v.isActive,
                'tamil_name': v.tamilName,
              },
            )
            .toList();

        await _client.from('product_variants').insert(variantData);
      }

      ProductService.invalidateCache();

      AuditService().log(
        action: 'create',
        entityType: 'product',
        entityId: createdProduct.id,
        newData: response,
        description: 'Created product: ${createdProduct.name}',
      );

      return createdProduct;
    } catch (e, stackTrace) {
      Logger.error('createProduct', e, stackTrace);
      // Queue for offline
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'insert',
        'data': product.toInsertJson(),
      });
      return null;
    }
  }

  Future<void> updateProduct(Product product) async {
    try {
      final hasVariants = product.hasVariants;
      final variants = product.variants;

      // Update product
      await _client
          .from('products')
          .update(product.toJson())
          .eq('id', product.id);

      // Handle variants
      if (hasVariants) {
        // Get existing variants
        final existingVariantsResponse = await _client
            .from('product_variants')
            .select()
            .eq('product_id', product.id);

        final existingVariantIds = (existingVariantsResponse as List)
            .map((v) => v['id'] as String)
            .toSet();

        final newVariantIds = product.variants
            .map((v) => v.id)
            .where((id) => id.isNotEmpty)
            .toSet();

        // Delete removed variants
        if (newVariantIds.isNotEmpty) {
          final toDelete = existingVariantIds.difference(newVariantIds);
          if (toDelete.isNotEmpty) {
            await _client
                .from('product_variants')
                .delete()
                .inFilter('id', toDelete.toList());
          }
        }

        // Upsert variants
        for (final variant in variants) {
          final variantData = {
            'product_id': product.id,
            'name': variant.name,
            'sku': variant.sku,
            'barcode': variant.barcode,
            'price': variant.price,
            'purchase_price': variant.purchasePrice,
            'stock': variant.stock,
            'min_stock': variant.minStock,
            'attributes': variant.attributes,
            'is_active': variant.isActive,
            'tamil_name': variant.tamilName,
          };

          if (existingVariantIds.contains(variant.id)) {
            await _client
                .from('product_variants')
                .update(variantData)
                .eq('id', variant.id);
          } else {
            await _client.from('product_variants').insert(variantData);
          }
        }
      } else {
        // Delete all variants if product no longer has variants
        await _client
            .from('product_variants')
            .delete()
            .eq('product_id', product.id);
      }
      ProductService.invalidateCache();

      AuditService().log(
        action: 'update',
        entityType: 'product',
        entityId: product.id,
        newData: product.toJson(),
        description: 'Updated product: ${product.name}',
      );
    } catch (e, stackTrace) {
      Logger.error('updateProduct', e, stackTrace);
      // Only a lost connection is retried later. A server refusal used to be
      // queued too, so the screen said "Product updated" while nothing was
      // saved and the edit failed again on every sync (QA #6).
      if (!isNetworkError(e)) rethrow;
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'update',
        'data': product.toJson(),
      });
    }
  }

  /// Changes only the price columns. The purchase screens used to send the
  /// whole (cached) product back, which wiped the second selling rate and
  /// wrote an old stock figure over newer sales (#8).
  Future<void> updatePrices(
    String productId, {
    double? purchasePrice,
    double? sellingPrice,
  }) async {
    final data = <String, dynamic>{
      if (purchasePrice != null) 'purchase_price': purchasePrice,
      if (sellingPrice != null) 'selling_price': sellingPrice,
    };
    if (data.isEmpty) return;
    await _client.from('products').update(data).eq('id', productId);
    invalidateCache();
  }

  /// Hides the products that sat at 0 stock with no sale or purchase for
  /// 30 days (admin only). Returns how many were hidden.
  Future<int> hideIdleProducts() async {
    final n = await _client.rpc('hide_idle_products');
    invalidateCache();
    return (n as num?)?.toInt() ?? 0;
  }

  /// Shows a hidden product again (admin only); it stays shown for 30 days.
  Future<void> showProduct(String productId) async {
    await _client.rpc('show_product', params: {'p_product': productId});
    invalidateCache();
  }

  /// The database function is not there yet (its SQL file not run).
  static bool isMissingFunction(Object e) =>
      e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');

  /// A shelf count or a stock correction (admin only): the stock becomes
  /// [counted], batches follow and the history keeps it. [appQty] is what
  /// the app showed when counting began: sales made while counting are kept
  /// (counted 40, 2 sold meanwhile → 38). Returns {stock, moved, difference}.
  static Future<Map<String, dynamic>> saveCountWith(
    SupabaseClient client,
    String productId,
    double counted, {
    double? appQty,
    String reason = 'Stock corrected',
  }) async {
    try {
      final res = await client.rpc('save_stock_count', params: {
        'p_product': productId,
        'p_counted': counted,
        'p_app_qty': appQty,
        'p_reason': reason,
      });
      invalidateCache();
      return Map<String, dynamic>.from(res as Map);
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      // before sql/2026_10_inventory_tools.sql is run: the old two steps
      final row = await client.from('products').select('stock').eq('id', productId).single();
      final system = appQty ?? (row['stock'] as num?)?.toDouble() ?? 0;
      await client.rpc('reconcile_stock_with_batches', params: {
        'p_product_id': productId,
        'p_physical_qty': counted,
      });
      try {
        await client.from('stock_reconciliation').insert({
          'product_id': productId,
          'system_qty': system,
          'physical_qty': counted,
          'notes': reason,
        });
      } catch (e) {
        Logger.warning('Count saved, history not written: $e');
      }
      invalidateCache();
      return {'stock': counted, 'moved': 0, 'difference': counted - system};
    }
  }

  Future<Map<String, dynamic>> saveCount(String productId, double counted,
          {double? appQty, String reason = 'Stock corrected'}) =>
      saveCountWith(_client, productId, counted, appQty: appQty, reason: reason);

  /// Sets stock to a counted quantity (admin only). Batches are kept in step
  /// by the database; a plain product update can no longer change stock.
  Future<void> setPhysicalStock(String productId, num quantity) async {
    await saveCount(productId, quantity.toDouble(), reason: 'Stock corrected');
  }

  /// The product's stock now, straight from the database.
  Future<double> currentStock(String productId) async {
    final row = await _client.from('products').select('stock').eq('id', productId).single();
    return (row['stock'] as num?)?.toDouble() ?? 0;
  }

  /// Every movement of one product, newest first (sql/2026_10_inventory_tools.sql).
  Future<List<StockMove>> getStockHistory(String productId, {int limit = 300}) async {
    final rows = await _client.rpc('get_stock_history', params: {'p_product': productId, 'p_limit': limit});
    return [for (final r in rows as List) StockMove.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _client.from('product_variants').delete().eq('product_id', id);
      await _client.from('products').delete().eq('id', id);
      ProductService.invalidateCache(full: true); // a delete leaves no updated_at

      AuditService().log(
        action: 'delete',
        entityType: 'product',
        entityId: id,
        description: 'Deleted product: $id',
      );
    } catch (e, stackTrace) {
      Logger.error('deleteProduct', e, stackTrace);
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'delete',
        'data': {'id': id},
      });
    }
  }

  /// Stock In: adds [quantity] in one locked database step (batches kept in
  /// step). Errors are thrown so the screen can show them (#27).
  Future<double> addStock(String productId, num quantity, {String? reason}) =>
      _adjustStock(productId, quantity, reason);

  /// Stock Out: removes [quantity]; the database refuses to go below zero.
  Future<double> deductStock(String productId, num quantity, {String? reason}) =>
      _adjustStock(productId, -quantity, reason);

  /// Written down with its reason, so it shows in the product's history.
  Future<double> _adjustStock(String productId, num delta, String? reason) async {
    dynamic res;
    try {
      res = await _client.rpc('adjust_stock_logged', params: {
        'p_product': productId,
        'p_delta': delta,
        'p_reason': reason,
      });
    } catch (e) {
      if (!isMissingFunction(e)) rethrow;
      res = await _client.rpc('adjust_stock', params: {'p_product_id': productId, 'p_delta': delta});
    }
    invalidateCache();
    return (res as num?)?.toDouble() ?? 0;
  }

  /// Returns true if stock was successfully updated, false if reconciliation
  /// record was saved but stock update failed (manual intervention needed).
  Future<bool> reconcileStock(
    String productId,
    double physicalQty, {
    String? notes,
  }) async {
    try {
      // one database step: stock, batches and the history line together
      await saveCount(productId, physicalQty, reason: notes ?? 'Counted');
      return true;
    } catch (e, stackTrace) {
      Logger.error('reconcileStock', e, stackTrace);
      return false;
    }
  }

  Future<List<Product>> getLowStockProducts() async {
    try {
      final allProducts = await getAllProducts();
      return allProducts.where((p) => p.isLowStock).toList();
    } catch (e, stackTrace) {
      Logger.error('Failed to get low stock products', e, stackTrace);
      return [];
    }
  }

  Future<List<String>> getCategories() async {
    try {
      final response = await _client
          .from('products')
          .select('category')
          .not('category', 'is', null);

      final categories = (response as List)
          .map((e) => e['category'] as String)
          .toSet()
          .toList();
      categories.sort();
      return categories;
    } catch (e, stackTrace) {
      Logger.error('Failed to get categories', e, stackTrace);
      return [];
    }
  }

  // ============================================
  // VARIANT METHODS
  // ============================================

  Future<List<ProductVariant>> getVariants(String productId) async {
    try {
      final response = await _client
          .from('product_variants')
          .select()
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('name', ascending: true);

      return (response as List).map((e) => ProductVariant.fromJson(e)).toList();
    } catch (e, stackTrace) {
      Logger.error('getVariants', e, stackTrace);
      return [];
    }
  }

  Future<ProductVariant?> getVariantById(String variantId) async {
    try {
      final response = await _client
          .from('product_variants')
          .select()
          .eq('id', variantId)
          .maybeSingle();

      if (response == null) return null;
      return ProductVariant.fromJson(response);
    } catch (e, stackTrace) {
      Logger.error('getVariantById', e, stackTrace);
      return null;
    }
  }

  Future<ProductVariant?> getVariantByBarcode(String barcode) async {
    try {
      final response = await _client
          .from('product_variants')
          .select()
          .eq('barcode', barcode)
          .maybeSingle();

      if (response == null) return null;
      return ProductVariant.fromJson(response);
    } catch (e, stackTrace) {
      Logger.error('getVariantByBarcode', e, stackTrace);
      return null;
    }
  }

  Future<void> updateVariantStock(String variantId, int newStock) async {
    try {
      await _client
          .from('product_variants')
          .update({'stock': newStock})
          .eq('id', variantId);
    } catch (e, stackTrace) {
      Logger.error('updateVariantStock', e, stackTrace);
    }
  }

  Future<void> addVariantStock(String variantId, int quantity) async {
    try {
      final variant = await getVariantById(variantId);
      if (variant == null) {
        Logger.warning('addVariantStock: variant $variantId not found');
        return;
      }
      await updateVariantStock(variantId, variant.stock + quantity);
    } catch (e, stackTrace) {
      Logger.error('addVariantStock', e, stackTrace);
    }
  }

  Future<void> deductVariantStock(String variantId, int quantity) async {
    try {
      final variant = await getVariantById(variantId);
      if (variant == null) {
        Logger.warning('deductVariantStock: variant $variantId not found');
        return;
      }
      if (variant.stock < quantity) {
        Logger.warning(
          'deductVariantStock: insufficient stock for $variantId '
          '(has ${variant.stock}, needs $quantity)',
        );
        return;
      }
      await updateVariantStock(variantId, variant.stock - quantity);
    } catch (e, stackTrace) {
      Logger.error('deductVariantStock', e, stackTrace);
    }
  }
}
