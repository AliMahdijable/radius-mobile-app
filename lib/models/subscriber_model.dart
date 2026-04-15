class SubscriberModel {
  final String? idx;
  final String username;
  final String firstname;
  final String lastname;
  final String? phone;
  final String? mobile;
  final String? expiration;
  final int? remainingDays;
  final String? notes;
  final double? debt;
  final bool? hasDebtFlag;
  final String? profileName;
  final int? profileId;
  final String? balance;
  final String? price;
  final String? parentUsername;
  final bool? isOnlineFlag;
  final int? enabled;
  final String? ipAddress;
  final String? macAddress;
  final int? sessionTime;
  final int? downloadBytes;
  final int? uploadBytes;
  final String? deviceVendor;

  const SubscriberModel({
    this.idx,
    required this.username,
    required this.firstname,
    required this.lastname,
    this.phone,
    this.mobile,
    this.expiration,
    this.remainingDays,
    this.notes,
    this.debt,
    this.hasDebtFlag,
    this.profileName,
    this.profileId,
    this.balance,
    this.price,
    this.parentUsername,
    this.isOnlineFlag,
    this.enabled,
    this.ipAddress,
    this.macAddress,
    this.sessionTime,
    this.downloadBytes,
    this.uploadBytes,
    this.deviceVendor,
  });

  String get fullName => '$firstname $lastname'.trim();

  String get displayPhone => phone ?? mobile ?? '';

  double get debtAmount {
    if (notes != null && notes!.isNotEmpty) {
      final v = double.tryParse(notes!);
      if (v != null) return v;
    }
    if (debt != null && debt != 0) return debt!;
    return 0;
  }

  bool get hasDebt {
    if (hasDebtFlag != null) return hasDebtFlag!;
    return debtAmount < 0;
  }

  bool get hasCredit => debtAmount > 0;

  double get balanceAmount {
    final b = double.tryParse(balance ?? '') ?? 0;
    return b;
  }

  bool get isExpired => (remainingDays ?? 0) < 0;

  bool get isActive => !isExpired;

  bool get isNearExpiry =>
      remainingDays != null && remainingDays! >= 0 && remainingDays! <= 3;

  bool get isEnabled => enabled == null || enabled == 1;

  bool get isOnline => isOnlineFlag == true;

  bool get isOffline => isActive && isEnabled && !isOnline;

  factory SubscriberModel.fromJson(Map<String, dynamic> json) {
    final profileDetails = json['profile_details'];
    final pdName = profileDetails is Map ? profileDetails['name'] : null;
    final pdId = profileDetails is Map ? profileDetails['id'] : null;

    final pName = pdName ?? json['profile_name'] ?? json['profileName'] ?? json['package_name'];
    final pId = pdId ?? json['profile_id'] ?? json['profileId'];
    final pPrice = json['price'] ?? json['profile_price'] ?? json['monthly_fee'];

    return SubscriberModel(
      idx: (json['id'] ?? json['idx'])?.toString(),
      username: (json['username'] ?? '').toString(),
      firstname: (json['firstname'] ?? '').toString(),
      lastname: (json['lastname'] ?? '').toString(),
      phone: json['phone']?.toString(),
      mobile: json['mobile']?.toString(),
      expiration: json['expiration']?.toString(),
      remainingDays: json['remaining_days'] is int
          ? json['remaining_days']
          : int.tryParse(json['remaining_days']?.toString() ?? ''),
      notes: json['notes']?.toString(),
      debt: json['debt'] is num
          ? (json['debt'] as num).toDouble()
          : double.tryParse(json['debt']?.toString() ?? ''),
      hasDebtFlag: json['hasDebt'] is bool ? json['hasDebt'] : null,
      profileName: pName?.toString(),
      profileId: pId is int ? pId : int.tryParse(pId?.toString() ?? ''),
      balance: json['balance']?.toString(),
      price: pPrice?.toString(),
      parentUsername: json['parent_username']?.toString(),
      isOnlineFlag: json['is_online'] == true || json['is_online'] == 1,
      enabled: json['enabled'] is int
          ? json['enabled']
          : int.tryParse(json['enabled']?.toString() ?? ''),
      ipAddress: (json['framedipaddress'] ?? json['framed_ip_address'])?.toString(),
      macAddress: json['callingstationid']?.toString(),
      sessionTime: json['acctsessiontime'] is int
          ? json['acctsessiontime']
          : int.tryParse(json['acctsessiontime']?.toString() ?? ''),
      downloadBytes: json['acctoutputoctets'] is int
          ? json['acctoutputoctets']
          : int.tryParse(json['acctoutputoctets']?.toString() ?? ''),
      uploadBytes: json['acctinputoctets'] is int
          ? json['acctinputoctets']
          : int.tryParse(json['acctinputoctets']?.toString() ?? ''),
      deviceVendor: json['oui']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'idx': idx,
        'username': username,
        'firstname': firstname,
        'lastname': lastname,
        'phone': phone,
        'mobile': mobile,
        'expiration': expiration,
        'remaining_days': remainingDays,
        'notes': notes,
        'debt': debt,
        'profile_name': profileName,
        'profile_id': profileId,
        'balance': balance,
        'price': price,
      };
}

class PackageModel {
  final int idx;
  final String name;
  final String? nameEn;
  final String? rateLimit;
  final String? monthlyFee;
  final String? price;
  final String? type;
  final int? expirationAmount;

  const PackageModel({
    required this.idx,
    required this.name,
    this.nameEn,
    this.rateLimit,
    this.monthlyFee,
    this.price,
    this.type,
    this.expirationAmount,
  });

  bool get isMonthly =>
      type == null || type == 'monthly' || type!.isEmpty;

  bool get isExtension =>
      type != null && type != 'monthly' && type!.isNotEmpty;

  String get typeLabel {
    switch (type) {
      case 'monthly':
      case null:
      case '':
        return 'شهرية';
      case 'daily':
        return 'يومية';
      case 'hourly':
        return 'ساعات';
      case 'extension':
        return 'تمديد';
      default:
        return type ?? 'شهرية';
    }
  }

  String get durationLabel {
    if (expirationAmount == null) return '';
    if (type == 'hourly') return '$expirationAmount ساعة';
    if (type == 'daily') return '$expirationAmount يوم';
    return '$expirationAmount يوم';
  }

  factory PackageModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['idx'];
    return PackageModel(
      idx: rawId is int
          ? rawId
          : int.tryParse(rawId?.toString() ?? '0') ?? 0,
      name: (json['name'] ?? '').toString(),
      nameEn: json['name_en']?.toString(),
      rateLimit: json['rate_limit']?.toString(),
      monthlyFee: (json['monthly_fee'] ?? json['price'])?.toString(),
      price: (json['price'] ?? json['profile_price'])?.toString(),
      type: json['type']?.toString(),
      expirationAmount: json['expiration_amount'] is int
          ? json['expiration_amount']
          : int.tryParse(json['expiration_amount']?.toString() ?? ''),
    );
  }
}
