import 'sale.dart' show isUuid;

class Expense {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final String createdBy;
  final DateTime createdAt;

  /// cash | upi | bank — stored so the cash book posts to (and a delete
  /// reverses from) the right account (#12).
  final String paymentMethod;

  Expense({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.createdBy,
    required this.createdAt,
    this.paymentMethod = 'cash',
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    category: json['category'] as String,
    description: json['description'] as String?,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    createdBy: json['created_by'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    paymentMethod: json['payment_method'] as String? ?? 'cash',
  );

  /// The expense date is sent as a real instant (UTC), so a back-dated
  /// expense lands on the right day in both the P&L and the cash book.
  Map<String, dynamic> toInsertJson() => {
    if (isUuid(id)) 'id': id,
    'category': category,
    'description': description,
    'amount': amount,
    'created_by': createdBy.isNotEmpty ? createdBy : null,
    'created_at': createdAt.toUtc().toIso8601String(),
    'payment_method': paymentMethod,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'description': description,
    'amount': amount,
    'created_by': createdBy,
    'created_at': createdAt.toUtc().toIso8601String(),
    'payment_method': paymentMethod,
  };
}
