import '../models/product.dart';

/// One physical count (a row of stock_reconciliation).
class StockCount {
  StockCount({
    required this.productId,
    required this.systemQty,
    required this.countedQty,
    required this.at,
    this.reason,
  });

  final String productId;
  final double systemQty;
  final double countedQty;
  final DateTime at;
  final String? reason;

  double get difference => countedQty - systemQty;
  bool get matched => difference.abs() < 0.001;

  /// A real count of the shelf. The October database upgrade also wrote
  /// lines here ("2026-10 upgrade: removed … batch units") when it trimmed
  /// old batch figures; those are not counts (the report showed 1%).
  bool get isShelfCount => !(reason ?? '').startsWith('2026-10 upgrade');
}

/// How often a product should be counted, by its importance (ABC):
/// A = the products that make most of the sales value.
enum CountClass { a, b, c }

extension CountClassX on CountClass {
  String get label => switch (this) { CountClass.a => 'A', CountClass.b => 'B', CountClass.c => 'C' };

  /// A every week, B every month, C every three months.
  Duration get every => switch (this) {
        CountClass.a => const Duration(days: 7),
        CountClass.b => const Duration(days: 30),
        CountClass.c => const Duration(days: 90),
      };
}

/// A product that should be counted today.
class CountDue {
  CountDue(this.product, this.cls, this.lastCounted);
  final Product product;
  final CountClass cls;
  final DateTime? lastCounted;
}

/// A product whose batches (FIFO stock) do not add up to its stock.
class BatchMismatch {
  BatchMismatch(this.product, this.batchTotal);
  final Product product;
  final double batchTotal;
  double get difference => batchTotal - product.stockOnHand;
}

/// Everything that tells how true the stock figures are (18 Oct 2026,
/// owner: "inventory accuracy 10 out of 10"). Pure: built from data the app
/// already has, so it is fully tested.
class StockHealth {
  StockHealth._({
    required this.belowZero,
    required this.noCost,
    required this.notCounted,
    required this.bigDifferences,
    required this.batchMismatches,
    required this.countsLast30,
    required this.matchedLast30,
    required this.dueToday,
    required this.classes,
  });

  /// Sold before the purchase was entered: enter the purchase.
  final List<Product> belowZero;

  /// Sold with no purchase price: profit counted as almost 100%.
  final List<Product> noCost;

  /// Not counted in the last 30 days (with stock or sales).
  final List<Product> notCounted;

  /// Counts of the last 30 days with the biggest differences, largest first.
  final List<StockCount> bigDifferences;

  /// Stock and batches disagree (an old drift; a count fixes it).
  final List<BatchMismatch> batchMismatches;

  final int countsLast30;
  final int matchedLast30;

  /// Today's short counting list (A first, oldest count first).
  final List<CountDue> dueToday;

  /// Each product's class (A, B or C).
  final Map<String, CountClass> classes;

  /// % of counts in the last 30 days where the shelf matched the app.
  double? get accuracyPercent => countsLast30 == 0 ? null : 100 * matchedLast30 / countsLast30;

  static const dailyListSize = 20;

  static StockHealth compute({
    required List<Product> products,
    required List<StockCount> counts,
    required Map<String, double> batchTotals,
    required Map<String, double> salesValue30d,
    required DateTime now,
  }) {
    // hidden: empty for 30 days, off every list until it is stocked again
    final active = products.where((p) => !p.hasVariants && !p.isHidden).toList();
    counts = counts.where((c) => c.isShelfCount).toList();

    // last count per product
    final lastCount = <String, DateTime>{};
    for (final c in counts) {
      final prev = lastCount[c.productId];
      if (prev == null || c.at.isAfter(prev)) lastCount[c.productId] = c.at;
    }

    // ABC by sales value of the last 30 days: A = first 80% of the value,
    // B = next 15%, C = the rest and products that did not sell
    final classes = <String, CountClass>{};
    final selling = active.where((p) => (salesValue30d[p.id] ?? 0) > 0).toList()
      ..sort((a, b) => (salesValue30d[b.id] ?? 0).compareTo(salesValue30d[a.id] ?? 0));
    final total = selling.fold<double>(0, (t, p) => t + (salesValue30d[p.id] ?? 0));
    var running = 0.0;
    for (final p in selling) {
      final before = total == 0 ? 1.0 : running / total;
      classes[p.id] = before < 0.80 ? CountClass.a : (before < 0.95 ? CountClass.b : CountClass.c);
      running += salesValue30d[p.id] ?? 0;
    }
    for (final p in active) {
      classes.putIfAbsent(p.id, () => CountClass.c);
    }

    final belowZero = active.where((p) => p.stock < -0.0005).toList()..sort((a, b) => a.stock.compareTo(b.stock));
    final noCost = active
        .where((p) => p.purchasePrice <= 0 && p.sellingPrice > 0 && ((salesValue30d[p.id] ?? 0) > 0 || p.stock > 0))
        .toList()
      ..sort((a, b) => (salesValue30d[b.id] ?? 0).compareTo(salesValue30d[a.id] ?? 0));

    final monthAgo = now.subtract(const Duration(days: 30));
    final notCounted = active
        .where((p) => p.stock != 0 || (salesValue30d[p.id] ?? 0) > 0)
        .where((p) => lastCount[p.id] == null || lastCount[p.id]!.isBefore(monthAgo))
        .toList()
      ..sort((a, b) => (salesValue30d[b.id] ?? 0).compareTo(salesValue30d[a.id] ?? 0));

    final recent = counts.where((c) => !c.at.isBefore(monthAgo)).toList();
    final bigDifferences = recent.where((c) => !c.matched).toList()
      ..sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));

    final mismatches = <BatchMismatch>[];
    for (final p in active) {
      final b = batchTotals[p.id] ?? 0;
      // below zero, every batch is used up; at or above zero they must agree
      if ((b - p.stockOnHand).abs() > 0.001) mismatches.add(BatchMismatch(p, b));
    }
    mismatches.sort((a, b) => b.difference.abs().compareTo(a.difference.abs()));

    // due: never counted, or counted longer ago than its class allows
    final due = <CountDue>[];
    for (final p in active) {
      if (p.stock == 0 && (salesValue30d[p.id] ?? 0) == 0) continue; // nothing to count
      // below zero: the purchase is not entered yet; counting now and
      // entering the purchase later would count those goods twice
      if (p.stock < -0.0005) continue;
      final cls = classes[p.id]!;
      final last = lastCount[p.id];
      if (last == null || now.difference(last) >= cls.every) due.add(CountDue(p, cls, last));
    }
    due.sort((a, b) {
      final c = a.cls.index.compareTo(b.cls.index);
      if (c != 0) return c;
      final la = a.lastCounted, lb = b.lastCounted;
      if (la == null && lb != null) return -1;
      if (lb == null && la != null) return 1;
      if (la != null && lb != null) return la.compareTo(lb);
      return (salesValue30d[b.product.id] ?? 0).compareTo(salesValue30d[a.product.id] ?? 0);
    });

    return StockHealth._(
      belowZero: belowZero,
      noCost: noCost,
      notCounted: notCounted,
      bigDifferences: bigDifferences,
      batchMismatches: mismatches,
      countsLast30: recent.length,
      matchedLast30: recent.where((c) => c.matched).length,
      dueToday: due.take(dailyListSize).toList(),
      classes: classes,
    );
  }
}

/// Why the shelf differs from the app (saved with each count).
const countReasons = [
  'Counting correction',
  'Purchase not entered',
  'Sale not billed',
  'Damaged',
  'Expired',
  'Missing / theft',
  'Extra received / free goods',
  'Other',
];
