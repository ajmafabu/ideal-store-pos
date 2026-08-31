class Profile {
  final String id;
  final String name;
  final String role;
  final String? pin;
  final String shopId;
  final bool active;
  final String? gstin;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String? stateCode;

  Profile({
    required this.id,
    required this.name,
    required this.role,
    this.pin,
    required this.shopId,
    this.active = true,
    this.gstin,
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.stateCode,
  });

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'User',
      role: json['role'] as String? ?? 'staff',
      pin: json['pin'] as String?,
      shopId: json['shop_id'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      gstin: json['gstin'] as String?,
      shopName: json['shop_name'] as String?,
      shopAddress: json['shop_address'] as String?,
      shopPhone: json['shop_phone'] as String?,
      stateCode: json['state_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'pin': pin,
      'shop_id': shopId,
      'active': active,
      'gstin': gstin,
      'shop_name': shopName,
      'shop_address': shopAddress,
      'shop_phone': shopPhone,
      'state_code': stateCode,
    };
  }
}
