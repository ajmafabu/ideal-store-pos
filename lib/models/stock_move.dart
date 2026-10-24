/// One movement in a product's stock history (get_stock_history).
class StockMove {
  StockMove({required this.at, required this.kind, required this.qty, required this.stockAfter, this.ref, this.note});

  final DateTime at;

  /// Sale, Purchase, Customer return, Damaged, Count, Correction, Stock In,
  /// Stock Out, Returned to supplier.
  final String kind;

  /// Stock units in (+) or out (−).
  final double qty;
  final double stockAfter;
  final String? ref;
  final String? note;

  bool get isIn => qty > 0;

  factory StockMove.fromJson(Map<String, dynamic> j) => StockMove(
    at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    kind: j['kind']?.toString() ?? '',
    qty: (j['qty'] as num?)?.toDouble() ?? 0,
    stockAfter: (j['stock_after'] as num?)?.toDouble() ?? 0,
    ref: j['ref']?.toString(),
    note: j['note']?.toString(),
  );
}
