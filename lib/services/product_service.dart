import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../utils/logger.dart';
import 'audit_service.dart';
import 'offline_service.dart';

class ProductService {
  final SupabaseClient _client = Supabase.instance.client;
  final OfflineService _offlineService;

  ProductService({OfflineService? offlineService})
    : _offlineService = offlineService ?? OfflineService();

  static List<Product>? _productsCache;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static void invalidateCache() {
    _productsCache = null;
    _cacheTime = null;
  }

  Future<List<Product>> getAllProducts() async {
    if (_productsCache != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _productsCache!;
    }
    try {
      // Fetch ALL products (may need multiple requests for >1000 products)
      List<Product> allProducts = [];
      int offset = 0;
      const batchSize = 1000;

      while (true) {
        final response = await _client
            .from('products')
            .select('*, variants:product_variants(*)')
            .order('name')
            .range(offset, offset + batchSize - 1);

        final batch = (response as List)
            .map((e) {
              try {
                return Product.fromJson(e);
              } catch (e) {
                Logger.warning(
                  'Failed to parse product ${e is Map ? e['id'] : 'unknown'}: $e',
                );
                return null;
              }
            })
            .whereType<Product>()
            .toList();

        allProducts.addAll(batch);

        if (batch.length < batchSize) break; // No more products
        offset += batchSize;
      }

      Logger.info('Loaded ${allProducts.length} products from database');
      _productsCache = allProducts;
      _cacheTime = DateTime.now();

      // Cache products for offline use
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
                  'variants': p.variants
                      ?.map(
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
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'update',
        'data': product.toJson(),
      });
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      await _client.from('product_variants').delete().eq('product_id', id);
      await _client.from('products').delete().eq('id', id);
      ProductService.invalidateCache();

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

  Future<void> addStock(String productId, int quantity) async {
    try {
      await _client.rpc(
        'increment_stock',
        params: {'p_product_id': productId, 'p_qty': quantity},
      );
      ProductService.invalidateCache();
    } catch (e, stackTrace) {
      Logger.error('addStock', e, stackTrace);
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'stock_add',
        'data': {'product_id': productId, 'qty': quantity},
      });
    }
  }

  Future<void> deductStock(String productId, int quantity) async {
    try {
      await _client.rpc(
        'decrement_stock',
        params: {'p_product_id': productId, 'p_qty': quantity},
      );
      ProductService.invalidateCache();
    } catch (e, stackTrace) {
      Logger.error('deductStock', e, stackTrace);
      await _offlineService.queuePendingWrite({
        'table': 'products',
        'operation': 'stock_deduct',
        'data': {'product_id': productId, 'qty': quantity},
      });
    }
  }

  /// Returns true if stock was successfully updated, false if reconciliation
  /// record was saved but stock update failed (manual intervention needed).
  Future<bool> reconcileStock(
    String productId,
    int physicalQty, {
    String? notes,
  }) async {
    try {
      final product = await getProductById(productId);
      if (product == null) return false;

      final systemQty = product.stock;
      final stockUpdated = systemQty != physicalQty;

      await _client.from('stock_reconciliation').insert({
        'product_id': productId,
        'system_qty': systemQty,
        'physical_qty': physicalQty,
        'notes': notes,
      });

      if (stockUpdated) {
        try {
          // Set stock directly to physical count instead of computing diff
          // to avoid TOCTOU race with concurrent stock changes
          await _client
              .from('products')
              .update({'stock': physicalQty})
              .eq('id', productId);
        } catch (e) {
          Logger.error('reconcileStock: stock update failed', e);
          ProductService.invalidateCache();
          return false; // Record saved but stock not updated
        }
      }

      ProductService.invalidateCache();
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
          .order('name');

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
