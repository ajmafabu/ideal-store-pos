/// Profit per product from sale lines minus returns, for the profit screens
/// (Profit Analysis, Top / All Profitable Products, Reports).
///
/// Same rules as the database (`item_cost`, `period_figures`):
/// * cost of a line = its FIFO `cost_total`, else `purchase_price × qty`
///   (else the product's current cost when the line has none);
/// * quantities are decimals (1.5 kg) — they used to be cut to whole numbers;
/// * returns in the period take back their quantity, `return_amount`
///   (else `refund_amount`) and `cost_amount` — they used to be ignored.
class ProductProfit {
  final String key;
  final String name;
  final String? tamilName;
  final String productId;
  double qty;
  double revenue;
  double cost;

  ProductProfit({
    required this.key,
    required this.name,
    this.tamilName,
    required this.productId,
    this.qty = 0,
    this.revenue = 0,
    this.cost = 0,
  });

  double get profit => revenue - cost;
  double get margin => revenue > 0 ? profit / revenue * 100 : 0;

  /// The map shape the screens already use.
  Map<String, dynamic> toMap() => {
        'name': name,
        'tamilName': tamilName,
        'productId': productId,
        'qtySold': qty,
        'totalSold': revenue,
        'revenue': revenue,
        'totalCost': cost,
        'cost': cost,
        'profit': profit,
        'margin': margin,
      };

  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  /// Cost of one sale line: FIFO `cost_total`, else `purchase_price × qty`
  /// (decimal qty), else [fallbackUnitCost] × qty. Same as `item_cost` in SQL.
  static double lineCost(Map item, {double fallbackUnitCost = 0}) {
    if (item['cost_total'] != null) return _num(item['cost_total']);
    var unitCost = _num(item['purchase_price']);
    if (unitCost <= 0) unitCost = fallbackUnitCost;
    return unitCost * _num(item['qty']);
  }

  /// [sales]: rows with an `items` list. [returns]: product_returns rows of
  /// the same period. [costMap]: product id → current purchase price.
  static List<ProductProfit> compute({
    required List<dynamic> sales,
    List<dynamic> returns = const [],
    Map<String, double> costMap = const {},
  }) {
    final rows = <String, ProductProfit>{};

    ProductProfit rowFor(String productId, String name, String? tamilName) {
      final key = productId.isNotEmpty ? productId : 'name:$name';
      return rows.putIfAbsent(
        key,
        () => ProductProfit(key: key, name: name, tamilName: tamilName, productId: productId),
      );
    }

    for (final sale in sales) {
      final items = (sale is Map ? sale['items'] : null) as List? ?? const [];
      for (final item in items) {
        if (item is! Map) continue;
        final productId = item['product_id']?.toString() ?? '';
        final name = item['name']?.toString() ?? 'Unknown';
        final qty = _num(item['qty']);
        final row = rowFor(productId, name, item['tamil_name']?.toString());
        row.qty += qty;
        row.revenue += _num(item['total']);
        row.cost += lineCost(item, fallbackUnitCost: costMap[productId] ?? 0);
      }
    }

    for (final r in returns) {
      if (r is! Map) continue;
      final productId = r['product_id']?.toString() ?? '';
      final name = r['product_name']?.toString() ?? 'Unknown';
      final key = productId.isNotEmpty ? productId : 'name:$name';
      final row = rows[key];
      if (row == null) continue; // returned item sold before this period
      final qty = _num(r['quantity']);
      final amount = r['return_amount'] != null && _num(r['return_amount']) > 0
          ? _num(r['return_amount'])
          : _num(r['refund_amount']);
      final cost = r['cost_amount'] != null && _num(r['cost_amount']) > 0
          ? _num(r['cost_amount'])
          : (costMap[productId] ?? 0) * qty;
      row.qty -= qty;
      row.revenue -= amount;
      row.cost -= cost;
    }

    return rows.values.where((p) => p.qty.abs() > 0.0001 || p.revenue.abs() > 0.005).toList();
  }
}
