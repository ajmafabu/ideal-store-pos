class Customer {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double totalCredit;
  final DateTime createdAt;
  final String? stateCode;
  final double creditLimit;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.totalCredit = 0,
    required this.createdAt,
    this.stateCode,
    this.creditLimit = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    totalCredit: (json['total_credit'] as num?)?.toDouble() ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    stateCode: json['state_code'] as String?,
    creditLimit: (json['credit_limit'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'total_credit': totalCredit,
    'credit_limit': creditLimit,
  };

  Map<String, dynamic> toInsertJson() => {
    'name': name,
    'phone': phone,
    'address': address,
    'state_code': stateCode,
    'credit_limit': creditLimit,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
