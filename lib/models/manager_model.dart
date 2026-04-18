class ManagerModel {
  final int id;
  final String username;
  final String firstname;
  final String lastname;
  final double balance;
  final int usersCount;
  final String? aclName;
  final int? aclId;
  final bool isActive;
  final String email;
  final String mobile;
  final String company;
  final String city;
  final String address;
  final String notes;
  final int? parentId;
  final double totalDebt;
  final double debtForMe;

  const ManagerModel({
    required this.id,
    required this.username,
    this.firstname = '',
    this.lastname = '',
    this.balance = 0,
    this.usersCount = 0,
    this.aclName,
    this.aclId,
    this.isActive = true,
    this.email = '',
    this.mobile = '',
    this.company = '',
    this.city = '',
    this.address = '',
    this.notes = '',
    this.parentId,
    this.totalDebt = 0,
    this.debtForMe = 0,
  });

  factory ManagerModel.fromJson(Map<String, dynamic> json) {
    final aclDetails = json['acl_group_details'];
    return ManagerModel(
      id: _toInt(json['id'] ?? json['idx']),
      username: (json['username'] ?? '').toString(),
      firstname: (json['firstname'] ?? '').toString(),
      lastname: (json['lastname'] ?? '').toString(),
      balance: _toDouble(json['balance']),
      usersCount: _toInt(json['users_count']),
      aclName: aclDetails is Map
          ? aclDetails['name']?.toString()
          : json['acl_name']?.toString(),
      aclId: json['acl_id'] != null
          ? _toInt(json['acl_id'])
          : (aclDetails is Map && aclDetails['id'] != null
              ? _toInt(aclDetails['id'])
              : null),
      isActive: _toBool(json['is_active'] ?? json['enabled'] ?? true),
      email: (json['email'] ?? '').toString(),
      mobile: (json['mobile'] ?? json['phone'] ?? '').toString(),
      company: (json['company'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      parentId: json['parent_id'] != null ? _toInt(json['parent_id']) : null,
      totalDebt: _toDouble(
        json['total_debt'] ?? json['debt'] ?? json['total'] ?? 0,
      ),
      debtForMe: _toDouble(json['debt_for_me']),
    );
  }

  String get fullName => '$firstname $lastname'.trim();

  double get credit => balance > 0 ? balance : 0;

  double get debt => totalDebt > 0 ? totalDebt : (balance < 0 ? balance.abs() : 0);

  ManagerModel copyWith({
    int? id,
    String? username,
    String? firstname,
    String? lastname,
    double? balance,
    int? usersCount,
    String? aclName,
    int? aclId,
    bool? isActive,
    String? email,
    String? mobile,
    String? company,
    String? city,
    String? address,
    String? notes,
    int? parentId,
    double? totalDebt,
    double? debtForMe,
  }) {
    return ManagerModel(
      id: id ?? this.id,
      username: username ?? this.username,
      firstname: firstname ?? this.firstname,
      lastname: lastname ?? this.lastname,
      balance: balance ?? this.balance,
      usersCount: usersCount ?? this.usersCount,
      aclName: aclName ?? this.aclName,
      aclId: aclId ?? this.aclId,
      isActive: isActive ?? this.isActive,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      company: company ?? this.company,
      city: city ?? this.city,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      parentId: parentId ?? this.parentId,
      totalDebt: totalDebt ?? this.totalDebt,
      debtForMe: debtForMe ?? this.debtForMe,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = value?.toString().toLowerCase().trim();
    return raw == '1' || raw == 'true';
  }
}

class ManagerAclGroup {
  final int id;
  final String name;

  const ManagerAclGroup({
    required this.id,
    required this.name,
  });

  factory ManagerAclGroup.fromJson(Map<String, dynamic> json) {
    return ManagerAclGroup(
      id: ManagerModel._toInt(json['id']),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class ManagerDebtInfo {
  final double balance;
  final double totalDebt;
  final double debtForMe;

  const ManagerDebtInfo({
    required this.balance,
    required this.totalDebt,
    required this.debtForMe,
  });

  factory ManagerDebtInfo.fromJson(Map<String, dynamic> json) {
    final data = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json;
    return ManagerDebtInfo(
      balance: ManagerModel._toDouble(data['balance']),
      totalDebt: ManagerModel._toDouble(data['total']),
      debtForMe: ManagerModel._toDouble(data['debt_for_me']),
    );
  }
}
