class Expense {
  final String id;
  final String category;
  final String? description;
  final double amount;
  final String createdBy;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.category,
    this.description,
    required this.amount,
    required this.createdBy,
    required this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    category: json['category'] as String,
    description: json['description'] as String?,
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    createdBy: json['created_by'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toInsertJson() => {
    'category': category,
    'description': description,
    'amount': amount,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'description': description,
    'amount': amount,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
  };
}
