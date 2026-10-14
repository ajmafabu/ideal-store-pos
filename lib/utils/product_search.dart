import '../models/product.dart';

/// Product search for the purchase screens.
///
/// Every word typed must appear in the name, Tamil name or barcode
/// ("dettol 10" finds "dettol 10 rs"). Best matches come first:
///   1. barcode typed exactly (a scan)
///   2. name starts with what was typed ("su" → sugar, sunfeast)
///   3. a word in the name starts with it ("su" → all rounder sunfeast)
///   4. the name contains it ("su" → kosupathi)
///   5. only the Tamil name or barcode matches
/// Before, matches came in list order, so "su" showed a few odd products
/// first (owner, 14 Oct 2026).
List<Product> searchProducts(List<Product> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final terms = q.split(RegExp(r'\s+'));

  final scored = <(int, Product)>[];
  for (final p in all) {
    final name = p.name.toLowerCase();
    final tamil = (p.tamilName ?? '').toLowerCase();
    final code = (p.barcode ?? '').toLowerCase();
    final everyWord = terms.every((t) => name.contains(t) || tamil.contains(t) || code.contains(t));
    if (!everyWord) continue;

    final int score;
    if (code.isNotEmpty && code == q) {
      score = 0;
    } else if (name.startsWith(q)) {
      score = 1;
    } else if (name.split(RegExp(r'[\s\-/(]+')).any((w) => w.startsWith(terms.first))) {
      score = 2;
    } else if (name.contains(terms.first)) {
      score = 3;
    } else {
      score = 4;
    }
    scored.add((score, p));
  }
  scored.sort((a, b) {
    final s = a.$1.compareTo(b.$1);
    return s != 0 ? s : a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
  });
  return [for (final s in scored) s.$2];
}
