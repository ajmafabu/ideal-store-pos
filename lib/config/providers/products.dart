import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product.dart';
import 'services.dart';

// ============================================
// PRODUCTS
// ============================================

final productsProvider = FutureProvider<List<Product>>((ref) async {
  final service = ref.watch(productServiceProvider);
  return service.getAllProducts();
});

// ============================================
// STOCK SELLING VALUE (what stock would sell for)
// ============================================

final stockSellingValueProvider = FutureProvider<double>((ref) async {
  try {
    final products = await ref.watch(productsProvider.future);
    double sellingValue = 0;
    for (final p in products) {
      if (!p.hasVariants) {
        sellingValue += p.stock * p.sellingPrice;
      } else {
        for (final v in p.variants) {
          if (v.isActive) {
            sellingValue += v.stock * v.price;
          }
        }
      }
    }
    return sellingValue;
  } catch (e) {
    return 0;
  }
});
