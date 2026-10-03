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

  /// Which document posted this entry ('sales', 'purchases', ...), or null
  /// for manual entries. Set by the database since app 1.1.0.
  final String? refType;
  final String? refId;
  final String? source;

  AccountTransaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.category,
    this.description,
    required this.createdAt,
    this.refType,
    this.refId,
    this.source,
  });

  bool get isTransfer => category == 'transfer';

  factory AccountTransaction.fromJson(Map<String, dynamic> json) {
    return AccountTransaction(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: json['category'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      refType: json['ref_type'] as String?,
      refId: json['ref_id'] as String?,
      source: json['source'] as String?,
    );
  }
}

/// Totals computed by the database over the whole period (no row cap, #20).
class AccountSummary {
  final double totalIn;
  final double totalOut;
  final double transfersIn;
  final double transfersOut;
  final int transactionCount;
  final Map<String, double> byCategory;

  const AccountSummary({
    this.totalIn = 0,
    this.totalOut = 0,
    this.transfersIn = 0,
    this.transfersOut = 0,
    this.transactionCount = 0,
    this.byCategory = const {},
  });

  double get net => totalIn - totalOut;

  Map<String, double> toLegacyMap() => {
        'total_in': totalIn,
        'total_out': totalOut,
        'net': net,
      };

  factory AccountSummary.fromJson(Map<String, dynamic> json) {
    final cats = <String, double>{};
    final raw = json['by_category'];
    if (raw is Map) {
      raw.forEach((k, v) => cats[k.toString()] = (v as num?)?.toDouble() ?? 0);
    }
    return AccountSummary(
      totalIn: (json['total_in'] as num?)?.toDouble() ?? 0,
      totalOut: (json['total_out'] as num?)?.toDouble() ?? 0,
      transfersIn: (json['transfers_in'] as num?)?.toDouble() ?? 0,
      transfersOut: (json['transfers_out'] as num?)?.toDouble() ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      byCategory: cats,
    );
  }
}
