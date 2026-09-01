class Account {
  final String id;
  final String name;
  final String accountType;
  final double balance;

  Account({
    required this.id,
    required this.name,
    required this.accountType,
    required this.balance,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      name: json['name'] as String,
      accountType: json['account_type'] as String,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AccountTransaction {
  final String id;
  final String accountId;
  final String type;
  final double amount;
  final String category;
  final String? description;
  final DateTime createdAt;

  AccountTransaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.category,
    this.description,
    required this.createdAt,
  });

  factory AccountTransaction.fromJson(Map<String, dynamic> json) {
    return AccountTransaction(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: json['category'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
