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

  static double _cleanParseDouble(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final cleaned = raw.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  /// Signed number from `notes` / `comments` only (SAS user field). No `balance` column.
  double? get _notesSignedOrNull {
    if (notes == null || notes!.trim().isEmpty) return null;
    return _cleanParseDouble(notes);
  }

  double get debtAmount {
    if (notes == null || notes!.trim().isEmpty) return 0;
    final val = _cleanParseDouble(notes);
    if (val.abs() < 1) return 0;
    return val;
  }

  bool get hasDebt => debtAmount < 0;

  bool get hasCredit => debtAmount > 0;

  /// Credit shown as «رصيد»: positive part of `notes`/`comments` only. Never read SAS `balance`.
  double get balanceAmount {
    final n = _notesSignedOrNull;
    if (n != null && n > 0) return n;
    return 0;
  }

  DateTime? get _parsedExpiration {
    if (expiration == null || expiration!.isEmpty) return null;
    try {
      final expStr = expiration!.trim();
      if (expStr.contains('T') || expStr.contains('+')) {
        return DateTime.tryParse(expStr);
      }
      return DateTime.tryParse('${expStr.replaceAll(' ', 'T')}+03:00');
    } catch (_) {
      return null;
    }
  }

  bool get isExpired {
    final expDate = _parsedExpiration;
    if (expDate != null) {
      return expDate.isBefore(DateTime.now());
    }
    return (remainingDays ?? 0) < 0;
  }

  bool get isExpiredToday {
    final expDate = _parsedExpiration;
    if (expDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expDay = DateTime(expDate.year, expDate.month, expDate.day);
    return expDay == today && expDate.isBefore(now);
  }

  bool get isActive => !isExpired;

  bool get isNearExpiry {
    final exp = _parsedExpiration;
    if (exp == null) {
      return remainingDays != null && remainingDays! >= 1 && remainingDays! <= 3;
    }
    final now = DateTime.now();
    if (exp.isBefore(now)) return false;
    final diff = exp.difference(now);
    return diff.inDays <= 3;
  }

  bool get isEnabled => enabled == null || enabled == 1;

  bool get isDisabled => !isEnabled;

  bool get isOnline => isOnlineFlag == true;

  // غير متصل: ليس متصل وليس منتهي. المعطّل قطعاً غير متصل فيُضمّ هنا.
  // (المعطّل له فلتر منفصل لو المدير يحتاج فقط المعطّلين.)
  bool get isOffline => !isOnline && !isExpired;

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
      notes: (json['notes'] ?? json['comments'])?.toString(),
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
  final String? userPrice;
  final String? type;
  final int? expirationAmount;

  const PackageModel({
    required this.idx,
    required this.name,
    this.nameEn,
    this.rateLimit,
    this.monthlyFee,
    this.price,
    this.userPrice,
    this.type,
    this.expirationAmount,
  });

  String? get displayPrice => userPrice ?? price;

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

  PackageModel copyWithUserPrice(String? newUserPrice) => PackageModel(
    idx: idx, name: name, nameEn: nameEn, rateLimit: rateLimit,
    monthlyFee: monthlyFee, price: price, userPrice: newUserPrice,
    type: type, expirationAmount: expirationAmount,
  );

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
      userPrice: json['user_price']?.toString(),
      type: json['type']?.toString(),
      expirationAmount: json['expiration_amount'] is int
          ? json['expiration_amount']
          : int.tryParse(json['expiration_amount']?.toString() ?? ''),
    );
  }
}
