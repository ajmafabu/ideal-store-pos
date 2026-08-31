class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? gstNumber;
  final double totalDues;
  final DateTime createdAt;

  Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.gstNumber,
    this.totalDues = 0,
    required this.createdAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    gstNumber: json['gst_number'] as String?,
    totalDues: (json['total_dues'] as num?)?.toDouble() ?? 0,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'gst_number': gstNumber,
    'total_dues': totalDues,
  };

  Map<String, dynamic> toInsertJson() => {
    'name': name,
    'phone': phone,
    'address': address,
    'gst_number': gstNumber,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
